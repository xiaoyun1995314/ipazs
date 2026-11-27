// App 内网页浏览器：软件源里的网页链接用 WKWebView 打开，不跳出应用。

import SwiftUI
import WebKit

struct WebBrowserView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var canGoBack = false
    @State private var loading = true
    @State private var errorText: String?
    @State private var dynamicTitle: String?

    var body: some View {
        NavigationStack {
            ZStack {
                WebViewBridge(url: url, canGoBack: $canGoBack, loading: $loading,
                              errorText: $errorText, title: $dynamicTitle)
                if loading {
                    ProgressView().controlSize(.large)
                }
            }
            .navigationTitle(dynamicTitle ?? "网页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if canGoBack {
                        Button { /* 由桥接层处理返回 */ } label: { Image(systemName: "chevron.left") }
                    }
                }
            }
        }
    }
}

private struct WebViewBridge: UIViewRepresentable {
    let url: URL
    @Binding var canGoBack: Bool
    @Binding var loading: Bool
    @Binding var errorText: String?
    @Binding var title: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewBridge
        init(_ parent: WebViewBridge) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true; parent.errorText = nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            parent.canGoBack = webView.canGoBack
            parent.title = webView.title
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
            parent.errorText = error.localizedDescription
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
            parent.errorText = error.localizedDescription
        }
    }
}
