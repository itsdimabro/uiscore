import Foundation

/// Per-meter ratings from one senior-designer Sonnet call (5 votes, median per meter), blended with the checklist score.
/// Weights were chosen on the gold calibrate half and the LabintheWild train 40 only (see README, 0.3.0).
public enum Designer {
    public static let version = "d1"
    public static let meters = ["contrast", "grouping", "balance", "order", "familiar", "ease", "clarity", "trust"]
    /// Share of the designer rating in each meter; 0 keeps the checklist alone.
    public static let weights: [String: Double] = ["contrast": 0, "grouping": 0.75, "balance": 1, "order": 0.5, "familiar": 0.5, "ease": 1, "clarity": 0.75, "trust": 0]
    public static let votes = 5

    public struct Rating: Codable, Equatable {
        public var scores: [String: Double]   // 1-9 per meter
        public var reason: String
    }

    static func prompt(facts: String) -> String {
        """
        You are a senior product designer reviewing one screenshot. Rate it on 8 meters, each an integer 1-9 (1 = poor, 5 = adequate, 9 = exemplary, the standard of the best-known products). Judge what is on screen against its own type (app screen, landing page, fragment); do not punish a page for things its type does not need. Use the full range and be decisive.
        
        Meters, with anchors:
        contrast - Is text easy to see against its background? 1: light grey on white, text on busy photos. 5: body text passes 4.5:1 but small or secondary text is faint. 9: every text passes WCAG AA with margin, headings strong, nothing strains the eye.
        grouping - Do related things look grouped (Gestalt proximity, common region, similarity, alignment)? 1: evenly spaced items, no sense of units. 5: groups exist but gaps inside and between groups are similar. 9: less space inside a group than between groups everywhere, cards or shared edges mark groups, edges align.
        balance - Does visual weight feel even across the page? 1: all heavy content crammed to one side or corner, big dead area. 5: mild lean to one side. 9: weight is distributed deliberately, asymmetry is counter-weighted, white space is intentional.
        order - Visual hierarchy: is it clear what to look at first, second, third? 1: many items of equal weight compete, no focal point. 5: a focal point exists but several things compete. 9: one clear focal point, 3-4 distinct type sizes/weights, the main action stands out by contrast.
        familiar - Does it follow conventions people already know (logo top-left, nav in a bar, standard icons, button shapes, 8pt rhythm)? 1: unusual layout where nothing works as expected. 5: mostly standard with surprises. 9: every pattern is one users already know.
        ease - Is it easy to take in without effort (little clutter, few choices, generous white space, readable sizes)? 1: dense wall of text and links, tiny type. 5: moderate density. 9: calm, few choices, text 16px or more, lots of room.
        clarity - Is it clear what this is and what to do next? 1: purpose unclear, many competing actions. 5: purpose clear but next step ambiguous. 9: headline says what it is, one obvious primary action.
        trust - Does it look professional and trustworthy (polish, consistent style, confident honest tone, no hype or pressure, no typos)? 1: dated, sloppy, loud sales pressure. 5: neutral. 9: polished, consistent, calm confident tone.
        
        Facts measured by code (use as evidence, they are reliable):
        \(facts)
        
        Reply with ONE JSON object only: {"reason":"<one sentence, plain, the main reason for the lowest score>","contrast":n,"grouping":n,"balance":n,"order":n,"familiar":n,"ease":n,"clarity":n,"trust":n}
        """
    }

    /// Facts the code measured, given to the designer as evidence.
    static func facts(context: PageContext, width: Int, height: Int, contrast: ContrastReport?, stats: PixelStats?, readingWords: Int) -> String {
        var f = ["page context: \(context.businessModel) / \(context.location); image \(width)x\(height)"]
        if let c = contrast {
            f.append("text boxes measured for contrast: \(c.boxes.count); passing \(c.passing); lowest ratio \(c.minRatio.map { String($0) } ?? "none")")
            for b in c.boxes.filter({ !$0.pass && $0.ratio != nil }).prefix(3) {
                f.append("weak text: '\(String(b.text.prefix(30)))' \(String(format: "%.1f", b.ratio!)):1 (needs \(b.need))")
            }
        }
        if let s = stats { f.append("empty space \(Int((s.emptyPct * 100).rounded()))%, distinct hues \(s.hueCount), background luminance \(String(format: "%.2f", s.bgLum))") }
        f.append("reading words: \(readingWords)")
        return f.joined(separator: "\n")
    }

    /// One reply: every meter must be an integer 1-9, otherwise the vote is dropped.
    static func parse(_ v: JSONValue) -> Rating? {
        var s: [String: Double] = [:]
        for m in meters {
            guard let d = v[m].double, d == d.rounded(), (1...9).contains(d) else { return nil }
            s[m] = d
        }
        return Rating(scores: s, reason: (v["reason"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Median per meter over the valid votes; needs at least 2 of them.
    static func median(_ rs: [Rating]) -> Rating? {
        guard rs.count >= 2 else { return nil }
        var out: [String: Double] = [:]
        for m in meters {
            let v = rs.map { $0.scores[m]! }.sorted()
            out[m] = v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
        }
        return Rating(scores: out, reason: rs.first { !$0.reason.isEmpty }?.reason ?? "")
    }

    /// 1-9 rating on the 0-100 meter scale.
    static func points(_ r: Double) -> Double { (r - 1) / 8 * 100 }

    /// Checklist and designer blended. A meter the checklist marked not applicable stays so; a meter with no checklist
    /// answer yet or no designer rating keeps the checklist.
    public static func blend(_ meters: [String: MeterResult], rating: Rating?, weights: [String: Double] = Designer.weights) -> [String: MeterResult] {
        guard let rating else { return meters }
        var out = meters
        for (m, w) in weights where w > 0 {
            guard var r = out[m], r.applicable != false, let d = rating.scores[m] else { continue }
            r.score = max(0, min(100, Int((w * points(d) + (1 - w) * Double(r.score)).rounded())))
            r.designer = Int(points(d).rounded())
            out[m] = r
        }
        return out
    }

    /// Five parallel votes, median per meter. The medians for one image are stored, so scoring it again gives the same answer.
    /// nil when fewer than 2 votes are valid: the caller keeps the checklist.
    static func rate(keys: [String], image: [String: Any], facts: String, hash: String?, cacheDir: URL) async -> Rating? {
        let file = hash.map { cacheDir.appendingPathComponent("designer-\($0)-\(version).json") }
        if let f = file, let d = try? Data(contentsOf: f), let r = try? JSONDecoder().decode(Rating.self, from: d) { return r }
        let content: [[String: Any]] = [image, ["type": "text", "text": prompt(facts: facts)]]
        let rs: [Rating] = await withTaskGroup(of: Rating?.self) { g in
            for _ in 0..<votes { g.addTask { (try? await Claude.call(keys: keys, system: "", content: content, maxTokens: 300, model: Claude.sonnet)).flatMap { parse($0.json) } } }
            var v: [Rating] = []
            for await x in g { if let x { v.append(x) } }
            return v
        }
        guard let r = median(rs) else { return nil }
        if rs.count == votes, let f = file {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            if let d = try? JSONEncoder().encode(r) { try? d.write(to: f) }
        }
        return r
    }
}
