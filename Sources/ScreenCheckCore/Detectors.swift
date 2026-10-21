import Foundation

/// Spacing grid, iconography and consistency measured from pixels and OCR boxes only.
/// No model is called and no model answer decides whether a check applies: counts decide, same image gives same numbers.
/// Sizes are in points (pixels divided by the screen scale).
public struct Rect: Codable, Equatable {
    public var x: Double, y: Double, w: Double, h: Double
    public var r: Double { x + w }
    public var b: Double { y + h }
}

public struct IconInfo: Codable, Equatable {
    public var rect: Rect
    public var stroke: Double
    public var color: [Int]
}

public struct ButtonInfo: Codable, Equatable {
    public var rect: Rect
    public var radius: Double
    public var fill: [Int]
    public var tier: Int
}

public struct DetectorMetrics: Codable, Equatable {
    public var gaps: Int = 0
    public var rhythmShare: Double = 0
    public var gridShare: Double = 0
    public var icons: [IconInfo] = []
    public var rowCount: Int = 0
    public var sizeCV: Double = 0
    public var strokeCV: Double = 0
    public var colorCount: Int = 0
    public var navIcons: Int = 0
    public var labeledShare: Double = 0
    public var buttons: [ButtonInfo] = []
    public var buttonGroups: Int = 0
    public var buttonShare: Double = 1
    public var textTiers: Int = 0
    public var textShare: Double = 1
    public init() {}
}

public enum Detectors {
    typealias RGB = (Int, Int, Int)
    struct Comp { var rect: Rect }

    /// Connected regions of pixels that differ from their right/lower neighbour, on a 2 px grid, joined across gaps of ~2 cells.
    static func components(_ px: Pixels) -> [Comp] {
        let cs = 2, cw = px.width / cs, ch = px.height / cs
        guard cw > 4, ch > 4 else { return [] }
        var on = [Bool](repeating: false, count: cw * ch)
        let d = px.data, W = px.width
        for y in 0..<(ch * cs - 1) { for x in 0..<(cw * cs - 1) {
            let i = (y * W + x) * 4, j = i + 4, k = i + W * 4
            let a = abs(Int(d[i]) - Int(d[j])) + abs(Int(d[i + 1]) - Int(d[j + 1])) + abs(Int(d[i + 2]) - Int(d[j + 2]))
            let b = abs(Int(d[i]) - Int(d[k])) + abs(Int(d[i + 1]) - Int(d[k + 1])) + abs(Int(d[i + 2]) - Int(d[k + 2]))
            if a > 40 || b > 40 { on[(y / cs) * cw + x / cs] = true }
        } }
        var m = on
        for y in 0..<ch { for x in 0..<cw where on[y * cw + x] {
            for dy in -1...1 { for dx in -1...1 { let nx = x + dx, ny = y + dy; if nx >= 0, ny >= 0, nx < cw, ny < ch { m[ny * cw + nx] = true } } }
        } }
        var seen = [Bool](repeating: false, count: cw * ch)
        var out: [Comp] = []
        for s in 0..<(cw * ch) where m[s] && !seen[s] {
            seen[s] = true
            var stack = [s]
            var x0 = cw, y0 = ch, x1 = 0, y1 = 0
            while let c = stack.popLast() {
                let x = c % cw, y = c / cw
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < cw && ny < ch && m[ny * cw + nx] && !seen[ny * cw + nx] {
                    seen[ny * cw + nx] = true; stack.append(ny * cw + nx)
                }
            }
            let rx0 = (x0 + 1) * cs, ry0 = (y0 + 1) * cs, rx1 = x1 * cs, ry1 = y1 * cs
            if rx1 > rx0 && ry1 > ry0 { out.append(Comp(rect: Rect(x: Double(rx0), y: Double(ry0), w: Double(rx1 - rx0), h: Double(ry1 - ry0)))) }
        }
        return out
    }

    static func overlapShare(_ a: Rect, _ b: Rect) -> Double {
        let w = min(a.r, b.r) - max(a.x, b.x), h = min(a.b, b.b) - max(a.y, b.y)
        return w > 0 && h > 0 ? w * h / max(1, min(a.w * a.h, b.w * b.h)) : 0
    }
    static func rect(_ t: TextBox) -> Rect { Rect(x: t.x, y: t.y, w: t.w, h: t.h) }
    static func pix(_ px: Pixels, _ x: Int, _ y: Int) -> RGB {
        let i = (y * px.width + x) * 4
        return (Int(px.data[i]), Int(px.data[i + 1]), Int(px.data[i + 2]))
    }

