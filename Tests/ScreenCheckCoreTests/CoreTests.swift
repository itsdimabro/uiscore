import XCTest
import ImageIO
import UniformTypeIdentifiers
import AppKit
@testable import ScreenCheckCore

final class CoreTests: XCTestCase {
    // Reference values from hone's ariGrade (bun run readability.ts) on the same strings.
    func testARIMatchesHone() {
        XCTAssertEqual(Readability.ariGrade("Make the page simple.\nWe help teams ship better software every day.\nStart your free trial today and see how clear the layout can be."), 2)
        XCTAssertEqual(Readability.ariGrade("The interface component uses a consistent palette and responsive layout for accessibility.\nA grid is a grid."), 1)
        XCTAssertEqual(Readability.ariGrade("Financial infrastructure to grow your revenue. Accept payments, handle business banking, and implement custom revenue models from your first transaction to your billionth.\nNo setup fees."), 11)
    }
    func testWCAGRatio() {
        XCTAssertEqual(Contrast.ratio((0, 0, 0), (255, 255, 255)), 21, accuracy: 0.001)
        XCTAssertEqual(Contrast.ratio((119, 119, 119), (255, 255, 255)), 4.478, accuracy: 0.01)
        XCTAssertEqual(Contrast.need(fontPx: 24, bold: false), 3.0)
        XCTAssertEqual(Contrast.need(fontPx: 19, bold: true), 3.0)
        XCTAssertEqual(Contrast.need(fontPx: 14, bold: false), 4.5)
    }
    func testRubricWeightsSumTo100() {
        for k in Rubric.meterKeys + Rubric.feelingKeys {
            XCTAssertEqual(Rubric.checks(for: k).reduce(0) { $0 + $1.w }, 100, k)
        }
    }
    func testWeightedScore() {
        let cs = Rubric.checks(for: "order")
        var ans: [String: (yes: Bool, p: Double?, kind: String)] = [:]
        for (i, c) in cs.enumerated() { ans[c.id] = (i < 2, 0.9, "jev") }
        XCTAssertEqual(Scoring.weightedScore("order", answers: ans).score, cs[0].w + cs[1].w)
    }
    func testFeelingScoreAndSummary() {
        let cs = Rubric.checks(for: "vv")
        let rs = cs.map { CheckResult(id: $0.id, yes: $0.id == "vv1" || $0.id == "vv7", p: 0.9, weight: $0.w, kind: "jev") }
        XCTAssertEqual(Feeling.score(rs, checks: cs), 50 + 14 - 14)
    }
    func testNewestFileFinder() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("sc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let a = d.appendingPathComponent("a.png"), b = d.appendingPathComponent("b.jpg"), c = d.appendingPathComponent("c.txt")
        for u in [a, b, c] { try Data([1]).write(to: u) }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: a.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -50)], ofItemAtPath: b.path)
        XCTAssertEqual(ScreenshotFinder.newest(in: d)?.lastPathComponent, "b.jpg")
        XCTAssertNil(ScreenshotFinder.newest(in: d, notOlderThan: 10))
    }
    func solidPixels(w: Int, h: Int, bg: UInt8, fg: UInt8, textRect: (Int, Int, Int, Int)) -> Pixels {
        var d = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let inText = x >= textRect.0 && x < textRect.2 && y >= textRect.1 && y < textRect.3 && (x + y) % 3 == 0
            let v = inText ? fg : bg
            let i = (y * w + x) * 4; d[i] = v; d[i + 1] = v; d[i + 2] = v
        } }
        return Pixels(width: w, height: h, data: d)
    }
    func testClusterRatioBlackOnWhite() {
        let px = solidPixels(w: 100, h: 40, bg: 255, fg: 0, textRect: (10, 10, 90, 30))
        let box = TextBox(text: "x", x: 5, y: 5, w: 90, h: 30, fontPx: 14, bold: false, role: "body", onImage: false)
        let s = Contrast.clusterSample(px, box: box)
        XCTAssertNotNil(s)
        XCTAssertEqual(s!.ratio, 21, accuracy: 0.01)
    }
    func testClusterIgnoresStrayPixelAndUnmeasuredNotFailed() {
        var px = solidPixels(w: 100, h: 40, bg: 255, fg: 119, textRect: (10, 10, 90, 30))
        let i = (8 * 100 + 8) * 4; px = Pixels(width: 100, height: 40, data: { var d = px.data; d[i] = 0; d[i+1] = 0; d[i+2] = 0; return d }())
        let box = TextBox(text: "x", x: 5, y: 5, w: 90, h: 30, fontPx: 14, bold: false, role: "body", onImage: false)
        XCTAssertEqual(Contrast.clusterSample(px, box: box)!.ratio, 4.48, accuracy: 0.05)
        let photo = TextBox(text: "p", x: 5, y: 5, w: 90, h: 30, fontPx: 14, bold: false, role: "body", onImage: true)
        let rep = Contrast.report(px, boxes: [box, photo], expected: 2)
        XCTAssertNil(rep.boxes[1].ratio)
        XCTAssertEqual(rep.measured, 1)
    }
    func testNothingToFixRule() {
        let c = Rubric.checks(for: "ease")
        XCTAssertEqual(Pipeline.finalFix("", score: 90, problem: false, failed: c, meter: "ease"), "Nothing to fix")
        XCTAssertNotEqual(Pipeline.finalFix("Nothing to fix", score: 90, problem: true, failed: c, meter: "ease"), "Nothing to fix")
        XCTAssertNotEqual(Pipeline.finalFix("Nothing to fix", score: 70, problem: false, failed: c, meter: "ease"), "Nothing to fix")
        XCTAssertEqual(Pipeline.finalFix("Cut the text.", score: 60, problem: true, failed: c, meter: "ease"), "Cut the text.")
    }
    func testCacheRoundTripAndHash() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("sc-cache-\(UUID().uuidString)")
        let img = d.appendingPathComponent("a.png")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: img)
        let h = Pipeline.imageHash(img)!
        XCTAssertEqual(h, Pipeline.imageHash(img))
        let r = RunResult(id: "x", createdAt: Date(), pageName: "P", imageWidth: 1, imageHeight: 1, meters: ["order": MeterResult(score: 77, lowConfidence: false, confidencePct: 90, checks: [], note: nil)], feeling: [:], feelingLow: [:], feelingConfidencePct: [:], readingGrade: nil, readingWords: 0, text: [:], timings: Timings(), contrastDetail: nil, vision: .null, pixelStats: nil)
        Pipeline.store(r, hash: h, dir: d)
        XCTAssertEqual(Pipeline.cached(hash: h, dir: d)?.meters["order"]?.score, 77)
    }
    func testCachedRunMakesNoCalls() async throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("sc-cache2-\(UUID().uuidString)")
        let img = d.appendingPathComponent("a.png")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Data([9, 9]).write(to: img)
        let r = RunResult(id: "y", createdAt: Date(), pageName: "P", imageWidth: 1, imageHeight: 1, meters: ["order": MeterResult(score: 61, lowConfidence: false, confidencePct: 90, checks: [], note: nil)], feeling: [:], feelingLow: [:], feelingConfidencePct: [:], readingGrade: nil, readingWords: 0, text: [:], timings: Timings(), contrastDetail: nil, vision: .null, pixelStats: nil)
        Pipeline.store(r, hash: Pipeline.imageHash(img)!, dir: d)
        // empty keys: any network path would throw noKey, so success proves the cache answered
        let out = try await Pipeline(keys: Keys(anthropic: "", jev: "")).run(imageURL: img, cacheDir: d)
        XCTAssertEqual(out.meters["order"]?.score, 61)
        XCTAssertEqual(out.id, "y")
    }
    func testOverall() {
        let m = ["balance": 80, "order": 70, "contrast": 90, "familiar": 60, "ease": 50, "clarity": 100, "trust": 40]
        XCTAssertEqual(Scoring.overall(meters: m, reading: nil), 70)
        XCTAssertEqual(Scoring.overall(meters: m, reading: 100), 74)
        XCTAssertEqual(Scoring.overall(meters: m, reading: 0), 61)
    }
    func testTruncate() {
        XCTAssertLessThanOrEqual(Pipeline.truncate(String(repeating: "word ", count: 60)).count, 110)
        XCTAssertEqual(Pipeline.truncate("Short."), "Short.")
    }
    func testNotApplicableCheckIsRenormalised() {
        let cs = Rubric.checks(for: "trust")
        var ans: [String: (yes: Bool, p: Double?, kind: String)] = [:]
        for c in cs { ans[c.id] = (true, nil, "code") }
        ans["T4"] = (false, nil, "code")
        XCTAssertEqual(Scoring.weightedScore("trust", answers: ans, notApplicable: ["T4"]).score, 100)
        XCTAssertEqual(Scoring.weightedScore("trust", answers: ans).score, 100 - Rubric.checks(for: "trust").first { $0.id == "T4" }!.w)
    }
    func testWeakSecondColorInBoxFailsContrast() {
        // black text plus red text on white: the black/white pair alone would read 21:1
        let w = 120, h = 40
        var d = [UInt8](repeating: 255, count: w * h * 4)
        for y in 10..<30 { for x in 10..<110 where (x + y) % 3 == 0 {
            let i = (y * w + x) * 4
            let red = x > 60
            d[i] = red ? 255 : 0; d[i + 1] = red ? 51 : 0; d[i + 2] = 0
        } }
        let box = TextBox(text: "x 9.999,-", x: 5, y: 5, w: 110, h: 30, fontPx: 14, bold: false, role: "body", onImage: false)
        let s = Contrast.clusterSample(Pixels(width: w, height: h, data: d), box: box)
        XCTAssertNotNil(s)
        XCTAssertLessThan(s!.ratio, 4.5)
    }
    func testProperNounCountsAsConcreteClaim() {
        let b = TextBox(text: "With GitHub, developers come together", x: 0, y: 0, w: 1, h: 1, fontPx: 16, bold: false, role: "body", onImage: false)
        XCTAssertTrue(Scoring.hasProperNoun([b]))
    }
    func textFixture() -> CGImage {
        let w = 900, h = 300
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let lines: [(String, CGFloat, CGFloat)] = [("Ship better software faster", 48, 220), ("Plan, build and review work with your whole team.", 22, 150), ("Start free trial", 18, 80)]
        for (t, size, y) in lines {
            (t as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }
    func testOCRBoxesIdenticalAcrossRuns() {
        let img = textFixture()
        let runs = (0..<3).map { _ in OCR.boxes(in: img) }
        XCTAssertGreaterThanOrEqual(runs[0].count, 3)
        XCTAssertEqual(runs[0], runs[1])
        XCTAssertEqual(runs[1], runs[2])
        XCTAssertTrue(runs[0].map { $0.text }.joined(separator: " ").contains("Ship better software"))
        XCTAssertLessThan(runs[0][0].y, runs[0].last!.y)
    }
    func testApplyRoles() {
        let b = (0..<3).map { TextBox(text: "t\($0)", x: 0, y: 0, w: 1, h: 1, fontPx: 10, bold: false, role: "body", onImage: false) }
        let roles = try! JSONValue.firstObject(in: #"{"heading":[0],"button":[2],"nav":[9]}"#)
        XCTAssertEqual(OCR.applyRoles(roles, to: b).map { $0.role }, ["heading", "body", "button"])
    }
    func box(_ t: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> TextBox {
        TextBox(text: t, x: x, y: y, w: w, h: h, fontPx: h * 0.85, bold: false, role: "body", onImage: false)
    }
    func testSplitHeadlineMergesIntoParagraph() {
        let bs = [box("Don't type,", 435, 234, 415, 115), box("just speak.", 451, 338, 358, 102)]
        XCTAssertEqual(Readability.countedParagraphs(bs, imageHeight: 800), ["Don't type, just speak."])
    }
    func testNavAndButtonsAreNotCopy() {
        let bs = [box("Pricing", 100, 30, 60, 16), box("Contact", 200, 30, 60, 16), box("Get started", 100, 500, 120, 20),
                  box("Wispr Flow Notetaker is now available on Windows and Mac today", 300, 20, 500, 18)]
        XCTAssertTrue(Readability.countedParagraphs(bs, imageHeight: 800).isEmpty)
    }
    func testPrimaryIDAcceptsListOrBareID() throws {
        let a = try JSONValue.firstObject(in: #"{"roles":{"primary":[3]}}"#)
        let b = try JSONValue.firstObject(in: #"{"roles":{"primary":"3"}}"#)
        let c = try JSONValue.firstObject(in: #"{"roles":{"primary":[]}}"#)
        XCTAssertEqual(Pipeline.primaryID(a, count: 5), 3)
        XCTAssertEqual(Pipeline.primaryID(b, count: 5), 3)
        XCTAssertNil(Pipeline.primaryID(c, count: 5))
    }
    func testMajorityVoteIgnoresOneOddReply() throws {
        let r = [#"{"fonts":"one_or_two","roles":{"nav":[1,2]}}"#, #"{"fonts":"three_plus","roles":{"nav":[1]}}"#, #"{"fonts":"one_or_two","roles":{"nav":[1,2]}}"#]
            .map { try! JSONValue.firstObject(in: $0) }
        let m = Pipeline.majority(r)
        XCTAssertEqual(m["fonts"].string, "one_or_two")
        XCTAssertEqual(m["roles"]["nav"].array.compactMap { $0.int }, [1, 2])
    }
    func testWeakSmallIconDoesNotDecideBoxRatio() {
        // dark text on white with a few pale-grey pixels (an icon): the text colour decides, not the icon
        let w = 200, h = 40
        var d = [UInt8](repeating: 255, count: w * h * 4)
        for y in 10..<30 { for x in 10..<190 where (x + y) % 2 == 0 {
            let i = (y * w + x) * 4; let v: UInt8 = x < 18 ? 200 : 20
            d[i] = v; d[i + 1] = v; d[i + 2] = v
        } }
        let b = box("x", 5, 5, 190, 30)
        XCTAssertGreaterThan(Contrast.clusterSample(Pixels(width: w, height: h, data: d), box: b)!.ratio, 10)
    }

    // Panel/track colours from Theme.swift (T.soft, T.card, T.track).
    static let surfaces: [Bool: [(Int, Int, Int)]] = [
        false: [(0xde, 0xde, 0xda), (0xf3, 0xf3, 0xf1), (0xfc, 0xfc, 0xfb)],
        true: [(0x40, 0x3f, 0x3d), (0x28, 0x28, 0x27), (0x1d, 0x1d, 0x1c)],
    ]
    func testScoreColorBoundariesAndNoJump() {
        for dark in [false, true] {
            XCTAssertEqual(ScoreColor.forScore(80, dark: dark), ScoreColor.forScore(100, dark: dark))
            XCTAssertEqual(ScoreColor.forScore(50, dark: dark), ScoreColor.forScore(0, dark: dark))
            var prev = ScoreColor.forScore(0, dark: dark)
            for s in 1...100 {
                let c = ScoreColor.forScore(Double(s), dark: dark)
                let d = max(abs(c.r - prev.r), abs(c.g - prev.g), abs(c.b - prev.b))
                XCTAssertLessThan(d, 0.10, "jump at \(s) dark=\(dark)")
                prev = c
            }
            // Just below 80 leans yellow-green: red falls, green dominates.
            let c = ScoreColor.forScore(79, dark: dark), y = ScoreColor.forScore(65, dark: dark)
            XCTAssertGreaterThan(c.g, c.r); XCTAssertGreaterThan(c.g, c.b)
            XCTAssertGreaterThan(y.r, 0.5 * y.g); XCTAssertGreaterThan(y.g, y.b + 0.2)
            XCTAssertGreaterThan(ScoreColor.forScore(49, dark: dark).r, ScoreColor.forScore(49, dark: dark).g)
        }
    }
    func testScoreColorContrastAtLeast3() {
        for dark in [false, true] {
            for s in stride(from: 0, through: 100, by: 1) {
                let c = ScoreColor.forScore(Double(s), dark: dark).bytes
                for bg in Self.surfaces[dark]! { XCTAssertGreaterThanOrEqual(Contrast.ratio(c, bg), 3.0, "score \(s) dark=\(dark)") }
            }
        }
    }
    func testReadingGradeScaleIsOneToTwelve() {
        XCTAssertEqual(Pipeline.gradePoints(1), 10); XCTAssertEqual(Pipeline.gradePoints(9), 10)
        XCTAssertEqual(Pipeline.gradePoints(10), 10 * 2 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(Pipeline.gradePoints(11), 10 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(Pipeline.gradePoints(12), 0); XCTAssertEqual(Pipeline.gradePoints(16), 0)
        let hard = ["Comprehensive organizational infrastructure necessitates interdepartmental collaboration, standardization, and extraordinarily sophisticated implementation methodologies throughout multinational enterprises, notwithstanding considerable organizational resistance everywhere."]
        let r = Readability.grade(forCopy: hard)!
        XCTAssertEqual(r.grade, 12); XCTAssertTrue(r.capped)
        let easy = Readability.grade(forCopy: ["We help you ship. It is fast. You can try it now. Add a team. See the plan. Pick a day. Go. We do the rest for you and it is fun."])!
        XCTAssertFalse(easy.capped); XCTAssertTrue((1...12).contains(easy.grade))
        var run = RunResult.placeholder
        run.readingGrade = 12; XCTAssertFalse(run.gradeCapped)
        run.readingGradeCapped = true; XCTAssertTrue(run.gradeCapped)
        run.readingGradeCapped = nil; run.readingGrade = 16; XCTAssertTrue(run.gradeCapped)
    }
    func testReadingColorCutoffs() {
        XCTAssertEqual(ReadingColor.greenUpTo, 9); XCTAssertEqual(ReadingColor.redFrom, 12)
        for dark in [false, true] {
            XCTAssertEqual(ReadingColor.forGrade(9, dark: dark), ScoreColor.ramp(1, dark: dark))
            XCTAssertEqual(ReadingColor.forGrade(3, dark: dark), ReadingColor.forGrade(9, dark: dark))
            XCTAssertEqual(ReadingColor.forGrade(12, dark: dark), ScoreColor.ramp(0, dark: dark))
            XCTAssertEqual(ReadingColor.forGrade(16, dark: dark), ReadingColor.forGrade(12, dark: dark))
            XCTAssertNotEqual(ReadingColor.forGrade(10.5, dark: dark), ReadingColor.forGrade(9, dark: dark))
            let mid = ReadingColor.forGrade(10.5, dark: dark)
            XCTAssertGreaterThan(mid.r, 0.5 * mid.g)
            for g in [9.0, 10, 10.5, 11, 12] {
                let c = ReadingColor.forGrade(g, dark: dark).bytes
                for bg in Self.surfaces[dark]! { XCTAssertGreaterThanOrEqual(Contrast.ratio(c, bg), 3.0) }
            }
        }
    }
    /// Writes score-gradient strips (0...100) when SCORE_STRIP_DIR is set, and prints contrast ratios.
    func testScoreStripAndContrastReport() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCORE_STRIP_DIR"] else { return }
        for dark in [false, true] {
            let surf = Self.surfaces[dark]!
            let w = 505, h = 60
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let px = rep.bitmapData!
            for x in 0..<w { for y in 0..<h {
                let score = Double(x) / Double(w - 1) * 100
                let c: RGB
                if y < 40 { c = ScoreColor.forScore(score, dark: dark) }
                else { let b = surf[1]; c = RGB(Double(b.0) / 255, Double(b.1) / 255, Double(b.2) / 255) }
                let o = y * rep.bytesPerRow + x * 3
                px[o] = UInt8((c.r * 255).rounded()); px[o + 1] = UInt8((c.g * 255).rounded()); px[o + 2] = UInt8((c.b * 255).rounded())
            } }
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir + "/score-strip-\(dark ? "dark" : "light").png"))
            var mn = 99.0
            for s in 0...100 { let c = ScoreColor.forScore(Double(s), dark: dark).bytes; for b in surf { mn = min(mn, Contrast.ratio(c, b)) } }
            for s in [0, 50, 65, 79, 100] {
                let c = ScoreColor.forScore(Double(s), dark: dark).bytes
                print("CONTRAST \(dark ? "dark" : "light") score \(s): " + surf.map { String(format: "%.2f", Contrast.ratio(c, $0)) }.joined(separator: " / "))
            }
            print("CONTRAST \(dark ? "dark" : "light") min over 0...100 and track/panel/card: \(String(format: "%.2f", mn))")
        }
    }

    func testLegacyFirstMeterRunStillComplete() {
        var r = RunResult.placeholder
        r.meters = ["first": MeterResult(score: 50, lowConfidence: false, confidencePct: 90, checks: [])]
        for k in Meters.order where !Rubric.layoutKeys.contains(k) { r.text[k] = MeterText(why: "ok", fix: "") }
        XCTAssertTrue(r.textComplete)
    }
}
