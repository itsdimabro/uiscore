import Foundation

/// Per-meter ratings from one senior-designer Sonnet call (5 votes, mean per meter), blended with the checklist score.
/// Weights were chosen on the gold calibrate half and the LabintheWild train 40 only (see README, 0.3.0).
public enum Designer {
    public static let version = "d6"
    public static let meters = ["contrast", "grouping", "balance", "order", "familiar", "ease", "clarity", "trust"]
    /// Share of the designer rating in each meter; 0 keeps the checklist alone.
    public static let weights: [String: Double] = ["contrast": 0, "grouping": 0.75, "balance": 1, "order": 0.5, "familiar": 0.5, "ease": 1, "clarity": 0.75, "trust": 0]
    public static let votes = 5

    public struct Rating: Codable, Equatable {
        public var scores: [String: Double]   // 1-9 per meter
        public var reason: String
        public var reasons: [String: String] = [:]   // one plain sentence per meter
    }

    /// The fixed rules: one system block, cached across the five votes and across images.
    static let systemPrompt = """
    You are a senior product designer rating one screenshot on 8 meters, each an integer 1-9 (9 = the standard of the best-known products, 3 = clearly poor, 1 = broken). You see only the image: never judge display size, zoom, DPI, hover states or anything below the capture.

    DEDUCTION DISCIPLINE (every meter)
    - Start each meter at 9 and subtract only for a real, visible defect. A 9 needs evidence of craft (deliberate hierarchy, spacing, finish), not just the absence of errors. A polished page from a professional team starts at 8-9; a dated, cluttered or default-looking page does not get that start: score what is plainly there. Compare to the best product in its category, not to a perfect page.
    - Every reason names the exact visible element ("the grey 'Learn more' link under the second card"), never "some elements". Never claim an element you cannot see: no ads, pop-ups, banners, borders or buttons that are not plainly on screen.
    - When nothing real is wrong, give 9 and stay silent: the reason is "". Do not hunt for something to say. At most one or two issues per meter.
    - Write each reason as ONE plain sentence saying what would take that meter to the top ("Give the 'Sign in' link the same weight as the other nav items"), with no numbers, no ratings and no other meter's name.
    - No single cue (alignment, whitespace, small text) decides a meter alone. Never state absolute sizes (no px, no "text is small"); only relative sizes and line length.
    - Cookie bars, consent banners, chat bubbles and notification pills are transient overlays: ignore them in every meter and never cite them. Product demos, mockups and sample UI inside the page are evidence, not reading load, clutter or competing buttons; do not score their inner text.
    - The "never penalise" lists below stop false deductions on good pages; they never excuse a weak page. DEDUCT (name the element) for: dense walls of text links or undifferentiated link columns; many competing font styles, sizes or colours; default-looking browser-style controls and unstyled tables; no clear primary action or no dominant element; cramped spacing between unrelated items; dated chrome (bevels, tiled backgrounds, table borders, clip-art). Each such page loses 2-4 points on the meters it hurts (order, ease, grouping, balance, familiar, trust, contrast). Grouping and balance are not free 9s on these pages: crowded link columns whose sections barely separate, a heavy crowded band beside empty or flat areas, or boxes and banners of unequal weight pulling in different directions score 3-5. On a dated or hostile page most meters land at 3-5; a mostly-9 profile there is wrong.
    - A first-screen capture has no footer: never penalise missing footer, contact, privacy or below-the-fold content.

    CONTEXT: decide first whether the page is MARKETING (hero, pricing, campaign, brand or store front: the visitor decides and acts) or APP/DASHBOARD (the visitor completes a task: tables, sidebars, editors, settings). The facts give a business model and location as a hint (homepage and landing are marketing; inside is app). Judge each meter by its own context.

    contrast - colour, size, weight and spacing contrast; contrast follows importance.
    9: the main action and headline stand out from everything else; body text reads easily on its ground; at least two of size, weight, colour, space separate the levels; text over photos has a dark area or overlay behind it. 3: body or label text is visibly faint on its background or lost on a busy image, or every level shares one size, weight and colour, or the main button is the tone of the page.
    Marketing: bold scale and weight jumps are the goal. App: contrast ranks data, states and actions; mostly neutral with one accent is correct.
    Also: fine detail (small text, thin lines, icons) needs a light/dark difference from its ground, not only a hue difference (orange on red, blue on black); pure saturated opposing hues touching vibrate; meaning carried by colour alone (a status shown only as a coloured dot) loses points; paragraphs in ALL CAPS read slower.
    Not a defect: distinct brand-colour buttons, deliberately muted but readable secondary text, text inside mockups, contrast you inferred from a photo or video rather than saw as unreadable text.

    grouping - meaning, proximity, similarity, common region. Alignment is minor.
    9: you can name the groups at a glance (nav, hero text, hero visual, search, card row) and each holds related things; space is tighter inside than between; same kinds look alike. 3: related items scattered or separated by more space than unrelated ones; unlike things look identical; labels nearer the wrong field; one undifferentiated block.
    Marketing: whole sections are groups; text on one side with an image on the other is two perfect groups. App: nav rail, toolbar, filters, table, detail pane; rows and cells group by proximity and similarity.
    Also: spacing outranks colour and shape as a grouping cue; look-alike items side by side read as one group, so an unrelated item styled like its neighbours (a promo tile styled as a nav item) loses points; each label must sit nearer its own value than any other.
    Not a defect: slight misalignment when proximity and meaning are fine; no cards, borders or panels (space groups); full-bleed layouts; uneven column edges. Name alignment only when it is the sole failed cue and visibly off. This is the most common false deduction on great pages.

    balance - distribution of visual weight.
    9: heavy elements (photos, big type, saturated blocks) are offset by quiet areas; the eye can rest; asymmetric layouts feel settled. 3: one side or corner carries all content and colour while the rest is empty without purpose, or a dense wall at one edge with clutter at the other and no rest.
    Marketing: asymmetry is intended (text left, visual right); penalise only a lopsided hero with no counterweight. App: stable, predictable structure; penalise a region that starves the others.
    False positives, never penalise: white space and breathing room (never a defect by itself); empty space beside a headline before a big visual; a left-text hero; a neutral header balancing busy photography; mirror symmetry; empty space below short content.

    order - hierarchy: what you see first, second, third.
    9: the squint test passes: one dominant element, then supporting, then chrome; the primary action stands out by contrast; a sequence is visible. 3: several elements shout equally, the primary action is buried or looks like the rest, type scale is flat, decoration outweighs content.
    Marketing: one dominant headline, one visible primary action, then support. App: scan order of the working task; table rows are legitimately equal peers.
    Also: pop-out is difference from neighbours, not the colour's meaning: penalise a primary action styled like the items around it, or an accent used on so many items that nothing differs; the main action wants two of bigger, more space around it, more contrast; faces, large photos and out-of-place objects pull the eye and must not outrank the action; forms and panels need their own headings and stronger styling for higher levels.
    Not a defect: two related paired buttons (a primary plus a secondary, "Get started" plus "Sign in with Google") that work together when one dominates or both serve one decision; tabs and chips that blend in; equal peers in a grid; a small CTA next to a big product shot that is still findable. Penalise only genuinely competing buttons: two same-weight buttons with different intents.

    familiar - patterns people already know.
    9: anyone can say what everything is and what clicking does; unusual styling keeps standard signifiers (logo, nav, search where expected, buttons that look like buttons). 3: controls unrecognisable or icon-only with no cue, navigation hidden or novel for no reason, the same kind of item styled three ways.
    Marketing: a distinctive authored look is a plus if the conventions that carry the action are intact. App: standard patterns are the goal (sidebar, tabs, sortable tables); a costume that hides standard controls loses points.
    Also: break convention in one dimension only; a page unusual in structure, controls and labels together loses points; different actions with near-identical icons or labels get confused.
    Not a defect: a famous brand's own visual language on a conventional structure.

    ease - effort to take the screen in.
    9: a glance gives one idea; few or well-chunked choices (about four chunks); brief text or comfortable line lengths; detail waits behind navigation. 3: walls of text or dozens of ungrouped options, very long lines (80+ characters), visible clutter, no entry point.
    Marketing: the first screen should be light, with progressive disclosure below. App: density is expected; judge scannability and consistent row structure.
    Also: ease comes from sorting and organising, not deleting: reward a dense page with clear sections, penalise a bare page or link wall that leaves all organising to the viewer; scanning wants short pieces with key words first, so repeated words in every row or link cost points; a comparison with many attributes and the decisive one unmarked is hard.
    Not a defect: "small text"; words inside demos, screenshots, code samples or mockups; a busy-by-nature page (marketplace, news) that already groups and spaces well; many evenly spaced cards. On busy pages the real fix is progressive disclosure, never "remove borders" or a spacing change that is already true.

    clarity - what this is and what to do next.
    9: you can state the screen's one job in a sentence; copy is concrete; the action label names the outcome. 3: a vague headline AND no explanation anywhere, generic labels ("Submit", "Click here") on the only action, unrelated jobs fighting, you cannot tell what is offered.
    Marketing: within five seconds, what is offered, for whom, what to do next. App: which region does what and what the next action is.
    Also: a headline that states the point as a sentence beats a topic label; caveats must not sit only in small text under a confident headline; button labels name the outcome ("Cancel reservation", not "OK"); abstract imagery that must be studied gets skipped.
    Not a defect: open-ended or poetic headlines from famous mainstream brands (Apple, Airbnb, Uber, Nike) whose imagery and product on screen carry the meaning; at most a light note that the line alone does not say what is sold, never a large deduction; paired related buttons. Name the exact element in any note.

    trust - credibility and safety.
    9: the real product or work is shown (demonstration counts as proof) and/or recognisable proof is on screen (named customer logos, ratings, numbers, press); polished and consistent; specific claims. 3: stock-only imagery with unsupported superlatives, broken or placeholder elements, inconsistent finish, shouty offers, sensitive data requested with no sign of legitimacy, looks abandoned.
    Marketing: logos, numbers, testimonials and product demonstration. App: consistency, honest states, real labels and data; social proof is rarely expected.
    Also: visible craftsmanship stands in for reliability: inconsistent button styles and placeholder or low-quality assets cost trust (never convert this into an alignment deduction); a long-established look carries stored trust.
    Not a defect: a famous brand with no testimonials (the brand is the proof); an app screen with no social proof; cookie banners or chat bubbles; missing footer or legal links. Credit visible logos and product demos explicitly.

    ANCHORS (described in words)
    About 9 on every meter, the Apple home page: one huge plainly worded headline with a product image, a quiet nav, product tiles that are each an obvious group of identical structure (headline, one line, two links), generous space that is breathing room, one dominant focal point per tile, instantly familiar and polished. Open-ended copy, whitespace and two paired text links per tile are not deductions.
    About 5, a mid-quality business homepage: a recognisable hero, nav and button, but a stock photo, two or three equal-weight buttons, a flat type scale, same-grey text blocks, an unreadable logo strip and vague hero copy ("Solutions for modern teams"). Groups are readable but nothing leads; deductions name the equal buttons and the vague line.
    About 3-4, a plain link directory or classifieds page (Craigslist) or a dated institutional site: long undifferentiated text-link columns, one type size and weight, no dominant element, a hero-less top, nothing leading the eye; the 9-start applies to polished pages only, so here order, balance and ease are 2-4 and each reason names the flat link column or the missing focal point.
    About 4, a dated government services page (DMV, USPS): a crowded top bar, dense lists of text links, several type styles and colours, default-looking boxes and buttons, a task menu with no single dominant action, cramped gaps between unrelated sections. Functional and honest, but not crafted: order, ease, grouping and familiar sit at 3-5, trust 4-5, and each reason names the link wall or the missing dominant action.
    About 3, a deliberately hostile or confusing UI (Userinyerface): controls that look wrong or hide their purpose, misleading labels, distracting pop-ups and fake buttons, competing styles. Familiar, order, ease and clarity sit at 2-3.
    About 2, Ling's Cars or the 1996 Space Jam site: dozens of competing colours and fonts, blinking or tiled backgrounds, nothing ranked, text unreadable on busy backgrounds, related and unrelated items interleaved, no resting space, unknown controls, untrustworthy. Expect 1-3 on most meters.

    Use the facts supplied with the image as reliable evidence. Reply with ONE JSON object only: {"reasons":{"contrast":"s","grouping":"s","balance":"s","order":"s","familiar":"s","ease":"s","clarity":"s","trust":"s"},"contrast":n,"grouping":n,"balance":n,"order":n,"familiar":n,"ease":n,"clarity":n,"trust":n}
    """

