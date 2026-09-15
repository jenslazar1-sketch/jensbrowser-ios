import SwiftUI
import WebKit

@main
struct J3nsBrowserApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @StateObject private var model = BrowserModel()
    var body: some View {
        ZStack {
            Theme.black.ignoresSafeArea()
            if let tab = model.activeTab {
                BrowserScreen(model: model, tab: tab)
                    .id(tab.id)   // rebind @ObservedObject when the active tab changes
            }
        }
    }
}

struct BrowserScreen: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: Tab
    @ObservedObject private var store = Store.shared

    @State private var omni = ""
    @State private var showTabs = false
    @State private var showSettings = false
    @State private var showBookmarks = false
    @FocusState private var omniFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            content
            bottomBar
        }
        .background(Theme.black.ignoresSafeArea())
        .onAppear { omni = displayURL(tab.urlString) }
        .onChange(of: tab.urlString) { v in if !omniFocused { omni = displayURL(v) } }
        .sheet(isPresented: $showTabs) { TabsSheet(model: model) }
        .sheet(isPresented: $showSettings) { SettingsSheet(model: model) }
        .sheet(isPresented: $showBookmarks) { BookmarksSheet(model: model) }
    }

    @ViewBuilder private var content: some View {
        if tab.isHome && tab.urlString.isEmpty {
            HomeView(model: model) { omni = $0; go() }
        } else {
            WebContainer(tab: tab).ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: tab.urlString.hasPrefix("https") ? "lock.fill" : "globe")
                    .foregroundColor(Theme.textHint).font(.system(size: 13))
                TextField("Search or enter address", text: $omni)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .foregroundColor(Theme.text)
                    .focused($omniFocused)
                    .onSubmit { go() }
                if !omni.isEmpty {
                    Button { omni = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Theme.textHint)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.cardGrey)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(omniFocused ? Theme.neonRed : Theme.redGlow, lineWidth: 1))

            HStack(spacing: 0) {
                toolButton("chevron.backward", enabled: tab.canGoBack) { tab.webView.goBack() }
                toolButton("chevron.forward", enabled: tab.canGoForward) { tab.webView.goForward() }
                toolButton("house") { model.goHome(); omni = "" }
                toolButton(store.isBookmarked(tab.urlString) ? "star.fill" : "star",
                           tint: store.isBookmarked(tab.urlString) ? Theme.neonRed : Theme.text) {
                    if !tab.urlString.isEmpty { store.toggleBookmark(url: tab.urlString, title: tab.title) }
                }
                tabsButton
                menuButton
            }
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 6)
        .background(Theme.darkGrey.ignoresSafeArea(edges: .bottom))
    }

    private var tabsButton: some View {
        Button { showTabs = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5).stroke(Theme.text, lineWidth: 1.8)
                    .frame(width: 22, height: 22)
                Text("\(model.tabs.count)").font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.text)
            }.frame(maxWidth: .infinity)
        }
    }

    private var menuButton: some View {
        Menu {
            Button { showBookmarks = true } label: { Label("Bookmarks", systemImage: "star") }
            Button { model.newTab() } label: { Label("New tab", systemImage: "plus.square") }
            Button { tab.webView.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
            Button {
                if let u = tab.webView.url { UIPasteboard.general.string = u.absoluteString }
            } label: { Label("Copy URL", systemImage: "doc.on.doc") }
            Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.text).frame(maxWidth: .infinity)
        }
    }

    private func toolButton(_ icon: String, enabled: Bool = true, tint: Color = Theme.text,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18))
                .foregroundColor(enabled ? tint : Theme.textHint)
                .frame(maxWidth: .infinity, minHeight: 30)
        }.disabled(!enabled)
    }

    private func displayURL(_ s: String) -> String { s.isEmpty ? "" : s }

    private func go() {
        omniFocused = false
        guard let url = store.resolve(input: omni) else { return }
        model.load(url)
    }
}
