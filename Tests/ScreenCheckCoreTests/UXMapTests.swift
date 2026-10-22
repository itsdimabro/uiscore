import XCTest
@testable import ScreenCheckCore

/// The "Comp Neo UX" map page: H1, subtitle, then a two-column grid of 8 cards (bold title + grey description).
/// Synthetic boxes reproduce the layout; the user's screenshot is never part of the repo.
final class UXMapTests: XCTestCase {
    func box(_ t: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, px: Double, bold: Bool = false, role: String = "body") -> TextBox {
        TextBox(text: t, x: x, y: y, w: w, h: h, fontPx: px, bold: bold, role: role, onImage: false)
    }
    func page(descLines: Int) -> [TextBox] {
        var b = [box("UX Map", 300, 60, 260, 44, px: 40, bold: true, role: "heading"), box("How people move through the product", 300, 116, 420, 20, px: 16, role: "subhead")]
        for i in 0..<8 {
            let x = i % 2 == 0 ? 300.0 : 820.0, y = 220.0 + Double(i / 2) * 190
            b.append(box("Card title \(i)", x, y, 230, 26, px: 22, bold: true, role: "subhead"))
            for l in 0..<descLines { b.append(box("Grey description line \(l) of card \(i)", x, y + 36 + Double(l) * 20, 360, 16, px: 14)) }
        }
        return b
    }

