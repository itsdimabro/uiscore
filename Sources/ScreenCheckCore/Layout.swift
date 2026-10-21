import Foundation

/// Balance and Alignment measured from pixels and OCR boxes. No model is called; same image, same numbers.
public struct BalanceMetrics: Codable, Equatable {
    public var centroidX: Double = 0    // visual-weight centroid, -1 (left edge) ... +1 (right edge), 0 = centre
    public var centroidY: Double = 0    // -1 top ... +1 bottom
    public var leftRight: Double = 1    // min(left, right) / max(left, right) weight, 1 = even
    public var topBottom: Double = 1
    public var symmetry: Double = 1     // mirror similarity of the weight map, 1 = identical halves
    public init() {}
}

public struct AlignmentMetrics: Codable, Equatable {
    public var boxes: Int = 0
    public var alignedShare: Double = 1   // share of text boxes sharing a left edge, right edge or centre line with another box
    public var leftLines: Int = 0         // left-edge lines holding 3+ boxes
    public var topLinesShare: Double = 0  // share of boxes on the 3 busiest alignment lines
    public var gapRegularity: Double = 1  // share of vertical gaps within a stack that match the stack's typical gap
    public init() {}
}

public enum Layout {
    /// Visual weight per 16 px cell = distance of the cell's colour from the page background (0-1) x area, saliency-lite.
    /// Returned as a row-major grid (rows x cols).
    public static func weightGrid(_ px: Pixels, cell: Int = 16) -> (w: [Double], cols: Int, rows: Int) {
        let cols = max(1, px.width / cell), rows = max(1, px.height / cell)
        // Page background = most common colour (5 bits per channel) over a 2 px sampling.
        var counts: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for y in stride(from: 0, to: px.height, by: 2) { for x in stride(from: 0, to: px.width, by: 2) {
            let i = (y * px.width + x) * 4
            let r = Int(px.data[i]), g = Int(px.data[i + 1]), b = Int(px.data[i + 2])
            let k = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            let e = counts[k] ?? (0, 0, 0, 0)
            counts[k] = (e.n + 1, e.r + r, e.g + g, e.b + b)
        } }
        let top = counts.max { a, b in a.value.n != b.value.n ? a.value.n < b.value.n : a.key > b.key }!.value
        let br = Double(top.r) / Double(top.n), bg = Double(top.g) / Double(top.n), bb = Double(top.b) / Double(top.n)
        var out = [Double](repeating: 0, count: cols * rows)
        for cy in 0..<rows { for cx in 0..<cols {
            var s = 0.0, n = 0.0
            for y in stride(from: cy * cell, to: min(px.height, (cy + 1) * cell), by: 2) { for x in stride(from: cx * cell, to: min(px.width, (cx + 1) * cell), by: 2) {
                let i = (y * px.width + x) * 4
                let dr = Double(px.data[i]) - br, dg = Double(px.data[i + 1]) - bg, db = Double(px.data[i + 2]) - bb
                s += (dr * dr + dg * dg + db * db).squareRoot() / 441.673
                n += 1
            } }
            out[cy * cols + cx] = n == 0 ? 0 : s / n
        } }
        return (out, cols, rows)
    }

    public static func balance(_ grid: (w: [Double], cols: Int, rows: Int)) -> BalanceMetrics {
        var m = BalanceMetrics()
        let c = grid.cols, r = grid.rows
        var total = 0.0, sx = 0.0, sy = 0.0, left = 0.0, right = 0.0, up = 0.0, down = 0.0
        for y in 0..<r { for x in 0..<c {
            let w = grid.w[y * c + x]
            total += w
            let nx = (Double(x) + 0.5) / Double(c) * 2 - 1, ny = (Double(y) + 0.5) / Double(r) * 2 - 1
            sx += w * nx; sy += w * ny
            if nx < 0 { left += w } else { right += w }
            if ny < 0 { up += w } else { down += w }
        } }
        guard total > 1e-9 else { return m }
        m.centroidX = sx / total; m.centroidY = sy / total
        m.leftRight = max(left, right) == 0 ? 1 : min(left, right) / max(left, right)
        m.topBottom = max(up, down) == 0 ? 1 : min(up, down) / max(up, down)
        var diff = 0.0
        for y in 0..<r { for x in 0..<c / 2 { diff += abs(grid.w[y * c + x] - grid.w[y * c + (c - 1 - x)]) } }
        m.symmetry = 1 - diff / total
        return m
    }

