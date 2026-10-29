import SwiftUI
import WebKit

/// Bundled so the current policy remains available without a connection.
struct PrivacyPolicyView: View {
    var body: some View {
        PolicyDocument()
            .navigationTitle("隐私政策")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PolicyDocument: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        view.navigationDelegate = context.coordinator
        if let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "html") {
            view.loadFileURL(url, allowingReadAccessTo: url)
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else { return .allow }
            if url.isFileURL, url.fragment != nil { return .allow }
            if url.scheme == "https" || url.scheme == "mailto" {
                await UIApplication.shared.open(url)
            }
            return .cancel
        }
    }
}
