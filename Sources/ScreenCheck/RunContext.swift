import Foundation
import ScreenCheckCore

/// Reads the page context the core adds to a run (`context.label`, `contextNote`) by name, so this target builds before and after
/// that core change lands. Runs saved without them answer nil and the header simply shows the size.
extension RunResult {
    private static func unwrap(_ v: Any) -> Any? {
        let m = Mirror(reflecting: v)
        guard m.displayStyle == .optional else { return v }
        return m.children.first?.value
    }
    private func field(_ name: String, in value: Any) -> Any? {
        guard let f = Mirror(reflecting: value).children.first(where: { $0.label == name })?.value else { return nil }
        return Self.unwrap(f)
    }
    /// One word: the business model or page kind ("SaaS"). Nil when the run has none.
    var uiContextLabel: String? {
        guard let c = field("context", in: self) else { return nil }
        let raw = (c as? String) ?? (field("label", in: c) as? String)
        guard let word = raw?.split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        return String(word)
    }
    var uiContextNote: String? {
        guard let n = field("contextNote", in: self) as? String else { return nil }
        let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
