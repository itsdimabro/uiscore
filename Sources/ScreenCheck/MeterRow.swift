import SwiftUI
import ScreenCheckCore

/// Wraps a value that lands when `on` turns true. `shown` flips with the approved ease after a small per-item stagger;
/// a stored result starts with `shown` already true, so nothing grows or counts up.
struct Lands<C: View>: View {
    let on: Bool; let instant: Bool; var index = 0
    @ViewBuilder let content: (Bool) -> C
    @State private var shown: Bool
    init(on: Bool, instant: Bool, index: Int = 0, @ViewBuilder content: @escaping (Bool) -> C) {
        self.on = on; self.instant = instant; self.index = index; self.content = content
        _shown = State(initialValue: on && instant)
    }
    var body: some View {
        content(shown)
            .onAppear { if on && !shown { fire() } }
            .onChange(of: on) { v in if v { fire() } else { shown = false } }
    }
    private func fire() {
        if instant || T.reduceMotion { var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { shown = true }; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(index)) { withAnimation(T.open(0.5)) { shown = true } }
    }
}

struct MeterRow: View {
    @ObservedObject var m: AppModel
    let r: RunResult; let k: String; let right: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let score = r.meters[k]?.score ?? 0
        let na = r.meters[k]?.applicable == false
        let idx = Meters.order.firstIndex(of: k) ?? 0
        Lands(on: m.ready.contains(k), instant: m.instant, index: idx % 4) { shown in
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .top, spacing: 5) {
                    Text(Meters.names[k] ?? k).font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink)
                    InfoMark(key: k, m: m).opacity(shown ? 1 : 0).allowsHitTesting(shown)
                }
                Spacer()
                ZStack(alignment: .trailing) {
                    Bar(w: 26, h: 12).opacity(shown ? 0 : 1)
                    if na { Text("—").font(.system(size: 15, weight: .bold)).foregroundStyle(T.ink.opacity(0.4)).opacity(shown ? 1 : 0) }
                    else { CountText(value: shown ? score : 0).font(.system(size: 15, weight: .bold)).foregroundStyle(T.ink).opacity(shown ? 1 : 0) }
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(T.track)
                    Capsule().fill(shown ? T.score(score, scheme) : T.track).frame(width: na || !shown ? 0 : g.size.width * CGFloat(score) / 100)
                }
            }.frame(height: 7)
        }
        .tipOverlay(m, active: m.tipKey == k && shown, trailing: right) { tipContent(m: m, r: r, k: k) }
        .zIndex(m.tipKey == k ? 30 : 0)
        }
    }
}

/// A row whose value does not exist yet: name stays, bar and number shimmer.
struct PendingRow: View {
    let name: String
    var body: some View {
        VStack(spacing: 5) {
            HStack { Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink); Spacer(); Bar(w: 26, h: 12) }
            Bar(h: 7)
        }
    }
}

struct Stagger: ViewModifier {
    let i: Int; let on: Bool
    @State private var shown = false
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 8)
            .onChange(of: on) { v in
                if v { DispatchQueue.main.asyncAfter(deadline: .now() + (T.reduceMotion ? 0 : 0.06 * Double(i))) { withAnimation(T.open(0.4)) { shown = true } } } else { shown = false }
            }
            .onAppear { if on { DispatchQueue.main.asyncAfter(deadline: .now() + (T.reduceMotion ? 0 : 0.06 * Double(i) + 0.05)) { withAnimation(T.open(0.4)) { shown = true } } } }
    }
}

struct CountText: View, Animatable {
    var value: Int
    var animatableData: Double { get { Double(value) } set { value = Int(newValue.rounded()) } }
    init(value: Int) { self.value = value }
    var body: some View { Text("\(value)").monospacedDigit() }
}
