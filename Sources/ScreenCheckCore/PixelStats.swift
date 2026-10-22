import Foundation

/// Facts about the whole screenshot that code can answer from pixels, so the vision model is not asked.
public struct PixelStats: Codable, Equatable {
    public var bgLum: Double = 0          // luminance of the most common color
    public var emptyPct: Double = 0       // share of 16px cells that are plain page background
    public var coloredPct: Double = 0     // share of pixels that are clearly colored (not gray)
    public var hueCount: Int = 0          // distinct hue families covering >= 0.5% of the screen
    public var hueBuckets: Int? = nil     // distinct 30-degree hue slices covering >= 0.5% (a rainbow ribbon counts every slice)
    public var redOrangePct: Double = 0
    public var warmPct: Double = 0        // red, orange, yellow
    public var coolShare: Double = 0      // cool hues as a share of colored pixels
    public var topHueShare: Double = 0    // biggest hue family as a share of colored pixels
    public var greenPct: Double? = nil
    public var coloredBlocks: Int? = nil  // connected blocks of colored 16px cells, each at least 4 cells
    public var colorfulness: Double? = nil // Hasler-Suesstrunk colorfulness M
    public var accentSat: Double = 0      // mean saturation inside the biggest hue family

    public init() {}

    public static func hsv(_ r: Int, _ g: Int, _ b: Int) -> (h: Double, s: Double, v: Double) {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let mx = max(rf, gf, bf), mn = min(rf, gf, bf), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == rf { h = (gf - bf) / d + (gf < bf ? 6 : 0) } else if mx == gf { h = (bf - rf) / d + 2 } else { h = (rf - gf) / d + 4 }
            h *= 60
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    public static func compute(_ px: Pixels) -> PixelStats {
        var st = PixelStats()
        let w = px.width, h = px.height
        if w < 16 || h < 16 { return st }
        var keyCounts: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        var buckets = [Double](repeating: 0, count: 12), satSum = [Double](repeating: 0, count: 12)
        var colored = 0.0, green = 0.0, red = 0.0, warm = 0.0, cool = 0.0, sampled = 0.0
        let step = 2
        var sRG = 0.0, sRG2 = 0.0, sYB = 0.0, sYB2 = 0.0
        for y in stride(from: 0, to: h, by: step) { for x in stride(from: 0, to: w, by: step) {
            let i = (y * w + x) * 4
            let r = Int(px.data[i]), g = Int(px.data[i + 1]), b = Int(px.data[i + 2])
            sampled += 1
            let rg = Double(r - g), yb = 0.5 * Double(r + g) - Double(b)
            sRG += rg; sRG2 += rg * rg; sYB += yb; sYB2 += yb * yb
            let k = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            let e = keyCounts[k] ?? (0, 0, 0, 0)
            keyCounts[k] = (e.n + 1, e.r + r, e.g + g, e.b + b)
            let c = hsv(r, g, b)
            if c.s > 0.25 && c.v > 0.25 {
                colored += 1
                let bi = Int(c.h / 30) % 12
                buckets[bi] += 1; satSum[bi] += c.s
                if c.h >= 85 && c.h <= 290 { cool += 1 }
                if c.s > 0.45 && c.v > 0.35 && c.h >= 85 && c.h <= 160 { green += 1 }
                if c.s > 0.5 && c.v > 0.35 && (c.h < 35 || c.h >= 340) { red += 1 }
                if c.s > 0.45 && c.v > 0.4 && (c.h < 65 || c.h >= 340) { warm += 1 }
            }
        } }
        guard let top = keyCounts.values.max(by: { $0.n < $1.n }) else { return st }
        let bg = (top.r / top.n, top.g / top.n, top.b / top.n)
        st.bgLum = Contrast.luminance(bg.0, bg.1, bg.2)
        st.coloredPct = colored / sampled
        let mRG = sRG / sampled, mYB = sYB / sampled
        let sdRG = max(0, sRG2 / sampled - mRG * mRG).squareRoot(), sdYB = max(0, sYB2 / sampled - mYB * mYB).squareRoot()
        st.colorfulness = (sdRG * sdRG + sdYB * sdYB).squareRoot() + 0.3 * (mRG * mRG + mYB * mYB).squareRoot()
        st.redOrangePct = red / sampled
        st.warmPct = warm / sampled
        st.greenPct = green / sampled
        st.coolShare = colored > 0 ? cool / colored : 0
        let on = buckets.map { $0 / sampled >= 0.005 }
        var fam = 0
        for i in 0..<12 where on[i] && !on[(i + 11) % 12] { fam += 1 }
        if on.allSatisfy({ $0 }) { fam = 1 }
        st.hueCount = fam
        st.hueBuckets = on.filter { $0 }.count
        if colored > 0, let bi = buckets.indices.max(by: { buckets[$0] < buckets[$1] }) {
            let ids = [(bi + 11) % 12, bi, (bi + 1) % 12]
            st.topHueShare = ids.reduce(0) { $0 + buckets[$1] } / colored
            let n = ids.reduce(0) { $0 + buckets[$1] }
            st.accentSat = n > 0 ? ids.reduce(0) { $0 + satSum[$1] } / n : 0
        }
        var cells = 0, empty = 0
        for cy in stride(from: 0, to: h - 15, by: 16) { for cx in stride(from: 0, to: w - 15, by: 16) {
            cells += 1
            var ok = true
            let i0 = (cy * w + cx) * 4
            let r0 = Int(px.data[i0]), g0 = Int(px.data[i0 + 1]), b0 = Int(px.data[i0 + 2])
            if abs(r0 - bg.0) > 14 || abs(g0 - bg.1) > 14 || abs(b0 - bg.2) > 14 { continue }
            scan: for y in stride(from: cy, to: cy + 16, by: 3) { for x in stride(from: cx, to: cx + 16, by: 3) {
                let i = (y * w + x) * 4
                if abs(Int(px.data[i]) - r0) > 6 || abs(Int(px.data[i + 1]) - g0) > 6 || abs(Int(px.data[i + 2]) - b0) > 6 { ok = false; break scan }
            } }
            if ok { empty += 1 }
        } }
        let gw = w / 16, gh = h / 16
        var colCell = [Bool](repeating: false, count: max(1, gw * gh))
        for cy in 0..<gh { for cx in 0..<gw {
            var n = 0
            for y in stride(from: cy * 16, to: cy * 16 + 16, by: 4) { for x in stride(from: cx * 16, to: cx * 16 + 16, by: 4) {
                let i = (y * w + x) * 4
                let c = hsv(Int(px.data[i]), Int(px.data[i + 1]), Int(px.data[i + 2]))
                if c.s > 0.35 && c.v > 0.3 { n += 1 }
            } }
            colCell[cy * gw + cx] = n >= 12
        } }
        var seen = [Bool](repeating: false, count: colCell.count), blocks = 0
        for start in colCell.indices where colCell[start] && !seen[start] {
            var stack = [start], size = 0; seen[start] = true
            while let c = stack.popLast() {
                size += 1
                let cx = c % gw, cy = c / gw
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = cx + dx, ny = cy + dy
                    if nx < 0 || ny < 0 || nx >= gw || ny >= gh { continue }
                    let ni = ny * gw + nx
                    if colCell[ni] && !seen[ni] { seen[ni] = true; stack.append(ni) }
                }
            }
            if size >= 4 { blocks += 1 }
        }
        st.coloredBlocks = blocks
        st.emptyPct = cells > 0 ? Double(empty) / Double(cells) : 0
        return st
    }
}
