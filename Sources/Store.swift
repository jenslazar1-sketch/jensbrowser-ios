import Foundation

struct Bookmark: Codable, Identifiable, Hashable {
    var url: String
    var title: String
    var id: String { url }
}

/// User settings + bookmarks, backed by UserDefaults (the iOS analogue of the
/// Android build's BrowserPrefs / BrowsingStore).
final class Store: ObservableObject {
    static let shared = Store()
    private let d = UserDefaults.standard

    @Published var bookmarks: [Bookmark] = []
    @Published var userBangsText: String = ""
    @Published var searchTemplate: String = "https://duckduckgo.com/?q={q}"
    @Published var desktopMode: Bool = false
    @Published var userAgentOverride: String = ""

    private init() { load() }

    func load() {
        if let data = d.data(forKey: "bookmarks"),
           let bm = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = bm
        }
        userBangsText = d.string(forKey: "userBangs") ?? ""
        searchTemplate = d.string(forKey: "searchTemplate") ?? searchTemplate
        desktopMode = d.bool(forKey: "desktopMode")
        userAgentOverride = d.string(forKey: "userAgentOverride") ?? ""
    }

    func save() {
        if let data = try? JSONEncoder().encode(bookmarks) { d.set(data, forKey: "bookmarks") }
        d.set(userBangsText, forKey: "userBangs")
        d.set(searchTemplate, forKey: "searchTemplate")
        d.set(desktopMode, forKey: "desktopMode")
        d.set(userAgentOverride, forKey: "userAgentOverride")
    }

    func isBookmarked(_ url: String) -> Bool { bookmarks.contains { $0.url == url } }

    func toggleBookmark(url: String, title: String) {
        if isBookmarked(url) {
            bookmarks.removeAll { $0.url == url }
        } else {
            bookmarks.insert(Bookmark(url: url, title: title.isEmpty ? url : title), at: 0)
        }
        save()
    }

    func removeBookmark(_ b: Bookmark) {
        bookmarks.removeAll { $0.url == b.url }
        save()
    }

    // MARK: - Omnibox input -> URL (port of the Android toUrl() fallback chain)

    func resolve(input raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if let bang = Bangs.expand(s, userText: userBangsText), let u = URL(string: bang) {
            return u
        }
        if let direct = Self.asDirectURL(s) { return direct }
        let enc = Bangs.encode(s)
        return URL(string: searchTemplate.replacingOccurrences(of: "{q}", with: enc))
    }

    static func asDirectURL(_ s: String) -> URL? {
        let lower = s.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("about:") {
            return URL(string: s)
        }
        if s.contains(" ") { return nil }
        if s.contains("."), !s.hasSuffix("."), !s.hasPrefix(".") {
            return URL(string: "https://" + s)
        }
        return nil
    }
}
