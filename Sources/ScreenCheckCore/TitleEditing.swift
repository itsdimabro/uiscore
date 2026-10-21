import Foundation

/// Rules for editing the screenshot title in place.
public enum TitleEditing {
    public static let defaultName = "Screenshot"
    /// Selection when editing starts: the whole text for the default name (so typing replaces it), otherwise a caret at the end.
    public static func initialSelection(for name: String) -> NSRange {
        let n = (name as NSString).length
        return name == defaultName ? NSRange(location: 0, length: n) : NSRange(location: n, length: 0)
    }
}

/// Rules for page names. Generated names are cleaned; typed names are limited as the user types.
public enum PageName {
    public static let maxWords = 3
    public static let maxChars = 32
    static let separators = CharacterSet(charactersIn: "·•∙|/\\:;,–—~_<>()[]{}\"“”‘’`*#")

    /// Model-written name: separators removed, first 3 words, each word starts with a capital (the rest of a word is kept,
    /// so "TypeSafe" and "API" stay as written), at most 32 characters. Nil when nothing usable is left.
    public static func generated(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let spaced = raw.unicodeScalars.map { separators.contains($0) ? " " : Character($0) }
        let words = String(spaced).split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-.!?&+=@$%^'")) }
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
            .prefix(maxWords)
            .map { w in w.prefix(1).uppercased() + w.dropFirst() }
        var out = ""
        for w in words {
            let next = out.isEmpty ? w : out + " " + w
            if next.count > maxChars { if out.isEmpty { out = String(w.prefix(maxChars)) }; break }
            out = next
        }
        return out.isEmpty ? nil : out
    }

    /// What the field may hold while typing: 3 words, 32 characters. Extra words and characters are not accepted.
    public static func limitTyped(_ s: String) -> String {
        let words = s.split(whereSeparator: \.isWhitespace).prefix(maxWords)
        var out = words.joined(separator: " ")
        if s.last?.isWhitespace == true, words.count < maxWords, !out.isEmpty { out += " " }
        return String(out.prefix(maxChars))
    }
}