    /// Nearest neighbour below and to the right of each element (overlapping on the other axis), in px.
    static func gaps(_ rects: [Rect]) -> [Double] {
        var out: [Double] = []
        for (i, a) in rects.enumerated() {
            var bv = Double.infinity, bh = Double.infinity
            for (j, c) in rects.enumerated() where j != i {
                let ox = min(a.r, c.r) - max(a.x, c.x), oy = min(a.b, c.b) - max(a.y, c.y)
                if c.y >= a.b - 0.5, ox >= 0.3 * min(a.w, c.w) { bv = min(bv, c.y - a.b) }
                if c.x >= a.r - 0.5, oy >= 0.5 * min(a.h, c.h) { bh = min(bh, c.x - a.r) }
            }
            if bv >= 2 && bv <= 200 { out.append(bv) }
            if bh >= 2 && bh <= 200 { out.append(bh) }
        }
        return out
    }
    static func rhythm(_ g: [Double]) -> Double {
        let ids = Layout.clusterIndex(g, tol: 2)
        var cnt: [Int: Int] = [:]; for i in ids { cnt[i, default: 0] += 1 }
        return Double(cnt.values.sorted(by: >).prefix(4).reduce(0, +)) / Double(max(1, g.count))
    }
    static func gridShare(_ g: [Double]) -> Double {
        Double(g.filter { abs($0 - 4 * ($0 / 4).rounded()) <= 1 }.count) / Double(max(1, g.count))
    }

    /// Ink of a small component: pixels clearly different from the flat ring around it. nil for photos, empty or solid blobs.
    static func inkOf(_ px: Pixels, _ r: Rect) -> (stroke: Double, color: RGB)? {
        let x0 = Int(r.x), y0 = Int(r.y), x1 = min(px.width, Int(r.r)), y1 = min(px.height, Int(r.b))
        guard x1 - x0 >= 6, y1 - y0 >= 6, x0 >= 4, y0 >= 4, x1 + 4 < px.width, y1 + 4 < px.height else { return nil }
        var ring: [RGB] = []
        for x in x0..<x1 { ring.append(pix(px, x, y0 - 3)); ring.append(pix(px, x, y1 + 2)) }
        for y in y0..<y1 { ring.append(pix(px, x0 - 3, y)); ring.append(pix(px, x1 + 2, y)) }
        var counts: [Int: (n: Int, c: RGB)] = [:]
        for c in ring { let k = (c.0 >> 4) << 8 | (c.1 >> 4) << 4 | (c.2 >> 4); counts[k] = ((counts[k]?.n ?? 0) + 1, c) }
        guard let top = counts.max(by: { $0.value.n != $1.value.n ? $0.value.n < $1.value.n : $0.key > $1.key }), Double(top.value.n) >= 0.9 * Double(ring.count) else { return nil }
        let bg = top.value.c
        let w = x1 - x0, h = y1 - y0
        var ink = [Bool](repeating: false, count: w * h)
        var n = 0, sr = 0, sg = 0, sb = 0
        for y in y0..<y1 { for x in x0..<x1 {
            let c = pix(px, x, y)
            if Contrast.dist(c, bg) > 60 { ink[(y - y0) * w + x - x0] = true; n += 1; sr += c.0; sg += c.1; sb += c.2 }
        } }
        guard n >= 8, n < w * h * 9 / 10 else { return nil }
        var edge = 0
        for y in 0..<h { for x in 0..<w where ink[y * w + x] {
            if x == 0 || y == 0 || x == w - 1 || y == h - 1 || !ink[y * w + x - 1] || !ink[y * w + x + 1] || !ink[(y - 1) * w + x] || !ink[(y + 1) * w + x] { edge += 1 }
        } }
        return (2 * Double(n) / Double(max(1, edge)), (sr / n, sg / n, sb / n))
    }

