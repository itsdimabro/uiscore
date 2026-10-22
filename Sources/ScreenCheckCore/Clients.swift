import Foundation

public enum Net {
    static func send(_ req: URLRequest, who: String, retries: Int = 3) async throws -> Data {
        var attempt = 0
        while true {
            let data: Data, resp: URLResponse
            do { (data, resp) = try await URLSession.shared.data(for: req) }
            catch { throw PipelineError.network(error.localizedDescription) }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (code == 429 || code == 529) && attempt < retries { attempt += 1; try await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt))); continue }
            // Anthropic reports an empty balance as a 400; treat it as 402 so key fallback sees it.
            if code == 400, String(data: data, encoding: .utf8)?.contains("credit balance") == true { throw PipelineError.api(who, 402) }
            if !(200..<300).contains(code) { throw PipelineError.api(who, code) }
            return data
        }
    }
}

public enum Claude {
    public static let model = "claude-haiku-5-5"
    public static let sonnet = "claude-sonnet-5-5"

    /// Tries the keys in order; a key that is rejected, out of credit or rate-limited hands the call to the next one.
    /// The system prompt as content blocks; with `cache` the block is marked for prompt caching so repeated votes reuse it.
    static func systemBlocks(_ system: String, cache: Bool) -> [[String: Any]] {
        var b: [String: Any] = ["type": "text", "text": system]
        if cache { b["cache_control"] = ["type": "ephemeral"] }
        return [b]
    }

    public static func call(keys: [String], system: String, content: [[String: Any]], maxTokens: Int, model: String = Claude.model, cacheSystem: Bool = false) async throws -> (json: JSONValue, ms: Double) {
        try await KeyFallback.run(keys: keys) { key, last in
            try await call(key: key, system: system, content: content, maxTokens: maxTokens, model: model, retries: last ? 3 : 0, cacheSystem: cacheSystem)
        }
    }

    public static func call(key: String, system: String, content: [[String: Any]], maxTokens: Int, model: String = Claude.model, retries: Int = 3, cacheSystem: Bool = false) async throws -> (json: JSONValue, ms: Double) {
        let t = Date()
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = ["model": model, "max_tokens": maxTokens,
                                   "messages": [["role": "user", "content": content]]]
        if !system.isEmpty { body["system"] = cacheSystem ? systemBlocks(system, cache: true) : system }
        if model == Claude.model { body["thinking"] = ["type": "disabled"] }   // Sonnet rejects "disabled" and does not think by default
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await Net.send(req, who: "Claude", retries: retries)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = obj["content"] as? [[String: Any]] else { throw PipelineError.badModelOutput("no content") }
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        do { return (try JSONValue.firstObject(in: text), Date().timeIntervalSince(t) * 1000) }
        catch {
            let why = (obj["stop_reason"] as? String) ?? "?"
            if ProcessInfo.processInfo.environment["SCREENCHECK_DEBUG"] != nil {
                FileHandle.standardError.write(Data("bad reply (stop_reason \(why), \(text.count) chars, max_tokens \(maxTokens)): \(text.prefix(120))…\(text.suffix(80))\n".utf8))
            }
            throw error
        }
    }
}

public enum Jev {
    /// One request, all questions. Returns id -> P(yes).
    public static func ask(key: String, state: JSONValue, questions: [String: String], retries: Int = 3) async throws -> (p: [String: Double], ms: Double) {
        let t = Date()
        var req = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let qs = questions.mapValues { ["type": "noul", "instructions": $0] }
        let stateObj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": "jev-1.13.0", "state": stateObj, "questions": qs])
        let data = try await Net.send(req, who: "Jev", retries: retries)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = obj["answers"] as? [String: [String: Any]] else { throw PipelineError.badModelOutput("no answers") }
        var out: [String: Double] = [:]
        for (k, v) in answers { if let n = v["noul"] as? Double { out[k] = n } }
        return (out, Date().timeIntervalSince(t) * 1000)
    }
}
