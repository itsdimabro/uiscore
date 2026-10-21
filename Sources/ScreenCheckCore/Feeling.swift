import Foundation

public enum Feeling {
    public static func score(_ results: [CheckResult], checks: [Check]) -> Int {
        var s = 50
        for r in results where r.yes {
            guard let c = checks.first(where: { $0.id == r.id }) else { continue }
            s += c.pushes == "high" ? c.w : -c.w
        }
        return min(100, max(0, s))
    }
}
