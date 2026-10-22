import SwiftUI
import ScreenCheckCore

struct FeelingView: View {
    @ObservedObject var m: AppModel
    let r: RunResult
    var body: some View {
        let on = m.ready.contains("feeling")
        let f = { (k: String) in Double(r.feeling[k] ?? 50) / 100 }
        VStack(alignment: .leading, spacing: 14) {
            Lands(on: on, instant: m.instant, index: 0) { shown in
                FeelRow(m: m, r: r, shown: shown, key: "feel-v", name: "Valence", lo: "unpleasant", hi: "pleasant", vis: f("vv"), cop: f("cv"), expl: "Does it feel good or bad?")
            }
            Lands(on: on, instant: m.instant, index: 1) { shown in
                FeelRow(m: m, r: r, shown: shown, key: "feel-a", name: "Intensity", lo: "excited", hi: "calm", vis: 1 - f("vi"), cop: 1 - f("ci"), expl: "Does it feel calm or exciting?")
            }
        }
    }
}

/// Neutral ink dot with a thin panel-coloured outline so it reads on the gradient. Filled = Visual, ring = Copy.
struct FeelDot: View {
    let ring: Bool
    var size: CGFloat = 13
    var body: some View {
        ZStack {
            if ring {
                Circle().strokeBorder(T.soft, lineWidth: 4.5)
                Circle().strokeBorder(T.ink, lineWidth: 2).padding(1.25)
            } else {
                Circle().fill(T.soft)
                Circle().fill(T.ink).padding(1.5)
            }
        }
        .frame(width: size, height: size)
    }
}

struct FeelRow: View {
    @ObservedObject var m: AppModel
    let r: RunResult
    let shown: Bool
    let key: String, name: String, lo: String, hi: String; let vis: Double, cop: Double
    let expl: String
    var textKey: String { key == "feel-v" ? "valence" : "intensity" }
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var feelTip: some View {
        TipEyebrow(text: expl); TipDivider()
        if let t = r.text[textKey], !t.why.isEmpty { TipLine(label: "Results", text: t.why) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 5) {
                Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink)
                if r.text[textKey].map({ !$0.why.isEmpty }) ?? false { InfoMark(key: key, m: m).opacity(shown ? 1 : 0).allowsHitTesting(shown) }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(T.track).frame(height: 4)
                    Capsule().fill(T.feelGradient(scheme)).frame(height: 4).opacity(shown ? 1 : 0)
                    FeelDot(ring: false).offset(x: g.size.width * (shown ? vis : 0.5) - 6.5).opacity(shown ? 1 : 0)
                    FeelDot(ring: true).offset(x: g.size.width * (shown ? cop : 0.5) - 6.5).opacity(shown ? 1 : 0)
                }
            }.frame(height: 13)
            HStack { Text(lo); Spacer(); Text(hi) }.font(.system(size: 11)).foregroundStyle(T.ink2)
        }
        .tipOverlay(m, active: m.tipKey == key && shown, trailing: true) { feelTip }
        .zIndex(m.tipKey == key ? 30 : 0)
    }
}
