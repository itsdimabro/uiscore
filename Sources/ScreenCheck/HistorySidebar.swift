import SwiftUI
import ScreenCheckCore

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
                        ForEach(m.history) { h in HistoryRow(m: m, h: h, now: now).transition(.opacity.combined(with: .move(edge: .top))) }
                        if m.history.isEmpty { Text("No checks yet.").font(.system(size: 11)).foregroundStyle(T.ink2).padding(8) }
                    }
                    .padding(.leading, 8).padding(.trailing, 16)
                    .animation(T.open(0.35), value: m.history.map(\.id))
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
        let selected = m.current?.id == h.result.id && !h.pending
        let hot = hover || m.demoHover == h.id
        HStack(spacing: 10) {
            if let i = h.imageURL.flatMap({ m.thumb($0) }) { Image(nsImage: i).resizable().scaledToFill().frame(width: 72, height: 45).clipShape(RoundedRectangle(cornerRadius: 5)) }
            else { RoundedRectangle(cornerRadius: 5).fill(T.track).frame(width: 72, height: 45) }
            VStack(alignment: .leading, spacing: 0) {
                if h.result.pageName.isEmpty { Bar(w: 90, h: 11).padding(.vertical, 1.5) }
                else { Text(h.result.pageName).font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink).lineLimit(1) }
                Text(RelativeDate.label(for: h.result.createdAt, now: now)).font(.system(size: 11)).foregroundStyle(T.ink2).lineLimit(1)
                if h.pending && !h.scoreReady { Bar(w: 44, h: 10).padding(.vertical, 1) }
                else { Text("Score \(h.result.overallScore)").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.score(h.result.overallScore, scheme)) }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? T.soft : (hot ? T.hoverSoft : .clear)))
        .overlay(alignment: .topTrailing) {
            if hot && !h.pending {
                Button { m.delete(h) } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .medium)).foregroundStyle(T.ink2).frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.card))
                }.buttonStyle(.plain).focusable(false).accessibilityLabel("Delete").padding(6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .focusable(false)
        .onTapGesture { if !h.pending { m.select(h) } }
        .onHover { hover = $0 }
        .contextMenu { if !h.pending { Button("Delete", role: .destructive) { m.delete(h) } } }
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
