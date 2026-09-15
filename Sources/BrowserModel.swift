import SwiftUI
import WebKit

/// One browser tab. Each keeps its own WKWebView alive; only the active tab's
/// view is attached to the tree (mirrors the Android TabManager design).
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView
    @Published var title: String = "New Tab"
    @Published var urlString: String = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var progress: Double = 0
    @Published var isHome: Bool = true

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 15.0, *) { webView.underPageBackgroundColor = UIColor.black }
        webView.isOpaque = false
        webView.backgroundColor = .black
    }
}

final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var tabs: [Tab] = []
    @Published var activeIndex: Int = 0

    let config: WKWebViewConfiguration

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        self.config = cfg
        super.init()
        newTab()
    }

    var activeTab: Tab? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil }

    @discardableResult
    func newTab(_ url: URL? = nil) -> Tab {
        let t = Tab(configuration: config)
        t.webView.navigationDelegate = self
        t.webView.uiDelegate = self
        applyUA(to: t)
        tabs.append(t)
        activeIndex = tabs.count - 1
        if let u = url { load(u, in: t) }
        return t
    }

    func closeTab(_ tab: Tab) {
        guard let idx = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: idx)
        if tabs.isEmpty { newTab() }
        activeIndex = min(activeIndex, tabs.count - 1)
    }

    func select(_ tab: Tab) {
        if let idx = tabs.firstIndex(where: { $0.id == tab.id }) { activeIndex = idx }
    }

    func load(_ url: URL, in tab: Tab? = nil) {
        let t = tab ?? activeTab
        t?.isHome = false
        t?.webView.load(URLRequest(url: url))
    }

    func goHome() {
        guard let t = activeTab else { return }
        t.isHome = true
        t.urlString = ""
        t.title = "New Tab"
    }

    func applyUA(to tab: Tab) {
        let s = Store.shared
        if !s.userAgentOverride.isEmpty {
            tab.webView.customUserAgent = s.userAgentOverride
        } else if s.desktopMode {
            tab.webView.customUserAgent =
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
                "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        } else {
            tab.webView.customUserAgent = nil
        }
    }

    func reapplyAllTabSettings() { tabs.forEach { applyUA(to: $0) }; activeTab?.webView.reload() }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { sync(webView) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { sync(webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { sync(webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { sync(webView) }

    private func sync(_ webView: WKWebView) {
        guard let t = tabs.first(where: { $0.webView === webView }) else { return }
        DispatchQueue.main.async {
            if let title = webView.title, !title.isEmpty { t.title = title }
            t.urlString = webView.url?.absoluteString ?? t.urlString
            t.canGoBack = webView.canGoBack
            t.canGoForward = webView.canGoForward
            if webView.url != nil { t.isHome = false }
        }
    }

    // MARK: - WKUIDelegate: open target=_blank in a new tab
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            newTab(url)
        }
        return nil
    }
}

/// Hosts the active tab's WKWebView, reparenting it when the active tab changes.
struct WebContainer: UIViewRepresentable {
    @ObservedObject var tab: Tab

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let web = tab.webView
        if web.superview !== uiView {
            web.removeFromSuperview()
            web.translatesAutoresizingMaskIntoConstraints = false
            uiView.addSubview(web)
            NSLayoutConstraint.activate([
                web.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
                web.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
                web.topAnchor.constraint(equalTo: uiView.topAnchor),
                web.bottomAnchor.constraint(equalTo: uiView.bottomAnchor),
            ])
        }
    }
}
