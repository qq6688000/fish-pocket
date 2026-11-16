import SwiftUI
import WebKit

/// An in-app browser that a vendor's own sign-in page runs in: the page stays inside the
/// app, and the moment it is signed in, the cookie the vendor issues is read back — no token
/// to copy by hand. Every vendor here signs in with a browser session rather than an OAuth
/// authorization code, so the cookie *is* the credential.
///
/// The cookie is only read after the page reaches the vendor's own signed-in destination;
/// anything earlier (a captcha, the code form, a QR step) is left to the user.
struct VendorSignInWeb: UIViewRepresentable {
    let url: URL
    /// Hosts the page must show before a cookie is collected: the signed-in workspace.
    let signedInPrefix: String
    /// Cookie names that carry the session, most specific first.
    let cookieNames: [String]
    let onCredential: (String) -> Void
    /// Reached the signed-in page but no session cookie could be read.
    var onStalled: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func clearCookies(hosts: [String]) {
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { cookies in
            for cookie in cookies where hosts.contains(where: { cookie.domain.contains($0) }) {
                store.delete(cookie)
            }
            for host in hosts {
                HTTPCookieStorage.shared.cookies(for: URL(string: "https://\(host)") ?? URL(string: "https://localhost")!)?
                    .forEach(HTTPCookieStorage.shared.deleteCookie)
            }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The vendor's page may open its own sign-in popup; keep it in this web view.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        context.coordinator.web = web
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let owner: VendorSignInWeb
        weak var web: WKWebView?
        private var collected = false

        init(_ owner: VendorSignInWeb) { self.owner = owner }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            collect(from: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {}

        /// Read the vendor's session cookie once the page has landed on its signed-in view.
        private func collect(from webView: WKWebView) {
            guard !collected, let landed = webView.url?.absoluteString, landed.hasPrefix(owner.signedInPrefix) else {
                if webView.url?.absoluteString.hasPrefix(owner.signedInPrefix) == true { owner.onStalled?() }
                return
            }
            collected = true
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let scope = cookies.filter { cookie in
                    guard let host = webView.url?.host else { return false }
                    return host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                }
                for name in self.owner.cookieNames {
                    if let value = scope.first(where: { $0.name == name })?.value, !value.isEmpty {
                        DispatchQueue.main.async { self.owner.onCredential(value) }
                        return
                    }
                }
                // Nothing matched yet: the page may still be settling, so allow another look.
                self.collected = false
            }
        }
    }
}

/// The sheet: the vendor's page with a title and a way out.
struct VendorSignInSheet: View {
    let preset: ProviderPreset
    let onCredential: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Said under the title when the page reached its signed-in destination without a cookie.
    @State private var status: String?
    @State private var webID = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let status {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(Palette.secondary)
                        Text(status).font(.footnote).foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Palette.control)
                }
                VendorSignInWeb(
                    url: preset.signInURL,
                    signedInPrefix: preset.signedInPrefix,
                    cookieNames: preset.cookieNames,
                    onCredential: { value in
                        onCredential(value)
                        dismiss()
                    },
                    onStalled: {
                        status = String(localized: "已进入登录后的页面，但没读到这个平台的会话凭据。改用「打开\(preset.name)获取 API Key」更稳。")
                    }
                )
                .id(webID)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(preset.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("重新加载登录页") { webID = UUID() }
                        if let page = preset.keyPage {
                            Button("改用 API Key") { openURL(page) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .tint(Palette.ink)
    }
}
