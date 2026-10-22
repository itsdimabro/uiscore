import Foundation

extension Pipeline {
    static let requiredFields = ["page_type", "screen_kind", "tone", "blocks", "fonts", "main_text_alignment", "nav_position", "logo_position", "panels", "columns",
                                 "first_fixation", "emphasis", "primary_buttons", "corner_style", "heaviest_weight", "roles"]
    /// The model sometimes answers `primary` as a list, sometimes as a bare id or a string id. Only a real box id counts.
    static func primaryID(_ v: JSONValue, count: Int) -> Int? {
        let p = v["roles"]["primary"]
        let id = p.array.first?.int ?? p.int ?? p.string.flatMap { Int($0) }
        if let id, (0..<count).contains(id) { return id }
        return nil
    }
    /// Field-by-field vote. Equal counts break by sorted value, so the result never depends on reply order.
    static func majority(_ rs: [JSONValue]) -> JSONValue {
        guard rs.count > 1, case .object(let first) = rs[0] else { return rs[0] }
        var out: [String: JSONValue] = [:]
        for k in first.keys.sorted() {
            if k == "roles" {
                var roles: [String: JSONValue] = [:]
                for role in rs.flatMap({ r -> [String] in if case .object(let o) = r["roles"] { return Array(o.keys) }; return [] }) where roles[role] == nil {
                    if role == "primary" {
                        let ids = rs.compactMap { primaryID($0, count: Int.max) }
                        let best = Dictionary(grouping: ids, by: { $0 }).max { ($0.value.count, -$0.key) < ($1.value.count, -$1.key) }
                        roles[role] = best.map { $0.value.count * 2 > rs.count ? .array([.number(Double($0.key))]) : .array([]) } ?? .array([])
                    } else {
                        var votes: [Int: Int] = [:]
                        for r in rs { for v in r["roles"][role].array { if let i = v.int { votes[i, default: 0] += 1 } } }
                        roles[role] = .array(votes.filter { $0.value * 2 > rs.count }.keys.sorted().map { .number(Double($0)) })
                        if role == "logo" {
                            let heads = Set(rs.flatMap { $0["roles"]["heading"].array.compactMap { $0.int } }.filter { id in rs.filter { $0["roles"]["heading"].array.contains { $0.int == id } }.count * 2 > rs.count })
                            roles[role] = .array(roles[role]!.array.filter { !heads.contains($0.int ?? -1) })
                        }
                    }
                }
                out[k] = .object(roles)
                continue
            }
            var counts: [String: (n: Int, v: JSONValue)] = [:]
            for r in rs { let v = r[k]; let key = String(describing: v); counts[key] = (( counts[key]?.n ?? 0) + 1, v) }
            out[k] = counts.sorted { ($0.value.n, $1.key) > ($1.value.n, $0.key) }.first!.value.v
        }
        return .object(out)
    }
    static func isComplete(_ v: JSONValue) -> Bool { requiredFields.allSatisfy { v[$0] != .null } }
}
