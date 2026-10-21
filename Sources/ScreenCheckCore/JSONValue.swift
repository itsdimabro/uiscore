import Foundation

/// Lenient JSON value: the vision model's answers vary in type, so fields are read through helpers.
public enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue { if case .object(let o) = self { return o[key] ?? .null }; return .null }
    public var double: Double? {
        switch self {
        case .number(let d): return d
        case .string(let s): return Double(s.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }
    public var int: Int? { double.map { Int($0.rounded()) } }
    public var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
    public var bool: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let d): return d != 0
        case .string(let s): return ["true", "yes", "1"].contains(s.lowercased()) ? true : (["false", "no", "0"].contains(s.lowercased()) ? false : nil)
        default: return nil
        }
    }
    public var array: [JSONValue] { if case .array(let a) = self { return a }; return [] }

    /// Parse the first complete JSON object found in model text.
    public static func firstObject(in text: String) throws -> JSONValue {
        let chars = Array(text.utf8)
        guard let start = chars.firstIndex(of: UInt8(ascii: "{")) else { throw PipelineError.badModelOutput("no JSON in reply") }
        var depth = 0, inStr = false, esc = false
        for i in start..<chars.count {
            let c = chars[i]
            if inStr {
                if esc { esc = false } else if c == UInt8(ascii: "\\") { esc = true } else if c == UInt8(ascii: "\"") { inStr = false }
            } else if c == UInt8(ascii: "\"") { inStr = true }
            else if c == UInt8(ascii: "{") { depth += 1 }
            else if c == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 {
                    let data = Data(chars[start...i])
                    do { return try JSONDecoder().decode(JSONValue.self, from: data) }
                    catch { throw PipelineError.badModelOutput("invalid JSON in reply") }
                }
            }
        }
        // Cut off: keep the complete items before the cut by closing after the last finished object.
        let tailBytes = Array(chars[start...])
        if let r = tailBytes.lastIndex(of: UInt8(ascii: "}")) {
            let head = Data(tailBytes[...r])
            for tail in ["]}", "}", "]}}"] {
                if let v = try? JSONDecoder().decode(JSONValue.self, from: head + Data(tail.utf8)) { return v }
            }
        }
        throw PipelineError.badModelOutput("JSON reply was cut off")
    }
}

public enum PipelineError: Error, LocalizedError {
    case noKey(String), noScreenshot, network(String), api(String, Int), badModelOutput(String), unreadableImage, allKeysFailed

    public var errorDescription: String? {
        switch self {
        case .noKey(let n): return "No \(n) key yet. Open Settings and paste it in."
        case .noScreenshot: return "I could not find an image. Take a screenshot or copy an image, then try again."
        case .network: return "The internet request failed. Check your connection and try again."
        case .api(let who, let code): return "\(who) said no (code \(code)). Check the key in Settings, then try again."
        case .badModelOutput: return "The answer came back in a shape I could not read. Try again."
        case .unreadableImage: return "I could not open that image."
        case .allKeysFailed: return "Your Claude keys stopped working. Check them in Settings."
        }
    }
    public var isRetryable: Bool {
        switch self { case .network, .badModelOutput, .api: return true; default: return false }
    }
}
