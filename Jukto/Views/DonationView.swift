import SwiftUI
import AppKit

/// One QR code shipped as an image in Assets.xcassets and shown exactly as provided — never generated or altered.
private struct QRTile: View {
    let assetName: String
    let caption: String
    var copyable: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(assetName)
                .resizable().interpolation(.none).scaledToFit()
                .frame(width: 150, height: 150)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))

            Text(caption).font(.system(size: 12, weight: .medium)).multilineTextAlignment(.center)

            if let c = copyable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(c, forType: .string)
                    ToastCenter.shared.show("Copied to clipboard.", seconds: 1)
                } label: {
                    Text(c)
                        .font(.system(size: 10.5, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 160)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(c)
            }
        }
    }
}

/// Thank-you card shown over the main window when it is closed. A plain overlay (no sheet, no extra window,
/// no blur), so it appears and disappears instantly.
struct DonationView: View {
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            VStack(spacing: 18) {
                Text("If you'd like to say thank you :)")
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                HStack(alignment: .top, spacing: 22) {
                    QRTile(assetName: "MBankQR", caption: "MBank\n\(JuktoConstants.mbankLabel)")
                    QRTile(assetName: "USDTQR", caption: "USDT (TRC20/ERC20)", copyable: JuktoConstants.usdtAddress)
                }

                Button("Close", action: onClose)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)
            .frame(width: 420)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}
