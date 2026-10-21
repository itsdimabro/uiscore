import Foundation

/// History row timestamps: "Just now", "23m ago", "3h ago", "Yesterday · 3:30pm", "Oct 17 · 4:15am", "Oct 17, 2025 · 4:15am".
public enum RelativeDate {
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    public static func label(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "Just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let h = c.hour ?? 0
        let time = "\((h % 12 == 0) ? 12 : h % 12):\(String(format: "%02d", c.minute ?? 0))\(h < 12 ? "am" : "pm")"
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday · \(time)" }
        var day = "\(months[(c.month ?? 1) - 1]) \(c.day ?? 1)"
        if c.year != calendar.component(.year, from: now) { day += ", \(c.year ?? 0)" }
        return "\(day) · \(time)"
    }
}
