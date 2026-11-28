// App 内网页浏览器：软件源里的网页链接用 WKWebView 打开，不跳出应用。
// 网盘/蓝奏云等需要 JS 交互或外部下载的页面，可点工具栏「Safari 打开」跳系统浏览器。

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
                if let errorText, !loading {
                    VStack(spacing: 12) {
                        Image(systemName: "globe.badge.chevron.backward").font(.largeTitle)
                        Text("页面加载失败").font(.headline)
                        Text(errorText).font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            openInSafari()
                        } label: {
                            Label("用 Safari 打开", systemImage: "safari")
                                .padding(.horizontal, 16).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(dynamicTitle ?? "网页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        openInSafari()
                    } label: {
                        Image(systemName: "safari")
                    }
                    .help("用 Safari 打开")
                }
            }
        }
    }

    private func openInSafari() {
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok { errorText = "无法打开外部浏览器" }
        }
        #endif
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
        // 开启 JavaScript（网盘/下载页依赖），允许弹窗与用户交互。
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
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
