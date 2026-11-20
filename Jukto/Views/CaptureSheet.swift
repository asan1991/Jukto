import SwiftUI
import WebKit
import Combine

struct CaptureRequest: Identifiable {
    let url: URL
    /// True when the link had no particular video in it: the page opens so the person can choose one.
    var choosing = false
    var id: String { url.absoluteString }
}

/// Ad blocking for the capture browser ONLY, using WebKit's built-in content blocking (the same mechanism Safari's
/// ad blockers use). The rules are a static file inside the app: nothing is downloaded or updated over the network,
/// nothing is loaded when the app starts, and nothing runs unless this window is open.
/// The ad-server list is derived from EasyList (see THIRD_PARTY_NOTICES.md).
enum AdBlock {
    static var identifier: String { "JuktoAdBlock-" + JuktoConstants.appVersion }
    static func rulesJSON() -> String? {
        try? String(contentsOfFile: JuktoConstants.resourcesPath + "/adblock.json", encoding: .utf8)
    }
}

struct SniffedStream: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let kind: String
    var host: String { url.host ?? "" }
}

/// A small private browser for sites yt-dlp can't read. You open the page and press play; Jukto watches which
/// video streams the page itself requests (HLS .m3u8, DASH .mpd, plain .mp4/.webm/.mov) and lets you download one.
/// Nothing is persisted (non-persistent data store). DRM-protected streams are detected and cannot be downloaded.
@MainActor
final class CaptureController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let pageURL: URL
    let webView: WKWebView
    @Published var streams: [SniffedStream] = []
    @Published var drmDetected = false
    @Published var isLoading = true
    @Published var currentHost = ""
    /// The address the page is showing right now (also changes inside single-page sites such as YouTube).
    @Published var currentURL: URL?
    private var seen = Set<String>()
    private let contentController: WKUserContentController
    private var urlObserver: AnyCancellable?

    init(url: URL) {
        pageURL = url
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: Self.snifferJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        cfg.userContentController = ucc
        contentController = ucc
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        ucc.add(self, name: "jukto")            // removed again in stop() to break the retain cycle
        webView.customUserAgent = JuktoConstants.browserUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        urlObserver = webView.publisher(for: \.url).sink { [weak self] u in self?.currentURL = u }
        loadWithAdBlock()
    }

    /// The page opens at once. If the ad-block rules were compiled before they are attached first (instant);
    /// otherwise they are compiled in the background, once, and take effect as soon as they are ready.
    private func loadWithAdBlock() {
        WKContentRuleListStore.default()?.lookUpContentRuleList(forIdentifier: AdBlock.identifier) { list, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let list { self.contentController.add(list) }
                self.webView.load(URLRequest(url: self.pageURL))
                if list == nil { self.compileAdBlock() }
            }
        }
    }

    private func compileAdBlock() {
        guard let json = AdBlock.rulesJSON() else { return }
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: AdBlock.identifier, encodedContentRuleList: json) { list, _ in
            Task { @MainActor [weak self] in
                if let list { self?.contentController.add(list) }
            }
        }
    }

    func stop() {
        urlObserver = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "jukto")
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)     // also stops any playing media
    }

    // MARK: messages from the page script
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        if kind == "drm" { drmDetected = true; return }
        guard kind == "media", let s = body["url"] as? String, s.count < 2000,
              let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              streams.count < 40, seen.insert(s).inserted else { return }
        streams.append(SniffedStream(url: url, kind: Self.kind(of: url)))
    }

    private static func kind(of url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": return "HLS"
        case "mpd": return "DASH"
        case "mp4", "m4v": return "MP4"
        case "webm": return "WebM"
        case "mov": return "MOV"
        default: return "Stream"
        }
    }

    /// Builds the download job for a stream: page URL as Referer and the session's cookies for the page/stream hosts.
    func makeMetadata(for stream: SniffedStream) async -> VideoMetadata {
        let page = webView.url ?? pageURL
        let hosts = [page.host, stream.url.host].compactMap { $0?.lowercased() }
        let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let cookies = all.filter { c in
            let d = c.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return hosts.contains { Platform.hostMatches($0, d) }
        }.prefix(100).map { StoredCookie($0) }

        let rawTitle = (webView.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var md = VideoMetadata(
            title: rawTitle.isEmpty ? (page.host ?? "video") : rawTitle,
            uploader: page.host, duration: nil, thumbnail: nil, platform: .unknown,
            originalURL: page, downloadURL: stream.url, maxHeight: nil)
        md.referer = page; md.cookies = Array(cookies); md.sniffed = true
        return md
    }

    // MARK: navigation (http/https only, no popups)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if url.absoluteString == "about:blank" { return .allow }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? .allow : .cancel
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { isLoading = true }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { currentHost = webView.url?.host ?? "" }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { isLoading = false }

    // MARK: injected script — reports media URLs the page requests, and flags DRM (EME) usage
    private static let snifferJS = #"""
    (function () {
      if (window.__juktoSniffer) return; window.__juktoSniffer = true;
      var post = function (o) { try { window.webkit.messageHandlers.jukto.postMessage(o); } catch (e) {} };
      var pat = /\.(m3u8|mpd|mp4|m4v|webm|mov)(\?|#|$)/i;
      var seen = {};
      function report(u, via) {
        try {
          var a = new URL(u, document.baseURI).href;
          if (!/^https?:/i.test(a) || seen[a] || !pat.test(a)) return;
          seen[a] = 1; post({ kind: 'media', url: a, via: via });
        } catch (e) {}
      }
      var of = window.fetch;
      if (of) window.fetch = function (i) { try { report(typeof i === 'string' ? i : (i && i.url), 'fetch'); } catch (e) {} return of.apply(this, arguments); };
      var xo = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (m, u) { try { report(u, 'xhr'); } catch (e) {} return xo.apply(this, arguments); };
      try { new PerformanceObserver(function (l) { l.getEntries().forEach(function (e) { report(e.name, 'perf'); }); }).observe({ type: 'resource', buffered: true }); } catch (e) {}
      setInterval(function () { document.querySelectorAll('video,source,audio').forEach(function (v) { report(v.currentSrc || v.src, 'tag'); }); }, 1500);
      // Pages that wrap/serialize CryptoKeys make WebKit create "Jukto WebCrypto Master Key" in the Keychain, which
      // asks for the login password. Nothing here needs it, so those calls are refused before they reach WebKit.
      try {
        var rej = function () { return Promise.reject(new DOMException('Not allowed', 'NotSupportedError')); };
        if (window.SubtleCrypto) { SubtleCrypto.prototype.wrapKey = rej; SubtleCrypto.prototype.unwrapKey = rej; }
        var isKey = function (x) { try { return typeof CryptoKey !== 'undefined' && x instanceof CryptoKey; } catch (e) { return false; } };
        var hasKey = function (v) {
          if (isKey(v)) return true;
          if (v && typeof v === 'object') { try { for (var k in v) { if (isKey(v[k])) return true; } } catch (e) {} }
          return false;
        };
        ['put', 'add'].forEach(function (n) {
          var o = window.IDBObjectStore && IDBObjectStore.prototype[n];
          if (o) IDBObjectStore.prototype[n] = function (v) {
            if (hasKey(v)) throw new DOMException('Not allowed', 'DataCloneError');
            return o.apply(this, arguments);
          };
        });
      } catch (e) {}
      try {
        var rk = navigator.requestMediaKeySystemAccess;
        if (rk) navigator.requestMediaKeySystemAccess = function (ks) { post({ kind: 'drm', keySystem: ks }); return rk.apply(this, arguments); };
      } catch (e) {}
    })();
    """#
}

struct CaptureSheet: View {
    let url: URL
    var choosing = false
    var onPick: (VideoMetadata) -> Void
    var onPage: (URL) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ctl: CaptureController

    init(url: URL, choosing: Bool = false,
         onPick: @escaping (VideoMetadata) -> Void,
         onPage: @escaping (URL) -> Void = { _ in }) {
        self.url = url; self.choosing = choosing; self.onPick = onPick; self.onPage = onPage
        _ctl = StateObject(wrappedValue: CaptureController(url: url))
    }

    /// The page currently open, when it is one particular video.
    private var videoPage: URL? {
        guard choosing, let u = ctl.currentURL, URLDetector.pointsToVideo(u) else { return nil }
        return u
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "scope").font(.system(size: 24)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(choosing ? "Choose the video" : "Find the video on this page").font(.headline)
                    Text(choosing
                         ? "This link doesn't point to one particular video. Open the video you want on the page — a button to download it appears below. Ads are blocked in this window; nothing is saved from it."
                         : "Press play on the page. Jukto lists the video streams the page loads — pick one below. Nothing is saved from this window.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    if ctl.isLoading { ProgressView().controlSize(.mini) } else { Image(systemName: "globe").font(.system(size: 9)) }
                    Text(ctl.currentHost.isEmpty ? "…" : ctl.currentHost).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            .padding(14)
            Divider()
            WebViewHost(webView: ctl.webView)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if ctl.drmDetected {
                    Label("This page uses DRM-protected streaming. Jukto can't download protected video.",
                          systemImage: "lock.trianglebadge.exclamationmark.fill")
                        .font(.caption).foregroundStyle(Color.juktoBronze)
                }
                if let page = videoPage {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.juktoSuccess)
                        Text("Video page open").font(.callout)
                        Spacer()
                        Button("Download this video") { onPage(page); dismiss() }
                            .buttonStyle(PillButtonStyle(prominent: true))
                    }
                } else if choosing {
                    Text("Open the video you want — then press “Download this video”.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if ctl.streams.isEmpty {
                    if !choosing {
                        Text("No video streams found yet — press play on the page.").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(ctl.streams) { s in
                                HStack(spacing: 10) {
                                    Text(s.kind).font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.15)))
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.url.lastPathComponent.isEmpty ? s.host : s.url.lastPathComponent).lineLimit(1).font(.callout)
                                        Text(s.host).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Use this") {
                                        Task {
                                            let md = await ctl.makeMetadata(for: s)
                                            onPick(md); dismiss()
                                        }
                                    }.buttonStyle(PillButtonStyle(prominent: true))
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
                HStack { Spacer(); Button("Close") { dismiss() }.buttonStyle(PillButtonStyle()) }
            }
            .padding(12)
        }
        .frame(width: 760, height: 780)
        .onDisappear { ctl.stop() }
    }
}
