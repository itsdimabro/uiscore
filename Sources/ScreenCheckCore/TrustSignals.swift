import AppKit

/// Trust signals that code can read straight from the screen's text (Fogg et al. 2003: tone, typos, overblown claims).
enum TrustSignals {
    static func norm(_ s: String) -> String {
        " " + s.lowercased().replacingOccurrences(of: "[^a-z0-9#' ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression) + " "
    }
    static func hits(_ text: String, _ phrases: [String]) -> Int {
        let t = norm(text)
        return phrases.reduce(0) { $0 + (t.contains(" " + $1 + " ") ? 1 : 0) }
    }

    static let hype = ["best ever", "best in the world", "number 1", "#1", "ultimate", "never before", "revolutionary", "10x", "world's best", "greatest", "guaranteed", "100% guaranteed", "amazing", "incredible", "unbeatable", "game changing", "game changer", "life changing", "mind blowing", "miracle", "perfect", "the best"]
    static let vague = ["world class", "cutting edge", "state of the art", "next generation", "next gen", "innovative", "seamless", "seamlessly", "best in class", "leading provider", "synergy", "empower", "empowers", "revolutionize", "robust", "holistic", "turnkey", "solutions"]
    static let hedges = ["maybe", "perhaps", "might", "hopefully", "i think", "we think", "we believe", "kind of", "sort of", "try to", "possibly", "probably", "somewhat", "we hope", "attempt to", "not sure"]
    static let pressure = ["act now", "last chance", "hurry", "limited time", "ends today", "ends soon", "expires", "don't miss", "while supplies last", "only left", "selling fast", "countdown", "today only", "offer ends", "final hours", "don't wait"]

    /// Hype words, "!!", or two or more shouted (ALL CAPS, 3+ word) lines.
    static func hasHype(copy: String, boxes: [TextBox]) -> Bool {
        let plain = copy.replacingOccurrences(of: "best practice", with: "", options: .caseInsensitive)
        if hits(plain, hype) > 0 || copy.contains("!!") { return true }
        let shouted = boxes.filter { b in
            let ws = Readability.splitWords(b.text)
            return ws.count >= 3 && b.text == b.text.uppercased() && b.text.contains { $0.isLetter }
        }.count
        return shouted >= 2
    }
    static func isVague(_ copy: String) -> Bool { hits(copy, vague) >= 2 }
    static func isHedging(_ copy: String) -> Bool { hits(copy, hedges) >= 2 }
    /// "only 3 left" style counters count too.
    static func hasPressure(_ copy: String) -> Bool {
        hits(copy, pressure) > 0 || copy.lowercased().range(of: #"only \d+ (left|remaining)"#, options: .regularExpression) != nil
    }

    static let techWords: Set<String> = ["codebase", "changelog", "workflow", "workflows", "repo", "repos", "app", "apps", "api", "apis", "login", "signup", "onboarding", "backend", "frontend", "plugin", "plugins", "webhook", "webhooks", "dev", "devs", "saas", "dropdown", "checkbox", "username", "online", "email", "emails", "wifi", "autocomplete", "github", "dashboard", "dashboards", "metadata", "blockchain", "integrations", "roadmap", "roadmaps", "analytics", "workspace", "workspaces", "customizable", "timeline", "backlog", "navbar", "sidebar", "popup", "popups", "unsubscribe", "ios", "macos", "screenshot", "screenshots", "toolbar", "hotkey", "hotkeys", "setup", "cloud"]

    /// Misspelled plain lowercase words, plus doubled words ("the the"). Names, acronyms, code and
    /// anything with digits or symbols are skipped, so only clear typos are counted.
    static func typos(in boxes: [TextBox]) -> [String] {
        var found = Set<String>()
        let checker = NSSpellChecker.shared
        for b in boxes where !["demo", "logo", "legal"].contains(b.role) {
            let toks = b.text.split(whereSeparator: { $0.isWhitespace }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?()\"“”‘’[]")) }
            var prev = ""
            for (i, w) in toks.enumerated() {
                let lw = w.lowercased()
                if i > 0, lw == prev, lw.count >= 3, lw.allSatisfy({ $0.isLetter }) { found.insert(lw + " " + lw) }
                prev = lw
                guard w.count >= 4, w.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.lowercaseLetters.contains($0) }), !techWords.contains(w) else { continue }
                let r = checker.checkSpelling(of: w, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
                if r.location != NSNotFound { found.insert(w) }
            }
        }
        return found.sorted()
    }
    /// Two or more different typos fail; one can be an OCR slip.
    static func hasTypos(_ boxes: [TextBox]) -> Bool { typos(in: boxes).count >= 2 }
}
