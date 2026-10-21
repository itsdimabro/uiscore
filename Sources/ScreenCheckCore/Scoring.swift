import Foundation

/// Facts derived from the vision JSON that code checks need.
public struct PageFacts {
    public var boxes: [TextBox]            // non-demo
    public var allCopy: String
    public var options: Int
    public var textItemCount: Int
    public var elementCount: Int
    public var navCount: Int
    public var labels: [String]            // button + nav + link labels
    public var vision: JSONValue
    public var imageHeight: Int? = nil
    public var allBoxes: [TextBox] = []
    public var unmeasuredShare: Double = 0   // share of text boxes sitting on a gradient, photo or busy area
    public var primaryText: String = ""
    public var primaryCount: Int = 0         // ids the model named as the primary button
}

public enum Scoring {
    static func clusters(_ values: [Double], within tol: Double) -> Int {
        var n = 0, last: Double? = nil
        for v in values.sorted() { if last == nil || v - last! > tol { n += 1; last = v } }
        return n
    }
    static func distinctSizes(_ boxes: [TextBox]) -> [Double] {
        // Size estimates jitter by a few px, so sizes within 20% of each other count as one size.
        var out: [Double] = []
        for s in boxes.map({ $0.fontPx }).sorted(by: >) where out.last == nil || s < out.last! * 0.8 { out.append(s) }
        return out
    }
    static func isGray(_ c: (Int, Int, Int)) -> Bool { max(c.0, c.1, c.2) - min(c.0, c.1, c.2) < 28 }
    static func hueBucket(_ c: (Int, Int, Int)) -> Int {
        let r = Double(c.0) / 255, g = Double(c.1) / 255, b = Double(c.2) / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d == 0 { return 0 }
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        return Int(h * 60 / 30) % 12
    }

    static func content(_ boxes: [TextBox]) -> [TextBox] { boxes.filter { !["demo", "logo"].contains($0.role) } }
    /// The biggest text is the headline (by role, or by dominating the median size). Measured, not asked.
    static func firstIsHeadline(_ boxes: [TextBox]) -> Bool {
        let c = content(boxes)
        guard let big = c.max(by: { $0.fontPx < $1.fontPx }) else { return false }
        let med = c.map { $0.fontPx }.sorted()[c.count / 2]
        return big.role == "heading" || big.fontPx >= 1.5 * med
    }
    /// Boxes set clearly larger than the median text (1.4x or more): what shouts at the highest emphasis.
    static func emphasisCount(_ boxes: [TextBox]) -> Int {
        let c = content(boxes)
        guard !c.isEmpty else { return 0 }
        let med = c.map { $0.fontPx }.sorted()[c.count / 2]
        return c.filter { $0.fontPx >= 1.4 * med }.count
    }

    /// Short labels stacked on one left edge (8+ of them): a menu or link list. Returns how many items sit in such columns.
    static func linkColumnCount(_ boxes: [TextBox]) -> Int {
        let short = boxes.filter { Readability.splitWords($0.text).count <= 4 && $0.h < 40 }
        var used = Set<Int>(), total = 0
        for i in short.indices where !used.contains(i) {
            let g = short.indices.filter { !used.contains($0) && abs(short[$0].x - short[i].x) <= 6 }
            if g.count >= 8 { total += g.count; used.formUnion(g) }
        }
        return total
    }

    static let verbs: Set<String> = ["sign", "get", "start", "try", "join", "buy", "shop", "download", "learn", "see", "book", "request", "contact", "create", "log", "view", "watch", "subscribe", "add", "order", "open", "explore", "build", "install", "request", "schedule", "talk", "read", "register"]
    static let generic: Set<String> = ["click here", "learn more", "submit", "more", "read more"]
    static let contactWords = ["contact", "privacy", "terms", "address", "phone", "support", "legal"]

