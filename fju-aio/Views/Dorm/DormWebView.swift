import SwiftUI
import WebKit
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "DormWebView")

/// A WKWebView that loads the dorm site and injects the JWT session into
/// localStorage so the site treats the user as already logged in.
struct DormWebView: UIViewRepresentable {
    let session: DormSession?

    private static let dormURL = URL(string: "https://dorm.fju.edu.tw/dormstu/#/")!

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: Self.dormURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.session = session
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var session: DormSession?
        private var hasInjected = false

        init(session: DormSession?) {
            self.session = session
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasInjected, let session else { return }
            hasInjected = true
            injectSession(session, into: webView)
        }

        private func injectSession(_ session: DormSession, into webView: WKWebView) {
            let exp = Int(session.expiresAt.timeIntervalSince1970)
            let js = """
            (function() {
                localStorage.setItem('dormitory_user_auth', \(jsString("Bearer " + session.token)));
                localStorage.setItem('dormitory_user_name', \(jsString(session.userName)));
                localStorage.setItem('dormitory_user_empNo', \(jsString(session.empNo)));
                localStorage.setItem('dormitory_user_stuIdty', \(jsString(session.studentIdentity)));
                localStorage.setItem('dormitory_user_role', \(jsString(session.roleSn)));
                localStorage.setItem('dormitory_user_exp', '\(exp)');
            })();
            """
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    logger.info("[DormWebView] localStorage injection error: \(error)")
                } else {
                    // Reload so the Vue SPA picks up the stored auth on startup
                    webView.reload()
                }
            }
        }

        /// Wraps a Swift string as a safe JS single-quoted string literal.
        private func jsString(_ value: String) -> String {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "'\(escaped)'"
        }
    }
}

// MARK: - Container view with auth loading state

struct DormBrowserView: View {
    @State private var session: DormSession? = nil
    @State private var isLoading = true
    @State private var authError: String? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在驗證身份…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DormWebView(session: session)
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        if let authError {
                            Text("自動登入失敗，請手動登入：\(authError)")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.orange.opacity(0.9), in: Capsule())
                                .padding(.top, 8)
                        }
                    }
            }
        }
        .task {
            await authenticate()
        }
    }

    private func authenticate() async {
        do {
            session = try await DormAuthService.shared.getValidSession()
        } catch {
            authError = error.localizedDescription
        }
        isLoading = false
    }
}