    static func cv(_ v: [Double]) -> Double {
        guard v.count >= 2 else { return 0 }
        let m = v.reduce(0, +) / Double(v.count)
        guard m > 0 else { return 0 }
        return (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)).squareRoot() / m
    }

    /// A filled button: a short label whose flat fill colour extends a few points around it. Radius from the area cut off the corners.
    static func button(_ px: Pixels, _ t: TextBox, scale: Double, page: RGB) -> ButtonInfo? {
        guard t.text.split(separator: " ").count <= 3, t.text.count <= 28, t.h >= 8 else { return nil }
        guard Contrast.isFilled(px, box: t), let s = Contrast.clusterSample(px, box: t) else { return nil }
        let fill = s.bg
        guard Contrast.dist(fill, page) >= 30 else { return nil }
        func same(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < px.width && y < px.height && Contrast.dist(pix(px, x, y), fill) < 36 }
        // Walk outward along the label's edge lines (text-free), stop at the first 2 non-fill pixels in a row.
        func walk(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> Int {
            var k = 0, miss = 0
            while k < 200 {
                if same(x + dx * (k + 1), y + dy * (k + 1)) { miss = 0 } else { miss += 1; if miss >= 2 { break } }
                k += 1
            }
            return k - (miss > 0 ? miss - 1 : 0)
        }
        let cx = Int(t.x + t.w / 2), cy = Int(t.y + t.h / 2)
        let left = Int(t.x) - walk(Int(t.x), cy, -1, 0), right = Int(t.x + t.w) + walk(Int(t.x + t.w), cy, 1, 0)
        let top = Int(t.y) - walk(cx, Int(t.y), 0, -1), bottom = Int(t.y + t.h) + walk(cx, Int(t.y + t.h), 0, 1)
        let r = Rect(x: Double(left), y: Double(top), w: Double(right - left), h: Double(bottom - top))
        guard r.h >= 18 * scale, r.h <= 64 * scale, r.h <= t.h * 3.2, r.w >= t.w + 6, r.w <= t.w + 6 * r.h, r.x >= 0, r.y >= 0, r.r <= Double(px.width), r.b <= Double(px.height) else { return nil }
        // The claimed rectangle must really be filled: at least 85% of the pixels outside the label box are the fill colour.
        var inside = 0, filled = 0
        for y in stride(from: Int(r.y), to: Int(r.b), by: 2) { for x in stride(from: Int(r.x), to: Int(r.r), by: 2) {
            if Double(x) >= t.x - 2 && Double(x) <= t.x + t.w + 2 && Double(y) >= t.y - 2 && Double(y) <= t.y + t.h + 2 { continue }
            inside += 1; if same(x, y) { filled += 1 }
        } }
        guard inside > 0, Double(filled) / Double(inside) >= 0.85 else { return nil }
        let side = max(2, Int(r.h / 2))
        var cut = 0
        for (ox, oy, sx, sy) in [(Int(r.x), Int(r.y), 1, 1), (Int(r.r) - 1, Int(r.y), -1, 1), (Int(r.x), Int(r.b) - 1, 1, -1), (Int(r.r) - 1, Int(r.b) - 1, -1, -1)] {
            for dy in 0..<side { for dx in 0..<side where !same(ox + sx * dx, oy + sy * dy) { cut += 1 } }
        }
        // a quarter-circle corner of radius R removes (1 - pi/4) R^2 pixels
        let radius = min(r.h / 2, (Double(cut) / 4 / (1 - Double.pi / 4)).squareRoot()) / scale
        return ButtonInfo(rect: Rect(x: r.x / scale, y: r.y / scale, w: r.w / scale, h: r.h / scale), radius: radius, fill: [fill.0, fill.1, fill.2], tier: Int(t.fontPx.rounded()))
    }

    public static func measure(pixels px: Pixels, boxes all: [TextBox], scale: Double = 1) -> DetectorMetrics {
        var m = DetectorMetrics()
        let text = all.filter { !["demo", "logo"].contains($0.role) && $0.h >= 6 && $0.w >= 8 }
        let demo = all.filter { $0.role == "demo" }.map(rect)
        let pad = all.filter { $0.h >= 4 }.map { Rect(x: $0.x - 2, y: $0.y - 2, w: $0.w + 4, h: $0.h + 4) }
        let comps = components(px).filter { c in !pad.contains { overlapShare(c.rect, $0) > 0.3 } && !demo.contains { overlapShare(c.rect, $0) > 0.3 } }

        var rects = text.map(rect)
        rects += comps.map { $0.rect }.filter { $0.w >= 8 * scale && $0.h >= 8 * scale }
        let g = gaps(rects).map { $0 / scale }
        m.gaps = g.count
        if g.count >= 8 { m.rhythmShare = rhythm(g); m.gridShare = gridShare(g) }

        var icons: [(Rect, Double, RGB)] = []
        for c in comps {
            let r = c.rect, wp = r.w / scale, hp = r.h / scale
            guard wp >= 12, wp <= 48, hp >= 12, hp <= 48, wp / hp >= 0.6, wp / hp <= 1.6, let ink = inkOf(px, r) else { continue }
            icons.append((r, ink.stroke / scale, ink.color))
        }
        icons.sort { ($0.0.y, $0.0.x) < ($1.0.y, $1.0.x) }
        let cyID = Layout.clusterIndex(icons.map { $0.0.y + $0.0.h / 2 }, tol: 8 * scale)
        let cxID = Layout.clusterIndex(icons.map { $0.0.x + $0.0.w / 2 }, tol: 8 * scale)
        var rowN: [Int: Int] = [:], colN: [Int: Int] = [:]
        for i in icons.indices { rowN[cyID[i], default: 0] += 1; colN[cxID[i], default: 0] += 1 }
        var cvs: [Double] = []
        for (id, n) in rowN where n >= 2 { cvs.append(cv(icons.indices.filter { cyID[$0] == id }.map { icons[$0].0.h / scale })) }
        m.rowCount = cvs.count
        m.sizeCV = cvs.isEmpty ? 0 : cvs.reduce(0, +) / Double(cvs.count)
        m.strokeCV = cv(icons.map { $0.1 })
        var palette: [RGB] = []
        for ic in icons where !palette.contains(where: { Contrast.dist($0, ic.2) < 70 }) { palette.append(ic.2) }
        m.colorCount = palette.count
        var nav = 0, labeled = 0
        for i in icons.indices where rowN[cyID[i]]! >= 3 || colN[cxID[i]]! >= 3 {
            nav += 1
            let r = icons[i].0, reach = 8 * scale
            let near = text.contains { t in
                let dx = max(0, max(r.x, t.x) - min(r.r, t.x + t.w)), dy = max(0, max(r.y, t.y) - min(r.b, t.y + t.h))
                return dy <= r.h * 0.5 && dx <= reach
            }
            if near { labeled += 1 }
        }
        m.navIcons = nav
        m.labeledShare = nav == 0 ? 0 : Double(labeled) / Double(nav)
        m.icons = icons.map { IconInfo(rect: Rect(x: $0.0.x / scale, y: $0.0.y / scale, w: $0.0.w / scale, h: $0.0.h / scale), stroke: $0.1, color: [$0.2.0, $0.2.1, $0.2.2]) }

        let page = Layout.pageBackground(px)
        m.buttons = text.compactMap { button(px, $0, scale: scale, page: page) }
        var tiers: [Int: [ButtonInfo]] = [:]
        for b in m.buttons { tiers[b.tier, default: []].append(b) }
        var inGroups = 0, agree = 0
        for (_, bs) in tiers where bs.count >= 2 {
            m.buttonGroups += 1
            let hmed = bs.map { $0.rect.h }.sorted()[bs.count / 2], rmed = bs.map { $0.radius }.sorted()[bs.count / 2]
            for b in bs { inGroups += 1; if abs(b.rect.h - hmed) <= 2 && abs(b.radius - rmed) <= 2 { agree += 1 } }
        }
        m.buttonShare = inGroups == 0 ? 1 : Double(agree) / Double(inGroups)
        var sizeTier: [Int: [RGB]] = [:]
        for t in text where t.fontPx >= 6 { if let s = Contrast.clusterSample(px, box: t) { sizeTier[Int(t.fontPx.rounded()), default: []].append(s.fg) } }
        var ok = 0
        for (_, cols) in sizeTier where cols.count >= 2 {
            m.textTiers += 1
            var pal: [RGB] = []
            for c in cols where !pal.contains(where: { Contrast.dist($0, c) < 90 }) { pal.append(c) }
            if pal.count <= 2 { ok += 1 }
        }
        m.textShare = m.textTiers == 0 ? 1 : Double(ok) / Double(m.textTiers)
        return m
    }
}