    /// `textBoxes` are OCR boxes with roles applied; counts come from them, not from the model.
    public static func facts(from v: JSONValue, textBoxes: [TextBox]) -> PageFacts {
        let boxes = textBoxes   // every OCR box counts; model role labels never change a count
        let copy = boxes.map { $0.text }.joined(separator: "\n")
        // Link lists are found by geometry too: the model's nav/link lists vary between runs on a cluttered page.
        let col = linkColumnCount(textBoxes.filter { !["demo", "logo"].contains($0.role) })
        let nav = max(textBoxes.filter { $0.role == "nav" }.count, col)
        let clickable = textBoxes.filter { ["nav", "button", "link"].contains($0.role) }
        return PageFacts(boxes: boxes, allCopy: copy, options: max(clickable.count, col),
                         textItemCount: textBoxes.count, elementCount: textBoxes.count, navCount: nav,
                         labels: clickable.map { $0.text }, vision: v, imageHeight: nil)
    }

    /// Body text size in CSS px: the character-weighted median size of sentence-like lines (15+ characters, not logo or demo text).
    /// Nil when the screen has no such lines.
    public static func bodyTextPx(_ boxes: [TextBox]) -> Double? {
        let body = boxes.filter { !["demo", "logo", "nav", "button", "heading"].contains($0.role) && $0.text.count >= 15 }.sorted { $0.fontPx < $1.fontPx }
        let total = body.reduce(0) { $0 + $1.text.count }
        guard total > 0 else { return nil }
        var run = 0
        for b in body { run += b.text.count; if run * 2 >= total { return b.fontPx } }
        return body.last?.fontPx
    }

    /// Answers every code-kind check. Returns id -> yes, plus contrast detail.
    public static func codeAnswers(_ f: PageFacts, pixels: Pixels?, appScreen: Bool = false) -> (answers: [String: Bool], contrast: ContrastReport, note: String?) {
        var a: [String: Bool] = [:]
        let sizes = distinctSizes(f.boxes)
        a["h_scale"] = sizes.count >= 2 ? sizes[0] / sizes[1] >= 1.2 : false
                a["E1"] = !sizes.isEmpty && sizes.count <= 6
        let words = Readability.splitWords(f.allCopy).count
        a["E4"] = words <= 120
        a["E5"] = (f.boxes.map { $0.text.count }.max() ?? 0) <= 80
        a["E9"] = (f.boxes.map { $0.fontPx }.min() ?? 0) >= 12
        a["E10"] = bodyTextPx(f.boxes).map { $0 >= (appScreen ? 13 : 16) } ?? false
        a["C4"] = f.navCount <= 7
        a["C5"] = f.options <= 15
        a["C9"] = !f.labels.contains { generic.contains($0.lowercased().trimmingCharacters(in: .whitespaces)) }
        let low = (f.allCopy + " " + f.labels.joined(separator: " ")).lowercased()
        a["T4"] = contactWords.contains { low.contains($0) }

        // Contrast from real pixels. Text that cannot be measured is left out, not failed, unless it is a big share.
        // Logos and product-mockup/decorative text are artwork, not page copy. A role label can only remove a box from
        // this meter, never add one, so a flipped label moves the score by at most that one box.
        // Rotated or curved text (very tall box for few characters) is decorative and cannot be measured reliably.
        let cb = f.boxes.filter { !["demo", "logo"].contains($0.role) && $0.w / max(1, $0.h) / Double(max(1, $0.text.count)) >= 0.2 }
        let rep = Contrast.report(pixels, boxes: cb, expected: cb.count)
        let measuredBoxes = rep.boxes.filter { $0.ratio != nil }
        let mIdx = rep.boxes.indices.filter { rep.boxes[$0].ratio != nil }
        let mCount = Double(max(1, measuredBoxes.count))
        let unmeasuredShare = rep.expected == 0 ? 1 : Double(rep.expected - rep.measured) / Double(rep.expected)
        a["c_cover"] = unmeasuredShare <= 0.3 && rep.measured > 0
        a["c_aa"] = Double(measuredBoxes.count - rep.passing) <= max(1, (mCount * 0.05).rounded(.down))
        a["c_none_fail"] = !measuredBoxes.isEmpty && measuredBoxes.allSatisfy { $0.pass }
        a["c_floor"] = (rep.minRatio ?? 0) >= 3.0
        a["c_small"] = !cb.isEmpty && cb.allSatisfy { $0.fontPx >= 12 }
        let smallM = mIdx.filter { cb[$0].fontPx < 18 }
        a["c_aaa"] = smallM.isEmpty ? true : Double(smallM.filter { (rep.boxes[$0].ratio ?? 0) >= 7 }.count) / Double(smallM.count) >= 0.5
        if let big = mIdx.max(by: { cb[$0].fontPx < cb[$1].fontPx }) { a["c_head"] = (rep.boxes[big].ratio ?? 0) >= rep.boxes[big].need } else { a["c_head"] = false }
        let fgs = measuredBoxes.compactMap { $0.fg }.map { h -> (Int, Int, Int) in
            let v = Int(h.dropFirst(), radix: 16) ?? 0; return ((v >> 16) & 255, (v >> 8) & 255, v & 255) }
        var colorKeys = Set<Int>(); var grayCount = 0
        for c in fgs { if isGray(c) { grayCount = 1 } else { colorKeys.insert(hueBucket(c)) } }
        // E2: distinct non-gray text hues <= 3
        a["E2"] = colorKeys.count <= 3
        var note: String? = nil
        if !a["c_cover"]! { note = "only \(rep.measured) of \(rep.expected) text items could be measured" }
        return (a, rep, note)
    }

