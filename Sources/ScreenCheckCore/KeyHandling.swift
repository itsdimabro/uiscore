import Foundation

public struct Keys {
    /// Claude API keys in the order to try them.
    public var claude: [String]
    public var jev: String
    public init(claude: [String], jev: String) { self.claude = claude; self.jev = jev }
    public init(anthropic: String, jev: String) { self.init(claude: anthropic.isEmpty ? [] : [anthropic], jev: jev) }
    public var anthropic: String { claude.first ?? "" }
}

public enum KeyFallback {
    /// Errors that mean "this key can't do it right now": rejected, out of credit, rate-limited, overloaded.
    public static func shouldFallback(_ e: Error) -> Bool {
        if case PipelineError.api(_, let c) = e { return [401, 402, 403, 429, 529].contains(c) }
        return false
    }
    /// Runs `op` with key 1. If that key is refused, runs it again with the next key, and so on down the list.
    /// `op` gets the key and whether it is the last one. Every key refused -> `allKeysFailed`. Other errors pass straight through.
    public static func run<T>(keys: [String], _ op: (String, Bool) async throws -> T) async throws -> T {
        guard !keys.isEmpty else { throw PipelineError.noKey("Claude") }
        for (i, k) in keys.enumerated() {
            do { return try await op(k, i == keys.count - 1) }
            catch { if !shouldFallback(error) { throw error } }
        }
        throw PipelineError.allKeysFailed
    }
}

/// Rules for the key form. Pure, so the window and the tests share them.
public enum KeyRules {
    public enum Field: Equatable { case jev, claude(Int) }
    public struct Issue: Equatable { public let field: Field; public let message: String }

    public static func validate(jev: String, claude: [String]) -> [Issue] {
        var out: [Issue] = []
        let j = jev.trimmingCharacters(in: .whitespacesAndNewlines)
        if j.isEmpty { out.append(Issue(field: .jev, message: "Paste your Jev key.")) }
        else if j.contains(where: { $0.isWhitespace }) { out.append(Issue(field: .jev, message: "This key has a space in it. Copy it again.")) }
        var seen = Set<String>()
        var any = false
        for (i, raw) in claude.enumerated() {
            let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if k.isEmpty { continue }
            any = true
            if k.contains(where: { $0.isWhitespace }) { out.append(Issue(field: .claude(i), message: "This key has a space in it. Copy it again.")) }
            else if !k.hasPrefix("sk-ant-") { out.append(Issue(field: .claude(i), message: "That doesn't look like a Claude key. It starts with sk-ant-.")) }
            else if !seen.insert(k).inserted { out.append(Issue(field: .claude(i), message: "You already added this key.")) }
        }
        if !any { out.append(Issue(field: .claude(0), message: "Add at least one Claude key.")) }
        return out
    }
    /// Trimmed, empty rows dropped, repeats dropped, order kept.
    public static func cleaned(_ claude: [String]) -> [String] {
        var seen = Set<String>()
        return claude.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    /// Only the last 4 characters are ever shown.
    public static func mask(_ key: String) -> String { key.count > 8 ? "••••" + key.suffix(4) : "••••" }
}

public enum KeyVerdict: Equatable {
    case ok, rejected, noCredit, busy, offline, unknown
    public func plain(_ who: String) -> String {
        switch self {
        case .ok: return "Works"
        case .rejected: return "\(who) said no. Check that you copied the whole key."
        case .noCredit: return "No credit left on this key."
        case .busy: return "\(who) is busy. Try again in a minute."
        case .offline: return "Could not reach the internet."
        case .unknown: return "Something went wrong. Try again."
        }
    }
    public static func from(_ e: Error) -> KeyVerdict {
        if let p = e as? PipelineError {
            switch p {
            case .network: return .offline
            case .api(_, let c):
                switch c { case 401, 403: return .rejected; case 402: return .noCredit; case 429, 529: return .busy; default: return .unknown }
            default: return .unknown
            }
        }
        return .unknown
    }
}

/// Cheap live checks for the "Test keys" button. One list call for Claude, one tiny question for Jev.
public enum KeyCheck {
    public static func claude(_ key: String) async -> KeyVerdict {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
        req.timeoutInterval = 20
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        do { _ = try await Net.send(req, who: "Claude", retries: 0); return .ok } catch { return .from(error) }
    }
    public static func jev(_ key: String) async -> KeyVerdict {
        do { _ = try await Jev.ask(key: key, state: .object(["text": .string("UIScore key test.")]), questions: ["t": "Is the text a sentence?"], retries: 0); return .ok }
        catch { return .from(error) }
    }
}