    static func clusterIndex(_ values: [Double], tol: Double) -> [Int] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var id = [Int](repeating: 0, count: values.count), cur = -1, last = -Double.infinity
        for i in order { if values[i] - last > tol { cur += 1 }; id[i] = cur; last = values[i] }
        return id
    }

    /// Alignment lines are left edges, right edges or centre lines (tolerance 1% of width, at least 8 px) that hold 3+ boxes.
    public static func alignment(_ boxes: [TextBox], imageWidth: Int) -> AlignmentMetrics {
        var m = AlignmentMetrics()
        let b = boxes.filter { $0.h >= 6 && $0.w >= 8 }
        m.boxes = b.count
        guard b.count >= 2 else { return m }
        let tol = max(8, Double(imageWidth) * 0.01)
        let L = clusterIndex(b.map { $0.x }, tol: tol), R = clusterIndex(b.map { $0.x + $0.w }, tol: tol), C = clusterIndex(b.map { $0.x + $0.w / 2 }, tol: tol)
        func size(_ ids: [Int]) -> [Int: Int] { var d: [Int: Int] = [:]; for i in ids { d[i, default: 0] += 1 }; return d }
        let M = clusterIndex(b.map { $0.y + $0.h / 2 }, tol: max(6, tol * 0.6))   // a row of items shares a centre line
        let ls = size(L), rs = size(R), cs = size(C), ms = size(M)
        var shared = 0
        for i in b.indices where ls[L[i]]! >= 3 || rs[R[i]]! >= 3 || cs[C[i]]! >= 3 || ms[M[i]]! >= 3 { shared += 1 }
        m.alignedShare = Double(shared) / Double(b.count)
        // Top 3 lines by box count (each line kind has its own ids): share of boxes on at least one of them.
        var lines: [(kind: Int, id: Int, n: Int)] = []
        for (k, n) in ls where n >= 3 { lines.append((0, k, n)) }
        for (k, n) in rs where n >= 3 { lines.append((1, k, n)) }
        for (k, n) in cs where n >= 3 { lines.append((2, k, n)) }
        for (k, n) in ms where n >= 3 { lines.append((3, k, n)) }
        lines.sort { ($0.n, $1.kind, $1.id) > ($1.n, $0.kind, $0.id) }
        let top = Array(lines.prefix(3))
        let onTop = b.indices.filter { i in top.contains { ($0.kind == 0 && L[i] == $0.id) || ($0.kind == 1 && R[i] == $0.id) || ($0.kind == 2 && C[i] == $0.id) || ($0.kind == 3 && M[i] == $0.id) } }.count
        m.topLinesShare = Double(onTop) / Double(b.count)
        m.leftLines = ls.values.filter { $0 >= 3 }.count
        // Spacing: only vertical stacks of 3+ boxes on one left line; gaps in a stack should repeat.
        var gaps = 0, regular = 0
        for (id, n) in ls where n >= 3 {
            let stack = b.indices.filter { L[$0] == id }.sorted { b[$0].y < b[$1].y }
            var g: [Double] = []
            for k in 1..<stack.count { g.append(max(0, b[stack[k]].y - (b[stack[k - 1]].y + b[stack[k - 1]].h))) }
            let med = g.sorted()[g.count / 2]
            for x in g { gaps += 1; if abs(x - med) <= max(4, 0.25 * med) { regular += 1 } }
        }
        m.gapRegularity = gaps == 0 ? 1 : Double(regular) / Double(gaps)
        return m
    }
}

extension Layout {
    /// Balance 0-100: centroid within 30% of centre horizontally (30) and 40% vertically (20), left/right weight ratio >= 0.5 (25), mirror similarity >= 0.8 (25).
    public static func balanceScore(_ m: BalanceMetrics) -> Int {
        (abs(m.centroidX) <= 0.3 ? 30 : 0) + (abs(m.centroidY) <= 0.4 ? 20 : 0) + (m.leftRight >= 0.5 ? 25 : 0) + (m.symmetry >= 0.8 ? 25 : 0)
    }
    /// Alignment 0-100: 50%+ of boxes sit on an alignment line of 3+ boxes (30), the 3 busiest lines hold 35%+ of boxes (45), 40%+ of stack gaps repeat (25).
    public static func alignmentScore(_ m: AlignmentMetrics) -> Int {
        (m.alignedShare >= 0.5 ? 30 : 0) + (m.topLinesShare >= 0.35 ? 45 : 0) + (m.gapRegularity >= 0.4 ? 25 : 0)
    }
    static func meters(pixels: Pixels?, boxes: [TextBox], imageWidth: Int) -> [String: MeterResult] {
        var out: [String: MeterResult] = [:]
        if let px = pixels {
            out["balance"] = MeterResult(score: balanceScore(balance(weightGrid(px))), lowConfidence: false, confidencePct: 100, checks: [], note: nil)
        }
        let text = boxes.filter { !["demo", "logo"].contains($0.role) }
        if text.count >= 4 {
            out["alignment"] = MeterResult(score: alignmentScore(alignment(text, imageWidth: imageWidth)), lowConfidence: false, confidencePct: 100, checks: [], note: nil)
        } else {
            out["alignment"] = MeterResult(score: 0, lowConfidence: false, confidencePct: 100, checks: [], note: nil, applicable: false)
        }
        return out
    }
}

extension Layout {
    /// Plain-language failures for the writer; empty when the meter passes every test.
    static func problems(pixels: Pixels?, boxes: [TextBox], imageWidth: Int) -> [String: [String]] {
        var out: [String: [String]] = [:]
        if let px = pixels {
            let b = balance(weightGrid(px)); var f: [String] = []
            if abs(b.centroidX) > 0.3 { f.append(b.centroidX < 0 ? "most visual weight sits on the left" : "most visual weight sits on the right") }
            if abs(b.centroidY) > 0.4 { f.append(b.centroidY < 0 ? "weight is pushed to the top" : "weight is pushed to the bottom") }
            if b.leftRight < 0.5 { f.append("left and right halves differ a lot in weight") }
            if b.symmetry < 0.8 { f.append("the two halves do not mirror each other") }
            out["balance"] = f
        }
        let text = boxes.filter { !["demo", "logo"].contains($0.role) }
        if text.count >= 4 {
            let a = alignment(text, imageWidth: imageWidth); var f: [String] = []
            if a.alignedShare < 0.5 { f.append("under half the text sits on a shared edge or row") }
            if a.topLinesShare < 0.35 { f.append("text is spread over many different edges") }
            if a.gapRegularity < 0.4 { f.append("spacing between stacked lines is uneven") }
            out["alignment"] = f
        }
        return out
    }
}
