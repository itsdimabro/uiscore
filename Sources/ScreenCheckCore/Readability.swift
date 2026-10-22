import Foundation

/// Reading level: ARI grade plus the rules for which copy counts.
public enum Readability {
    static let whitelist: Set<String> = {
        let base = ["hierarchy", "typography", "typographic", "contrast", "affordance", "kerning", "leading",
                    "proximity", "gestalt", "heuristic", "accessibility", "consistency", "palette", "saturation",
                    "modular", "interface", "usability", "semantic", "viewport", "responsive", "wireframe",
                    "prototype", "component", "layout", "serif", "baseline", "grid", "eyebrow", "overline",
                    "colorblind", "cognitive", "valence", "arousal", "guideline", "guidelines", "convention",
                    "isolation", "attention", "eye-tracking"]
        var s = Set<String>()
        for w in base { s.insert(w); s.insert(w + "s"); s.insert(w + "es") }
        return s
    }()
    static let whitelistChars = 5
    public static let minWords = 20

    static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    /// /[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu
    public static func splitWords(_ text: String) -> [String] {
        var words: [String] = [], cur = ""
        for ch in text {
            if cur.isEmpty { if isWordChar(ch) { cur.append(ch) } }
            else if isWordChar(ch) || ch == "'" || ch == "\u{2019}" || ch == "-" { cur.append(ch) }
            else { words.append(cur); cur = "" }
        }
        if !cur.isEmpty { words.append(cur) }
        return words
    }

    /// split on whitespace after . ! ? or on newlines; keep pieces with words.
    public static func splitSentences(_ text: String) -> [String] {
        var out: [String] = [], cur = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\n" { out.append(cur); cur = "" }
            else if c.isWhitespace, let last = cur.last, ".!?".contains(last) { out.append(cur); cur = "" }
            else { cur.append(c) }
            i += 1
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !splitWords($0).isEmpty }
    }

    static func letterCount(_ w: String) -> Int { w.filter { $0.isLetter || $0.isNumber }.count }

    /// ARI, rounded and floored at 0. 
    public static func ariGrade(_ text: String) -> Int {
        let words = splitWords(text), sentences = splitSentences(text)
        if words.isEmpty || sentences.isEmpty { return 0 }
        let chars = words.reduce(0) { n, w in
            let c = letterCount(w)
            return n + (whitelist.contains(w.lowercased()) ? min(c, whitelistChars) : c)
        }
        let raw = 4.71 * Double(chars) / Double(words.count) + 0.5 * Double(words.count) / Double(sentences.count) - 21.43
        return max(0, Int(raw.rounded()))
    }

    /// Reading level for the copy lines that count; nil when under 20 words.
    /// `grade` is shown on a 1-12 scale; `capped` means the real grade is above 12 and the UI shows "12+".
    public static func grade(forCopy lines: [String]) -> (grade: Int, words: Int, capped: Bool)? {
        let text = lines.joined(separator: "\n")
        let n = splitWords(text).count
        if n < minWords { return nil }
        let raw = ariGrade(text)
        return (min(12, max(1, raw)), n, raw > 12)
    }

    /// Reading copy from geometry only (role labels cannot shift the grade). OCR often splits one headline or paragraph
    /// into short lines, so lines stacked tightly under each other with similar height and overlapping width are merged
    /// into one paragraph. A paragraph counts when it has 2+ lines and 3+ words, or one line of 6+ words outside the top 10% (nav row). Nav items and
    /// buttons are short single lines, so they fall out; a headline split over two lines stays in.
    public static func countedParagraphs(_ boxes: [TextBox], imageHeight: Int) -> [String] {
        let bs = boxes.filter { $0.text.contains { $0.isLetter } }
            .sorted { ($0.y, $0.x, $0.text) < ($1.y, $1.x, $1.text) }
        var paras: [[TextBox]] = []
        for b in bs {
            var joined = false
            for i in paras.indices.reversed() {
                guard let l = paras[i].last else { continue }
                let gap = b.y - (l.y + l.h)
                if b.y - l.y > l.h * 3 { break }
                let ratio = b.h / max(1, l.h)
                let overlap = min(l.x + l.w, b.x + b.w) - max(l.x, b.x)
                if gap < l.h * 0.9 && gap > -l.h * 0.3 && ratio > 0.75 && ratio < 1.33 && overlap > 0.3 * min(l.w, b.w) && abs(b.x - l.x) < max(l.h * 4, 0.25 * l.w) + 1 || (gap < l.h * 0.9 && gap > -l.h * 0.3 && ratio > 0.75 && ratio < 1.33 && overlap > 0.3 * min(l.w, b.w) && abs((b.x + b.w / 2) - (l.x + l.w / 2)) < l.h * 2) {
                    paras[i].append(b); joined = true; break
                }
            }
            if !joined { paras.append([b]) }
        }
        return paras.compactMap { p in
            let text = p.map { $0.text }.joined(separator: " ")
            let n = splitWords(text).count
            let top = p.map { $0.y }.min() ?? 0
            // A single line is body copy only with 6+ words and below the top 10% of the page (nav bar, banner row).
            guard (p.count >= 2 && n >= 3) || (n >= 6 && top > Double(imageHeight) * 0.10) else { return nil }
            return ".!?".contains(text.last ?? " ") ? text : text + "."
        }
    }

    /// The longest sentence and the hardest words (longest, 3 of them) in the counted copy, for the writer to name.
    public static func hardest(paras: [String]) -> [String: Any] {
        let text = paras.joined(separator: "\n")
        let longest = splitSentences(text).max { splitWords($0).count < splitWords($1).count } ?? ""
        var seen = Set<String>(), words: [String] = []
        for w in splitWords(text).sorted(by: { letterCount($0) > letterCount($1) }) where seen.insert(w.lowercased()).inserted { words.append(w); if words.count == 3 { break } }
        return ["longest_sentence": String(longest.prefix(120)), "hardest_words": words]
    }
}
