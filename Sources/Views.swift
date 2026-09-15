import SwiftUI

// MARK: - Home / speed dial

struct HomeView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var store = Store.shared
    var onOpen: (String) -> Void

    private let cols = [GridItem(.adaptive(minimum: 84), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("J3NSONTOP")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.neonRed)
                    .shadow(color: Theme.neonRed.opacity(0.6), radius: 12)
                    .padding(.top, 48)
                Text("BROWSER")
                    .font(.system(size: 12, weight: .semibold)).tracking(6)
                    .foregroundColor(Theme.textHint)

                if store.bookmarks.isEmpty {
                    Text("Bookmark a page and it lands here.")
                        .foregroundColor(Theme.textHint).font(.system(size: 13))
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: cols, spacing: 18) {
                        ForEach(store.bookmarks) { bm in
                            SpeedTile(bookmark: bm) { onOpen(bm.url) }
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 12)
                }
                Spacer(minLength: 40)
            }.frame(maxWidth: .infinity)
        }
        .background(Theme.black)
    }
}

struct SpeedTile: View {
    let bookmark: Bookmark
    var onTap: () -> Void
    private var letter: String {
        String((bookmark.title.first ?? bookmark.url.first ?? "?")).uppercased()
    }
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Theme.cardGrey)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.redGlow, lineWidth: 1))
                        .frame(width: 64, height: 64)
                    Text(letter).font(.system(size: 26, weight: .bold)).foregroundColor(Theme.neonRed)
                }
                Text(host(bookmark.url)).font(.system(size: 11)).foregroundColor(Theme.textHint)
                    .lineLimit(1).frame(width: 80)
            }
        }
    }
    private func host(_ u: String) -> String {
        URL(string: u)?.host?.replacingOccurrences(of: "www.", with: "") ?? u
    }
}

// MARK: - Tabs

struct TabsSheet: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            List {
                ForEach(model.tabs) { t in
                    TabRow(tab: t,
                           active: t.id == model.activeTab?.id,
                           onSelect: { model.select(t); dismiss() },
                           onClose: { model.closeTab(t) })
                        .listRowBackground(Theme.darkGrey)
                }
            }
            .scrollContentBackgroundHiddenCompat()
            .background(Theme.black)
            .navigationTitle("Tabs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { model.newTab(); dismiss() } label: { Image(systemName: "plus") }
                        .tint(Theme.neonRed)
                }
            }
        }
    }
}

struct TabRow: View {
    @ObservedObject var tab: Tab
    let active: Bool
    var onSelect: () -> Void
    var onClose: () -> Void
    var body: some View {
        HStack {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title).foregroundColor(active ? Theme.neonRed : Theme.text)
                        .lineLimit(1)
                    Text(tab.urlString.isEmpty ? "Home" : tab.urlString)
                        .font(.system(size: 11)).foregroundColor(Theme.textHint).lineLimit(1)
                }
            }
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark").foregroundColor(Theme.textHint) }
        }
    }
}

// MARK: - Bookmarks

struct BookmarksSheet: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            List {
                ForEach(store.bookmarks) { bm in
                    Button {
                        if let u = URL(string: bm.url) { model.load(u); dismiss() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bm.title).foregroundColor(Theme.text).lineLimit(1)
                            Text(bm.url).font(.system(size: 11)).foregroundColor(Theme.textHint).lineLimit(1)
                        }
                    }.listRowBackground(Theme.darkGrey)
                }
                .onDelete { idx in idx.map { store.bookmarks[$0] }.forEach { store.removeBookmark($0) } }
            }
            .scrollContentBackgroundHiddenCompat()
            .background(Theme.black)
            .navigationTitle("Bookmarks")
        }
    }
}

// MARK: - Settings

struct SettingsSheet: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    private let engines: [(String, String)] = [
        ("DuckDuckGo", "https://duckduckgo.com/?q={q}"),
        ("Google", "https://www.google.com/search?q={q}"),
        ("Bing", "https://www.bing.com/search?q={q}"),
        ("Brave", "https://search.brave.com/search?q={q}"),
    ]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Search engine").foregroundColor(Theme.neonRed)) {
                    ForEach(engines, id: \.1) { name, tmpl in
                        Button {
                            store.searchTemplate = tmpl; store.save()
                        } label: {
                            HStack {
                                Text(name).foregroundColor(Theme.text)
                                Spacer()
                                if store.searchTemplate == tmpl {
                                    Image(systemName: "checkmark").foregroundColor(Theme.neonRed)
                                }
                            }
                        }.listRowBackground(Theme.darkGrey)
                    }
                }
                Section(header: Text("Page rendering").foregroundColor(Theme.neonRed)) {
                    Toggle("Desktop mode", isOn: Binding(
                        get: { store.desktopMode },
                        set: { store.desktopMode = $0; store.save(); model.reapplyAllTabSettings() }))
                        .tint(Theme.neonRed).foregroundColor(Theme.text)
                        .listRowBackground(Theme.darkGrey)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom User-Agent (overrides desktop mode)")
                            .font(.system(size: 12)).foregroundColor(Theme.textHint)
                        TextField("leave blank for default", text: Binding(
                            get: { store.userAgentOverride },
                            set: { store.userAgentOverride = $0 }))
                            .foregroundColor(Theme.text).autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                        Button("Apply") { store.save(); model.reapplyAllTabSettings() }
                            .tint(Theme.neonRed)
                    }.listRowBackground(Theme.darkGrey)
                }
                Section(header: Text("Address-bar bangs").foregroundColor(Theme.neonRed),
                        footer: Text("One per line:  keyword  https://site/?q={q}   (# comments)")
                            .foregroundColor(Theme.textHint)) {
                    TextEditor(text: Binding(
                        get: { store.userBangsText },
                        set: { store.userBangsText = $0 }))
                        .frame(minHeight: 120).foregroundColor(Theme.text)
                        .scrollContentBackgroundHiddenCompat()
                        .listRowBackground(Theme.darkGrey)
                    Button("Save bangs") { store.save() }.tint(Theme.neonRed)
                        .listRowBackground(Theme.darkGrey)
                }
                Section {
                    Text("J3NSONTOP Browser  \u{2022}  iOS port  \u{2022}  v0.1.0")
                        .font(.system(size: 12)).foregroundColor(Theme.textHint)
                        .listRowBackground(Theme.darkGrey)
                }
            }
            .scrollContentBackgroundHiddenCompat()
            .background(Theme.black)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.tint(Theme.neonRed)
                }
            }
        }
    }
}

// MARK: - compat helper (scrollContentBackground is iOS 16+)

extension View {
    @ViewBuilder func scrollContentBackgroundHiddenCompat() -> some View {
        if #available(iOS 16.0, *) { self.scrollContentBackground(.hidden) }
        else { self }
    }
}
