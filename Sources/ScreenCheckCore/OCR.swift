import Foundation
import CoreGraphics
import Vision

/// Text boxes from Apple's Vision framework (built into macOS). Same pixels in, same boxes out; no network, no model variance.
public enum OCR {
    /// Boxes are in pixels of `image`, origin top-left, in reading order (top to bottom, then left to right).
    /// `role` is "body" until the vision model labels the box by id.
    public static func boxes(in image: CGImage) -> [TextBox] {
        var out = recognize(image, dx: 0, dy: 0, minConf: 0.3, edge: false)
        // Apple Vision drops some lines on a full page (a subhead under a huge headline). Re-reading overlapping
        // horizontal strips finds them. Strip boxes are added only where the full pass found nothing; boxes cut by a
        // strip edge and low-confidence strip text are ignored. Fixed strips, so output is identical every run.
        let H = image.height, stripH = 280, step = 200
        var y = 0
        while y < H {
            let h = min(stripH, H - y)
            if h >= 60, let crop = image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: h)) {
                for b in recognize(crop, dx: 0, dy: Double(y), minConf: 0.6, edge: true) where b.text.split(separator: " ").count >= 2 && !out.contains(where: { overlaps($0, b) }) {
                    out.append(b)
                }
            }
            if y + h >= H { break }
            y += step
        }
        return out.sorted { a, b in
            let ra = (a.y / 8).rounded(.down), rb = (b.y / 8).rounded(.down)
            if ra != rb { return ra < rb }
            if a.x != b.x { return a.x < b.x }
            return a.text < b.text
        }
    }

    static func overlaps(_ a: TextBox, _ b: TextBox) -> Bool {
        let w = min(a.x + a.w, b.x + b.w) - max(a.x, b.x), h = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
        return w > 0 && h > 0 && w * h > 0.2 * min(a.w * a.h, b.w * b.h)
    }

    static func recognize(_ image: CGImage, dx: Double, dy: Double, minConf: Float, edge: Bool) -> [TextBox] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = ["en-US"]
        req.automaticallyDetectsLanguage = false
        req.minimumTextHeight = 0
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([req]) } catch { return [] }
        let W = Double(image.width), H = Double(image.height)
        var out: [TextBox] = []
        for o in req.results ?? [] {
            guard let c = o.topCandidates(1).first, c.confidence >= minConf else { continue }
            let t = c.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            let b = o.boundingBox
            let w = b.width * W, h = b.height * H
            let top = (1 - b.maxY) * H
            if edge && (top < 3 || top + h > H - 3 || b.minX * W < 3 || b.maxX * W > W - 3) { continue }
            out.append(TextBox(text: t, x: b.minX * W + dx, y: top + dy, w: w, h: h, fontPx: fontSize(height: h, text: t),
                               bold: false, role: "body", onImage: false))
        }
        return out
    }

    /// Font size in px from a line's box height. Calibrated on Chromium renders of 12-24 px Inter: a line with a capital, digit,
    /// ascender or descender is about 1.0x the font size tall; a line of x-height letters only (e.g. "nearness more sun") is about 0.75x.
    static func fontSize(height h: Double, text: String) -> Double {
        let tall = text.contains { $0.isUppercase || $0.isNumber || "bdfhijklgpqty".contains($0) }
        return tall ? h : h * 1.3
    }

    /// Applies the model's role labels (by box index). Unlisted boxes stay "body".
    public static func applyRoles(_ roles: JSONValue, to boxes: [TextBox]) -> [TextBox] {
        var out = boxes
        for role in ["heading", "subhead", "label", "nav", "button", "link", "logo", "demo", "legal"] {
            for v in roles[role].array {
                if let i = v.int, out.indices.contains(i) { out[i].role = role }
            }
        }
        return out
    }
}
