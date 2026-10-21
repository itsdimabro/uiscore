import XCTest
@testable import ScreenCheckCore

final class TitleEditingTests: XCTestCase {
    func testDefaultNameIsFullySelected() {
        XCTAssertEqual(TitleEditing.initialSelection(for: "Screenshot"), NSRange(location: 0, length: 10))
    }
    func testOtherNamesGetCaretAtEnd() {
        XCTAssertEqual(TitleEditing.initialSelection(for: "Linear pricing"), NSRange(location: 14, length: 0))
        XCTAssertEqual(TitleEditing.initialSelection(for: "screenshot"), NSRange(location: 10, length: 0))
        XCTAssertEqual(TitleEditing.initialSelection(for: ""), NSRange(location: 0, length: 0))
    }
}