    static let positive = ["love", "simple", "easy", "free", "better", "great", "clear", "fast", "save", "grow", "happy", "best", "enjoy", "welcome", "thanks", "secure", "trusted"]
    static let negative = ["lose", "risk", "miss out", "warning", "never", "kill", "danger", "error", "fail", "threat", "attack"]
    static let pressure = ["last chance", "hurry", "ends", "only ", "left", "final", "expires"]
    static let urgency = ["now", "today", "instantly", "limited", "last", "fast", "immediately"]
    static let superlative = ["best", "#1", "ultimate", "never before", "revolutionary", "10x", "world's", "greatest"]
    static let hedge = ["can", "may", "helps", "supports", "gently", "might"]
    static let benefit = ["save", "grow", "simple", "free", "easy", "clear", "faster", "better"]
    static let invite = ["you", "your", "try", "start", "join", "get"]

    /// A name inside a sentence (not the first word, not all caps like "AI"): "With GitHub", "Mac, Windows".
    static func hasProperNoun(_ boxes: [TextBox]) -> Bool {
        for b in boxes {
            let ws = b.text.split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) }
            for w in ws.dropFirst() where w.count >= 3 && w.first!.isUppercase && w.dropFirst().contains(where: { $0.isLowercase }) { return true }
        }
        return false
    }
    static func has(_ text: String, _ words: [String]) -> Bool {
        let t = " " + text.lowercased().replacingOccurrences(of: "[^a-z0-9#' ]", with: " ", options: .regularExpression) + " "
        return words.contains { t.contains(" " + $0.trimmingCharacters(in: .whitespaces) + " ") || ($0.hasSuffix(" ") && t.contains(" " + $0)) }
    }
    static func count(_ text: String, _ words: [String]) -> Int {
        Readability.splitWords(text.lowercased()).filter { w in words.contains(w) }.count
    }

    /// Checks that code can answer from integer/enum vision fields, pixel stats and the copy. Jev is not asked these.
    public static func visionAnswers(_ f: PageFacts, stats: PixelStats?) -> [String: Bool] {
        let v = f.vision
        var a: [String: Bool] = [:]
        let flag = { (k: String, d: Bool) in v[k].bool ?? d }
        let word = { (k: String) in (v[k].string ?? "").lowercased() }
        let head1 = f.boxes.filter { $0.role == "heading" }.map { $0.text }.joined(separator: " ")
        // 'one' vs 'several' flipped between runs on the same page, so it comes from the primary id list, not the enum.
        let prim = f.primaryCount == 0 ? "none" : "one"
        // Type ratio from OCR heights: largest text over the median text.
        let hs = f.boxes.map { $0.fontPx }.sorted()
        let typeRatio = hs.isEmpty ? 0 : (hs.last! / max(1, hs[hs.count / 2]))
        a["fi_simple"] = word("blocks") != "many"
        a["fi_images"] = flag("images_ok", true)
        a["fi_align"] = ["left", "center"].contains(word("main_text_alignment"))
        a["fi_fonts"] = word("fonts") != "three_plus"
        a["fi_dated"] = !flag("has_dated_cues", false)
        a["fi_overlay"] = !flag("has_overlay", false)
        a["h_first"] = Scoring.firstIsHeadline(f.boxes)
        a["h_one_cta"] = prim == "one"
        a["h_cta_fold"] = prim != "none" && (v["primary_y_pct"].double ?? 100) <= 60
        a["h_nav_quiet"] = flag("nav_quieter_than_headline", true)
        a["h_emphasis"] = Scoring.emphasisCount(f.boxes) <= 3
        a["f_logo"] = ["top-left", "top-center"].contains(word("logo_position"))
        a["f_nav"] = ["top", "left"].contains(word("nav_position"))
        a["f_navcount"] = f.navCount <= 7
        // Geometry: a search/log-in/sign-up/cart label inside the top-right quarter of the page (top 12%).
        let H = Double(f.imageHeight ?? 800), Wd = f.allBoxes.map { $0.x + $0.w }.max() ?? 1280
        a["f_topright"] = f.allBoxes.contains { $0.y < H * 0.12 && $0.x + $0.w / 2 >= Wd * 0.72 && has($0.text, ["search", "log in", "login", "sign in", "sign up", "cart", "basket", "account", "contact sales", "get started"]) }
        a["f_pattern"] = flag("follows_page_type_pattern", true)
        a["f_links"] = flag("links_look_clickable", true)
        a["f_odd"] = !flag("has_unusual_pattern", false)
        a["E6"] = word("panels") != "many"
        a["E7"] = f.unmeasuredShare <= 0.12
        a["C1"] = prim == "one"
        a["C3"] = prim != "none"
        a["C7"] = flag("links_look_clickable", true)
        // The promo flag flips between runs on a wall of stickers and banners; a page that is both "many blocks" and
        // "many emphasised items" always has competing promos, so that is answered from the stable enums.
        let promo = flag("has_competing_promo", false) || (word("blocks") == "many" && word("emphasis") == "many")
        a["C8"] = !flag("has_overlay", false) && !promo
        a["T1"] = word("logo_position") != "none" && word("logo_position") != ""
        a["T2"] = flag("has_proof", false)
        a["T3"] = flag("real_imagery", false)
        a["T5"] = !flag("has_overlay", false) && !promo
        a["T9"] = !flag("has_dated_cues", false) && !flag("has_layout_error", false) && flag("images_ok", true)
        a["T7"] = !flag("has_inconsistent_style", false)
        a["T6"] = !flag("has_layout_error", false)
        if let s = stats {
            a["fi_space"] = s.emptyPct >= 0.25
            a["fi_palette"] = (s.colorfulness ?? 0) <= 45
            // Visual feeling, all from pixels.
            a["vv1"] = s.bgLum > 0.5
            a["vv2"] = s.coolShare >= 0.5
            a["vv3"] = s.emptyPct >= 0.3
            a["vv5"] = (s.hueBuckets ?? s.hueCount) > 4
            a["vv6"] = s.redOrangePct > 0.03 && (s.greenPct ?? 0) > 0.03
            a["vv7"] = s.bgLum < 0.05
            a["vv9"] = s.accentSat > 0.7
            a["vi9"] = s.bgLum < 0.2
            a["vi1"] = s.accentSat > 0.7
            a["vi2"] = s.warmPct > 0.10
            a["vi3"] = (s.coloredBlocks ?? 0) >= 4
            a["vi4"] = s.coloredPct > 0.25 && (s.hueBuckets ?? s.hueCount) >= 4
            a["vi5"] = s.topHueShare >= 0.7
            a["vi6"] = s.accentSat < 0.4
            a["vi7"] = s.emptyPct > 0.4
        }
        a["vi8"] = ["regular", "medium"].contains(word("heaviest_weight")) && typeRatio <= 3
        let headBtn = f.boxes.filter { ["heading", "button"].contains($0.role) }.map { $0.text }.joined(separator: " ")
        a["cv1"] = has(headBtn, benefit)
        a["cv4"] = has(f.allCopy, ["welcome", "thanks", "thank you", "free", "hello", "hi"])
        a["cv8"] = !(has(f.allCopy, positive) || has(f.allCopy, benefit) || has(f.allCopy, negative) || has(f.allCopy, pressure) || has(f.allCopy, urgency) || has(f.allCopy, invite))
        let pw = Readability.splitWords(f.primaryText.lowercased())
        a["C2"] = !pw.isEmpty && pw.count <= 4 && verbs.contains(pw[0])
        a["T8"] = !TrustSignals.isVague(f.allCopy)
        a["T11"] = !TrustSignals.hasHype(copy: f.allCopy, boxes: f.boxes)
        a["T12"] = !TrustSignals.isHedging(f.allCopy)
        a["T13"] = !TrustSignals.hasTypos(f.boxes)
        a["T14"] = !TrustSignals.hasPressure(f.allCopy)
        // plain_confident vs stiff flipped between runs on the same page (trust 42/34/34); only hedging or slang fails this check.
        a["T15"] = !["hedging", "slangy"].contains(word("tone"))
        a["cv3"] = count(f.allCopy, positive) >= 3
        a["cv5"] = has(f.allCopy, negative)
        a["cv6"] = has(head1, ["don't", "no", "not", "never"])
        a["cv7"] = has(f.allCopy, pressure)
        a["ci1"] = f.allCopy.contains("!")
        a["ci2"] = f.boxes.contains { ["heading", "button"].contains($0.role) && $0.text == $0.text.uppercased() && $0.text.contains { $0.isLetter } && Readability.splitWords($0.text).count > 2 }
        let sentences = Readability.splitSentences(f.allCopy)
        let avgSentence = sentences.isEmpty ? 0 : Double(Readability.splitWords(f.allCopy).count) / Double(sentences.count)
        a["ci3"] = has(f.allCopy, urgency)
        a["ci6"] = !f.allCopy.contains("!") && !has(f.allCopy, urgency)
        a["C10"] = !sentences.isEmpty && avgSentence <= 20
        a["ci8"] = has(head1, hedge)
        a["ci4"] = has(f.allCopy, superlative)
        a["ci9"] = !f.allCopy.contains { $0.isNumber }
        return a
    }

    /// Equal-weight mean of the 8 bar meters plus the Reading level ring value (0-100) when there is enough copy.
    public static func overall(meters: [String: Int], reading: Int?) -> Int {
        var v = (Rubric.meterKeys + Rubric.layoutKeys).compactMap { meters[$0].map(Double.init) }
        if let reading { v.append(Double(reading)) }
        return v.isEmpty ? 0 : Int((v.reduce(0, +) / Double(v.count)).rounded())
    }

    /// A meter whose applicable checks carry less than this share of its total weight is shown as not applicable.
    public static let minApplicablePct = 40

    public static func weightedScore(_ meter: String, answers: [String: (yes: Bool, p: Double?, kind: String)], cap: Int? = nil, notApplicable: Set<String> = [], weights: [String: Int] = [:]) -> MeterResult {
        let checks = Rubric.checks(for: meter).filter { !notApplicable.contains($0.id) }
        func wt(_ c: Check) -> Int { weights[c.id] ?? c.w }
        let possible = max(1, checks.reduce(0) { $0 + wt($1) })
        let full = Rubric.checks(for: meter).reduce(0) { $0 + $1.w }
        if full > 0 && possible * 100 < Self.minApplicablePct * full {
            return MeterResult(score: 0, lowConfidence: false, confidencePct: 100, checks: [], note: nil, applicable: false)
        }
        var total = 0
        var conf = 0.0
        var results: [CheckResult] = []
        for c in checks {
            let ans = answers[c.id]
            let yes = ans?.yes ?? false
            if yes { total += wt(c) }
            let p = ans?.p
            conf += Double(wt(c)) * (p.map { max($0, 1 - $0) } ?? 1)
            results.append(CheckResult(id: c.id, yes: yes, p: p, weight: wt(c), kind: c.kind))
        }
        if possible != 100 { total = Int((Double(total) * 100 / Double(possible)).rounded()) }
        if let cap { total = min(total, cap) }
        let pct = Int((conf * 100 / Double(possible)).rounded())
        return MeterResult(score: min(100, total), lowConfidence: pct < 78, confidencePct: pct, checks: results, note: nil)
    }
}
