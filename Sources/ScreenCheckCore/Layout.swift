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

public struct GroupingMetrics: Codable, Equatable {
    public var boxes: Int = 0
    public var groups: Int = 0              // clusters after cutting gaps of 1.5x the typical gap or more
    public var groupedShare: Double = 0     // share of boxes inside a group of 2+ boxes
    public var ambiguousShare: Double = 0   // share of gaps between 1.2x and 1.5x the typical gap (neither within nor between)
    public var separation: Double = 1       // median between-group gap / typical within-group gap
    public var regionShare: Double = 0      // share of boxes sitting on a non-page background
    public var regionAgreement: Double = 1  // share of region-holding groups whose boxes share one background
    public var styleShare: Double = 1       // share of boxes matching their group's dominant size, weight and colour
    public var alignment = AlignmentMetrics()
    public init() {}
}

extension Layout {
    static func edgeGap(_ a: TextBox, _ b: TextBox) -> Double {
        let dx = max(0, max(a.x, b.x) - min(a.x + a.w, b.x + b.w)), dy = max(0, max(a.y, b.y) - min(a.y + a.h, b.y + b.h))
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Gestalt grouping cues from OCR boxes and pixels: proximity (Wertheimer 1923; Kubovy 1998 ratio 1.5), common region (Palmer 1992),
    /// similarity, and the shared lines of `alignment`. Deterministic: same boxes and pixels, same numbers.
    public static func grouping(_ all: [TextBox], pixels: Pixels?, imageWidth: Int) -> GroupingMetrics {
        var m = GroupingMetrics()
        let b = all.filter { $0.h >= 6 && $0.w >= 8 }
        m.boxes = b.count
        m.alignment = alignment(b, imageWidth: imageWidth)
        guard b.count >= 2 else { return m }
        // Minimum spanning tree edges (Prim); its gaps are the single-linkage grouping gaps.
        var inTree = [Bool](repeating: false, count: b.count), best = [Double](repeating: .infinity, count: b.count), from = [Int](repeating: -1, count: b.count)
        best[0] = 0
        var edges: [(Int, Int, Double)] = []
        for _ in 0..<b.count {
            var u = -1
            for i in b.indices where !inTree[i] && (u < 0 || best[i] < best[u]) { u = i }
            inTree[u] = true
            if from[u] >= 0 { edges.append((from[u], u, best[u])) }
            for v in b.indices where !inTree[v] { let g = edgeGap(b[u], b[v]); if g < best[v] { best[v] = g; from[v] = u } }
        }
        let med = max(4, edges.map { $0.2 }.sorted()[edges.count / 2])
        var parent = Array(b.indices)
        func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
        for e in edges where e.2 < 1.5 * med { parent[find(e.0)] = find(e.1) }
        let ids = b.indices.map { find($0) }
        var members: [Int: [Int]] = [:]
        for i in b.indices { members[ids[i], default: []].append(i) }
        m.groups = members.count
        m.groupedShare = Double(members.values.filter { $0.count >= 2 }.reduce(0) { $0 + $1.count }) / Double(b.count)
        m.ambiguousShare = Double(edges.filter { $0.2 >= 1.2 * med && $0.2 < 1.5 * med }.count) / Double(edges.count)
        var between: [Double] = []
        for (id, mem) in members {
            var nearest = Double.infinity
            for i in mem { for j in b.indices where ids[j] != id { nearest = min(nearest, edgeGap(b[i], b[j])) } }
            if nearest.isFinite { between.append(nearest) }
        }
        m.separation = between.isEmpty ? 1 : between.sorted()[between.count / 2] / med
        // Similarity: size within 20%, same weight, colour within 80 (RGB distance) of the group's dominant style.
        var fg: [Int: (Int, Int, Int)] = [:], bgc: [Int: (Int, Int, Int)] = [:]
        if let px = pixels { for i in b.indices { if let s = Contrast.clusterSample(px, box: b[i]) { fg[i] = s.fg; bgc[i] = s.bg } } }
        func close(_ p: (Int, Int, Int), _ q: (Int, Int, Int)) -> Bool { abs(p.0 - q.0) + abs(p.1 - q.1) + abs(p.2 - q.2) <= 80 }
        var matching = 0, counted = 0
        for mem in members.values where mem.count >= 2 {
            func sim(_ i: Int, _ j: Int) -> Bool {
                let r = b[i].fontPx / max(1, b[j].fontPx)
                return r >= 0.8 && r <= 1.25 && b[i].bold == b[j].bold && (fg[i] == nil || fg[j] == nil || close(fg[i]!, fg[j]!))
            }
            let dom = mem.max { a, c in
                let na = mem.filter { sim($0, a) }.count, nc = mem.filter { sim($0, c) }.count
                return na != nc ? na < nc : a > c
            }!
            counted += mem.count; matching += mem.filter { sim($0, dom) }.count
        }
        m.styleShare = counted == 0 ? 1 : Double(matching) / Double(counted)
        // Common region: boxes whose own background differs from the page background; groups should sit on one region each.
        if let px = pixels, !bgc.isEmpty {
            let page = pageBackground(px)
            func off(_ i: Int) -> Bool { guard let c = bgc[i] else { return false }; return abs(c.0 - page.0) + abs(c.1 - page.1) + abs(c.2 - page.2) > 24 }
            m.regionShare = Double(bgc.keys.filter { off($0) }.count) / Double(b.count)
            var holders = 0, agree = 0
            for mem in members.values {
                let known = mem.filter { bgc[$0] != nil }
                guard known.contains(where: off) else { continue }
                holders += 1
                let first = bgc[known[0]]!
                if known.allSatisfy({ abs(bgc[$0]!.0 - first.0) + abs(bgc[$0]!.1 - first.1) + abs(bgc[$0]!.2 - first.2) <= 24 }) { agree += 1 }
            }
            m.regionAgreement = holders == 0 ? 1 : Double(agree) / Double(holders)
        }
        return m
    }

    static func pageBackground(_ px: Pixels) -> (Int, Int, Int) {
        var counts: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for y in stride(from: 0, to: px.height, by: 4) { for x in stride(from: 0, to: px.width, by: 4) {
            let i = (y * px.width + x) * 4
            let r = Int(px.data[i]), g = Int(px.data[i + 1]), bl = Int(px.data[i + 2])
            let k = (r >> 3) << 10 | (g >> 3) << 5 | (bl >> 3)
            let e = counts[k] ?? (0, 0, 0, 0)
            counts[k] = (e.n + 1, e.r + r, e.g + g, e.b + bl)
        } }
        let t = counts.max { a, c in a.value.n != c.value.n ? a.value.n < c.value.n : a.key > c.key }!.value
        return (t.r / t.n, t.g / t.n, t.b / t.n)
    }

    /// Grouping checks: id, weight, pass (nil = not applicable). Weights sum to 100.
    public static func groupingChecks(_ m: GroupingMetrics) -> [(id: String, weight: Int, pass: Bool?)] {
        [("g_prox", 35, m.groups >= 2 && m.groups <= 24 && m.groupedShare >= 0.6 && m.ambiguousShare <= 0.25 && m.separation >= 1.5),
         ("g_align", 25, m.alignment.alignedShare >= 0.5 && m.alignment.topLinesShare >= 0.35),
         ("g_region", 20, m.regionShare < 0.15 ? nil : m.regionAgreement >= 0.75),
         ("g_sim", 20, m.styleShare >= 0.6)]
    }
    public static func groupingScore(_ m: GroupingMetrics) -> Int {
        let cs = groupingChecks(m).filter { $0.pass != nil }
        let tot = cs.reduce(0) { $0 + $1.weight }
        return Int((Double(cs.filter { $0.pass == true }.reduce(0) { $0 + $1.weight }) * 100 / Double(max(1, tot))).rounded())
    }
    static func groupingResult(_ m: GroupingMetrics) -> MeterResult {
        let cs = groupingChecks(m).filter { $0.pass != nil }
        return MeterResult(score: groupingScore(m), lowConfidence: false, confidencePct: 100,
                           checks: cs.map { CheckResult(id: $0.id, yes: $0.pass!, p: nil, weight: $0.weight, kind: "code") }, note: nil)
    }
    static let groupingFailures: [String: String] = [
        "g_prox": "gaps inside groups and between groups are too alike, so groups blur together",
        "g_align": "text does not share a few clear left, right or centre lines",
        "g_region": "groups do not sit on shared cards or panels",
        "g_sim": "items in one group differ in size, weight or colour",
    ]
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
            out["grouping"] = groupingResult(grouping(text, pixels: pixels, imageWidth: imageWidth))
        } else {
            out["grouping"] = MeterResult(score: 0, lowConfidence: false, confidencePct: 100, checks: [], note: nil, applicable: false)
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
            let g = grouping(text, pixels: pixels, imageWidth: imageWidth)
            out["grouping"] = groupingChecks(g).filter { $0.pass == false }.compactMap { groupingFailures[$0.id] }
        }
        return out
    }
}
