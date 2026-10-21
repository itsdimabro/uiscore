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

/// `MeterResult.note` is also used for pipeline details ("rated from the screenshot, 3 votes", measurement coverage).
/// Only notes that are written for the user are shown; no note is user-facing today, so nothing appears.
enum UserNotice {
    static let userFacing: Set<String> = []
    static func text(_ note: String?) -> String? {
        guard let n = note?.trimmingCharacters(in: .whitespacesAndNewlines), userFacing.contains(n) else { return nil }
        return n
    }
}

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

struct HistorySidebar: View {
    @ObservedObject var m: AppModel
    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    /// 0...1: how far the content is from the top / bottom edge, in units of the fade height. Follows the scroll offset directly.
    @State private var topFade: CGFloat = 0
    @State private var bottomFade: CGFloat = 0
    private var fadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(1 - topFade), .black], startPoint: .top, endPoint: .bottom).frame(height: LeftScroller.fade)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(1 - bottomFade)], startPoint: .top, endPoint: .bottom).frame(height: LeftScroller.fade)
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("History").font(.system(size: 17, weight: .bold)).foregroundStyle(T.ink).padding(.horizontal, 8).padding(.bottom, 12)
                // Layout flipped so the overlay scroller sits on the left; the content is flipped back.
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(m.history) { h in HistoryRow(m: m, h: h, now: now) }
                        if m.history.isEmpty { Text("No checks yet.").font(.system(size: 11)).foregroundStyle(T.ink2).padding(8) }
                    }
                    .padding(.leading, 8).padding(.trailing, 16)
                    .environment(\.layoutDirection, .leftToRight)
                }
                .environment(\.layoutDirection, .rightToLeft)
                .mask(fadeMask)
                .background(LeftScroller(top: $topFade, bottom: $bottomFade))
                if let u = m.undoItem { UndoToast(m: m, name: u.result.pageName, progress: m.undoProgress.map { CGFloat($0) }).id(u.id).transition(.opacity) }
            }
            .frame(width: 218)
            Rectangle().fill(T.hair).frame(width: 1)
            Spacer().frame(width: 18)
        }
        .frame(width: CardView.sidebarWidth).frame(maxHeight: .infinity)
        .onReceive(tick) { now = $0 }
        .onAppear { now = Date() }
    }
}

struct HistoryRow: View {
    @ObservedObject var m: AppModel
    let h: HistoryItem
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false
    var now: Date
    var body: some View {
        let selected = m.current?.id == h.id
        let hot = hover || m.demoHover == h.id
        HStack(spacing: 10) {
            if let i = m.thumb(h.imageURL) { Image(nsImage: i).resizable().scaledToFill().frame(width: 72, height: 45).clipShape(RoundedRectangle(cornerRadius: 5)) }
            else { RoundedRectangle(cornerRadius: 5).fill(T.track).frame(width: 72, height: 45) }
            VStack(alignment: .leading, spacing: 0) {
                Text(h.result.pageName).font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink).lineLimit(1)
                Text(RelativeDate.label(for: h.result.createdAt, now: now)).font(.system(size: 11)).foregroundStyle(T.ink2).lineLimit(1)
                Text("Score \(h.result.overallScore)").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.score(h.result.overallScore, scheme))
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? T.soft : (hot ? T.hoverSoft : .clear)))
        .overlay(alignment: .topTrailing) {
            if hot {
                Button { m.delete(h) } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .medium)).foregroundStyle(T.ink2).frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.card))
                }.buttonStyle(.plain).focusable(false).accessibilityLabel("Delete").padding(6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .focusable(false)
        .onTapGesture { m.select(h) }
        .onHover { hover = $0 }
        .contextMenu { Button("Delete", role: .destructive) { m.delete(h) } }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
    }
}

/// Thin overlay scroller (right-to-left layout puts it on the left); knob kept faint. Also reports whether content lies above/below the viewport.
struct LeftScroller: NSViewRepresentable {
    static let fade: CGFloat = 32
    @Binding var top: CGFloat
    @Binding var bottom: CGFloat
    func makeCoordinator() -> Coord { Coord() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ v: NSView, context: Context) {
        context.coordinator.top = $top; context.coordinator.bottom = $bottom
        find(v, tries: 20, context: context)
    }
    private func find(_ v: NSView, tries: Int, context: Context) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (tries == 20 ? 0 : 0.05)) {
            func search(_ x: NSView) -> NSScrollView? {
                if let s = x as? NSScrollView { return s }
                for c in x.subviews { if let s = search(c) { return s } }
                return nil
            }
            guard let sv = v.window?.contentView.flatMap(search) else { if tries > 0 { find(v, tries: tries - 1, context: context) }; return }
            sv.scrollerStyle = .overlay; sv.scrollerKnobStyle = .default
            sv.verticalScroller?.controlSize = .mini; sv.verticalScroller?.alphaValue = 0.45
            context.coordinator.attach(sv)
        }
    }
    final class Coord: NSObject {
        var top: Binding<CGFloat>?; var bottom: Binding<CGFloat>?
        weak var sv: NSScrollView?
        func attach(_ s: NSScrollView) {
            if sv === s { report(); return }
            sv = s
            s.contentView.postsBoundsChangedNotifications = true
            s.documentView?.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSView.boundsDidChangeNotification, object: s.contentView)
            if let d = s.documentView { NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSView.frameDidChangeNotification, object: d) }
            report()
        }
        @objc func changed() { report() }
        func report() {
            guard let s = sv, let d = s.documentView else { return }
            let b = s.contentView.bounds
            let above = max(0, b.minY), below = max(0, d.frame.height - b.maxY)
            // documents may be flipped; "top" is the visual top either way
            let (t, bt) = d.isFlipped ? (above, below) : (below, above)
            let ts = min(1, t / LeftScroller.fade), bs = min(1, bt / LeftScroller.fade)
            var tx = Transaction(); tx.disablesAnimations = true
            withTransaction(tx) {
                if self.top?.wrappedValue != ts { self.top?.wrappedValue = ts }
                if self.bottom?.wrappedValue != bs { self.bottom?.wrappedValue = bs }
            }
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

/// Undo toast: a grey container whose fill grows linearly over the undo window; the whole container undoes.
struct UndoToast: View {
    @ObservedObject var m: AppModel
    let name: String
    @State private var filled = false
    var progress: CGFloat? = nil
    var body: some View {
        let p = progress ?? (filled ? 1 : 0)
        Button { m.undoDelete() } label: {
            ZStack(alignment: .leading) {
                GeometryReader { g in
                    Rectangle().fill(T.toastFill).frame(width: g.size.width * p)
                }
                HStack {
                    Text("Deleted \(name)").font(.system(size: 12)).foregroundStyle(T.ink2).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("Undo").font(.system(size: 12, weight: .semibold)).foregroundStyle(T.ink)
                }.padding(.horizontal, 12)
            }
            .frame(height: 36)
            .background(T.soft)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain).focusable(false).accessibilityLabel("Undo delete")
        .onAppear { if progress == nil { withAnimation(.linear(duration: PendingDeletions.window)) { filled = true } } }
    }
}
