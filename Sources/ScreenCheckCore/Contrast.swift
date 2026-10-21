import Foundation
import CoreGraphics
import ImageIO

public struct Pixels {
    public let width: Int, height: Int
    public let data: [UInt8]   // RGBA
    public init(width: Int, height: Int, data: [UInt8]) { self.width = width; self.height = height; self.data = data }
    public init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok = buf.withUnsafeMutableBytes { p -> Bool in
            guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        if !ok { return nil }
        self.init(width: w, height: h, data: buf)
    }
}

public enum Contrast {
    static func lin(_ v: Double) -> Double { let c = v / 255; return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    public static func luminance(_ r: Int, _ g: Int, _ b: Int) -> Double {
        0.2126 * lin(Double(r)) + 0.7152 * lin(Double(g)) + 0.0722 * lin(Double(b))
    }
    /// WCAG 2 contrast ratio. Never rounded.
    public static func ratio(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Double {
        let x = luminance(a.0, a.1, a.2), y = luminance(b.0, b.1, b.2)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    public static func need(fontPx: Double, bold: Bool) -> Double { (fontPx >= 24 || (bold && fontPx >= 18.7)) ? 3.0 : 4.5 }
    public static func hex(_ c: (Int, Int, Int)) -> String { String(format: "#%02x%02x%02x", c.0, c.1, c.2) }

    public struct ClusterSample {
        public let dark: (Int, Int, Int), light: (Int, Int, Int), bg: (Int, Int, Int), fg: (Int, Int, Int)
        public let ratio: Double
    }

    /// Real-pixel measurement of one text box. Colors are quantised into clusters; stray anti-alias pixels are ignored
    /// by requiring a cluster to hold a minimum share of the box. The darkest and lightest clusters give the WCAG ratio.
    /// Returns nil when the box cannot be measured (too small, flat, or a busy photo/gradient with too many colors).
    public static func clusterSample(_ px: Pixels, box b: TextBox, maxClusters: Int = 48) -> ClusterSample? {
        let x0 = max(0, Int(b.x.rounded())), y0 = max(0, Int(b.y.rounded()))
        let x1 = min(px.width, Int((b.x + b.w).rounded())), y1 = min(px.height, Int((b.y + b.h).rounded()))
        if x1 - x0 < 4 || y1 - y0 < 4 { return nil }
        guard let s = clusterSample(px, x0: x0, y0: y0, x1: x1, y1: y1, maxClusters: maxClusters) else { return nil }
        return flatSurround(px, x0: x0, y0: y0, x1: x1, y1: y1, bg: s.bg) ? s : nil
    }

    static func clusterSample(_ px: Pixels, x0: Int, y0: Int, x1: Int, y1: Int, maxClusters: Int) -> ClusterSample? {
        var counts: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for y in y0..<y1 { for x in x0..<x1 {
            let i = (y * px.width + x) * 4
            let r = Int(px.data[i]), g = Int(px.data[i + 1]), bl = Int(px.data[i + 2])
            let k = (r >> 3) << 10 | (g >> 3) << 5 | (bl >> 3)
            let e = counts[k] ?? (0, 0, 0, 0)
            counts[k] = (e.n + 1, e.r + r, e.g + g, e.b + bl)
        } }
        let total = (x1 - x0) * (y1 - y0)
        let minN = max(3, Int(Double(total) * 0.004))
        let sig = counts.values.filter { $0.n >= minN }
            .map { (n: $0.n, c: ($0.r / $0.n, $0.g / $0.n, $0.b / $0.n)) }
        if sig.count < 2 || sig.count > maxClusters { return nil }
        let lum = sig.map { luminance($0.c.0, $0.c.1, $0.c.2) }
        guard let iMin = lum.indices.min(by: { lum[$0] < lum[$1] }), let iMax = lum.indices.max(by: { lum[$0] < lum[$1] }) else { return nil }
        let dark = sig[iMin].c, light = sig[iMax].c
        let r = ratio(dark, light)
        if r < 1.05 { return nil }
        let bg = sig.max(by: { $0.n < $1.n })!.c
        let cols = sig.map { $0.c }
        // Ink = clusters clearly different from the background and not an anti-aliased blend of two others.
        // Only colors holding a real share of the ink are text colors: a small icon, bullet dot or logo mark inside
        // the box must not decide the ratio. The weakest real text color against the background decides.
        var ink: [(c: (Int, Int, Int), n: Int)] = []
        for i in sig.indices where dist(sig[i].c, bg) >= 40 && !isBlend(sig[i].c, of: i, in: cols) { ink.append((sig[i].c, sig[i].n)) }
        let inkTotal = ink.reduce(0) { $0 + $1.n }
        let top = ink.map { $0.n }.max() ?? 0
        let real = ink.filter { $0.n * 5 >= inkTotal || $0.n == top }
        guard let weakest = real.min(by: { ratio($0.c, bg) < ratio($1.c, bg) }) else {
            return ClusterSample(dark: dark, light: light, bg: bg, fg: ratio(dark, bg) >= ratio(light, bg) ? dark : light, ratio: r)
        }
        return ClusterSample(dark: dark, light: light, bg: bg, fg: weakest.c, ratio: ratio(weakest.c, bg))
    }

    /// True when the pixels just outside the box are the same flat color as the box background. A gradient, photo or
    /// neighbouring artwork behind the text makes the measured background wrong, so such boxes are left unmeasured.
    static func flatSurround(_ px: Pixels, x0: Int, y0: Int, x1: Int, y1: Int, bg: (Int, Int, Int)) -> Bool {
        let t = 3
        var n = 0, same = 0
        func probe(_ x: Int, _ y: Int) {
            if x < 0 || y < 0 || x >= px.width || y >= px.height { return }
            n += 1
            let i = (y * px.width + x) * 4
            if dist((Int(px.data[i]), Int(px.data[i + 1]), Int(px.data[i + 2])), bg) < 36 { same += 1 }
        }
        for x in x0..<x1 { for d in 1...t { probe(x, y0 - d); probe(x, y1 - 1 + d) } }
        for y in y0..<y1 { for d in 1...t { probe(x0 - d, y); probe(x1 - 1 + d, y) } }
        return n == 0 || Double(same) / Double(n) >= 0.8
    }

    /// A filled button: the box's own background differs clearly from the page just outside it.
    public static func isFilled(_ px: Pixels, box b: TextBox) -> Bool {
        let x0 = max(0, Int(b.x.rounded())), y0 = max(0, Int(b.y.rounded()))
        let x1 = min(px.width, Int((b.x + b.w).rounded())), y1 = min(px.height, Int((b.y + b.h).rounded()))
        guard x1 - x0 >= 4, y1 - y0 >= 4, let s = clusterSample(px, x0: x0, y0: y0, x1: x1, y1: y1, maxClusters: 48) else { return false }
        // Button padding can be wider than one text height, so probe at two distances in four directions
        // and call it filled when at least two probes land on a clearly different color.
        var differ = 0
        for k in [2.0, 4.0] {
            let m = Int(max(24, b.h * k))
            for (x, y) in [(x0 - m, (y0 + y1) / 2), (x1 + m, (y0 + y1) / 2), ((x0 + x1) / 2, y0 - m), ((x0 + x1) / 2, y1 + m)] where x >= 0 && y >= 0 && x < px.width && y < px.height {
                let i = (y * px.width + x) * 4
                if dist(s.bg, (Int(px.data[i]), Int(px.data[i + 1]), Int(px.data[i + 2]))) >= 40 { differ += 1 }
            }
        }
        return differ >= 2
    }

    static func dist(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Double {
        let x = Double(a.0 - b.0), y = Double(a.1 - b.1), z = Double(a.2 - b.2)
        return (x * x + y * y + z * z).squareRoot()
    }
    /// True when color `c` sits on the line between two other colors in the box: an anti-aliased edge, not real text.
    static func isBlend(_ c: (Int, Int, Int), of idx: Int, in cols: [(Int, Int, Int)]) -> Bool {
        for a in cols.indices where a != idx {
            for b in cols.indices where b != idx && b > a {
                let ab = (Double(cols[b].0 - cols[a].0), Double(cols[b].1 - cols[a].1), Double(cols[b].2 - cols[a].2))
                let len2 = ab.0 * ab.0 + ab.1 * ab.1 + ab.2 * ab.2
                if len2 < 1 { continue }
                let ac = (Double(c.0 - cols[a].0), Double(c.1 - cols[a].1), Double(c.2 - cols[a].2))
                let t = (ac.0 * ab.0 + ac.1 * ab.1 + ac.2 * ab.2) / len2
                if t < 0.08 || t > 0.92 { continue }
                let p = (Double(cols[a].0) + t * ab.0, Double(cols[a].1) + t * ab.1, Double(cols[a].2) + t * ab.2)
                let d = ((Double(c.0) - p.0) * (Double(c.0) - p.0) + (Double(c.1) - p.1) * (Double(c.1) - p.1) + (Double(c.2) - p.2) * (Double(c.2) - p.2)).squareRoot()
                if d < 26 { return true }
            }
        }
        return false
    }

    /// Per-box report. Text that cannot be measured (on a photo, flat/misplaced box, busy background) has ratio nil and
    /// is left out of scoring; `expected` is only used for the coverage check.
    public static func report(_ px: Pixels?, boxes: [TextBox], expected: Int) -> ContrastReport {
        var out: [BoxContrast] = []
        for b in boxes {
            let need = need(fontPx: b.fontPx, bold: b.bold)
            if !b.onImage, let px, let s = clusterSample(px, box: b) {
                out.append(BoxContrast(text: b.text, ratio: s.ratio, need: need, pass: s.ratio >= need, fg: hex(s.fg), bg: hex(s.bg)))
            } else {
                out.append(BoxContrast(text: b.text, ratio: nil, need: need, pass: false, fg: nil, bg: nil))
            }
        }
        let measured = out.filter { $0.ratio != nil }
        return ContrastReport(expected: max(expected, boxes.count), measured: measured.count,
                              passing: out.filter { $0.pass }.count,
                              minRatio: measured.map { $0.ratio! }.min(), boxes: out)
    }

    public static func downscaled(_ image: CGImage, maxSide: Int = 1568) -> CGImage {
        let m = max(image.width, image.height)
        if m <= maxSide { return image }
        let s = Double(maxSide) / Double(m)
        let w = Int((Double(image.width) * s).rounded()), h = Int((Double(image.height) * s).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let d = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(d, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? d as Data : nil
    }

    /// Screen scale of a screenshot: 2 for a Retina capture (144 dpi metadata, or the image is wider than any 1x laptop/desktop
    /// screen would give), else 1. Text sizes in px are divided by this so a 2x capture is judged in CSS px / pt.
    public static func screenScale(_ url: URL, width: Int) -> Double {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let dpi = (props[kCGImagePropertyDPIWidth] as? Double) {
            if dpi >= 216 { return 3 }
            if dpi >= 108 { return 2 }
            return 1
        }
        return width >= 2880 ? 2 : 1
    }

    public static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
