import SwiftUI
import ScreenCheckCore

struct ReadingView: View {
    @ObservedObject var m: AppModel
    let r: RunResult
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Lands(on: m.ready.contains("reading"), instant: m.instant) { shown in readingBody(shown) }
    }
    /// Readability, not grade: full at grade 9 or lower, shrinking along the core's gradePoints curve to empty at 12 or higher.
    static func ringFill(_ grade: Int) -> Double {
        if grade >= 12 { return 0 }
        let top = Pipeline.gradePoints(9), low = Pipeline.gradePoints(12)
        return min(1, max(0, (Pipeline.gradePoints(grade) - low) / (top - low)))
    }
    @ViewBuilder func readingBody(_ shown: Bool) -> some View {
        let g = r.readingGrade
        let frac = shown ? (g.map { Self.ringFill($0) } ?? 1) : 0
        let ring = shown ? (g.map { T.grade($0, scheme) } ?? T.ink2.opacity(0.4)) : T.track
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(T.track, lineWidth: 8)
                Circle().trim(from: 0, to: frac).stroke(ring, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                ZStack {
                    Bar(w: 34, h: 22).opacity(shown ? 0 : 1)
                    Text(g.map { $0 >= 12 ? "12+" : String($0) } ?? "–").font(.system(size: 22, weight: .bold)).foregroundStyle(T.ink).opacity(shown ? 1 : 0)
                }
            }.frame(width: 90, height: 90)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 5) {
                    Text("Reading level").font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink)
                    if r.text["reading"].map({ !$0.why.isEmpty }) ?? false { InfoMark(key: "reading", m: m).opacity(shown ? 1 : 0).allowsHitTesting(shown) }
                }
                ZStack(alignment: .leading) {
                    Bar(w: 70, h: 10).opacity(shown ? 0 : 1)
                    Text(g == nil ? "Too little copy" : "grade level").font(.system(size: 11)).foregroundStyle(T.ink2).opacity(shown ? 1 : 0)
                }
            }
            .tipOverlay(m, active: m.tipKey == "reading" && shown, trailing: false) { tipContent(m: m, r: r, k: "reading") }
            .zIndex(m.tipKey == "reading" ? 30 : 0)
        }
    }
}
