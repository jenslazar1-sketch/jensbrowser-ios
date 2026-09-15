import Foundation
import WebKit

/// Declarative tracker/content blocking via WKContentRuleList. iOS has no
/// per-request `shouldInterceptRequest`, so blocking is compiled rules, not a
/// live filter — but it still layers user domains over a built-in tracker list.
enum ContentBlocking {

    static let builtinTrackers: [String] = [
        "doubleclick.net", "googlesyndication.com", "google-analytics.com",
        "googletagmanager.com", "googleadservices.com", "adservice.google.com",
        "scorecardresearch.com", "adnxs.com", "criteo.com", "taboola.com",
        "outbrain.com", "amazon-adsystem.com", "facebook.net", "connect.facebook.net",
        "quantserve.com", "moatads.com", "rubiconproject.com", "pubmatic.com",
        "casalemedia.com", "bidswitch.net", "advertising.com", "adroll.com",
    ]

    /// Build the WKContentRuleList JSON: block third-party loads to each domain.
    static func rulesJSON(userDomains: [String]) -> String {
        let domains = (builtinTrackers + userDomains)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        var rules: [[String: Any]] = []
        for d in Set(domains) {
            let escaped = NSRegularExpression.escapedPattern(for: d)
            rules.append([
                "trigger": [
                    "url-filter": "^https?://([^/]+\\.)?\(escaped)",
                    "load-type": ["third-party"],
                ],
                "action": ["type": "block"],
            ])
        }
        let data = (try? JSONSerialization.data(withJSONObject: rules, options: [])) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func compile(userDomains: [String],
                        completion: @escaping (WKContentRuleList?) -> Void) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "j3ns-blocklist",
            encodedContentRuleList: rulesJSON(userDomains: userDomains)) { list, error in
            if let error = error { print("content rule compile error: \(error)") }
            DispatchQueue.main.async { completion(list) }
        }
    }

    /// Parse the user's block-rules editor text: one domain per line, `#` comments.
    static func parseUserDomains(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if let h = line.firstIndex(of: "#") { line = String(line[line.startIndex..<h]) }
            line = line.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { out.append(line) }
        }
        return out
    }
}
