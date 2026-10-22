import Foundation

/// What kind of screen the image shows. Checks that only make sense for some kinds are marked N/A for the rest.
public enum ScreenKind: String, CaseIterable {
    case marketing   // landing, pricing, store and product pages
    case app         // settings, dashboard, form, list or editor screen
    case modal       // dialog, sheet or popover
    case fragment    // a crop of part of a screen: a few cards, a panel, a diagram
    case document    // article, email, document

    /// The vision call's `screen_kind` wins; an older `page_type` answer is mapped; a small image is always a fragment
    /// unless the model called it a modal. The result is deterministic for a given vision JSON and image size.
    public static func resolve(vision v: JSONValue, width: Int, height: Int) -> ScreenKind {
        let sk = (v["screen_kind"].string ?? "").lowercased()
        let pt = (v["page_type"].string ?? "").lowercased()
        var kind: ScreenKind
        if sk.contains("modal") || sk.contains("dialog") { kind = .modal }
        else if sk.contains("fragment") || sk.contains("crop") { kind = .fragment }
        else if sk.contains("document") || sk.contains("email") || sk.contains("article") { kind = .document }
        else if sk.contains("marketing") || sk.contains("landing") || sk.contains("store") { kind = .marketing }
        else if sk.contains("app") { kind = .app }
        else if pt.contains("landing") || pt.contains("store") { kind = .marketing }
        else if pt.contains("article") { kind = .document }
        else { kind = .app }
        if kind != .modal && (height < 500 || width < 600) { kind = .fragment }
        return kind
    }
}

public enum Applicability {
    static let all = Set(ScreenKind.allCases)
    /// Checks that apply to only some kinds. A check not listed here applies to every kind.
    public static let kinds: [String: Set<ScreenKind>] = [
        "h_scale": [.marketing, .app, .document],
        "h_first": [.marketing, .app, .document],
        "h_one_cta": [.marketing, .modal],
        "h_levels": [.marketing, .app, .document],
        "h_cta_fold": [.marketing],
        "h_nav_quiet": [.marketing, .app, .document],
        "f_logo": [.marketing], "f_nav": [.marketing, .app], "f_navcount": [.marketing, .app], "f_topright": [.marketing],
        "E4": [.marketing, .app, .modal, .fragment],
        "E6": [.marketing, .app, .modal, .document],
        "C1": [.marketing, .modal], "C2": [.marketing, .modal], "C3": [.marketing, .modal],
        "C4": [.marketing, .app], "C5": [.marketing, .modal], "C6": [.marketing], "C8": [.marketing, .modal],
        "T1": [.marketing], "T2": [.marketing], "T3": [.marketing],
        "T5": [.marketing, .app, .document],
        "f_words": [.marketing, .document],
    ]

