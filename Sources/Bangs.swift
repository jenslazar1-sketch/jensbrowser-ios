import Foundation

// Faithful port of the Android BangShortcuts.expandWith(): DuckDuckGo-style
// address-bar bangs. Pure and platform-free.
enum Bangs {
    static let builtIn: [String: String] = [
        "g":   "https://www.google.com/search?q={q}",
        "ddg": "https://duckduckgo.com/?q={q}",
        "yt":  "https://www.youtube.com/results?search_query={q}",
        "w":   "https://en.wikipedia.org/w/index.php?search={q}",
        "gh":  "https://github.com/search?q={q}",
        "so":  "https://stackoverflow.com/search?q={q}",
        "r":   "https://www.reddit.com/search/?q={q}",
        "map": "https://www.google.com/maps/search/{q}",
        "a":   "https://www.amazon.com/s?k={q}",
        "img": "https://www.google.com/search?tbm=isch&q={q}",
        "npm": "https://www.npmjs.com/search?q={q}",
        "mdn": "https://developer.mozilla.org/en-US/search?q={q}",
        "tw":  "https://twitter.com/search?q={q}",
        "wa":  "https://www.wolframalpha.com/input?i={q}",
    ]

    // Uri.encode-style: percent-encode everything except unreserved chars.
    static func encode(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "-._~").union(.alphanumerics)
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Expand `input` if it starts with a known bang; else nil so the caller
    /// falls back to normal URL/search handling. Parses user bangs from raw
    /// editor text (`keyword url-with-{q}` per line, `#` comments).
    static func expand(_ input: String, userText: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("!"), trimmed.count >= 2 else { return nil }

        let body = String(trimmed.dropFirst())
        let keyword: String
        let query: String
        if let sp = body.firstIndex(of: " ") {
            keyword = String(body[body.startIndex..<sp]).lowercased()
            query = String(body[body.index(after: sp)...]).trimmingCharacters(in: .whitespaces)
        } else {
            keyword = body.lowercased()
            query = ""
        }

        guard let template = resolve(keyword, userText: userText) else { return nil }
        if query.isEmpty {
            if let r = template.range(of: "{q}") {
                let base = String(template[template.startIndex..<r.lowerBound])
                return base.isEmpty ? template : base
            }
            return template
        }
        return template.replacingOccurrences(of: "{q}", with: encode(query))
    }

    static func resolve(_ keyword: String, userText: String) -> String? {
        return parseUser(userText)[keyword] ?? builtIn[keyword]
    }

    /// `keyword url-with-{q}` per line; `#` starts a comment.
    static func parseUser(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") { line = String(line[line.startIndex..<hash]) }
            line = line.trimmingCharacters(in: .whitespaces)
            guard let sp = line.firstIndex(of: " ") else { continue }
            var key = String(line[line.startIndex..<sp]).trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("!") { key = String(key.dropFirst()) }
            key = key.lowercased()
            let url = String(line[line.index(after: sp)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && url.contains("{q}") { out[key] = url }
        }
        return out
    }

    static func allKeywords(userText: String) -> [String] {
        return Array(Set(Array(builtIn.keys) + Array(parseUser(userText).keys))).sorted()
    }
}
