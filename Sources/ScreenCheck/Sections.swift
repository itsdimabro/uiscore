import SwiftUI
import ScreenCheckCore

struct Sections: View {
    @ObservedObject var m: AppModel
    let r: RunResult
    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Panel(title: "Visual", stretch: true) { MeterColumn { ForEach(Meters.visual.filter { !(r.meters["first"] != nil && Rubric.layoutKeys.contains($0)) && !($0 == "grouping" && r.meters["alignment"] != nil && r.meters["grouping"] == nil) }, id: \.self) { MeterRow(m: m, r: r, k: $0, right: false) } } }.lifted(m, Meters.visual).modifier(Stagger(i: 0, on: m.shown))
                Panel(title: "Visual + Copy", stretch: true) { MeterColumn { ForEach(Meters.visualCopy, id: \.self) { MeterRow(m: m, r: r, k: $0, right: true) } } }.lifted(m, Meters.visualCopy).modifier(Stagger(i: 1, on: m.shown))
            }.fixedSize(horizontal: false, vertical: true).zIndex(2)
            HStack(alignment: .top, spacing: 10) {
                Panel(title: "Copy", stretch: true) { ReadingView(m: m, r: r) }.lifted(m, ["reading"]).modifier(Stagger(i: 2, on: m.shown))
                Panel(title: "Feeling", legend: true, stretch: true) { FeelingView(m: m, r: r) }.lifted(m, ["feel-v","feel-a"]).modifier(Stagger(i: 3, on: m.shown))
            }.fixedSize(horizontal: false, vertical: true).zIndex(m.tipKey == "reading" ? 3 : 0)
        }
        .zIndex(1)
    }
}

/// Rows sit on a fixed grid from the top of the panel, so both top panels line up row for row; spare height stays at the bottom.
struct MeterColumn<C: View>: View {
    @ViewBuilder var content: C
    var body: some View { VStack(spacing: 12) { content }.frame(maxHeight: .infinity, alignment: .top) }
}

extension View {
    func lifted(_ m: AppModel, _ keys: [String]) -> some View { zIndex(keys.contains(m.tipKey ?? "") ? 5 : 0) }
}

func tipContent(m: AppModel, r: RunResult, k: String) -> some View {
    let t = r.text[k]
    let na = r.meters[k]?.applicable == false
    let score = r.meters[k]?.score ?? (k == "reading" ? (r.readingGrade.map { Int((Pipeline.gradePoints($0) * 10).rounded()) } ?? 100) : 0)
    let fix = t?.fix.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let showFix = !na && score < 100 && !fix.isEmpty && !fix.lowercased().hasPrefix("nothing to fix")
    return VStack(alignment: .leading, spacing: 7) {
        TipEyebrow(text: Meters.definitions[k] ?? "")
        TipDivider()
        if na { TipLine(label: "Results", text: "This doesn't apply to this kind of screen.") }
        else if let t, !t.why.isEmpty {
            TipLine(label: "Results", text: t.why)
            if showFix { TipLine(label: "Fix", text: fix) }
        } else { TipLine(label: "Results", text: "Writing this now…") }
        if let n = UserNotice.text(r.meters[k]?.note) { TipLine(label: "Notice", text: n) }
    }
}

/// `MeterResult.note` carries pipeline details; only notes listed in `userFacing` are shown to the user.
enum UserNotice {
    static let userFacing: Set<String> = []
    static func text(_ note: String?) -> String? {
        guard let n = note?.trimmingCharacters(in: .whitespacesAndNewlines), userFacing.contains(n) else { return nil }
        return n
    }
}
