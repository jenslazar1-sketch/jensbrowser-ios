import Foundation
import Combine

/// A user mod: CSS + JS attached to a host glob, injected at page-finished
/// (mirrors the Android UserScripts, which injects from onPageFinished).
struct UserMod: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = "New mod"
    var hostGlob: String = "*"
    var css: String = ""
    var js: String = ""
    var enabled: Bool = true
}

final class UserScriptsStore: ObservableObject {
    static let shared = UserScriptsStore()
    private let d = UserDefaults.standard
    private let key = "userMods"

    @Published var mods: [UserMod] = []

    private init() {
        if let data = d.data(forKey: key),
           let m = try? JSONDecoder().decode([UserMod].self, from: data) {
            mods = m
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(mods) { d.set(data, forKey: key) }
    }

    func upsert(_ mod: UserMod) {
        if let i = mods.firstIndex(where: { $0.id == mod.id }) { mods[i] = mod } else { mods.append(mod) }
        save()
    }

    func delete(_ mod: UserMod) { mods.removeAll { $0.id == mod.id }; save() }

    /// Enabled mods whose glob matches this host.
    func matching(host: String) -> [UserMod] {
        mods.filter { $0.enabled && Self.hostMatches(host, glob: $0.hostGlob) }
    }

    // MARK: - injection

    /// One self-contained IIFE per mod: CSS appended as a <style>, JS in its own
    /// function scope inside a try, so one broken mod can't take down the others.
    static func injectionJS(for mod: UserMod) -> String {
        var body = ""
        if !mod.css.isEmpty {
            body += "var s=document.createElement('style');s.textContent=\(jsLiteral(mod.css));" +
                    "(document.head||document.documentElement).appendChild(s);"
        }
        if !mod.js.isEmpty { body += "\n" + mod.js + "\n" }
        return "(function(){try{\(body)}catch(e){console.error('[mod \(mod.name)]',e);}})();"
    }

    /// A properly-escaped JS string literal for arbitrary text.
    static func jsLiteral(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [])) ?? Data("[\"\"]".utf8)
        let arr = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())   // strip the surrounding [ ]
    }

    static func hostMatches(_ host: String, glob rawGlob: String) -> Bool {
        let g = rawGlob.trimmingCharacters(in: .whitespaces).lowercased()
        let h = host.lowercased()
        if g.isEmpty || g == "*" { return true }
        if g.hasPrefix("*.") {
            let suffix = String(g.dropFirst(2))
            return h == suffix || h.hasSuffix("." + suffix)
        }
        if g.contains("*") {
            let parts = g.split(separator: "*", omittingEmptySubsequences: false)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = "^" + parts.joined(separator: ".*") + "$"
            if let re = try? NSRegularExpression(pattern: pattern) {
                return re.firstMatch(in: h, range: NSRange(h.startIndex..., in: h)) != nil
            }
            return false
        }
        return h == g || h.hasSuffix("." + g)
    }
}
