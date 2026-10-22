import Foundation

public struct Check: Codable {
    public let meter: String
    public let id: String
    public let q: String
    public let yes: String
    public let w: Int
    public let kind: String
    public let jev: String
    public let pushes: String?    // feeling checks: "high" / "low"
    public let fix: String
}

public enum Rubric {
    public static let checks: [Check] = {
        try! JSONDecoder().decode([Check].self, from: Data(rubricJSON.utf8))
    }()
    public static func checks(for meter: String) -> [Check] { checks.filter { $0.meter == meter } }
    /// Display meters scored by yes/no checks, in card order.
    public static let meterKeys = ["order", "contrast", "familiar", "ease", "clarity", "trust"]
    /// Code-only meters, not in the rubric JSON (see Layout).
    public static let layoutKeys = ["balance", "grouping"]
    public static let feelingKeys = ["vv", "vi", "cv", "ci"]
}
