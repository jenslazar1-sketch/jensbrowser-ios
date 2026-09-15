import SwiftUI
import WebKit

/// One browser tab. Each keeps its own WKWebView alive; only the active tab's
/// view is attached to the tree (mirrors the Android TabManager design).
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView
    let isPrivate: Bool
    @Published var title: String = "New Tab"
    @Published var urlString: String = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isHome: Bool = true

    init(configuration: WKWebViewConfiguration, isPrivate: Bool) {
        self.isPrivate = isPrivate
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 15.0, *) { webView.underPageBackgroundColor = UIColor.black }
        webView.isOpaque = false
        webView.backgroundColor = .black
        if isPrivate { title = "Private Tab" }
    }
}

final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var tabs: [Tab] = []
    @Published var activeIndex: Int = 0

    let consoleLog = ConsoleLog()
    private(set) var ruleList: WKContentRuleList?
    private let config: WKWebViewConfiguration
    private let privateConfig: WKWebViewConfiguration

    override init() {
        // Build the two shared configs (persistent + private) up front.
        config = WKWebViewConfiguration()
        privateConfig = WKWebViewConfiguration()
        super.init()
        setupConfig(config, persistent: true)
        setupConfig(privateConfig, persistent: false)
        newTab()
        compileBlocking()
    }

    private func setupConfig(_ cfg: WKWebViewConfiguration, persistent: Bool) {
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        if !persistent { cfg.websiteDataStore = .nonPersistent() }
        let ucc = cfg.userContentController
        ucc.add(consoleLog, name: "j3nsConsole")
        ucc.addUserScript(WKUserScript(source: DevConsole.consoleHookJS,
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: false))
    }

    var activeTab: Tab? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil }

    // MARK: - tabs

    @discardableResult
    func newTab(_ url: URL? = nil, isPrivate: Bool = false) -> Tab {
        let t = Tab(configuration: isPrivate ? privateConfig : config, isPrivate: isPrivate)
        t.webView.navigationDelegate = self
        t.webView.uiDelegate = self
        applyUA(to: t)
        if let rl = ruleList { t.webView.configuration.userContentController.add(rl) }
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
        t.title = t.isPrivate ? "Private Tab" : "New Tab"
    }

    // MARK: - settings

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

    // MARK: - content blocking

    func compileBlocking() {
        let s = Store.shared
        guard s.blockingEnabled else { removeBlocking(); return }
        ContentBlocking.compile(userDomains: ContentBlocking.parseUserDomains(s.blockRulesText)) { [weak self] list in
            guard let self = self else { return }
            self.ruleList = list
            self.config.userContentController.removeAllContentRuleLists()
            self.privateConfig.userContentController.removeAllContentRuleLists()
            if let list = list {
                self.config.userContentController.add(list)
                self.privateConfig.userContentController.add(list)
                self.tabs.forEach { $0.webView.configuration.userContentController.add(list) }
            }
        }
    }

    func removeBlocking() {
        ruleList = nil
        config.userContentController.removeAllContentRuleLists()
        privateConfig.userContentController.removeAllContentRuleLists()
        tabs.forEach { $0.webView.configuration.userContentController.removeAllContentRuleLists() }
    }

    // MARK: - tools (dev console / god mode)

    func runJS(_ code: String, completion: @escaping (String) -> Void) {
        activeTab?.webView.evaluateJavaScript(code) { result, error in
            if let error = error { completion("Error: \(error.localizedDescription)") }
            else if let result = result { completion(String(describing: result)) }
            else { completion("undefined") }
        }
    }

    func capturePageText(completion: @escaping (String) -> Void) {
        activeTab?.webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { result, _ in
            completion((result as? String) ?? "")
        }
    }

    func pageInfo(completion: @escaping (String) -> Void) {
        activeTab?.webView.evaluateJavaScript(DevConsole.pageInfoJS) { result, _ in
            completion((result as? String) ?? "{}")
        }
    }

    func findInPage(_ text: String) {
        let literal = UserScriptsStore.jsLiteral(text)
        activeTab?.webView.evaluateJavaScript("window.find ? window.find(\(literal)) : false", completionHandler: nil)
    }

    func clearActiveSiteData() {
        guard let host = activeTab?.webView.url?.host else { return }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let store = activeTab?.webView.configuration.websiteDataStore ?? .default()
        store.fetchDataRecords(ofTypes: types) { records in
            let mine = records.filter { $0.displayName.contains(host) || host.contains($0.displayName) }
            store.removeData(ofTypes: types, for: mine) {}
        }
    }

    func clearAllSiteData(completion: @escaping () -> Void) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
            completion()
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { sync(webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { sync(webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { sync(webView) }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync(webView)
        injectMods(into: webView)
    }

    private func injectMods(into webView: WKWebView) {
        guard let tab = tabs.first(where: { $0.webView === webView }), !tab.isPrivate,
              let host = webView.url?.host else { return }
        for mod in UserScriptsStore.shared.matching(host: host) {
            webView.evaluateJavaScript(UserScriptsStore.injectionJS(for: mod), completionHandler: nil)
        }
    }

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
            let priv = tabs.first(where: { $0.webView === webView })?.isPrivate ?? false
            newTab(url, isPrivate: priv)
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
