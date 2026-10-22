import XCTest
@testable import ScreenCheckCore

final class DesignerTests: XCTestCase {
    func reply(_ n: Int, reason: String = "Text is faint.") -> JSONValue {
        let body = Designer.meters.map { "\"\($0)\":\(n)" }.joined(separator: ",")
        return try! JSONValue.firstObject(in: "ok {\"reason\":\"\(reason)\",\(body)}")
    }
    func testParseAcceptsFullReply() {
        let r = Designer.parse(reply(7))
        XCTAssertEqual(r?.scores["trust"], 7)
        XCTAssertEqual(r?.reason, "Text is faint.")
    }
    func testParseRejectsMissingOutOfRangeAndFractional() {
        XCTAssertNil(Designer.parse(try! JSONValue.firstObject(in: "{\"contrast\":5}")))
        XCTAssertNil(Designer.parse(reply(10)))
        XCTAssertNil(Designer.parse(reply(0)))
        XCTAssertNil(Designer.parse(try! JSONValue.firstObject(in: "{\"reason\":\"x\"," + Designer.meters.map { "\"\($0)\":5.5" }.joined(separator: ",") + "}")))
    }
    func testMeanNeedsTwoVotesAndIsContinuous() {
        let a = Designer.parse(reply(3))!, b = Designer.parse(reply(5))!, c = Designer.parse(reply(9))!
        XCTAssertNil(Designer.mean([a]))
        XCTAssertEqual(Designer.mean([a, b, c])!.scores["order"]!, 17.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(Designer.mean([a, c])?.scores["order"], 6)
        // five votes, one moving a single step: the mean moves 0.2 of a rating step (2.5 points), not a whole step
        let five = [5, 5, 5, 5, 5].map { Designer.parse(reply($0))! }, flip = [5, 5, 5, 5, 6].map { Designer.parse(reply($0))! }
        let d = Designer.points(Designer.mean(flip)!.scores["order"]!) - Designer.points(Designer.mean(five)!.scores["order"]!)
        XCTAssertEqual(d, 2.5, accuracy: 1e-9)
    }
    func meter(_ s: Int, applicable: Bool? = nil) -> MeterResult {
        MeterResult(score: s, lowConfidence: false, confidencePct: 100, checks: [], note: nil, applicable: applicable)
    }
    func testBlendUsesWeights() {
        let ms = ["balance": meter(40), "grouping": meter(80), "contrast": meter(60), "trust": meter(60)]
        let out = Designer.blend(ms, rating: Designer.parse(reply(9)))
        XCTAssertEqual(out["balance"]?.score, 100)   // w 1
        XCTAssertEqual(out["grouping"]?.score, 95)   // w .75: 75 + 20
        XCTAssertEqual(out["contrast"]?.score, 60)   // w 0
        XCTAssertEqual(out["trust"]?.score, 60)
        XCTAssertEqual(out["balance"]?.designer, 100)
    }
    func testBlendSkipsNotApplicable() {
        let out = Designer.blend(["balance": meter(0, applicable: false)], rating: Designer.parse(reply(9)))
        XCTAssertEqual(out["balance"]?.score, 0)
        XCTAssertNil(out["balance"]?.designer)
    }
    func testFallbackKeepsChecklist() {
        let ms = ["balance": meter(40)]
        XCTAssertEqual(Designer.blend(ms, rating: nil)["balance"]?.score, 40)
    }
}

final class DesignerV2Tests: XCTestCase {
    func testSystemPromptCarriesContextSplitAnchorsAndDiscipline() {
        let p = Designer.systemPrompt.lowercased()
        for need in ["marketing", "app", "dashboard", "apple", "ling", "every reason names", "never claim", "9", "silent", "false positive", "alignment"] { XCTAssertTrue(p.contains(need), need) }
        XCTAssertFalse(p.contains("alignment is the"))
    }
    func testPromptIsOneCachedSystemBlockAndFactsStayOutOfIt() {
        XCTAssertFalse(Designer.systemPrompt.contains("Facts measured"))
        let u = Designer.userText(facts: "page context: x")
        XCTAssertTrue(u.contains("page context: x"))
        let body = Claude.systemBlocks(Designer.systemPrompt, cache: true)
        XCTAssertEqual(body.count, 1)
        XCTAssertEqual((body[0]["cache_control"] as? [String: String])?["type"], "ephemeral")
        XCTAssertNil(Claude.systemBlocks("x", cache: false)[0]["cache_control"])
    }
    func testVersionBumped() { XCTAssertEqual(Designer.version, "d6") }
    func ctx(_ loc: String, _ m: String = "saas") -> PageContext { PageContext(businessModel: m, location: loc, purpose: "", label: "SaaS", confidence: "high") }
    func testC6PassesWhenMarketingHomepageDemonstratesProduct() {
        XCTAssertTrue(Applicability.c6Holds(vote: false, context: ctx("homepage"), demonstrates: true))
        XCTAssertTrue(Applicability.c6Holds(vote: false, context: ctx("landing"), demonstrates: true))
        XCTAssertFalse(Applicability.c6Holds(vote: false, context: ctx("homepage"), demonstrates: false))
        XCTAssertFalse(Applicability.c6Holds(vote: false, context: ctx("inside"), demonstrates: true))
        XCTAssertTrue(Applicability.c6Holds(vote: true, context: ctx("homepage"), demonstrates: false))
    }
    func testDemonstratesProductFromImageryOrDemoText() {
        let b = { (r: String) in TextBox(text: "x", x: 0, y: 0, w: 1, h: 1, fontPx: 12, bold: false, role: r, onImage: false) }
        var f = Scoring.facts(from: try! JSONValue.firstObject(in: "{\"real_imagery\":true}"), textBoxes: [])
        XCTAssertTrue(f.demonstratesProduct)
        f = Scoring.facts(from: try! JSONValue.firstObject(in: "{\"real_imagery\":false}"), textBoxes: [])
        XCTAssertFalse(f.demonstratesProduct)
        f.allBoxes = [b("demo"), b("demo"), b("demo")]
        XCTAssertTrue(f.demonstratesProduct)
    }
    func testT4IsNotAskedWithoutADetectedFooter() {
        var f = Scoring.facts(from: try! JSONValue.firstObject(in: "{}"), textBoxes: [])
        XCTAssertTrue(Applicability.notApplicable(kind: .document, pageType: "article", facts: f).contains("T4"))
        f.allBoxes = [TextBox(text: "© 2026 Acme", x: 0, y: 0, w: 1, h: 1, fontPx: 10, bold: false, role: "legal", onImage: false)]
        XCTAssertFalse(Applicability.notApplicable(kind: .document, pageType: "article", facts: f).contains("T4"))
        XCTAssertTrue(Applicability.notApplicable(kind: .marketing, pageType: "landing page", facts: f).contains("T4"))
    }
}

final class KeychainGuardTests: XCTestCase {
    func testEnvKeysModeNeverReadsOrWritesKeychain() {
        setenv("SCREENCHECK_ENV_KEYS", "1", 1); defer { unsetenv("SCREENCHECK_ENV_KEYS") }
        XCTAssertTrue(KeyStore.offKeychain)
        XCTAssertNil(KeyStore.get("jev"))
        setenv("ANTHROPIC_API_KEY", "a", 1); setenv("JEV_API_KEY", "j", 1)
        let k = KeyStore.keys()
        XCTAssertEqual(k.claude, ["a"]); XCTAssertEqual(k.jev, "j")
    }
}
