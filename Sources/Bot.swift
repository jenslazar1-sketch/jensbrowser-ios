import Foundation
import Combine

// Ported from the Android bot layer (AiBackend / AiRouter / clients). Three
// interchangeable backends; keys live in the Keychain, never bundled.

enum BotBackend: String, CaseIterable, Identifiable {
    case ollama, claude, openai
    var id: String { rawValue }
    var label: String {
        switch self { case .ollama: return "Ollama"; case .claude: return "Claude"; case .openai: return "OpenAI" }
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var role: String     // "user" | "assistant"
    var content: String
}

enum BotError: LocalizedError {
    case http(Int)
    case noKey(String)
    var errorDescription: String? {
        switch self {
        case .http(let c): return "Server returned HTTP \(c)"
        case .noKey(let name): return "No \(name) API key set — add it in Bot settings"
        }
    }
}

final class BotSettings: ObservableObject {
    static let shared = BotSettings()
    private let d = UserDefaults.standard

    @Published var backend: BotBackend { didSet { d.set(backend.rawValue, forKey: "botBackend") } }
    @Published var ollamaBase: String { didSet { d.set(ollamaBase, forKey: "ollamaBase") } }
    @Published var ollamaModel: String { didSet { d.set(ollamaModel, forKey: "ollamaModel") } }
    @Published var openaiModel: String { didSet { d.set(openaiModel, forKey: "openaiModel") } }
    @Published var claudeModel: String { didSet { d.set(claudeModel, forKey: "claudeModel") } }

    private init() {
        backend = BotBackend(rawValue: d.string(forKey: "botBackend") ?? "ollama") ?? .ollama
        ollamaBase = d.string(forKey: "ollamaBase") ?? "http://localhost:11434"
        ollamaModel = d.string(forKey: "ollamaModel") ?? "llama3.2"
        openaiModel = d.string(forKey: "openaiModel") ?? "gpt-4o-mini"
        claudeModel = d.string(forKey: "claudeModel") ?? "claude-opus-4-8"
    }
}

struct BotEngine {
    let settings: BotSettings

    func stream(history: [ChatMessage], pageContext: String?,
                onDelta: @escaping (String) -> Void) async throws {
        switch settings.backend {
        case .ollama: try await streamOllama(history, pageContext, onDelta)
        case .claude: try await streamClaude(history, pageContext, onDelta)
        case .openai: try await streamOpenAI(history, pageContext, onDelta)
        }
    }

    private func ctxTrim(_ s: String?) -> String? {
        guard let s = s, !s.isEmpty else { return nil }
        return String(s.prefix(6000))
    }

    private func check(_ resp: URLResponse) throws {
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BotError.http(http.statusCode)
        }
    }

    // Ollama: POST {base}/api/chat, newline-delimited JSON, done:true terminates.
    private func streamOllama(_ history: [ChatMessage], _ ctx: String?,
                              _ onDelta: @escaping (String) -> Void) async throws {
        var msgs: [[String: String]] = []
        if let c = ctxTrim(ctx) { msgs.append(["role": "system", "content": "Current page content:\n" + c]) }
        msgs += history.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = ["model": settings.ollamaModel, "messages": msgs, "stream": true]

        var req = URLRequest(url: URL(string: settings.ollamaBase + "/api/chat")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        try check(resp)
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let message = obj["message"] as? [String: Any],
               let content = message["content"] as? String, !content.isEmpty {
                onDelta(content)
            }
            if obj["done"] as? Bool == true { break }
        }
    }

    // Anthropic: POST /v1/messages, SSE, content_block_delta -> delta.text.
    private func streamClaude(_ history: [ChatMessage], _ ctx: String?,
                              _ onDelta: @escaping (String) -> Void) async throws {
        guard let key = Keychain.get("anthropic"), !key.isEmpty else { throw BotError.noKey("Anthropic") }
        let msgs = history.map { ["role": $0.role, "content": $0.content] }
        var body: [String: Any] = ["model": settings.claudeModel, "max_tokens": 1024,
                                   "stream": true, "messages": msgs]
        if let c = ctxTrim(ctx) { body["system"] = "You can see the page the user is viewing:\n" + c }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        try check(resp)
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if obj["type"] as? String == "content_block_delta",
               let delta = obj["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                onDelta(text)
            }
        }
    }

    // OpenAI: POST /v1/chat/completions, SSE, choices[0].delta.content, [DONE] ends.
    private func streamOpenAI(_ history: [ChatMessage], _ ctx: String?,
                              _ onDelta: @escaping (String) -> Void) async throws {
        guard let key = Keychain.get("openai"), !key.isEmpty else { throw BotError.noKey("OpenAI") }
        var msgs: [[String: String]] = []
        if let c = ctxTrim(ctx) { msgs.append(["role": "system", "content": "Current page:\n" + c]) }
        msgs += history.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = ["model": settings.openaiModel, "stream": true, "messages": msgs]

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        try check(resp)
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let choices = obj["choices"] as? [[String: Any]], let first = choices.first,
               let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                onDelta(content)
            }
        }
    }
}

final class BotViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var streaming = false
    @Published var error: String?

    let settings = BotSettings.shared
    private var task: Task<Void, Never>?

    func send(pageContext: String?) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !streaming else { return }
        input = ""; error = nil
        messages.append(ChatMessage(role: "user", content: text))
        messages.append(ChatMessage(role: "assistant", content: ""))
        let idx = messages.count - 1
        let history = Array(messages[0..<idx])
        streaming = true
        let engine = BotEngine(settings: settings)
        task = Task { [weak self] in
            do {
                try await engine.stream(history: history, pageContext: pageContext) { [weak self] delta in
                    DispatchQueue.main.async {
                        guard let self = self, self.messages.indices.contains(idx) else { return }
                        self.messages[idx].content += delta
                    }
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.error = msg
                    if self.messages.indices.contains(idx), self.messages[idx].content.isEmpty {
                        self.messages[idx].content = "\u{26A0} " + msg
                    }
                }
            }
            DispatchQueue.main.async { self?.streaming = false }
        }
    }

    func stop() { task?.cancel(); streaming = false }
    func clear() { messages.removeAll(); error = nil }
}
