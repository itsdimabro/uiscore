import Foundation

public struct TextBox: Codable, Equatable {
    public var text: String
    public var x: Double, y: Double, w: Double, h: Double
    public var fontPx: Double
    public var bold: Bool
    public var role: String   // heading|subhead|body|label|nav|button|logo|demo|legal
    public var onImage: Bool
    public init(text: String, x: Double, y: Double, w: Double, h: Double, fontPx: Double, bold: Bool, role: String, onImage: Bool) {
        self.text = text; self.x = x; self.y = y; self.w = w; self.h = h; self.fontPx = fontPx; self.bold = bold; self.role = role; self.onImage = onImage
    }
}

public struct CheckResult: Codable {
    public var id: String
    public var yes: Bool
    public var p: Double?        // Jev probability, nil for code checks
    public var weight: Int
    public var kind: String
}

public struct MeterResult: Codable {
    public var score: Int
    public var lowConfidence: Bool
    public var confidencePct: Int
    public var checks: [CheckResult]
    public var note: String?     // e.g. "only 9 of 40 text items checked"
    public var designer: Int? = nil      // designer rating on the 0-100 scale, when one was blended in
    public var applicable: Bool? = nil   // false: too few checks apply to this kind of screen; shown as "—", left out of Score
}

public struct MeterText: Codable, Equatable {
    public var why: String
    public var fix: String
}

public struct Timings: Codable {
    public var visionFields: Double = 0
    public var visionText: Double = 0
    public var ocr: Double = 0
    public var vision: Double = 0      // wall time of both vision calls together
    public var jev: Double = 0
    public var code: Double = 0
    public var scoresFirst: Double = 0 // from start to scores ready
    public var write: Double = 0
    public var total: Double = 0
    public var firstValue: Double? = nil // from start to the first value shown
    public init() {}
}

public struct RunResult: Codable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var pageName: String
    public var imageWidth: Int
    public var imageHeight: Int
    public var designerReason: String? = nil       // the designer's main reason, one sentence
    public var meters: [String: MeterResult]       // contrast, grouping, balance, order, familiar, ease, clarity, trust
    public var feeling: [String: Int]              // vv vi cv ci (0-100)
    public var feelingLow: [String: Bool]          // v / a
    public var feelingConfidencePct: [String: Int]
    public var readingGrade: Int?                  // 1-12; above 12 is stored as 12 with readingGradeCapped true
    public var readingGradeCapped: Bool? = nil
    public var readingWords: Int
    public var text: [String: MeterText]           // filled after scores
    public var timings: Timings
    public var contrastDetail: ContrastReport?
    public var vision: JSONValue
    public var pixelStats: PixelStats?
    public var overall: Int?
    /// Detected page context (nil on runs saved before it existed) and one sentence about what it changed.
    public var context: PageContext? = nil
    public var contextNote: String? = nil
    /// Hash of the decoded pixels (see Pipeline.imageHash); lets a copy of the same image find this run.
    public var imageHash: String?
}

extension RunResult {
    /// Scores exist, so the run can be reused. Missing or cut-off tooltip text is filled in afterwards.
    public var isScored: Bool { !meters.isEmpty }
    public var textComplete: Bool {
        guard !text.isEmpty, !Pipeline.isTruncated(self) else { return false }
        // Runs saved before Balance and Alignment have a "first" meter and no such rows; their text is complete without them.
        // Runs saved before Grouping have "alignment" instead and no grouping row.
        let legacy = meters["first"] != nil
        return Meters.order.filter { !((legacy && Rubric.layoutKeys.contains($0)) || ($0 == "grouping" && meters["alignment"] != nil)) }.allSatisfy { k in text[k].map { !$0.why.isEmpty } ?? false }
    }
}

extension RunResult {
    /// True when the grade shows as "12+". Runs saved before the 1-12 scale keep their old grade, so above 12 counts too.
    public var gradeCapped: Bool { readingGradeCapped ?? ((readingGrade ?? 0) > 12) }
}

extension RunResult {
    /// Stored value, or recomputed for runs saved before Overall existed.
    public var overallScore: Int {
        if let overall { return overall }
        let ms = meters.filter { $0.value.applicable != false }.mapValues { $0.score }
        return Scoring.overall(meters: ms, reading: readingGrade.map { Int((Pipeline.gradePoints($0) * 10).rounded()) })
    }
}

public struct ContrastReport: Codable {
    public var expected: Int
    public var measured: Int
    public var passing: Int
    public var minRatio: Double?
    public var boxes: [BoxContrast]
}

public struct BoxContrast: Codable {
    public var text: String
    public var ratio: Double?
    public var need: Double
    public var pass: Bool
    public var fg: String?
    public var bg: String?
}

public enum Meters {
    public static let names: [String: String] = [
        "order": "Hierarchy", "balance": "Balance", "grouping": "Grouping", "contrast": "Contrast", "familiar": "Familiarity",
        "ease": "Ease", "clarity": "Clarity", "trust": "Trust", "reading": "Reading level",
    ]
    public static let order = visual + visualCopy + ["reading"]
    /// Perception order (Ware 2012 three stages; see evidence/fundamentals.md): features, then layout and grouping, then reading.
    public static let visual = ["contrast", "grouping", "balance", "order"]
    public static let visualCopy = ["familiar", "ease", "clarity", "trust"]
    /// Every part of the card that fills in on its own while a run is going.
    public static let allReady: Set<String> = Set(order + ["feeling"])
    public static let definitions: [String: String] = [
        "balance": "Does the weight feel even?",
        "grouping": "Do related things look grouped?",
        "order": "Is it clear what to look at first?",
        "contrast": "Is the text easy to see?",
        "familiar": "Does it look like similar sites?",
        "ease": "Is it easy to take in?",
        "clarity": "Is the next step clear?",
        "trust": "Does it look trustworthy?",
        "reading": "What grade can read this easily?",
    ]
}

extension RunResult {
    /// Shown behind the card's skeleton while nothing is known yet.
    public static let placeholder = RunResult(id: "", createdAt: .distantPast, pageName: "", imageWidth: 0, imageHeight: 0, meters: [:], feeling: [:], feelingLow: [:], feelingConfidencePct: [:], readingGrade: nil, readingWords: 0, text: [:], timings: Timings(), contrastDetail: nil, vision: .null, pixelStats: nil)
}
