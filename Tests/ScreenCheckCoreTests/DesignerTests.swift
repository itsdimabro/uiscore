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
