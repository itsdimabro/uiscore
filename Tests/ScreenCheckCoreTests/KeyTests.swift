import XCTest
@testable import ScreenCheckCore

final class KeyTests: XCTestCase {
    func testFallbackUsesKeyOneFirst() async throws {
        var seen: [String] = []
        let r: Int = try await KeyFallback.run(keys: ["a", "b"]) { k, _ in seen.append(k); return 1 }
        XCTAssertEqual(r, 1); XCTAssertEqual(seen, ["a"])
    }
    func testFallbackMovesOnForEachRefusal() async throws {
        for code in [401, 402, 403, 429, 529] {
            var seen: [String] = []
            let r: String = try await KeyFallback.run(keys: ["a", "b", "c"]) { k, _ in
                seen.append(k); if k != "c" { throw PipelineError.api("Claude", code) }; return k
            }
            XCTAssertEqual(r, "c"); XCTAssertEqual(seen, ["a", "b", "c"], "code \(code)")
        }
    }
    func testAllKeysFailed() async {
        do { let _: Int = try await KeyFallback.run(keys: ["a", "b"]) { _, _ in throw PipelineError.api("Claude", 401) }; XCTFail() }
        catch { guard case PipelineError.allKeysFailed = error else { return XCTFail("\(error)") } }
        XCTAssertEqual(PipelineError.allKeysFailed.errorDescription, "Your Claude keys stopped working. Check them in Settings.")
    }
    func testOtherErrorsDoNotFallBack() async {
        var n = 0
        do { let _: Int = try await KeyFallback.run(keys: ["a", "b"]) { _, _ in n += 1; throw PipelineError.api("Claude", 500) }; XCTFail() } catch {}
        XCTAssertEqual(n, 1)
    }
    func testNoKeys() async {
        do { let _: Int = try await KeyFallback.run(keys: []) { _, _ in 1 }; XCTFail() }
        catch { guard case PipelineError.noKey = error else { return XCTFail() } }
    }
    func testFormRules() {
        let good = "sk-ant-api03-abcdefgh1234"
        XCTAssertTrue(KeyRules.validate(jev: "jev-key", claude: [good]).isEmpty)
        XCTAssertEqual(KeyRules.validate(jev: " ", claude: [good]).map { $0.field }, [.jev])
        XCTAssertEqual(KeyRules.validate(jev: "j", claude: ["", " "]).map { $0.field }, [.claude(0)])
        XCTAssertEqual(KeyRules.validate(jev: "j", claude: ["abc"]).map { $0.field }, [.claude(0)])
        XCTAssertEqual(KeyRules.validate(jev: "j", claude: [good, good]).map { $0.field }, [.claude(1)])
        XCTAssertEqual(KeyRules.validate(jev: "j", claude: [good, ""]).count, 0)
        XCTAssertEqual(KeyRules.validate(jev: "a b", claude: [good]).map { $0.field }, [.jev])
    }
    func testCleanedAndMask() {
        XCTAssertEqual(KeyRules.cleaned([" a ", "", "a", "b"]), ["a", "b"])
        XCTAssertEqual(KeyRules.mask("sk-ant-api03-WXYZ"), "••••WXYZ")
        XCTAssertEqual(KeyRules.mask("short"), "••••")
    }
    func testKeyListRoundTrip() {
        XCTAssertEqual(KeyStore.decodeList(KeyStore.encodeList(["x", "y"])), ["x", "y"])
    }
}
