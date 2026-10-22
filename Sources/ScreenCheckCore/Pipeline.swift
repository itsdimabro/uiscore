import Foundation
import CoreGraphics
import CryptoKit

public struct Pipeline {
    public var keys: Keys
    public init(keys: Keys) { self.keys = keys }

    public static func truncate(_ s: String, max n: Int = 110) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= n { return t }
        let cut = String(t.prefix(n - 1))
        if let sp = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: sp) > n / 2 {
            return String(cut[..<sp]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:")) + "…"
        }
        return cut + "…"
    }

    static let requiredFields = ["page_type", "screen_kind", "tone", "blocks", "fonts", "main_text_alignment", "nav_position", "logo_position", "panels", "columns",
                                 "first_fixation", "emphasis", "primary_buttons", "corner_style", "heaviest_weight", "roles"]
    /// The model sometimes answers `primary` as a list, sometimes as a bare id or a string id. Only a real box id counts.
    static func primaryID(_ v: JSONValue, count: Int) -> Int? {
        let p = v["roles"]["primary"]
        let id = p.array.first?.int ?? p.int ?? p.string.flatMap { Int($0) }
        if let id, (0..<count).contains(id) { return id }
        return nil
    }
    /// Field-by-field vote. Equal counts break by sorted value, so the result never depends on reply order.
    static func majority(_ rs: [JSONValue]) -> JSONValue {
        guard rs.count > 1, case .object(let first) = rs[0] else { return rs[0] }
        var out: [String: JSONValue] = [:]
        for k in first.keys.sorted() {
            if k == "roles" {
                var roles: [String: JSONValue] = [:]
                for role in rs.flatMap({ r -> [String] in if case .object(let o) = r["roles"] { return Array(o.keys) }; return [] }) where roles[role] == nil {
                    if role == "primary" {
                        let ids = rs.compactMap { primaryID($0, count: Int.max) }
                        let best = Dictionary(grouping: ids, by: { $0 }).max { ($0.value.count, -$0.key) < ($1.value.count, -$1.key) }
                        roles[role] = best.map { $0.value.count * 2 > rs.count ? .array([.number(Double($0.key))]) : .array([]) } ?? .array([])
                    } else {
                        var votes: [Int: Int] = [:]
                        for r in rs { for v in r["roles"][role].array { if let i = v.int { votes[i, default: 0] += 1 } } }
                        roles[role] = .array(votes.filter { $0.value * 2 > rs.count }.keys.sorted().map { .number(Double($0)) })
                        if role == "logo" {
                            let heads = Set(rs.flatMap { $0["roles"]["heading"].array.compactMap { $0.int } }.filter { id in rs.filter { $0["roles"]["heading"].array.contains { $0.int == id } }.count * 2 > rs.count })
                            roles[role] = .array(roles[role]!.array.filter { !heads.contains($0.int ?? -1) })
                        }
                    }
                }
                out[k] = .object(roles)
                continue
            }
            var counts: [String: (n: Int, v: JSONValue)] = [:]
            for r in rs { let v = r[k]; let key = String(describing: v); counts[key] = (( counts[key]?.n ?? 0) + 1, v) }
            out[k] = counts.sorted { ($0.value.n, $1.key) > ($1.value.n, $0.key) }.first!.value.v
        }
        return .object(out)
    }
    static func isComplete(_ v: JSONValue) -> Bool { requiredFields.allSatisfy { v[$0] != .null } }

    static func parseBoxes(_ v: JSONValue) -> [TextBox] {
        v["text_boxes"].array.compactMap { b in
            guard let t = b["text"].string, let x = b["x"].double, let y = b["y"].double,
                  let w = b["w"].double, let h = b["h"].double else { return nil }
            return TextBox(text: t, x: x, y: y, w: w, h: h, fontPx: b["font_px"].double ?? (h * 0.8),
                           bold: b["bold"].bool ?? false, role: (b["role"].string ?? "body").lowercased(),
                           onImage: b["on_image"].bool ?? false)
        }
    }

    public static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ScreenCheck/results", isDirectory: true)
    }
    /// SHA-256 of the decoded pixels (width, height, 8-bit sRGB RGBA), not of the file bytes: the same picture
    /// read from the clipboard (TIFF or re-encoded PNG) or from a screenshot file hashes the same.
    public static func imageHash(_ url: URL) -> String? {
        if let img = Contrast.load(url), let h = pixelHash(img) { return h }
        guard let d = try? Data(contentsOf: url) else { return nil }   // not a decodable image: fall back to the file bytes
        return "raw-" + SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }
    public static func pixelHash(_ img: CGImage) -> String? {
        let w = img.width, h = img.height
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let base = ctx.data else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var hasher = SHA256()
        hasher.update(data: Data("\(w)x\(h)|".utf8))
        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: base, count: w * 4 * h))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func cacheFile(_ hash: String, _ dir: URL) -> URL { dir.appendingPathComponent(hash + ".json") }
    public static func cached(hash: String, dir: URL = Pipeline.cacheDir) -> RunResult? {
        guard let d = try? Data(contentsOf: cacheFile(hash, dir)) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(RunResult.self, from: d)
    }
    public static func store(_ r: RunResult, hash: String, dir: URL = Pipeline.cacheDir) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(r) { try? d.write(to: cacheFile(hash, dir)) }
    }

    /// Tooltip text is never cut: the writer is asked for one short sentence, and whatever it returns is shown whole.
    static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Results saved before text stopped being cut end in "…"; they are scored again instead of shown cut off.
    public static func isTruncated(_ r: RunResult) -> Bool {
        r.text.values.contains { $0.why.hasSuffix("…") || $0.fix.hasSuffix("…") }
    }

    /// The stored result for these image bytes, or nil. No model is called.
    /// The image is matched by the hash of its bytes, first in the results cache, then in the saved history runs.
    public static func lookup(imageURL: URL, cacheDir: URL = Pipeline.cacheDir, historyRoot: URL? = History.root) -> RunResult? {
        guard let h = imageHash(imageURL) else { return nil }
        if let hit = cached(hash: h, dir: cacheDir), hit.isScored { return hit }
        if let root = historyRoot { return History.find(imageHash: h, root: root) }
        return nil
    }

    /// Hands out partial results in order: state and callback share one lock, so a late stage can never show before an earlier one.
    final class Stages {
        private let lock = NSLock()
        private let t0 = Date()
        private let sink: ((RunResult, Set<String>) -> Void)?
        private let make: (Stages) -> RunResult
        var meters: [String: MeterResult] = [:]
        var ready: Set<String> = []
        var name = ""
        var vision: JSONValue = .null
        var contrast: ContrastReport?
        var stats: PixelStats?
        private(set) var firstMS: Double?
        init(sink: ((RunResult, Set<String>) -> Void)?, make: @escaping (Stages) -> RunResult) { self.sink = sink; self.make = make }
        func emit(meters m: [String: MeterResult] = [:], ready r: Set<String>, update: ((Stages) -> Void)? = nil) {
            lock.lock(); defer { lock.unlock() }
            update?(self)
            for (k, v) in m { meters[k] = v }
            ready.formUnion(r)
            if firstMS == nil { firstMS = Date().timeIntervalSince(t0) * 1000 }
            sink?(make(self), ready)
        }
    }

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
            guard let q, !page.isEmpty || true else { return true }
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
        let topic = ["balance": "how weight spreads across the page", "grouping": "how clearly related items sit together", "contrast": "how easily text reads against its background", "order": "how clearly the eye is led through the page", "familiar": "how closely the layout follows usual patterns", "ease": "how easy the page is to take in", "clarity": "how clearly the main action stands out", "trust": "how trustworthy the page looks"][meter] ?? "the overall look"
        _ = topic
        return ""
    }
    /// Quoted copy or capitalised product-like phrases in a Fix must exist in the page text; unknown copy means the Fix invented it.
    /// An empty page text means no OCR is available, so nothing can be checked.
    static func quotesOnPage(_ fix: String, page: String) -> Bool {
        guard !page.isEmpty else { return true }
        let hay = page.lowercased()
        var quoted = (try? NSRegularExpression(pattern: #"[\"“”']([^\"“”']{2,})[\"“”']"#))?.matches(in: fix, range: NSRange(fix.startIndex..., in: fix)).compactMap { m in Range(m.range(at: 1), in: fix).map { String(fix[$0]) } } ?? []
        // "such as Explore iPhone Duo features": an example phrase after "such as" / "to say" is invented copy too.
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

    /// Runs the whole pipeline. `onScores` fires as soon as scores are ready; the returned result also has the text.
    /// With `useCache` the stored result for the same image bytes is returned and no model is called.
    public func run(imageURL: URL, useCache: Bool = true, fallbackName: String = "Screenshot", cacheDir: URL = Pipeline.cacheDir, historyRoot: URL? = History.root, onScores: ((RunResult) -> Void)? = nil, onPartial: ((RunResult, Set<String>) -> Void)? = nil) async throws -> RunResult {
        let hash = Pipeline.imageHash(imageURL)
        if useCache, let hit = Pipeline.lookup(imageURL: imageURL, cacheDir: cacheDir, historyRoot: historyRoot) {
            onScores?(hit)
            if hit.textComplete { return hit }
            return try await completeText(hit, hash: hash, cacheDir: cacheDir)
        }
        guard !keys.claude.isEmpty else { throw PipelineError.noKey("Claude") }
        guard !keys.jev.isEmpty else { throw PipelineError.noKey("Jev") }
        guard let full = Contrast.load(imageURL) else { throw PipelineError.unreadableImage }
        let t0 = Date()
        let runID = UUID().uuidString
        var T = Timings()

        // Text boxes come from Apple Vision on the full image: same pixels, same boxes, every run.
        let to = Date()
        var boxes = OCR.boxes(in: full)
        // Retina captures: text height in px is twice the CSS px, so every size threshold would be wrong. Sizes are put in points.
        let screenScale = Contrast.screenScale(imageURL, width: full.width)
        if screenScale > 1 { for i in boxes.indices { boxes[i].fontPx /= screenScale } }
        T.ocr = Date().timeIntervalSince(to) * 1000
        // Reading level uses line geometry only, so it does not wait for the labels.
        let rd = Readability.grade(forCopy: Readability.countedParagraphs(boxes, imageHeight: full.height))
        let stages = Stages(sink: onPartial) { s in
            RunResult(id: runID, createdAt: Date(), pageName: s.name, imageWidth: full.width, imageHeight: full.height, meters: s.meters,
                      feeling: [:], feelingLow: [:], feelingConfidencePct: [:], readingGrade: rd?.grade, readingGradeCapped: rd?.capped, readingWords: rd?.words ?? 0,
                      text: [:], timings: T, contrastDetail: s.contrast, vision: s.vision, pixelStats: s.stats)
        }
        stages.emit(ready: ["reading"])

        let small = Contrast.downscaled(full)
        guard let png = Contrast.pngData(small) else { throw PipelineError.unreadableImage }
        let b64 = png.base64EncodedString()
        let img: [String: Any] = ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": b64]]
        let k = Double(small.width) / Double(full.width)   // ids are listed to the model in small-image pixels
        let listed = boxes.indices.sorted { boxes[$0].w * boxes[$0].h > boxes[$1].w * boxes[$1].h }.prefix(250).sorted()
        let list = listed.map { i -> String in
            let b = boxes[i]
            return "\(i)|\(Int(b.x * k)),\(Int(b.y * k)),\(Int(b.w * k)),\(Int(b.h * k))|\(String(b.text.prefix(60)))"
        }.joined(separator: "\n")

        let key = keys.claude
        // A reply cut off before its last fields would leave them missing, and missing fields used to read as "fine".
        // Such a reply is never scored: ask again once, then fail.
        let content: [[String: Any]] = [img, ["type": "text", "text": "Image is \(small.width)x\(small.height) px. OCR boxes:\n\(list)"]]
        // C6 (headline says what this is): Sonnet looks at the image. Jev agreed with Opus on 52% of pages, Sonnet on 90%.
        let c6Content: [[String: Any]] = [img, ["type": "text", "text": "OCR text on the page:\n" + String(listed.map { String(boxes[$0].text.prefix(60)) }.joined(separator: "\n").prefix(3000))]]
        let c6Task = Task<Bool?, Never> {
            // The vote on one image is stored the first time, so scoring the same image again gives the same answer.
            let c6File = hash.map { cacheDir.appendingPathComponent("c6-\($0).txt") }
            if let f = c6File, let t = try? String(contentsOf: f, encoding: .utf8) { return t == "1" }
            let votes: [Bool] = await withTaskGroup(of: Bool?.self) { g in
                for _ in 0..<5 { g.addTask { do { return try await Claude.call(keys: key, system: Prompts.c6, content: c6Content, maxTokens: 500, model: Claude.sonnet).json["C6"].bool } catch { if ProcessInfo.processInfo.environment["SCREENCHECK_DEBUG"] != nil { FileHandle.standardError.write(Data("c6 error: \(error)\n".utf8)) }; return nil } } }
                var v: [Bool] = []
                for await x in g { if let x { v.append(x) } }
                return v
            }
            // 5 votes; a headline counts as plain only with a clear majority (4 of 5), so a 3-2 split cannot flip run to run.
            guard !votes.isEmpty else { return nil }
            let yes = votes.filter { $0 }.count * 5 >= votes.count * 4
            if votes.count >= 4, let f = c6File { try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true); try? (yes ? "1" : "0").write(to: f, atomically: true, encoding: .utf8) }
            return yes
        }
        // Three identical label calls in parallel; every field takes the majority answer, so one odd reply cannot flip a check.
        let replies: [(json: JSONValue, ms: Double)] = await withTaskGroup(of: (json: JSONValue, ms: Double)?.self) { g in
            for _ in 0..<3 { g.addTask { try? await Claude.call(keys: key, system: Prompts.label, content: content, maxTokens: 2600) } }
            var r: [(json: JSONValue, ms: Double)] = []
            for await x in g { if let x, Self.isComplete(x.json) { r.append(x) } }
            return r
        }
        if replies.isEmpty, await Self.everyKeyRejected(keys.claude) { throw PipelineError.allKeysFailed }
        guard !replies.isEmpty else { throw PipelineError.badModelOutput("label reply incomplete") }
        let labelR = (json: Self.majority(replies.map { $0.json }), ms: replies.map { $0.ms }.max() ?? 0)
        T.visionFields = labelR.ms
        T.vision = Date().timeIntervalSince(t0) * 1000

        var vision = labelR.json
        // Page context: per-field majority over the label replies, locked before any check is asked.
        let context = PageContext.resolve(votes: replies.map { $0.json })
        boxes = OCR.applyRoles(vision["roles"], to: boxes)
        // Where the primary button sits comes from its OCR box, not from the model.
        let px0 = Pixels(cgImage: full)
        let primary = Self.primaryID(vision, count: boxes.count).flatMap { id in px0.map { Contrast.isFilled($0, box: boxes[id]) } ?? true ? id : nil }
        if let pid = primary {
            let b = boxes[pid]
            if case .object(var o) = vision { o["primary_y_pct"] = .number((b.y + b.h / 2) / Double(full.height) * 100); o["primary_y_pt"] = .number((b.y + b.h / 2) / max(1, screenScale)); vision = .object(o) }
        }
        // Consent bars and chat bubbles are transient overlays: they leave every layout and text meter.
        let scaled = boxes.filter { $0.role != "overlay" }

        // Code checks
        let tc = Date()
        let pixels = Pixels(cgImage: full)
        let stats = pixels.map { PixelStats.compute($0) }
        var facts = Scoring.facts(from: vision, textBoxes: scaled)
        facts.imageHeight = full.height
        facts.allBoxes = scaled
        // Unmeasurable text (gradient, photo, neighbouring artwork) counted over all non-logo, non-demo boxes.
        let textOnly = scaled.filter { !Scoring.nonPage.contains($0.role) }
        let un = pixels.map { px in textOnly.filter { Contrast.clusterSample(px, box: $0) == nil }.count } ?? 0
        facts.unmeasuredShare = textOnly.isEmpty ? 0 : Double(un) / Double(textOnly.count)
        facts.primaryCount = primary == nil ? 0 : 1
        facts.primaryText = primary.map { boxes[$0].text } ?? ""
        let code = Scoring.codeAnswers(facts, pixels: pixels, appScreen: PageContext.resolve(votes: replies.map { $0.json }).adjust(ScreenKind.resolve(vision: vision, width: full.width, height: full.height), width: full.width, height: full.height) == .app)
        var codeAns = code.answers
        for (k, v) in Scoring.visionAnswers(facts, stats: stats) where codeAns[k] == nil { codeAns[k] = v }
        T.code = Date().timeIntervalSince(tc) * 1000

        // Designer ratings start as soon as the code facts exist and run in parallel with Jev and the writer.
        let designerFacts = Designer.facts(context: context, width: full.width, height: full.height, contrast: code.contrast, stats: stats, readingWords: rd?.words ?? 0)
        let designerTask = Task<Designer.Rating?, Never> { await Designer.rate(keys: key, image: img, facts: designerFacts, hash: useCache ? hash : nil, cacheDir: cacheDir) }
        let pageName = PageName.generated(vision["page_name"].string) ?? fallbackName
        // Stage 1: everything code alone can answer.
        var contrastAns: [String: (yes: Bool, p: Double?, kind: String)] = [:]
        for c in Rubric.checks(for: "contrast") { contrastAns[c.id] = (codeAns[c.id] ?? false, nil, "code") }
        var contrastR = Scoring.weightedScore("contrast", answers: contrastAns)
        contrastR.note = code.note
        stages.emit(meters: ["contrast": contrastR], ready: ["contrast"]) { $0.name = pageName; $0.vision = vision; $0.contrast = code.contrast; $0.stats = stats }
        // Balance and Alignment: pixels and OCR boxes only.
        let meaning = vision["grouping_clear"].bool
        let layoutMeters = Layout.meters(pixels: pixels, boxes: scaled, imageWidth: full.width, meaning: meaning)
        stages.emit(meters: layoutMeters, ready: Set(layoutMeters.keys))
        let lp = Layout.problems(pixels: pixels, boxes: scaled, imageWidth: full.width, meaning: meaning)
        // Text fill-in starts now, in parallel with Jev. It sees every check answered so far; Jev-only checks come later.
        let provisional: [String: Any] = {
            var sc: [String: Any] = [:]
            for m in Rubric.meterKeys {
                let cs = Rubric.checks(for: m)
                let failed = Self.writerFailedText(Array(cs.filter { codeAns[$0.id] == false }.prefix(3)))
                let got = cs.filter { codeAns[$0.id] == true }.reduce(0) { $0 + $1.w }
                let known = cs.filter { codeAns[$0.id] != nil }.reduce(0) { $0 + $1.w }
                sc[m] = ["score": known == 0 ? 0 : Int((Double(got) / Double(known) * 100).rounded()), "failed": Array(failed)]
            }
            for (k, v) in layoutMeters { sc[k] = ["score": v.score, "failed": lp[k] ?? [String]()] }
            if let rd { sc["reading"] = ["grade": rd.grade, "score": Int((Self.gradePoints(rd.grade) * 10).rounded())] }
            let bad = code.contrast.boxes.filter { !$0.pass && $0.ratio != nil }.prefix(2).map { "\(Self.truncate($0.text, max: 24)) \(String(format: "%.1f", $0.ratio!)):1" }
            var f: [String: Any] = ["page": pageName, "copy": String(facts.allCopy.prefix(500)),
                                    "look": Self.truncate(vision["visual_description"].string ?? "", max: 240), "meters": sc]
            if !bad.isEmpty { f["weak_text"] = Array(bad) }
            f["feeling_facts"] = Self.feelingFacts(stats: stats, copy: facts.allCopy)
            if let rd { f["reading_facts"] = Readability.hardest(paras: Readability.countedParagraphs(scaled, imageHeight: full.height)).merging(["grade": rd.grade, "capped": rd.capped]) { a, _ in a } }
            return f
        }()
        // Jev: only the checks code could not answer.
        var state: [String: JSONValue] = [:]
        if case .object(let o) = vision { state = o }
        // Free text from the model (name, description, role ids) wobbles between runs and would sway Jev's answers.
        for k in ["roles", "visual_description", "page_name", "primary_y_pct", "primary_y_pt", "heaviest_weight", "logo_position", "main_text_alignment", "real_imagery", "text_on_busy_bg"] { state[k] = nil }
        state["all_copy"] = .string(facts.allCopy)
        state["text_box_count"] = .number(Double(facts.boxes.count))
        let c6 = await c6Task.value
        if let c6 { codeAns["C6"] = Applicability.c6Holds(vote: c6, context: context, demonstrates: facts.demonstratesProduct) }
        let notApplicableEarly = Applicability.notApplicable(kind: context.adjust(ScreenKind.resolve(vision: vision, width: full.width, height: full.height), width: full.width, height: full.height), pageType: vision["page_type"].string ?? "", facts: facts, context: context)
        // Meters whose checks code already answered do not wait for Jev.
        for m in Rubric.meterKeys where m != "contrast" {
            let cs = Rubric.checks(for: m).filter { !notApplicableEarly.contains($0.id) }
            guard !cs.isEmpty, cs.allSatisfy({ codeAns[$0.id] != nil }) else { continue }
            var ans: [String: (yes: Bool, p: Double?, kind: String)] = [:]
            for c in Rubric.checks(for: m) { ans[c.id] = (codeAns[c.id] ?? false, nil, "code") }
            stages.emit(meters: [m: Scoring.weightedScore(m, answers: ans, cap: nil, notApplicable: notApplicableEarly, weights: Applicability.contextWeights(context))], ready: [m])
        }
        var qs: [String: String] = [:]
        for c in Rubric.checks where codeAns[c.id] == nil && !notApplicableEarly.contains(c.id) { qs[c.id] = Applicability.contextWording(context)[c.id] ?? c.jev }
        var jevP: [String: Double] = [:]
        if !qs.isEmpty {
            let jev = try await Jev.ask(key: keys.jev, state: .object(state), questions: qs)
            jevP = jev.p; T.jev = jev.ms
        }
        func answer(_ c: Check) -> (yes: Bool, p: Double?, kind: String) {
            if let y = codeAns[c.id] { return (y, nil, "code") }
            let p = jevP[c.id] ?? 0
            return (p >= 0.5, p, "jev")
        }

        // Footer items (contact, privacy, terms) are normally below the first screen of a landing page, so T4 is not asked there.
        let screenKind = context.adjust(ScreenKind.resolve(vision: vision, width: full.width, height: full.height), width: full.width, height: full.height)
        let notApplicable = Applicability.notApplicable(kind: screenKind, pageType: vision["page_type"].string ?? "", facts: facts, context: context)
        var meters: [String: MeterResult] = [:]
        for m in Rubric.meterKeys {
            var ans: [String: (yes: Bool, p: Double?, kind: String)] = [:]
            for c in Rubric.checks(for: m) { ans[c.id] = answer(c) }
            var r = Scoring.weightedScore(m, answers: ans, cap: nil, notApplicable: notApplicable, weights: Applicability.contextWeights(context))
            if m == "contrast" { r.note = code.note }
            meters[m] = r
        }
        for (k, v) in layoutMeters { meters[k] = v }
        // Falls back to the checklist alone when fewer than 2 designer votes were valid.
        let designer = await designerTask.value
        meters = Designer.blend(meters, rating: designer)

        var feeling: [String: Int] = [:]
        var fconf: [String: Int] = [:]
        for k in Rubric.feelingKeys {
            let cs = Rubric.checks(for: k)
            let rs = cs.map { c -> CheckResult in let a = answer(c); return CheckResult(id: c.id, yes: a.yes, p: a.p, weight: c.w, kind: a.kind) }
            feeling[k] = Feeling.score(rs, checks: cs)
            fconf[k] = Int((rs.reduce(0.0) { $0 + Double($1.weight) * ($1.p.map { max($0, 1 - $0) } ?? 1) } / Double(max(1, cs.reduce(0) { $0 + $1.w })) * 100).rounded())
        }

        T.scoresFirst = Date().timeIntervalSince(t0) * 1000
        T.firstValue = stages.firstMS
        var result = RunResult(
            id: runID, createdAt: Date(), pageName: pageName,
            imageWidth: full.width, imageHeight: full.height, meters: meters, feeling: feeling,
            feelingLow: ["v": min(fconf["vv"]!, fconf["cv"]!) < 78, "a": min(fconf["vi"]!, fconf["ci"]!) < 78],
            feelingConfidencePct: ["v": min(fconf["vv"]!, fconf["cv"]!), "a": min(fconf["vi"]!, fconf["ci"]!)],
            readingGrade: rd?.grade, readingGradeCapped: rd?.capped, readingWords: rd?.words ?? 0, text: [:], timings: T,
            contrastDetail: code.contrast, vision: vision, pixelStats: stats)
        result.overall = Scoring.overall(meters: meters.filter { $0.value.applicable != false }.mapValues { $0.score }, reading: rd.map { Int((Self.gradePoints($0.grade) * 10).rounded()) })
        result.imageHash = hash
        result.designerReason = designer?.reason
        result.designerReasons = designer?.reasons
        result.context = context
        let ctxChanged = notApplicable.filter { Applicability.kinds[$0] != nil || !Applicability.contextNotApplicable(context).isDisjoint(with: [$0]) }
        result.contextNote = Applicability.contextNote(context, changed: ctxChanged)
        // Scores are reusable from here on, even while the text is still being written.
        if useCache, let h = hash { Pipeline.store(result, hash: h, dir: cacheDir) }
        onScores?(result)

        // The writer sees the FINAL blended scores, the failed checks (code and Jev) and the designer's deduction.
        let writeStart = Date()
        var wf = provisional
        var sc = (wf["meters"] as? [String: Any]) ?? [:]
        var failedQ: [String: [String]] = [:]
        for k in Meters.order where k != "reading" {
            failedQ[k] = Rubric.checks(for: k).filter { c in !Self.navCountIDs.contains(c.id) }.filter { c in result.meters[k]?.checks.first { $0.id == c.id }?.yes == false }.prefix(3).map { Self.plainCheck[$0.id] ?? $0.q }
        }
        for (k, v) in lp { failedQ[k] = v }
        for (k, v) in Pipeline.writerMeterFacts(meters: result.meters.filter { $0.value.applicable != false }, failed: failedQ) { sc[k] = v }
        wf["meters"] = sc
        wf["feeling_facts"] = Self.feelingFacts(stats: stats, copy: facts.allCopy)
        let w: JSONValue? = await {
            guard let data = try? JSONSerialization.data(withJSONObject: wf), let str = String(data: data, encoding: .utf8) else { return nil }
            return try? await Claude.call(keys: key, system: Prompts.write, content: [["type": "text", "text": str]], maxTokens: 900).json
        }()
        T.write = Date().timeIntervalSince(writeStart) * 1000
        result.text = Self.texts(for: result, written: w, pageText: facts.allCopy, overlayPresent: boxes.contains { $0.role == "overlay" })
        T.total = Date().timeIntervalSince(t0) * 1000
        result.timings = T
        if useCache, let h = hash { Pipeline.store(result, hash: h, dir: cacheDir) }
        return result
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

    /// Writes the tooltip text for a stored run that has scores but no (or cut-off) text. Scores are not touched.
    func completeText(_ stored: RunResult, hash: String?, cacheDir: URL) async throws -> RunResult {
        var r = stored
        var sc: [String: Any] = [:]
        for k in Meters.order {
            let failed = Rubric.checks(for: k).filter { c in !Self.navCountIDs.contains(c.id) }.filter { c in r.meters[k]?.checks.first { $0.id == c.id }?.yes == false }.prefix(3).map { Self.plainCheck[$0.id] ?? $0.q }
            if k == "reading" { sc[k] = ["grade": r.readingGrade ?? 0, "score": Int(((r.readingGrade.map { Self.gradePoints($0) * 10 }) ?? 100).rounded())]; continue }
            sc[k] = ["score": r.meters[k]?.score ?? 0, "failed": Array(failed)]
        }
        var facts: [String: Any] = ["page": r.pageName, "look": Self.truncate(r.vision["visual_description"].string ?? "", max: 240), "meters": sc]
        facts["feeling_facts"] = Self.feelingFacts(stats: r.pixelStats, copy: "")
        var w: JSONValue?
        if let data = try? JSONSerialization.data(withJSONObject: facts), let str = String(data: data, encoding: .utf8) {
            w = try? await Claude.call(keys: keys.claude, system: Prompts.write, content: [["type": "text", "text": str]], maxTokens: 900).json
        }
        r.text = Self.texts(for: r, written: w)
        if let h = hash, r.textComplete { Pipeline.store(r, hash: h, dir: cacheDir) }
        return r
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

    /// Reading points (0-10): grade 9 or lower = 10 (WCAG 3.1.5), falling linearly to 0 at grade 12 and above.
    public static func gradePoints(_ g: Int) -> Double {
        let g = Double(g)
        if g <= 9 { return 10 }
        if g >= 12 { return 0 }
        return 10 * (12 - g) / 3
    }
}