    /// The per-image part: the facts the code measured.
    static func userText(facts: String) -> String { "Facts measured by code (reliable evidence):\n\(facts)" }

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
        var rs: [String: String] = [:]
        for m in meters { rs[m] = (v["reasons"][m].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        return Rating(scores: s, reason: (v["reason"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines), reasons: rs)
    }

    /// Mean per meter over the valid votes, kept continuous so one vote moving one step moves a meter by a fraction of a
    /// point, not 13; needs at least 2 votes.
    static func mean(_ rs: [Rating]) -> Rating? {
        guard rs.count >= 2 else { return nil }
        var out: [String: Double] = [:]
        for m in meters {
            out[m] = rs.map { $0.scores[m]! }.reduce(0, +) / Double(rs.count)
        }
        return Rating(scores: out, reason: rs.first { !$0.reason.isEmpty }?.reason ?? "", reasons: pickReasons(rs, mean: out))
    }

    /// Per meter, the reason of the vote closest to the mean rating (ties: the alphabetically first reason), so the pick does not depend on arrival order.
    static func pickReasons(_ rs: [Rating], mean: [String: Double]) -> [String: String] {
        var out: [String: String] = [:]
        for m in meters {
            let c = rs.filter { !($0.reasons[m] ?? "").isEmpty }.sorted { (abs($0.scores[m]! - mean[m]!), $0.reasons[m]!) < (abs($1.scores[m]! - mean[m]!), $1.reasons[m]!) }
            if let f = c.first { out[m] = f.reasons[m]! }
        }
        return out
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

    /// Five parallel votes (the model rejects a temperature setting), mean per meter. The means for one image (keyed by image hash) are stored, so scoring it again gives the same answer.
    /// nil when fewer than 2 votes are valid: the caller keeps the checklist.
    static func rate(keys: [String], image: [String: Any], facts: String, hash: String?, cacheDir: URL) async -> Rating? {
        let file = hash.map { cacheDir.appendingPathComponent("designer-\($0)-\(version).json") }
        if let f = file, let d = try? Data(contentsOf: f), let r = try? JSONDecoder().decode(Rating.self, from: d) { return r }
        let content: [[String: Any]] = [image, ["type": "text", "text": userText(facts: facts)]]
        let rs: [Rating] = await withTaskGroup(of: Rating?.self) { g in
            for _ in 0..<votes { g.addTask { (try? await Claude.call(keys: keys, system: systemPrompt, content: content, maxTokens: 800, model: Claude.sonnet, cacheSystem: true)).flatMap { parse($0.json) } } }
            var v: [Rating] = []
            for await x in g { if let x { v.append(x) } }
            return v
        }
        if rs.count < votes { FileHandle.standardError.write(Data("designer: only \(rs.count) of \(votes) votes valid\(rs.count < 2 ? "; scoring from the checklist alone" : "; rating not cached")\n".utf8)) }
        guard let r = mean(rs) else { return nil }
        if rs.count == votes, let f = file {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            if let d = try? JSONEncoder().encode(r) { try? d.write(to: f) }
        }
        return r
    }
}
