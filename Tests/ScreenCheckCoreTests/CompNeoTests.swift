import XCTest
@testable import ScreenCheckCore

/// The dark "Comp Neo UX" sign-in card: a well-made screen that the scorer misread (slice 02).
final class CompNeoTests: XCTestCase {
    func box(_ t: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ role: String, px: Double = 16) -> TextBox {
        TextBox(text: t, x: x, y: y, w: w, h: h, fontPx: px, bold: false, role: role, onImage: false)
    }
    // OCR boxes of the real screenshot (1982x1420): centred title, left-aligned labels, centred button text.
    var boxes: [TextBox] { [box("Comp Neo UX", 806, 445, 316, 52, "heading", px: 26), box("Email", 610, 535, 77, 25, "body"),
                            box("Password", 607, 708, 135, 25, "body"), box("Sign in", 907, 912, 106, 32, "button")] }
    var vision: JSONValue { try! JSONValue.firstObject(in: "{\"screen_kind\":\"app\",\"page_type\":\"form\",\"tone\":\"plain_confident\"}") }

    func testCenteredTitleOverLeftAlignedFieldsStillAlignsWithinGroups() {
        let g = Layout.grouping(boxes, pixels: nil, imageWidth: 1982)
        let checks = Dictionary(uniqueKeysWithValues: Layout.groupingChecks(g).compactMap { c in c.pass.map { (c.id, $0) } })
        XCTAssertEqual(checks["g_align"], true)
    }
    func testMixedAlignmentInsideOneGroupStillFails() {
        let b = [box("A line", 100, 100, 200, 20, "body"), box("Second line", 180, 130, 200, 20, "body"), box("Third", 40, 160, 90, 20, "body"), box("Far", 900, 700, 100, 20, "body")]
        let g = Layout.grouping(b, pixels: nil, imageWidth: 1000)
        XCTAssertEqual(Layout.groupingChecks(g).first { $0.id == "g_align" }?.pass, false)
    }

    func feelingScores() -> (vv: Int, cv: Int) {
        var st = PixelStats(); st.bgLum = 0.0056; st.emptyPct = 0.93
        let f = Scoring.facts(from: vision, textBoxes: boxes)
        let a = Scoring.visionAnswers(f, stats: st)
        func s(_ k: String) -> Int {
            let cs = Rubric.checks(for: k)
            return Feeling.score(cs.map { CheckResult(id: $0.id, yes: a[$0.id] ?? false, p: nil, weight: $0.w, kind: "code") }, checks: cs)
        }
        return (s("vv"), s("cv"))
    }
    func testDarkCraftedUIDoesNotReadUnpleasant() { XCTAssertGreaterThanOrEqual(feelingScores().vv, 50) }
    func testNeutralCopyReadsNeutral() { XCTAssertEqual(feelingScores().cv, 50) }
    func testClashingDarkPaletteStillReadsLower() {
        var st = PixelStats(); st.bgLum = 0.01; st.emptyPct = 0.3; st.hueCount = 6; st.hueBuckets = 6; st.accentSat = 0.9
        let a = Scoring.visionAnswers(Scoring.facts(from: vision, textBoxes: boxes), stats: st)
        XCTAssertEqual(a["vv1"], false)
        XCTAssertEqual(a["vv7"], true)
    }

    func testCtaFoldNotAskedOnForms() {
        var f = Scoring.facts(from: vision, textBoxes: boxes); f.primaryCount = 1
        XCTAssertTrue(Applicability.notApplicable(kind: .marketing, pageType: "form", facts: f).contains("h_cta_fold"))
        XCTAssertTrue(Applicability.notApplicable(kind: .app, pageType: "form", facts: f).contains("h_cta_fold"))
    }

    func testNothingActionableMeansNoFix() {
        XCTAssertEqual(Pipeline.finalFix("", score: 90, problem: false, failed: [], meter: "balance"), "")
        XCTAssertEqual(Pipeline.finalFix("Nothing to fix", score: 88, problem: false, failed: [], meter: "balance"), "")
    }

    func testWriterNeverSeesDesignerReasons() {
        func m(_ s: Int, _ d: Int?) -> MeterResult { MeterResult(score: s, lowConfidence: false, confidencePct: 100, checks: [], note: nil, designer: d) }
        let facts = Pipeline.writerMeterFacts(meters: ["balance": m(88, 88), "contrast": m(100, nil)], failed: [:])
        XCTAssertNil((facts["balance"] as? [String: Any])?["deduction"])
        XCTAssertEqual((facts["balance"] as? [String: Any])?["score"] as? Int, 88)
    }

    func testNeverAdviseMovingSubmitUp() {
        XCTAssertTrue(Pipeline.unsafeSubmitAdvice("Move the Sign in button higher into the card's top 60% without placing it beside the fields."))
        XCTAssertTrue(Pipeline.unsafeSubmitAdvice("Move the Sign in button into the upper part of the card, near the fields."))
        XCTAssertFalse(Pipeline.unsafeSubmitAdvice("Make the title white so it leads the card."))
    }
}