    func testRepeatedCardTitlesAreOneEmphasisTier() {
        XCTAssertLessThanOrEqual(Scoring.emphasisCount(page(descLines: 2)), 2)   // H1 + one card-title tier
    }
    func testSingleLoudItemsStillCountSeparately() {
        var b = page(descLines: 2).filter { $0.role != "subhead" || $0.fontPx < 20 }
        b[0].fontPx = 16; b[0].bold = false
        b.append(box("Big banner", 300, 1300, 400, 50, px: 36, bold: true, role: "heading"))
        b.append(box("Other banner", 300, 1500, 400, 50, px: 30, bold: true, role: "heading"))
        b.append(box("Fourth banner", 300, 1900, 400, 50, px: 44))
        b.append(box("Third banner", 300, 1700, 400, 50, px: 24, bold: true, role: "heading"))
        XCTAssertGreaterThan(Scoring.emphasisCount(b), 3)
    }
    func testCardTitleAndDescriptionAreDifferentRolesNotADissimilarGroup() {
        let g = Layout.grouping(page(descLines: 1), pixels: nil, imageWidth: 1400)
        XCTAssertEqual(Layout.groupingChecks(g).first { $0.id == "g_sim" }?.pass, true)
    }
    func testOneOddCardStillFailsSimilarity() {
        var b = page(descLines: 1)
        for i in b.indices where b[i].text.hasPrefix("Card title") || b[i].text.hasPrefix("Grey") { b[i].fontPx = 10 + Double(i) * 4; b[i].bold = i % 3 == 0 }
        let g = Layout.grouping(b, pixels: nil, imageWidth: 1400)
        XCTAssertEqual(Layout.groupingChecks(g).first { $0.id == "g_sim" }?.pass, false)
    }
    func testBalanceProblemNeverBlamesMirrorSymmetry() {
        var m = BalanceMetrics(); m.symmetry = 0.3
        let w = Layout.balanceProblems(m)
        XCTAssertFalse(w.joined(separator: " ").lowercased().contains("mirror"))
        XCTAssertTrue(w.isEmpty)
    }
    func testDesignerBalanceAnchorAllowsAsymmetryAndEmptyBelow() {
        let p = Designer.systemPrompt.lowercased()
        XCTAssertTrue(p.contains("asymmetric"))
        XCTAssertTrue(p.contains("empty space below"))
    }
    func testFailedChecksReachTheWriterAsPlainStatements() {
        let s = Pipeline.writerFailedText(Rubric.checks(for: "order").filter { $0.id == "h_emphasis" })
        XCTAssertEqual(s, ["Too many items shout for attention at once."])
    }
    func testWhyNeverKeepsAnOrFewerCountSentence() {
        let w = Pipeline.cleanWhy("Three or fewer elements stand out most, and the page has too many bold shouts at the top.", meter: "order")
        XCTAssertFalse(w.lowercased().contains("or fewer"))
    }
    func testEveryFallbackSentenceReadsAsAFailureAndCitesNoThreshold() {
        for (id, sentence) in Pipeline.plainCheck {
            XCTAssertNil(sentence.range(of: #"\b(or fewer|or more|\d+)\b|\?"#, options: .regularExpression), id)
            XCTAssertTrue(sentence.hasSuffix("."), id)
        }
    }

    // Per-meter designer reasons
    func vote(_ n: Double, _ reason: String) -> Designer.Rating {
        Designer.Rating(scores: Dictionary(uniqueKeysWithValues: Designer.meters.map { ($0, n) }), reason: "", reasons: Dictionary(uniqueKeysWithValues: Designer.meters.map { ($0, reason) }))
    }
    func testReasonComesFromVoteNearestTheMeanAndIsOrderIndependent() {
        let rs = [vote(5, "Five."), vote(7, "Seven b."), vote(7, "Seven a."), vote(8, "Eight."), vote(7, "Seven c.")]
        XCTAssertEqual(Designer.mean(rs)!.reasons["order"], "Seven a.")
        XCTAssertEqual(Designer.mean(rs.reversed())!.reasons["order"], "Seven a.")
    }
    func testParseReadsPerMeterReasons() {
        let body = Designer.meters.map { "\"\($0)\":6" }.joined(separator: ",")
        let r = Designer.parse(try! JSONValue.firstObject(in: "{\"reasons\":{\"balance\":\" Leans left. \"},\(body)}"))
        XCTAssertEqual(r?.reasons["balance"], "Leans left.")
    }
    func testFailedCheckWhyUsesWriterNotDesigner() {
        let m = MeterResult(score: 80, lowConfidence: false, confidencePct: 100, checks: [CheckResult(id: "E5", yes: false, p: nil, weight: 7, kind: "code")], note: nil, designer: 80)
        var r = RunResult(id: "s", createdAt: Date(), pageName: "P", imageWidth: 1, imageHeight: 1, meters: ["ease": m], feeling: [:], feelingLow: [:], feelingConfidencePct: [:], readingGrade: nil, readingWords: 0, text: [:], timings: Timings(), contrastDetail: nil, vision: .null, pixelStats: nil)
        r.designerReasons = ["ease": "The cards feel crowded."]
        let t = Pipeline.texts(for: r, written: try! JSONValue.firstObject(in: "{\"ease\":[\"Some lines run long.\",\"\",1]}"))
        XCTAssertEqual(t["ease"]!.why, "Some lines run long.")
    }

    // Applicability: a single box the model calls nav is not a navigation
    func testOneNavBoxDoesNotChangeNavCount() {
        let plain = [box("Home", 10, 10, 60, 20, px: 14, role: "body"), box("Body copy here", 300, 100, 300, 20, px: 16)]
        var one = plain; one[0].role = "nav"
        XCTAssertEqual(Scoring.facts(from: .null, textBoxes: one).navCount, Scoring.facts(from: .null, textBoxes: plain).navCount)
        let f = Scoring.facts(from: .null, textBoxes: one)
        XCTAssertTrue(Applicability.notApplicable(kind: .app, pageType: "dashboard", facts: f).contains("f_navcount"))
    }
    // E10: OCR size jitter of a pixel around 16 reads the same
    func testBorderlineBodySizeReadsTheSame() {
        func e10(_ px: Double) -> Bool? {
            let b = [box("A sentence of body text long enough", 100, 100, 400, 20, px: px)]
            return Scoring.codeAnswers(Scoring.facts(from: .null, textBoxes: b), pixels: nil, appScreen: false).answers["E10"]
        }
        XCTAssertEqual(e10(15.6), true)
        XCTAssertEqual(e10(16.2), true)
        XCTAssertEqual(e10(14), true)   // no absolute size claim: only the ratio to the headline counts
    }
}
