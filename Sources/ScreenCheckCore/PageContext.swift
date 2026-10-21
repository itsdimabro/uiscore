import Foundation

/// What the page is for: business model x where it sits. Read from the three label replies (per-field majority) and used only to
/// decide which checks are asked and how a few are worded. It never multiplies a score.
public struct PageContext: Codable, Equatable {
    public var businessModel: String   // ecommerce | saas | information | agency | other
    public var location: String        // homepage | landing | elsewhere | inside | not_a_page | unknown
    public var purpose: String         // at most 3 words, may be empty
    public var label: String           // one word for display: SaaS, Store, Course, Agency, or Screen
    public var confidence: String      // high | medium | low (business model)
    public init(businessModel: String, location: String, purpose: String, label: String, confidence: String = "low") {
        self.businessModel = businessModel; self.location = location; self.purpose = purpose; self.label = label; self.confidence = confidence
    }
    public static let unknown = PageContext(businessModel: "other", location: "unknown", purpose: "", label: "Screen")

    static let models = ["ecommerce", "saas", "information", "agency", "other"]
    static let locations = ["homepage", "landing", "elsewhere", "inside", "not_a_page"]
    static let labels = ["ecommerce": "Store", "saas": "SaaS", "information": "Course", "agency": "Agency"]

    /// Value with more than half the votes, else nil.
    static func majority(_ values: [String], among allowed: [String]) -> String? {
        let v = values.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { allowed.contains($0) }
        let counts = Dictionary(grouping: v, by: { $0 }).mapValues { $0.count }
        guard let best = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), best.value * 2 > values.count else { return nil }
        return best.key
    }

    /// A split vote gives `other` for the model and `unknown` for the location (the screen_kind rules then apply as before).
    public static func resolve(votes: [JSONValue]) -> PageContext {
        let model = majority(votes.map { $0["business_model"].string ?? "" }, among: models) ?? "other"
        let loc = majority(votes.map { $0["location"].string ?? "" }, among: locations) ?? "unknown"
        let agreeing = votes.filter { ($0["business_model"].string ?? "").lowercased() == model && ($0["location"].string ?? "").lowercased() == (loc == "unknown" ? ($0["location"].string ?? "").lowercased() : loc) }
        let unanimous = agreeing.count == votes.count
        let rank = ["low": 0, "medium": 1, "high": 2]
        let confs = agreeing.map { rank[($0["business_model_confidence"].string ?? "low").lowercased()] ?? 0 }
        var c = confs.min() ?? 0
        if !unanimous { c = min(c, 1) }
        let conf = ["low", "medium", "high"][c]
        let purposes = agreeing.compactMap { $0["page_purpose"].string }.compactMap { PageName.generated($0) }.sorted { ($0.count, $0) < ($1.count, $1) }
        let known = model != "other" && c >= 1
        return PageContext(businessModel: known ? model : "other", location: loc, purpose: purposes.first ?? "", label: known ? (labels[model] ?? "Screen") : "Screen", confidence: conf)
    }

    var inside: Bool { location == "inside" }
    var outside: Bool { ["homepage", "landing", "elsewhere"].contains(location) }

    /// Location refines the screen kind: not a page is a fragment, inside the product is an app screen, an outside page is a marketing page
    /// (only when the model is confident, otherwise the model's own screen_kind stands). A modal stays a modal.
    public func adjust(_ kind: ScreenKind, width: Int, height: Int) -> ScreenKind {
        if kind == .modal || kind == .document { return kind }
        if width < 600 || height < 500 { return .fragment }
        // Low confidence: today's screen_kind rules stand.
        if confidence == "low" { return kind }
        if location == "not_a_page" { return .fragment }
        if inside && kind == .marketing { return .app }
        if outside && kind == .app && confidence == "high" { return .marketing }
        return kind
    }
}
