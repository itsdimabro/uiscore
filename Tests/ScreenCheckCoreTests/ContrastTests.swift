import XCTest
@testable import ScreenCheckCore

final class ContrastTests: XCTestCase {
    func box(_ t: String, _ y: Double, _ px: Double, role: String = "body", bold: Bool = false) -> TextBox { TextBox(text: t, x: 40, y: y, w: 300, h: px, fontPx: px, bold: bold, role: role, onImage: false) }

    func testContrastHasFourSubRubricsSummingTo100() {
        let ids = Rubric.checks(for: "contrast").map { $0.id }
        for id in ["c_aa", "c_size", "c_weight", "c_space"] { XCTAssertTrue(ids.contains(id), id) }
        XCTAssertEqual(Rubric.checks(for: "contrast").reduce(0) { $0 + $1.w }, 100)
    }
    func testButtonLabelNeedsThreeToOne() {
        var d = [UInt8](repeating: 255, count: 120 * 40 * 4)
        for y in 0..<40 { for x in 0..<120 { let i = (y * 120 + x) * 4; let v: UInt8 = (x + y) % 3 == 0 && x > 10 && x < 100 && y > 10 && y < 30 ? 255 : 0x33; d[i] = v; d[i+1] = v; d[i+2] = v } }
        let px = Pixels(width: 120, height: 40, data: d)
        let b = TextBox(text: "Go now", x: 5, y: 5, w: 110, h: 30, fontPx: 14, bold: false, role: "button", onImage: false)
        XCTAssertEqual(Contrast.report(px, boxes: [b], expected: 1).boxes[0].need, 3.0)
    }
    func testSizeContrastNeedsHeadlineWellAboveBody() {
        let flat = [box("Headline words", 0, 18), box("A sentence of body text long enough", 40, 16), box("Another sentence of body text here", 70, 16)]
        let big = [box("Headline words", 0, 48), box("A sentence of body text long enough", 70, 16), box("Another sentence of body text here", 100, 16)]
        XCTAssertEqual(Scoring.codeAnswers(Scoring.facts(from: .null, textBoxes: flat), pixels: nil).answers["c_size"], false)
        XCTAssertEqual(Scoring.codeAnswers(Scoring.facts(from: .null, textBoxes: big), pixels: nil).answers["c_size"], true)
    }
    func testGroupingAlignmentIsMinorAndMeaningIsScored() {
        let cs = Layout.groupingChecks(GroupingMetrics())
        XCTAssertEqual(cs.first { $0.id == "g_align" }?.weight, 10)
        XCTAssertTrue(cs.contains { $0.id == "g_meaning" })
        XCTAssertEqual(cs.reduce(0) { $0 + $1.weight }, 100)
    }
    func testAlignmentNamedOnlyWhenItIsTheOnlyFailure() {
        func m(_ meaning: Bool?) -> [String] {
            let b = (0..<8).map { TextBox(text: "word", x: 40 + Double($0 % 3) * 31, y: Double($0) * 22, w: 200, h: 16, fontPx: 16, bold: false, role: "body", onImage: false) }
            return Layout.problems(pixels: nil, boxes: b, imageWidth: 800, meaning: meaning)["grouping"] ?? []
        }
        XCTAssertFalse(m(false).contains { $0.contains("left, right or centre") })
    }
    func testBalanceToleratesAsymmetricHero() {
        var b = BalanceMetrics(); b.centroidX = -0.35; b.centroidY = 0.1; b.leftRight = 0.4; b.symmetry = 0.65
        XCTAssertEqual(Layout.balanceScore(b), 100)
    }
    func testEaseNeverClaimsAbsoluteTextSize() {
        XCTAssertEqual(Pipeline.groundedWhy("The body text is under 16 px. Lines run long.", meter: "ease", overlayPresent: false), "Lines run long.")
        XCTAssertEqual(Pipeline.groundedWhy("The text is too small.", meter: "ease", overlayPresent: false), "")
    }
    func testNoClaimedElementThatIsAbsent() {
        XCTAssertEqual(Pipeline.groundedWhy("Ad-like items clutter the page.", meter: "trust", overlayPresent: false), "")
        XCTAssertEqual(Pipeline.groundedWhy("A cookie banner competes with the button.", meter: "clarity", overlayPresent: true), "A cookie banner competes with the button.")
        XCTAssertEqual(Pipeline.groundedWhy("Groups lack a card or panel.", meter: "grouping", overlayPresent: false), "")
        XCTAssertEqual(Pipeline.groundedWhy("Items do not line up on a shared edge.", meter: "grouping", overlayPresent: false), "")
    }
    func testContrastExplainsItsFailures() {
        let r = RunResult.placeholder
        let w = Pipeline.contrastWhy(r, failedIDs: ["c_size", "c_weight"], score: 72, fallback: "")
        XCTAssertTrue(w.contains("larger") && w.contains("heavier"), w)
        XCTAssertFalse(Pipeline.contrastWhy(r, failedIDs: [], score: 100, fallback: "").isEmpty)
    }
    func testDemoTextIsNotReadingLoadAndOverlayLeavesLayout() {
        let boxes = [box("Real copy here", 0, 16), box("demo words", 30, 12, role: "demo"), box("cookie words", 60, 12, role: "overlay")]
        XCTAssertFalse(Scoring.facts(from: .null, textBoxes: boxes).allCopy.contains("demo words"))
        XCTAssertEqual(Scoring.content(boxes).count, 1)
    }
    func testDemoAndLogosCountAsTrust() {
        var f = Scoring.facts(from: .null, textBoxes: [])
        f.allBoxes = (0..<5).map { box("logo\($0)", Double($0) * 30, 14, role: "logo") }
        XCTAssertEqual(Scoring.visionAnswers(f, stats: nil)["T2"], true)
        f.allBoxes = (0..<4).map { box("ui\($0)", Double($0) * 30, 12, role: "demo") }
        XCTAssertEqual(Scoring.visionAnswers(f, stats: nil)["T3"], true)
    }
}
