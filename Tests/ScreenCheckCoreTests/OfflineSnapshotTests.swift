import XCTest
@testable import ScreenCheckCore

/// Scores stored inputs with the pure scoring and text-guard functions and compares the output to a recorded snapshot.
/// No model is called. Set SCREENCHECK_CALIBRATION_DIR to a folder of stored result JSON files to snapshot those too;
/// SCREENCHECK_SNAPSHOT_OUT then names the file the snapshot is written to.
final class OfflineSnapshotTests: XCTestCase {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e
    }()

    private func json<T: Encodable>(_ v: T) -> String {
        String(data: try! Self.encoder.encode(v), encoding: .utf8)!
    }

    private func jsonObject(_ d: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]), encoding: .utf8)!
    }

    private func vision(_ s: String) -> JSONValue { try! JSONValue.firstObject(in: s) }

    private func box(_ t: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ role: String, px: Double? = nil, bold: Bool = false, onImage: Bool = false) -> TextBox {
        TextBox(text: t, x: x, y: y, w: w, h: h, fontPx: px ?? h * 0.8, bold: bold, role: role, onImage: onImage)
    }

    private func syntheticPixels(width: Int, height: Int) -> Pixels {
        var d = [UInt8](repeating: 255, count: width * height * 4)
        func fill(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
            for y in y0..<min(y1, height) { for x in x0..<min(x1, width) {
                let i = (y * width + x) * 4; d[i] = r; d[i + 1] = g; d[i + 2] = b
            } }
        }
        fill(0, 0, width, 70, 20, 30, 60)
        fill(420, 120, 780, 420, 230, 120, 40)
        fill(60, 330, 220, 380, 20, 90, 220)
        for y in stride(from: 120, to: 300, by: 7) { for x in stride(from: 60, to: 380, by: 3) {
            let i = (y * width + x) * 4; d[i] = 40; d[i + 1] = 40; d[i + 2] = 40
        } }
        return Pixels(width: width, height: height, data: d)
    }

    private func syntheticSnapshot() -> [String] {
        var out: [String] = []
        let boxes = [
            box("Acme", 20, 20, 60, 28, "logo"), box("Pricing", 300, 24, 70, 20, "nav"), box("Docs", 390, 24, 50, 20, "nav"), box("Sign in", 700, 24, 60, 20, "nav"),
            box("Plan every project in one place", 60, 120, 320, 44, "heading", px: 40, bold: true),
            box("Acme keeps tasks, files and people together so your team ships on time without extra meetings.", 60, 190, 320, 20, "body", px: 16),
            box("Every plan includes unlimited projects and a free trial for fourteen days.", 60, 220, 320, 20, "body", px: 16),
            box("Start free trial", 70, 340, 140, 26, "button", px: 16, bold: true),
            box("Trusted by 10,000 teams", 60, 440, 220, 18, "label", px: 13),
            box("tiny legal text", 60, 570, 120, 10, "legal", px: 9),
        ]
        let v = vision("""
        {"page_type":"landing page","screen_kind":"marketing","tone":"neutral","blocks":"few","fonts":"two","main_text_alignment":"left","nav_position":"top","logo_position":"top_left",
         "panels":"none","columns":"two","first_fixation":"headline","emphasis":"one","primary_buttons":"one","corner_style":"round","heaviest_weight":"heading",
         "roles":{"primary":[7],"logo":[0],"heading":[4],"nav":[1,2,3]},"images_ok":true,"has_overlay":false,"real_imagery":true,"grouping_clear":true,
         "primary_y_pt":353.0,"primary_y_pct":58.0,"page_name":"Acme home"}
        """)
        let px = syntheticPixels(width: 800, height: 600)
        let facts0 = Scoring.facts(from: v, textBoxes: boxes)
        var facts = facts0
        facts.imageHeight = 600
        facts.allBoxes = boxes
        facts.primaryCount = 1
        facts.primaryText = "Start free trial"
        let code = Scoring.codeAnswers(facts, pixels: px, appScreen: false)
        out.append("code.answers=" + code.answers.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))
        out.append("code.contrast=" + json(code.contrast))
        out.append("code.note=\(code.note ?? "nil")")
        let stats = PixelStats.compute(px)
        out.append("stats=" + json(stats))
        let va = Scoring.visionAnswers(facts, stats: stats)
        out.append("vision.answers=" + va.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))
        for (k, m) in Layout.meters(pixels: px, boxes: boxes, imageWidth: 800, meaning: true).sorted(by: { $0.key < $1.key }) { out.append("layout.\(k)=" + json(m)) }
        for (k, p) in Layout.problems(pixels: px, boxes: boxes, imageWidth: 800, meaning: true).sorted(by: { $0.key < $1.key }) { out.append("layout.problems.\(k)=\(p)") }
        out.append("grouping=" + json(Layout.grouping(boxes, pixels: px, imageWidth: 800)))
        out.append("balance=" + json(Layout.balance(Layout.weightGrid(px))))
        out.append("detectors=" + json(Detectors.measure(pixels: px, boxes: boxes, scale: 2)))
        let paras = Readability.countedParagraphs(boxes, imageHeight: 600)
        out.append("readability.paras=\(paras)")
        if let g = Readability.grade(forCopy: paras) { out.append("readability.grade=\(g)") }
        out.append("readability.hardest=" + jsonObject(Readability.hardest(paras: paras)))
        for kind in ScreenKind.allCases {
            let na = Applicability.notApplicable(kind: kind, pageType: "landing page", facts: facts)
            out.append("na.\(kind)=\(na.sorted())")
        }
        out.append("kind.small=\(ScreenKind.resolve(vision: v, width: 500, height: 400))")
        return out
    }

    private func contextSnapshot() -> [String] {
        var out: [String] = []
        let models = ["ecommerce", "saas", "other"], locations = ["homepage", "landing", "elsewhere", "inside", "not_a_page", "unknown"]
        for m in models { for l in locations { for c in ["low", "medium", "high"] {
            let ctx = PageContext(businessModel: m, location: l, purpose: "x", label: "L", confidence: c)
            let key = "ctx.\(m).\(l).\(c)"
            out.append("\(key).na=\(Applicability.contextNotApplicable(ctx).sorted())")
            out.append("\(key).weights=\(Applicability.contextWeights(ctx).sorted { $0.key < $1.key })")
            out.append("\(key).wording=\(Applicability.contextWording(ctx).sorted { $0.key < $1.key })")
            out.append("\(key).note=\(Applicability.contextNote(ctx, changed: ["C6"]) ?? "nil")")
            for kind in ScreenKind.allCases { out.append("\(key).adjust.\(kind)=\(ctx.adjust(kind, width: 1200, height: 800))") }
            out.append("\(key).c6=\(Applicability.c6Holds(vote: false, context: ctx, demonstrates: true))")
        } } }
        return out
    }

    private func textGuardSnapshot() -> [String] {
        var out: [String] = []
        let whys = [
            "Contrast score is 62 because the faint grey text is hard to read. The designer says the hierarchy is the lowest score.",
            "Balance is at 70 because most weight sits on the left. Nothing needs to change.",
            "The grouping is unclear; add a card around the pricing, and the text is only 11px.",
            "the eye lands on the banner first. There is an ad-like pop-up near the button.",
            "Buttons have 3 or fewer options and the nav menu has too many links.",
        ]
        let fixes = [
            "Raise the contrast of the grey caption to at least 4.5:1.", "Move the sign in button up above the fields.", "Nothing to fix.",
            "Rewrite the headline to \"Plan every project\".", "Add placeholders as labels.", "Lower the contrast of the nav.", "Put all items inside a single panel.",
            "Replace the hero screenshot with a clearer image.", "Add a line such as Explore Acme features.",
        ]
        for k in Meters.order {
            for (i, w) in whys.enumerated() {
                out.append("why.\(k).\(i)=\(Pipeline.cleanWhy(w, meter: k))")
                out.append("why.\(k).\(i).free=\(Pipeline.cleanWhy(w, meter: k, topicFilter: false))")
                out.append("grounded.\(k).\(i)=\(Pipeline.groundedWhy(w, meter: k, overlayPresent: false))|\(Pipeline.groundedWhy(w, meter: k, overlayPresent: true))")
            }
            let checks = Rubric.checks(for: k)
            for score in [40, 84, 85, 99, 100] { for problem in [true, false] {
                for (i, f) in fixes.enumerated() {
                    out.append("fix.\(k).\(score).\(problem).\(i)=\(Pipeline.finalFix(f, score: score, problem: problem, failed: checks, meter: k))|\(Pipeline.finalFix(f, score: score, problem: problem, failed: [], meter: k, hasDeduction: false))")
                }
                out.append("fix.\(k).\(score).\(problem).empty=\(Pipeline.finalFix("", score: score, problem: problem, failed: checks, meter: k))")
            } }
            out.append("rubricFix.\(k)=\(Pipeline.rubricFix(failed: checks, score: 50, meter: k))")
            out.append("fallbackWhy.\(k)=\(Pipeline.fallbackWhy(score: 50, failed: checks, designer: 60, designerReason: "Give the caption more weight.", meter: k))|\(Pipeline.fallbackWhy(score: 50, failed: checks, designer: nil, designerReason: "", meter: k))")
            out.append("fallbackFix.\(k)=\(Pipeline.fallbackFix(meter: k, failed: checks))")
        }
        for f in fixes { out.append("banned.\(f)=\(Pipeline.bannedFix(f))|\(Pipeline.bannedFix(f, page: "Plan every project"))|unsafe=\(Pipeline.unsafeSubmitAdvice(f))|quotes=\(Pipeline.quotesOnPage(f, page: "Plan every project Explore Acme features"))") }
        for g in 1...14 { out.append("gradePoints.\(g)=\(Pipeline.gradePoints(g))") }
        for s in ["", "short", "A sentence that is a lot longer than the limit so it must be cut at a word boundary somewhere", "NoSpacesAtAllInThisVeryLongStringThatKeepsGoingAndGoingAndGoing"] {
            out.append("truncate=\(Pipeline.truncate(s))|\(Pipeline.truncate(s, max: 24))")
        }
        out.append("writerFailed=\(Pipeline.writerFailedText(Rubric.checks))")
        out.append("feelingFacts=" + jsonObject(Pipeline.feelingFacts(stats: PixelStats.compute(syntheticPixels(width: 800, height: 600)), copy: "Buy now, limited offer")))
        let votes = [
            vision(#"{"page_type":"a","tone":"x","roles":{"primary":[1],"logo":[0],"heading":[2]},"blocks":"few"}"#),
            vision(#"{"page_type":"a","tone":"y","roles":{"primary":[1],"logo":[0,2],"heading":[2]},"blocks":"many"}"#),
            vision(#"{"page_type":"b","tone":"y","roles":{"primary":[3],"logo":[0],"heading":[2]},"blocks":"few"}"#),
        ]
        out.append("majority=" + json(Pipeline.majority(votes)))
        out.append("primaryID=\(String(describing: Pipeline.primaryID(votes[0], count: 5)))|\(String(describing: Pipeline.primaryID(votes[0], count: 1)))")
        out.append("complete=\(Pipeline.isComplete(votes[0]))")
        return out
    }

    private func storedSnapshot(_ r: RunResult, name: String) -> [String] {
        var out: [String] = []
        let p = "stored.\(name)"
        let written: JSONValue? = nil
        let texts = Pipeline.texts(for: r, written: written)
        for (k, t) in texts.sorted(by: { $0.key < $1.key }) { out.append("\(p).text.\(k)=\(t.why)|\(t.fix)") }
        let overlay = Pipeline.texts(for: r, written: written, pageText: "Plan every project", overlayPresent: true)
        for (k, t) in overlay.sorted(by: { $0.key < $1.key }) { out.append("\(p).overlaytext.\(k)=\(t.why)|\(t.fix)") }
        for k in Rubric.meterKeys {
            guard let m = r.meters[k] else { continue }
            var answers: [String: (yes: Bool, p: Double?, kind: String)] = [:]
            for c in m.checks { answers[c.id] = (c.yes, c.p, c.kind) }
            let present = Set(m.checks.map { $0.id })
            let na = Set(Rubric.checks(for: k).map { $0.id }.filter { !present.contains($0) })
            let re = Scoring.weightedScore(k, answers: answers, notApplicable: na)
            out.append("\(p).rescore.\(k)=\(re.score)|\(re.confidencePct)|\(re.lowConfidence)|\(re.applicable.map(String.init(describing:)) ?? "nil")|\(re.checks.map { "\($0.id)\($0.yes ? 1 : 0)\($0.weight)" })")
        }
        let ms = r.meters.filter { $0.value.applicable != false }.mapValues { $0.score }
        out.append("\(p).overall=\(Scoring.overall(meters: ms, reading: r.readingGrade.map { Int((Pipeline.gradePoints($0) * 10).rounded()) }))|stored=\(r.overallScore)")
        var scores: [String: Double] = [:]
        for k in Designer.meters { if let d = r.meters[k]?.designer { scores[k] = Double(d) / 100 * 8 + 1 } }
        var cleared = r.meters
        for k in cleared.keys { cleared[k]?.designer = nil }
        let blended = Designer.blend(cleared, rating: Designer.Rating(scores: scores, reason: "r"))
        for (k, m) in blended.sorted(by: { $0.key < $1.key }) { out.append("\(p).blend.\(k)=\(m.score)|\(m.designer.map(String.init) ?? "nil")") }
        if let ctx = r.context {
            let kind = ctx.adjust(ScreenKind.resolve(vision: r.vision, width: r.imageWidth, height: r.imageHeight), width: r.imageWidth, height: r.imageHeight)
            var facts = Scoring.facts(from: r.vision, textBoxes: [])
            facts.primaryCount = 1
            out.append("\(p).kind=\(kind)")
            out.append("\(p).na=\(Applicability.notApplicable(kind: kind, pageType: r.vision["page_type"].string ?? "", facts: facts, context: ctx).sorted())")
            out.append("\(p).contextNote=\(Applicability.contextNote(ctx, changed: ["C6"]) ?? "nil")")
        }
        var f = Scoring.facts(from: r.vision, textBoxes: [])
        f.primaryCount = 1
        let va = Scoring.visionAnswers(f, stats: r.pixelStats)
        out.append("\(p).visionAnswers=" + va.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))
        for (k, t) in r.text.sorted(by: { $0.key < $1.key }) {
            out.append("\(p).cleanWhy.\(k)=\(Pipeline.cleanWhy(t.why, meter: k))")
            let failed = Rubric.checks(for: k).filter { c in r.meters[k]?.checks.first { $0.id == c.id }?.yes == false }
            out.append("\(p).finalFix.\(k)=\(Pipeline.finalFix(t.fix, score: r.meters[k]?.score ?? 0, problem: true, failed: failed, meter: k))")
            out.append("\(p).ari.\(k)=\(Readability.ariGrade(t.why))")
        }
        out.append("\(p).truncated=\(Pipeline.isTruncated(r))|complete=\(r.textComplete)")
        return out
    }

    private func feelingSnapshot() -> [String] {
        var out: [String] = []
        for k in Rubric.feelingKeys {
            let cs = Rubric.checks(for: k)
            let all = cs.map { CheckResult(id: $0.id, yes: true, p: nil, weight: $0.w, kind: $0.kind) }
            let half = cs.enumerated().map { CheckResult(id: $1.id, yes: $0 % 2 == 0, p: 0.6, weight: $1.w, kind: $1.kind) }
            out.append("feeling.\(k)=\(Feeling.score(all, checks: cs))|\(Feeling.score(half, checks: cs))")
        }
        for k in Rubric.meterKeys + Rubric.layoutKeys {
            var answers: [String: (yes: Bool, p: Double?, kind: String)] = [:]
            for (i, c) in Rubric.checks(for: k).enumerated() { answers[c.id] = (i % 3 != 0, i % 2 == 0 ? 0.7 : nil, c.kind) }
            let r = Scoring.weightedScore(k, answers: answers, cap: 90, notApplicable: ["C4", "T4"], weights: ["T14": 3])
            out.append("weighted.\(k)=\(r.score)|\(r.confidencePct)|\(r.applicable.map(String.init(describing:)) ?? "nil")")
        }
        return out
    }

    private func decodeStored(_ url: URL) -> RunResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(RunResult.self, from: data)
    }

    func testSyntheticOutputsMatchRecordedSnapshot() throws {
        let lines = syntheticSnapshot() + contextSnapshot() + textGuardSnapshot() + feelingSnapshot()
        let got = lines.joined(separator: "\n") + "\n"
        let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/offline-synthetic.snapshot")
        if ProcessInfo.processInfo.environment["SCREENCHECK_RECORD_SNAPSHOT"] != nil {
            try got.write(to: golden, atomically: true, encoding: .utf8)
            return
        }
        let expected = try String(contentsOf: golden, encoding: .utf8)
        if got != expected {
            let a = got.split(separator: "\n", omittingEmptySubsequences: false), b = expected.split(separator: "\n", omittingEmptySubsequences: false)
            let firstDiff = zip(a, b).enumerated().first { $1.0 != $1.1 }
            XCTFail("snapshot differs at line \(firstDiff.map { $0.offset + 1 } ?? min(a.count, b.count)): got \(firstDiff?.element.0 ?? "") expected \(firstDiff?.element.1 ?? "")")
        }
    }

    func testStoredCalibrationResultsMatchSnapshotWhenAvailable() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREENCHECK_CALIBRATION_DIR"], let out = env["SCREENCHECK_SNAPSHOT_OUT"] else { throw XCTSkip("set SCREENCHECK_CALIBRATION_DIR and SCREENCHECK_SNAPSHOT_OUT") }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".json") }.sorted()
        var lines: [String] = []
        for f in files {
            guard let r = decodeStored(URL(fileURLWithPath: dir).appendingPathComponent(f)) else { lines.append("undecodable \(f)"); continue }
            lines += storedSnapshot(r, name: f)
        }
        XCTAssertFalse(files.isEmpty)
        try (lines.joined(separator: "\n") + "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }
}
