import Foundation
import ScreenCheckCore

extension RunResult {
    /// One word: the business model or page kind ("SaaS"). Nil when the run has none.
    var uiContextLabel: String? {
        context?.label.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }
    var uiContextNote: String? {
        let t = contextNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty ?? true) ? nil : t
    }
}
