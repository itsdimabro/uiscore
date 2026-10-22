import Foundation

extension Pipeline {
    public static func truncate(_ s: String, max n: Int = 110) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= n { return t }
        let cut = String(t.prefix(n - 1))
        if let sp = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: sp) > n / 2 {
            return String(cut[..<sp]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:")) + "…"
        }
        return cut + "…"
    }

    /// Tooltip text is never cut: the writer is asked for one short sentence, and whatever it returns is shown whole.
    static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Per-meter facts for the writer: score and what failed. A designer-only deduction is explained by that meter's own designer reason, never by the writer.
    static func writerMeterFacts(meters: [String: MeterResult], failed: [String: [String]]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, m) in meters {
            out[k] = ["score": m.score, "failed": failed[k] ?? [String]()] as [String: Any]
        }
        return out
    }

    /// The Why line explains in words: no score numbers, no naming another meter. Sentences that do are dropped.
    static let topicWords: [String: String] = [
        "balance": #"\b(weight|halves|mirror|lopsided|heavier|centroid)\b"#, "grouping": #"\b(groups?|grouped|line up|shared edge)\b"#,
        "contrast": #"\b(contrast|faint|hard to read|heavier|larger|space between)\b"#, "order": #"\b(eye|hierarchy|emphasis|focal|first stop|shouted)\b"#,
        "familiar": #"\b(convention|usual pattern|top menu|familiar)\b"#, "ease": #"\b(px|words|clutter|dense|gradient|flat|text size)\b"#,
        "clarity": #"\b(button|headline|label|slogan|vague)\b"#, "trust": #"\b(proof|screenshot|ads?|chat widget|customer logos?)\b"#]
    /// A sentence about another meter's topic and none of this one's is dropped.
    static func offTopic(_ l: String, meter: String) -> Bool {
        guard let own = topicWords[meter] else { return false }
        if l.range(of: own, options: .regularExpression) != nil { return false }
        return topicWords.contains { $0.key != meter && l.range(of: $0.value, options: .regularExpression) != nil }
    }
    static func cleanWhy(_ s0: String, meter: String, topicFilter: Bool = true) -> String {
        let s = s0.replacingOccurrences(of: #"^[\s;:,.\-–—]+"#, with: "", options: .regularExpression)
        let s2 = s.replacingOccurrences(of: #"(?i)^(the )?[a-z]+ (score )?(lost|loses|lose) points (because|since)\s*"#, with: "", options: .regularExpression, range: nil)
        var t = s2.replacingOccurrences(of: #"^\s*[A-Z][a-z]+ (scores?|is at|sits at|has a score of) \d+( out of 100)?(?![\w%])( because| since|,)?\s*"#, with: "", options: .regularExpression)
        if t != s2, let f = t.first { t = f.uppercased() + t.dropFirst() }
        let others = Meters.order.filter { $0 != meter }
        let sentences = t.replacingOccurrences(of: #"(?<=[.!?])\s+"#, with: "\u{1}", options: .regularExpression).split(separator: "\u{1}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let kept = sentences.filter { sen in
            let l = sen.lowercased()
            if l.range(of: #"worth (changing|fixing)|nothing (needs|to) (change|fix)|small deduction remains"#, options: .regularExpression) != nil { return false }
            if topicFilter, offTopic(l, meter: meter) { return false }
            if l.range(of: #"doesn't reach|does not reach|\bis the (lowest|weakest)\b|\bthe designer\b|(?<![\d.:,])[1-9](?![\d.:,%]|\s?px)"#, options: .regularExpression) != nil { return false }
            if l.range(of: #"\b(\d+|one|two|three|four|five|six|seven|eight|ten|twelve|fifteen) or (fewer|more|less)\b|_px\b|\b[a-z]+_[a-z_]+\b|\bprimary=|\bbuttons\[\]"#, options: .regularExpression) != nil { return false }
            if l.range(of: #"\b(nav(igation)?|menu)\b[^.]*\b(items?|choices|links|entries|count|many|long)\b|\b(too many|more than (seven|7))\b[^.]*\b(nav|menu)"#, options: .regularExpression) != nil { return false }
            if l.range(of: #"\b(score|scores|scored|points?)\b[^.]*\d|\d+ ?/ ?100|\b(lowest|highest) score\b|\bscores? (is|of)\b"#, options: .regularExpression) != nil { return false }
            if others.contains(where: { o in ["order", "balance", "grouping", "contrast", "familiar", "ease", "clarity", "trust"].contains(o) && l.range(of: "\\b" + o + "\\b (issue|problem|score|meter)", options: .regularExpression) != nil }) { return false }
            if others.contains(where: { o in ["order", "balance", "grouping", "contrast", "familiar", "ease", "clarity", "trust"].contains(o) && l.range(of: "\\b\(o)\\b[^.]*\\b(weakest|lowest|most room|area|meter|is below|stays below)\\b|\\b(weakest|lowest) (area|meter)\\b", options: .regularExpression) != nil }) { return false }
            return true
        }
        guard !kept.isEmpty else { return "" }
        var out = kept.joined(separator: " ")
        if let f = out.first, f.isLowercase { out = f.uppercased() + out.dropFirst() }
        return out.last.map { ".!?".contains($0) } == true ? out : out + "."
    }
    /// Drops sentences that claim an element the page does not have (ads, pop-ups, banners, promos unless an overlay or promo was detected),
    /// absolute text-size talk, a missing card/panel, and alignment talk on any meter but Balance-free Alignment cases.
    static func groundedWhy(_ s: String, meter: String, overlayPresent: Bool) -> String {
        let sentences = s.replacingOccurrences(of: #"(?<=[.!?])\s+"#, with: "\u{1}", options: .regularExpression).split(separator: "\u{1}").map(String.init)
        let kept = sentences.filter { sen in
            let l = sen.lowercased()
            if !overlayPresent, l.range(of: #"\b(ads?|ad-like|pop-?ups?|banners?|promos?|promotions?|cookie|chat)\b"#, options: .regularExpression) != nil { return false }
            if l.range(of: #"\b\d+ ?px\b|\bpixels?\b|\b(tiny|small(er)?) (body )?(text|type|font)|\btext (is|are) (too )?small\b"#, options: .regularExpression) != nil { return false }
            if meter == "grouping", l.range(of: #"\b(card|panel)s?\b"#, options: .regularExpression) != nil, l.range(of: #"\b(lack|no|without|missing|need|add)\b"#, options: .regularExpression) != nil { return false }
            if meter == "grouping", l.range(of: #"\b(align|aligned|alignment|line up|edge)\b"#, options: .regularExpression) != nil { return false }
            return true
        }
        return kept.joined(separator: " ")
    }
    /// Contrast always explains itself in terms of its four sub-rubrics (colour, size, weight, spacing); nothing but the failures at under 100.
    static func contrastWhy(_ r: RunResult, failedIDs: [String], score: Int, fallback: String) -> String {
        let ids = Set(failedIDs)
        var bits: [String] = []
        if !ids.isDisjoint(with: ["c_aa", "c_most", "c_floor", "c_head"]), let d = r.contrastDetail {
            let weak = d.boxes.filter { !$0.pass && $0.ratio != nil }.sorted { ($0.ratio ?? 0) < ($1.ratio ?? 0) }.prefix(2).map { "\"" + truncate($0.text, max: 24) + "\"" }
            bits.append(weak.isEmpty ? "Some text is too faint against its background" : "Some text is too faint against its background, such as " + weak.joined(separator: " and "))
        }
        if ids.contains("c_size") { bits.append("the headline is not much larger than the body text") }
        if ids.contains("c_weight") { bits.append("the headline is not set heavier than the body text") }
        if ids.contains("c_space") { bits.append("the space between groups is no bigger than the space inside them") }
        if bits.isEmpty { return score >= 100 ? "Text colour, size, weight and spacing all set the important things apart." : fallback }
        let t = bits.joined(separator: "; ")
        return t.prefix(1).uppercased() + t.dropFirst() + "."
    }
    /// Scored, but the 7-item cut-off is an own choice (meta-analysis of choice overload about 0): never advised, never nagged.
    static let navCountIDs: Set<String> = ["C4", "f_navcount"]
    /// Fix shapes a senior designer would not give: placeholders as labels, moving chat widgets or nav links, aligning nav with
    /// hero, and vague "review/consider" lines.
    static func bannedFix(_ s: String, page: String = "") -> Bool {
        let f = s.lowercased()
        if f.range(of: #"\b(lower|reduce|decrease|weaken)\b[^.]*\bcontrast\b"#, options: .regularExpression) != nil { return true }
        if f.range(of: #"\b(shared|one|single) (horizontal |vertical )?(line|panel|card)\b|\bequal spacing\b|\binside a (single|one) panel\b"#, options: .regularExpression) != nil { return true }
        if f.range(of: #"\b(rewrite|change|replace|reword)\b[^.]*\b(headline|title|hero)\b"#, options: .regularExpression) != nil {
            // a rewrite is allowed only to a quoted replacement that is on the page
            let q = (try? NSRegularExpression(pattern: #"\bto [\"“]([^\"”]+)[\"”]"#))?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)).flatMap { Range($0.range(at: 1), in: s).map { String(s[$0]) } }
            guard let q else { return true }
            if !page.isEmpty, !page.lowercased().contains(q.lowercased()) { return true }
        }
        let pats = [#"\b(add|use|rely on|put)\b[^.]*placeholders?"#, #"placeholders?\s+(as|instead of)\s+(a\s+)?labels?"#, "promo", "ribbon", "swoosh", "shared panel", "one panel", #"replace [^.]*(screenshot|image)"#, #"\b(move|shift|reposition|relocate)\b[^.]*\blinks?\b"#, #"\b(add|show)\b[^.]*(customer logos|rating|award|screenshot|left-side|counter-weight|visual weight)"#, "logo strip", "mirror", "gradient swoosh", "weight toward", "chat widget", "chat bubble", #"(move|shift|align|reposition)[^.]*\bnav"#, #"\bnav(igation)?\b[^.]*(one|shared|same) (left|line|edge|centre|center)"#, #"^\s*(review|consider|think about|look at|revisit)\b"#, "against its checklist", "cut copy until", #"\b(?!(16|13)\b)\d+(\.\d+)? ?px\b"#, #"\b(one|shared?|same) (centre|center) line\b|\bshare one\b"#, #"\bsmallest text\b|\b12 ?(-|to) ?14\b"#, #"\band (then )?(make|set|keep|use|put|add|remove|cut|raise|lower|move|change|enlarge|shrink)\b"#, #",\s*(then )?(make|set|keep|use|put|add|remove|cut|raise|lower|move|change|enlarge|shrink)\b"#, #"\bone step (smaller|lighter|larger|bigger|darker)\b|\bsmaller or lighter\b"#, #";\s*\w+"#, #"\b(rewrite|change|replace)\b.*\b(headline|slogan|line)\b.*\bsay what\b"#, #"\b\d+-\d+ real\b"#, #"\bnav(igation)?\b[^.]*\b(\d+|seven|few(er)?)\b|\b(menu|nav(igation)?) items\b"#, #"\b(less|lower|reduce)\b[^.]*\b(bold|emphasis)\b[^.]*\ball (but|except)\b|\ball (but|except)\b[^.]*\b(less bold|lower (the )?emphasis)\b"#, #"\bemphasis on all but\b"#]
        return pats.contains { f.range(of: $0, options: .regularExpression) != nil }
    }
    /// A plain Why for a meter below 100 when the writer returned nothing: the designer's reason, else the first failed check as a sentence.
    static let genericWhyPrefix = "A few points are lost on "
    static func fallbackWhy(score: Int, failed: [Check], designer: Int?, designerReason: String, meter: String = "") -> String {
        if score >= 100 { return "" }
        let real = failed.filter { !navCountIDs.contains($0.id) }
        if let d = designer, d < 100, !designerReason.isEmpty {
            let w = cleanWhy(designerReason.replacingOccurrences(of: #"^[A-Za-z ]+ is the (lowest|weakest|lowest score) (at|of) \d+:\s*"#, with: "", options: .regularExpression), meter: meter, topicFilter: false)
            let t = w.isEmpty ? "" : w.prefix(1).uppercased() + w.dropFirst()
            if !t.isEmpty { return t }
        }
        if let s = real.compactMap({ plainCheck[$0.id] }).first { return s }
        return ""
    }
    /// Quoted copy or capitalised product-like phrases in a Fix must exist in the page text; unknown copy means the Fix invented it.
    /// An empty page text means no OCR is available, so nothing can be checked.
    static func quotesOnPage(_ fix: String, page: String) -> Bool {
        guard !page.isEmpty else { return true }
        let hay = page.lowercased()
        var quoted = (try? NSRegularExpression(pattern: #"[\"“”']([^\"“”']{2,})[\"“”']"#))?.matches(in: fix, range: NSRange(fix.startIndex..., in: fix)).compactMap { m in Range(m.range(at: 1), in: fix).map { String(fix[$0]) } } ?? []
        // An example phrase after "such as" / "to say" is invented copy too.
        if let r = fix.range(of: #"(such as|e\.g\.|like) [A-Z][^.]*"#, options: .regularExpression) { quoted.append(String(fix[r]).replacingOccurrences(of: #"^(such as|e\.g\.|like) "#, with: "", options: .regularExpression)) }
        if let r = fix.range(of: #"(?<=\bto )[A-Z]\w*(?:\s+(?:[A-Z]|i[A-Z])\w*)+"#, options: .regularExpression) { quoted.append(String(fix[r])) }
        return quoted.allSatisfy { hay.contains($0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ."))) }
    }
    /// Failed checks go to the writer as the plain failed statement, never as a yes/no question or a "N or fewer" threshold it could echo back as a contradiction.
    static func writerFailedText(_ checks: [Check]) -> [String] { checks.map { plainCheck[$0.id] ?? $0.q } }
    static let layoutPlain: [String: String] = ["g_prox": "Gaps inside groups and between groups are too alike, so groups blur together.", "g_align": "Items inside a group do not share a left, right or centre line.", "g_region": "Some groups straddle two different background colours.", "g_meaning": "Items that sit together do not read as related.", "g_sim": "Matching items in different groups differ in size, weight or colour."]
    static let plainCheck: [String: String] = [
        "C8": "A banner or pop-up next to the main button competes with it.", "T3": "The page does not show the real product in use or a real person.", "T2": "The page shows no proof such as customer logos, ratings or user counts.",
        "E9": "Some text is much smaller than the body text.", "E10": "The body text is tiny next to the headline.", "E4": "The screen shows a lot of words.", "E7": "Some text sits on a gradient or photo.",
        "E6": "Many boxed panels crowd the screen.", "E1": "Too many text sizes are in use.", "E5": "Some lines of text run long.", "C6": "The headline does not say plainly what the product does.",
        "C7": "Some links or buttons do not look clickable.", "C9": "Some button labels are generic.", "C1": "More than one button competes as the main action.", "h_one_cta": "More than one button competes as the main action.",
        "h_emphasis": "Too many items shout for attention at once.", "h_cta_fold": "The main button sits low on the screen.", "h_first": "The eye does not land on the headline first.",
        "h_scale": "The headline is not much bigger than the text under it.", "c_aa": "Some text is hard to read against its background.", "T5": "A promo banner or pop-up competes with the page.", "c_most": "Several text items are too faint against their background.", "c_floor": "The faintest text is too faint against its background.", "c_head": "The largest text is too faint against its background.", "c_size": "The headline is not much larger than the body text.", "c_weight": "The headline is not set heavier than the body text.", "c_space": "The space between groups is no bigger than the space inside them.",
        "h_nav_quiet": "The navigation is as loud as the headline.", "C3": "The main button is not visible without scrolling.", "C10": "The sentences run long."]
    /// The Fix is the vetted rubric sentence of the heaviest failed check on the meter, or nothing. Designer-only deductions get no Fix.
    static func rubricFix(failed: [Check], score: Int, meter: String) -> String {
        if score >= 100 || meter == "balance" { return "" }
        guard let top = failed.max(by: { $0.w < $1.w }) else { return "" }
        let f = clean(top.fix)
        return f.isEmpty || bannedFix(f) || unsafeSubmitAdvice(f) ? "" : f
    }
    static func fallbackFix(meter k: String, failed: [Check]) -> String {
        if let f = failed.first(where: { !navCountIDs.contains($0.id) }) { let x = clean(f.fix); return bannedFix(x) || unsafeSubmitAdvice(x) ? "" : x }
        return ""
    }

    /// After the label calls all failed: asks each key once whether it is the keys that are at fault, not the reply.
    static func everyKeyRejected(_ keys: [String]) async -> Bool {
        for k in keys { if await KeyCheck.claude(k) == .ok { return false } }
        return true
    }

    /// Plain facts the writer may cite for Valence and Intensity: background brightness, dominant colour feel, copy tone words.
    static func feelingFacts(stats: PixelStats?, copy: String) -> [String: Any] {
        var f: [String: Any] = ["copy_sample": String(copy.prefix(300))]
        if let s = stats {
            f["background"] = s.bgLum > 0.5 ? "light" : (s.bgLum < 0.2 ? "dark" : "mid-tone")
            f["colors"] = s.accentSat > 0.7 ? "vivid accent" : (s.accentSat < 0.4 ? "muted or pastel" : "moderate accent")
            f["hue_mix"] = s.coolShare >= 0.5 ? "mostly cool (blue/green) or neutral" : "mostly warm"
            f["empty_space"] = s.emptyPct > 0.4 ? "lots" : (s.emptyPct < 0.2 ? "little" : "some")
        }
        return f
    }

    /// Tooltip text for every meter from the writer's reply (nil reply gives the fallback fixes and empty why lines).
    static func texts(for r: RunResult, written w: JSONValue?, pageText: String = "", overlayPresent: Bool = false) -> [String: MeterText] {
        var out: [String: MeterText] = [:]
        for k in Meters.order {
            let score = k == "reading" ? Int((r.readingGrade.map { gradePoints($0) * 10 } ?? 100).rounded()) : (r.meters[k]?.score ?? 0)
            let failed = Rubric.checks(for: k).filter { c in r.meters[k]?.checks.first { $0.id == c.id }?.yes == false }
            let failedIDs = (r.meters[k]?.checks ?? []).filter { !$0.yes && !navCountIDs.contains($0.id) }.map { $0.id }
            let arr = w?[k].array ?? []
            let own = r.designerReasons?[k] ?? ""
            let written = cleanWhy(clean(arr.count > 0 ? (arr[0].string ?? "") : ""), meter: k)
            var why: String
            if score >= 100 { why = "" }
            else if !failedIDs.isEmpty {
                // Failed checks: the writer's sentence about them, else a plain sentence for the heaviest one.
                why = written.isEmpty ? (layoutPlain[failedIDs[0]] ?? fallbackWhy(score: score, failed: failed.filter { !navCountIDs.contains($0.id) }, designer: nil, designerReason: "", meter: k)) : written
            } else if let d = r.meters[k]?.designer, d < 100, !own.isEmpty {
                // The only deduction is the designer's: that meter's own reason.
                let c = cleanWhy(own, meter: k, topicFilter: false)
                why = c.isEmpty ? fallbackWhy(score: score, failed: [], designer: d, designerReason: "", meter: k) : c
            } else {
                why = written.isEmpty ? fallbackWhy(score: score, failed: [], designer: r.meters[k]?.designer, designerReason: "", meter: k) : written
            }
            let problem = (arr.count > 2 ? (arr[2].bool ?? false) : false) || (k == "reading" && score < 85)
            if r.meters[k]?.applicable == false { out[k] = MeterText(why: "This doesn't apply to this kind of screen.", fix: ""); continue }
            why = groundedWhy(why, meter: k, overlayPresent: overlayPresent || (r.vision["has_overlay"].bool ?? false) || (r.vision["has_competing_promo"].bool ?? false))
            if k == "contrast" { why = contrastWhy(r, failedIDs: failedIDs, score: score, fallback: why) }
            out[k] = MeterText(why: why, fix: rubricFix(failed: failed, score: score, meter: k))
        }
        // Valence and Intensity are positions, not scores: a reason only. Reading gets a fix only above grade 9.
        for k in ["valence", "intensity"] {
            let arr = w?[k].array ?? []
            out[k] = MeterText(why: clean(arr.count > 0 ? (arr[0].string ?? "") : ""), fix: "")
        }
        if let g = r.readingGrade, g <= 9 { out["reading"]?.fix = "" }
        return out
    }

    /// Advice to move a submit / sign-in / primary button up, above or beside its fields. A senior designer never gives it:
    /// the action belongs below the fields it submits.
    static func unsafeSubmitAdvice(_ fix: String) -> Bool {
        let f = fix.lowercased()
        guard f.range(of: #"\b(button|submit|sign in|sign-in|log in|cta)\b"#, options: .regularExpression) != nil else { return false }
        // Only a position move counts; "raise the button contrast above 4.5:1" is a contrast fix.
        if f.range(of: #"\b(contrast|colou?rs?|size|label|text|font|padding|radius)\b"#, options: .regularExpression) != nil { return false }
        return f.range(of: #"\b(move|put|place|bring|shift|raise|lift)\b[^.]*\b(up|higher|upper|above|top|beside|near|next to)\b"#, options: .regularExpression) != nil
    }

    /// No Fix when the score is 100, or 85+ and the WHY line names no problem; a lower score always gets one.
    public static func finalFix(_ fix: String, score: Int, problem: Bool, failed: [Check], meter: String, hasDeduction: Bool = true) -> String {
        if score >= 100 || !hasDeduction || meter == "balance" { return "" }
        let none = fix.isEmpty || fix.lowercased().hasPrefix("nothing to fix")
        if fix.lowercased().hasPrefix("nothing to fix") && !problem { return "" }
        if score >= 85 && !problem { return "" }
        if none { return fallbackFix(meter: meter, failed: failed) }
        return bannedFix(fix) || unsafeSubmitAdvice(fix) ? "" : fix
    }
}
