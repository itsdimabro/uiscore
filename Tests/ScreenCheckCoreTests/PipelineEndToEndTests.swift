import XCTest
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
@testable import ScreenCheckCore

/// Runs Pipeline.run offline with fixed model replies and compares the result to a recorded snapshot.
final class PipelineEndToEndTests: XCTestCase {
    struct FakeClient: ModelClient {
        static let label = """
        {"page_name":"Acme Home","page_type":"landing","screen_kind":"marketing","tone":"plain_confident","visual_description":"A light page with a headline and one button.",
         "primary_buttons":"one","blocks":"few","fonts":"one_or_two","main_text_alignment":"left","nav_position":"top","logo_position":"top-left","top_right_control":true,
         "panels":"few","columns":"up_to_three","has_dated_cues":false,"has_overlay":false,"has_competing_promo":false,"has_proof":true,"real_imagery":true,
         "first_fixation":"headline","images_ok":true,"text_on_busy_bg":false,"grouping_clear":true,"links_look_clickable":true,"nav_quieter_than_headline":true,
         "emphasis":"few","business_model":"saas","business_model_confidence":"high","location":"homepage","page_purpose":"Plan projects",
         "corner_style":"rounded","accent_colors":"one","heaviest_weight":"bold","roles":{"heading":[0],"subhead":[1],"nav":[],"button":[3],"link":[],"logo":[],"demo":[],"legal":[],"overlay":[],"primary":[3]}}
        """
        func claude(keys: [String], system: String, content: [[String: Any]], maxTokens: Int, model: String, cacheSystem: Bool) async throws -> (json: JSONValue, ms: Double) {
            let text: String
            if system == Prompts.label { text = Self.label }
            else if system == Prompts.c6 { text = "{\"C6\":true}" }
            else if system == Prompts.write {
                let w = Meters.order.map { "\"\($0)\":[\"The \($0) reads as fine.\",\"\",false]" } + ["\"valence\":[\"Calm and light.\"]", "\"intensity\":[\"Quiet.\"]"]
                text = "{" + w.joined(separator: ",") + "}"
            } else {
                text = "{\"reason\":\"The headline is clear.\"," + Designer.meters.map { "\"\($0)\":7" }.joined(separator: ",") + "}"
            }
            return (try JSONValue.firstObject(in: text), 1)
        }
        func jev(key: String, state: JSONValue, questions: [String: String]) async throws -> (p: [String: Double], ms: Double) {
            (Dictionary(uniqueKeysWithValues: questions.keys.sorted().enumerated().map { ($1, $0 % 3 == 0 ? 0.2 : 0.9) }), 1)
        }
    }

    private func writeFixtureImage(to url: URL) throws {
        let w = 1200, h = 800
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: 100, y: 400, width: 260, height: 70))
        func draw(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool, white: Bool = false) {
            let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
            let color = white ? CGColor(red: 1, green: 1, blue: 1, alpha: 1) : CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
            let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
            ctx.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        }
        draw("Plan every project in one place", x: 100, y: 640, size: 56, bold: true)
        draw("Acme keeps tasks, files and people together so your team ships on time.", x: 100, y: 570, size: 24, bold: false)
        draw("Every plan includes unlimited projects and a free trial for fourteen days.", x: 100, y: 530, size: 24, bold: false)
        draw("Start free trial", x: 140, y: 425, size: 28, bold: true, white: true)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    private func snapshot(_ r: RunResult) -> String {
        var r = r
        r.id = ""; r.createdAt = .distantPast; r.timings = Timings(); r.imageHash = nil
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .prettyPrinted]; enc.dateEncodingStrategy = .iso8601
        return String(data: try! enc.encode(r), encoding: .utf8)! + "\n"
    }

    func testRunWithFixedReplies() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let img = dir.appendingPathComponent("shot.png")
        try writeFixtureImage(to: img)
        let pipeline = Pipeline(keys: Keys(claude: ["k"], jev: "j"), client: FakeClient())
        let r = try await pipeline.run(imageURL: img, useCache: false, cacheDir: dir, historyRoot: nil)
        let got = snapshot(r)
        let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/pipeline-end-to-end.snapshot")
        if ProcessInfo.processInfo.environment["SCREENCHECK_RECORD_SNAPSHOT"] != nil { try got.write(to: golden, atomically: true, encoding: .utf8); return }
        XCTAssertEqual(got, try String(contentsOf: golden, encoding: .utf8))
    }
}