    /// Extra checks that do not apply for this page context (sources: RubricSources "context").
    public static func contextNotApplicable(_ c: PageContext) -> Set<String> {
        var na = Set<String>()
        if c.confidence == "low" { return na }
        if c.location == "elsewhere" { na.formUnion(["h_cta_fold", "C6"]) }
        if c.businessModel == "ecommerce" && (c.location == "homepage" || c.location == "elsewhere") { na.formUnion(["h_one_cta", "E6", "C5", "C1"]) }
        return na
    }
    /// Weight changes for a context (scaled to 100 with the other applicable checks).
    public static func contextWeights(_ c: PageContext) -> [String: Int] {
        if c.confidence == "low" { return [:] }
        return c.businessModel == "ecommerce" && (c.location == "elsewhere" || c.location == "homepage") ? ["T14": 3] : [:]
    }
    /// Reworded questions for a context. Only the wording changes, never the weight.
    public static func contextWording(_ c: PageContext) -> [String: String] {
        var w: [String: String] = [:]
        if c.confidence == "low" { return w }
        if c.inside {
            w["h_first"] = "Is this true of the screen? Is the first thing the eye lands on the page title or the main content (table, form, editor) rather than chrome or decoration?"
            w["f_pattern"] = "Is this true of the screen? Does the layout follow the usual app pattern: navigation at the side or top, a page title, then the content, with the main action near the title?"
        } else if c.outside {
            w["f_pattern"] = "Is this true of the screen? Does the layout follow the usual pattern for a \(c.businessModel == "other" ? "web" : c.businessModel) page of this kind?"
            if c.location == "elsewhere" { w["h_one_cta"] = "Is this true of the screen? Is there one clearly strongest action (filled, strongest color)?" }
        }
        return w
    }
    /// One plain sentence (25 words or fewer): the kind of page and the main thing that changes in scoring. Nil when context is unsure.
    public static func contextNote(_ c: PageContext, changed: Set<String>) -> String? {
        guard c.confidence != "low", c.location != "unknown", c.location != "not_a_page" else { return nil }
        let thing = ["ecommerce": "store", "saas": "SaaS", "information": "course or content", "agency": "agency"][c.businessModel]
        let place = ["homepage": "home page", "landing": "landing page", "elsewhere": "inner page", "inside": "screen inside the product"][c.location] ?? "page"
        let article = (thing == "agency") ? "An" : "A"
        let head = thing.map { "\(article) \($0) \(place)" } ?? "A \(place)"
        let effect: String
        if c.inside { effect = "judged on direction rather than selling" }
        else if c.businessModel == "ecommerce" && c.location != "landing" { effect = "judged as a product listing, with one-button and promo-pressure rules relaxed" }
        else if c.location == "elsewhere" { effect = "judged without home-page rules like a headline above the fold" }
        else { effect = "judged on how well it persuades" }
        return head + ", so it's " + effect + "."
    }

    /// C6 (headline says plainly what the product is). An open-ended headline on a marketing home or landing page is
    /// not a failure when the page demonstrates the product right away: the product on screen answers the question.
    static func c6Holds(vote: Bool, context: PageContext, demonstrates: Bool) -> Bool {
        vote || (demonstrates && context.outside && (context.location == "homepage" || context.location == "landing"))
    }

    /// Checks that cannot be asked of this screen. They are left out of the meter and the other weights are scaled up.
    public static func notApplicable(kind: ScreenKind, pageType: String, facts f: PageFacts, context: PageContext = .unknown) -> Set<String> {
        var na = contextNotApplicable(context)
        for (id, ks) in kinds where !ks.contains(kind) { na.insert(id) }
        // The footer sits below the first screen of a landing page, so contact/privacy cannot be asked there.
        let footerKnown = kind == .document || (kind == .marketing && !pageType.lowercased().contains("landing"))
        // A first-screen capture has no footer to judge: T4 is asked only when legal/footer text was detected.
        let footerSeen = f.allBoxes.contains { $0.role == "legal" }
        if !footerKnown || !footerSeen { na.insert("T4") }
        if f.navCount == 0 { na.formUnion(["h_nav_quiet", "f_nav", "f_navcount", "C4"]) }
        if f.primaryCount == 0 { na.formUnion(["C2", "C3", "C8", "h_cta_fold"]) }
        // Sign-in, forms and screens inside a product: the submit button sits below its fields by design, so the fold is not asked.
        if pageType.lowercased().range(of: #"\bforms?\b"#, options: .regularExpression) != nil || context.inside { na.insert("h_cta_fold") }
        if f.options == 0 { na.formUnion(["C7", "f_links"]) }
        if f.vision["fonts"].string == nil { na.insert("E12") }
        if f.vision["accent_colors"].string == nil { na.insert("E13") }
        if f.labels.isEmpty { na.formUnion(["f_words", "C9"]) }
        let words = Readability.splitWords(f.allCopy).count
        if words < 8 { na.formUnion(["T8", "T11", "T12", "T14", "T15", "C10"]) }
        if words < 5 { na.insert("T13") }
        if Readability.splitSentences(f.allCopy).count < 2 { na.insert("C10") }
        if (f.vision["tone"].string ?? "no_copy").lowercased() == "no_copy" { na.insert("T15") }
        return na
    }
}
