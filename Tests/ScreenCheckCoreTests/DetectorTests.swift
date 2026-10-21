import XCTest
@testable import ScreenCheckCore

final class DetectorTests: XCTestCase {
    func canvas(_ w: Int, _ h: Int, _ draw: (inout [UInt8], Int) -> Void) -> Pixels {
        var d = [UInt8](repeating: 255, count: w * h * 4)
        draw(&d, w)
        return Pixels(width: w, height: h, data: d)
    }
    func fill(_ d: inout [UInt8], _ w: Int, _ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: (UInt8, UInt8, UInt8)) {
        for yy in y..<(y + rh) { for xx in x..<(x + rw) { let i = (yy * w + xx) * 4; d[i] = c.0; d[i + 1] = c.1; d[i + 2] = c.2 } }
    }
    func ring(_ d: inout [UInt8], _ w: Int, _ x: Int, _ y: Int, _ s: Int, _ t: Int) {
        fill(&d, w, x, y, s, t, (0, 0, 0)); fill(&d, w, x, y + s - t, s, t, (0, 0, 0))
        fill(&d, w, x, y, t, s, (0, 0, 0)); fill(&d, w, x + s - t, y, t, s, (0, 0, 0))
    }

    func testSpacingOnEightPointGrid() {
        let px = canvas(400, 700) { d, w in for i in 0..<10 { fill(&d, w, 40, 20 + i * 56, 200, 24, (0, 0, 0)) } }
        let boxes = (0..<10).map { TextBox(text: "Row \($0)", x: 40, y: Double(20 + $0 * 56), w: 200, h: 24, fontPx: 16, bold: false, role: "body", onImage: false) }
        let m = Detectors.measure(pixels: px, boxes: boxes)
        XCTAssertGreaterThanOrEqual(m.gaps, 8)
        XCTAssertEqual(m.rhythmShare, 1, accuracy: 0.01)
        XCTAssertEqual(m.gridShare, 1, accuracy: 0.01)
    }
    func testSpacingIrregularFailsGrid() {
        let ys = [20, 70, 120, 166, 216, 270, 316, 366, 416, 466]
        let px = canvas(400, 700) { d, w in for y in ys { fill(&d, w, 40, y, 200, 24, (0, 0, 0)) } }
        let boxes = ys.map { TextBox(text: "Row", x: 40, y: Double($0), w: 200, h: 24, fontPx: 16, bold: false, role: "body", onImage: false) }
        let m = Detectors.measure(pixels: px, boxes: boxes)
        XCTAssertLessThan(m.gridShare, 0.5)
    }
    func testFewGapsAreNotApplicable() {
        let px = canvas(300, 200) { d, w in fill(&d, w, 20, 20, 100, 20, (0, 0, 0)); fill(&d, w, 20, 80, 100, 20, (0, 0, 0)) }
        let boxes = [TextBox(text: "A", x: 20, y: 20, w: 100, h: 20, fontPx: 14, bold: false, role: "body", onImage: false),
                     TextBox(text: "B", x: 20, y: 80, w: 100, h: 20, fontPx: 14, bold: false, role: "body", onImage: false)]
        let m = Detectors.measure(pixels: px, boxes: boxes)
        XCTAssertLessThan(m.gaps, 8)
        XCTAssertEqual(m.rhythmShare, 0)
    }
    func testIconGridFindsFiveEqualIcons() {
        let px = canvas(500, 200) { d, w in for i in 0..<5 { ring(&d, w, 40 + i * 80, 80, 24, 3) } }
        let m = Detectors.measure(pixels: px, boxes: [])
        XCTAssertEqual(m.icons.count, 5)
        XCTAssertEqual(m.rowCount, 1)
        XCTAssertEqual(m.sizeCV, 0, accuracy: 0.01)
        XCTAssertEqual(m.strokeCV, 0, accuracy: 0.05)
        XCTAssertEqual(m.colorCount, 1)
    }
    func testMixedIconSizesRaiseCV() {
        let sizes = [16, 24, 32, 20, 40]
        let px = canvas(600, 200) { d, w in var x = 20; for s in sizes { ring(&d, w, x, 80, s, 3); x += 90 } }
        let m = Detectors.measure(pixels: px, boxes: [])
        XCTAssertEqual(m.icons.count, 5)
        XCTAssertGreaterThan(m.sizeCV, 0.25)
    }
    func testIconsOverTextAreIgnored() {
        let px = canvas(300, 120) { d, w in ring(&d, w, 40, 40, 24, 3) }
        let box = TextBox(text: "O", x: 36, y: 36, w: 32, h: 32, fontPx: 20, bold: false, role: "body", onImage: false)
        XCTAssertEqual(Detectors.measure(pixels: px, boxes: [box]).icons.count, 0)
    }
    func testButtonsWithDifferentHeightsDisagree() {
        let blue: (UInt8, UInt8, UInt8) = (20, 90, 230)
        let px = canvas(700, 200) { d, w in
            fill(&d, w, 40, 60, 150, 40, blue); fill(&d, w, 240, 55, 150, 52, blue); fill(&d, w, 440, 60, 150, 40, blue)
        }
        func label(_ x: Double, _ y: Double) -> TextBox { TextBox(text: "Go now", x: x, y: y, w: 60, h: 18, fontPx: 15, bold: false, role: "button", onImage: false) }
        var p = px
        var d = p.data
        for (x, y) in [(85, 71), (285, 72), (485, 71)] { for yy in y..<(y + 18) { for xx in x..<(x + 60) where (xx + yy) % 3 == 0 { let i = (yy * 700 + xx) * 4; d[i] = 255; d[i + 1] = 255; d[i + 2] = 255 } } }
        p = Pixels(width: 700, height: 200, data: d)
        let m = Detectors.measure(pixels: p, boxes: [label(85, 71), label(285, 72), label(485, 71)])
        XCTAssertEqual(m.buttons.count, 3)
        XCTAssertEqual(m.buttonGroups, 1)
        XCTAssertLessThan(m.buttonShare, 1)
    }
    func testDeterministic() {
        let px = canvas(500, 200) { d, w in for i in 0..<5 { ring(&d, w, 40 + i * 80, 80, 24, 3) } }
        XCTAssertEqual(Detectors.measure(pixels: px, boxes: []), Detectors.measure(pixels: px, boxes: []))
    }
}
