import SwiftUI
import WebKit

/// Sign-in window. The password is typed straight into the website inside a sandboxed web view that
/// never touches disk (non-persistent data store) and is limited to the site's own domains.
/// Jukto never reads form fields; it only collects the session cookies of that site once you are signed in.
@MainActor
final class LoginController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let platform: Platform
    let webView: WKWebView
    @Published var isLoading = true
    @Published var currentHost = ""
    @Published var message: String?
    var onDone: ((Bool) -> Void)?

    private var timer: Timer?
    private var finished = false
    private var finalizing = false

    init(platform: Platform) {
        self.platform = platform
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        webView.customUserAgent = JuktoConstants.browserUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        if let url = platform.loginURL { webView.load(URLRequest(url: url)) }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func relevantCookies() async -> [HTTPCookie] {
        let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        return all.filter { c in
            let d = c.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return platform.cookieDomains.contains { Platform.hostMatches(d, $0) }
        }
    }

    private func hasSession(_ cookies: [HTTPCookie]) -> Bool {
        cookies.contains { platform.sessionCookieNames.contains($0.name) }
    }

    private func poll() async {
        guard !finished, !finalizing else { return }
        guard hasSession(await relevantCookies()) else { return }
        await save()
    }

    private func save() async {
        finalizing = true
        try? await Task.sleep(nanoseconds: 1_200_000_000)    // let the site finish setting its cookies
        let cookies = await relevantCookies()
        CookieVault.save(cookies.map { StoredCookie($0) }, for: platform)
        finish(true)
    }

    func confirmManually() {
        Task {
            if hasSession(await relevantCookies()) {
                if !finalizing { await save() }
            } else {
                message = "No sign-in detected yet. Finish signing in, then try again."
            }
        }
    }

    func cancel() { finish(false) }

    private func finish(_ ok: Bool) {
        guard !finished else { return }
        finished = true
        stop(); webView.stopLoading()
        onDone?(ok)
    }

    // MARK: navigation allow-list
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if url.absoluteString == "about:blank" { return .allow }
        guard url.scheme == "https", let host = url.host?.lowercased(), platform.isTrusted(host: host) else { return .cancel }
        return .allow
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "https",
           let host = url.host?.lowercased(), platform.isTrusted(host: host) {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { isLoading = true }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { currentHost = webView.url?.host ?? "" }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { isLoading = false }
}

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct LoginSheet: View {
    let platform: Platform
    @EnvironmentObject var auth: AuthCoordinator
    @StateObject private var ctl: LoginController

    init(platform: Platform) {
        self.platform = platform
        _ctl = StateObject(wrappedValue: LoginController(platform: platform))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill").font(.system(size: 26)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sign in to \(platform.displayName)").font(.headline)
                    Text("Your password goes straight to the website — Jukto never sees it. Only the session is kept, encrypted in your Keychain, and you can remove it any time in Settings.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    if ctl.isLoading { ProgressView().controlSize(.mini) } else { Image(systemName: "lock.fill").font(.system(size: 9)) }
                    Text(ctl.currentHost.isEmpty ? "…" : ctl.currentHost).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            .padding(14)
            Divider()
            WebViewHost(webView: ctl.webView)
            Divider()
            HStack {
                if let m = ctl.message { Text(m).font(.caption).foregroundStyle(Color.juktoCoral) }
                Spacer()
                Button("Cancel") { ctl.cancel() }.buttonStyle(PillButtonStyle())
                Button("I'm signed in") { ctl.confirmManually() }.buttonStyle(PillButtonStyle(prominent: true))
            }
            .padding(12)
        }
        .frame(width: 520, height: 700)
        .onAppear {
            ctl.onDone = { ok in
                if ok { auth.completed(platform) } else { auth.cancel() }
            }
            ctl.start()
        }
        .onDisappear { ctl.stop() }
    }
}
