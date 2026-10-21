import SwiftUI
import ScreenCheckCore

struct CardView: View {
    @ObservedObject var m: AppModel

    /// Room around the card inside the transparent window; bigger than the shadow (radius 28, offset 14) so it is never cut.
    static let inset: CGFloat = 96
    static let sidebarWidth: CGFloat = 237
    /// The window never resizes: it holds the widest card (history open) and the tallest one, so nothing clips and nothing glitches.
    static let windowSize = CGSize(width: 664 + 36 + sidebarWidth + 2 * inset, height: 612 + 2 * inset)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // The sidebar is an overlay of a clear spacer, so it takes the main column's height and never adds any.
            Color.clear.frame(width: m.historyOpen ? Self.sidebarWidth : 0)
                .overlay(alignment: .trailing) { HistorySidebar(m: m).frame(width: Self.sidebarWidth) }
                .clipped()
                .opacity(m.historyOpen ? 1 : 0)
                .allowsHitTesting(m.historyOpen)
            MainColumn(m: m)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlayPreferenceValue(TipSpecKey.self) { TipHost(m: m, specs: $0) }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.card))
        .background(GeometryReader { g in
            Color.clear.onAppear { m.cardFrame = g.frame(in: .global) }.onChange(of: g.size) { _ in m.cardFrame = g.frame(in: .global) }
        })
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(T.hair, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(CardShadow())
        .scaleEffect(m.shown ? 1 : 0.96, anchor: .top)
        .opacity(m.shown ? 1 : 0)
        .padding(Self.inset)
        // Right edge stays put; History adds width on the left.
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .topTrailing)
    }
}

/// The shadow is its own shape behind the card, blurred from the card's outline alone. It used to be applied to the clipped group
/// that also holds the sliding history column, the lightbox and the scale/opacity animation, so it was rasterised with whatever
/// that group's bounds were at that moment. Now it never depends on them.
struct CardShadow: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.card)
            .shadow(color: T.shadow, radius: 28, y: 14)
    }
}

struct MainColumn: View {
    @ObservedObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(m: m)
            switch m.phase {
            case .error(let msg, let retry): ErrorView(message: msg, retry: retry) { m.checkLatest() }
            case .idle: ErrorView(message: "Take a screenshot or copy any image, then press Command + Shift + V.", retry: false) {}
            case .loading, .ready: Sections(m: m, r: m.current ?? .placeholder)
            }
        }
        .frame(width: 664)
    }
}

/// Score: a skeleton while the run is going, then the number counts up once every meter and the tooltip text are in.
struct ScoreHead: View {
    @ObservedObject var m: AppModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let done = m.scoresDone
        let running = { if case .loading = m.phase { return true }; return m.textPending }()
        if done || running {
            let o = m.current?.overallScore ?? 0
            Lands(on: done, instant: m.instant, index: 0) { shown in
                VStack(alignment: .trailing, spacing: 0) {
                    ZStack(alignment: .trailing) {
                        Bar(w: 44, h: 26).opacity(shown ? 0 : 1)
                        CountText(value: shown ? o : 0).font(.system(size: 28, weight: .bold)).foregroundStyle(T.score(o, scheme)).opacity(shown ? 1 : 0)
                    }
                    Text("Score").font(.system(size: 11)).foregroundStyle(T.ink2)
                }
            }
            .padding(.trailing, 6)
        }
    }
}

struct Header: View {
    @ObservedObject var m: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var infoHover = false
    var body: some View {
        HStack(spacing: 12) {
            if let url = m.currentImage, let img = m.thumb(url) {
                Button { m.openLightbox() } label: {
                    Image(nsImage: img).resizable().scaledToFill().frame(width: 80, height: 50).clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: T.shadow.opacity(0.5), radius: 2, y: 1)
                }.buttonStyle(PressStyle()).focusable(false).accessibilityLabel("View screenshot larger")
            } else {
                RoundedRectangle(cornerRadius: 6).fill(T.soft).frame(width: 80, height: 50)
            }
            VStack(alignment: .leading, spacing: 0) {
                if (m.current?.pageName ?? "").isEmpty { Bar(w: 120, h: 14).transition(.opacity); Bar(w: 80, h: 10).padding(.top, 6).transition(.opacity) }
                else {
                    HStack(alignment: .top, spacing: 5) {
                        TitleView(m: m)
                        if let note = m.demoNote ?? m.current?.uiContextNote {
                            InfoMark(key: "context", m: m).tipOverlay(m, active: m.tipKey == "context", trailing: false) {
                                TipEyebrow(text: "What this is"); TipDivider(); TipLine(label: "Results", text: note)
                            }
                        }
                    }
                    if let r = m.current {
                        Text(((m.demoLabel ?? r.uiContextLabel).map { "\($0)  ·  " } ?? "") + "\(r.imageWidth.formatted()) × \(r.imageHeight.formatted())").font(.system(size: 11)).foregroundStyle(T.ink2)
                    }
                }
            }
            .animation(m.instant ? nil : T.open(0.4), value: (m.current?.pageName ?? "").isEmpty)
            Spacer(minLength: 0)
            ScoreHead(m: m)
            // Pinned to the top so the gap above the buttons equals the card's right padding.
            HStack(spacing: 12) {
                SquareButton(icon: "clock.arrow.circlepath", label: "History", active: m.historyOpen) { m.toggleHistory() }
                SquareButton(icon: "xmark", label: "Close", active: false) { m.close() }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 50)
        .zIndex(10)
    }
}

/// 36 pt square button with the panels' corner radius. Active look only while its thing is open; no focus ring.
struct SquareButton: View {
    let icon: String; let label: String; let active: Bool; let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
                .foregroundStyle(T.ink)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(active ? T.selected : (hover ? T.hover : T.soft)))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle()).focusable(false).accessibilityLabel(label).help(label)
        .onHover { hover = $0 }
    }
}

/// The page name. Click to edit in place: same text, font and position, only a caret appears.
struct TitleView: View {
    @ObservedObject var m: AppModel
    @State private var hover = false
    @State private var draft = ""
    var body: some View {
        let name = m.current?.pageName ?? "UIScore"
        let editable = !(m.current?.pageName ?? "").isEmpty
        Text(m.editing ? (draft.isEmpty ? name : draft) : name).font(.system(size: 17, weight: .bold)).foregroundStyle(T.ink).lineLimit(1)
            .opacity(m.editing ? 0 : 1)
            .overlay(alignment: .leading) {
                if m.editing { TitleField(initial: name, text: $draft, model: m, commit: { m.rename($0) }).padding(.trailing, -24).frame(minWidth: 40) }
            }
            .onChange(of: m.editing) { e in if e { draft = name } }
        .fixedSize()
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 6).fill(editable && hover && !m.editing ? T.soft : .clear))
        .contentShape(Rectangle())
        .padding(.horizontal, -6).padding(.vertical, -1)
        .onHover { h in hover = h }
        .focusable(false)
        .onTapGesture { if editable && !m.editing { draft = name; m.editing = true } }
        .help(editable ? "Click to rename" : "")
    }
}

/// Borderless text field that looks like the label it replaces. Enter or a click outside saves; Esc is handled by the model (cancel).
struct TitleField: NSViewRepresentable {
    let initial: String
    @Binding var text: String
    let model: AppModel
    let commit: (String) -> Void
    func makeCoordinator() -> Coord { Coord(self) }
    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField(string: initial)
        f.isBordered = false; f.drawsBackground = false; f.focusRingType = .none
        f.font = .systemFont(ofSize: 17, weight: .bold); f.textColor = NSColor(T.ink)
        f.lineBreakMode = .byClipping; f.cell?.usesSingleLineMode = true; f.cell?.isScrollable = true
        f.delegate = context.coordinator
        context.coordinator.field = f
        model.commitEdit = { [weak coord = context.coordinator] in coord?.finish() }
        model.commitOwner = context.coordinator
        DispatchQueue.main.async {
            guard let w = f.window else { return }
            w.makeFirstResponder(f)
            if let ed = f.currentEditor() as? NSTextView {
                ed.textContainer?.lineFragmentPadding = 0
                ed.selectedRange = TitleEditing.initialSelection(for: initial)
            }
        }
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak f] e in
            guard let f, let w = f.window, e.window === w else { return e }
            if !f.bounds.contains(f.convert(e.locationInWindow, from: nil)) { context.coordinator.finish() }
            return e
        }
        return f
    }
    func updateNSView(_ f: NSTextField, context: Context) { f.textColor = NSColor(T.ink); context.coordinator.parent = self }
    static func dismantleNSView(_ f: NSTextField, coordinator: Coord) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
        let m = coordinator.parent.model
        if m.commitOwner === coordinator { m.commitEdit = nil; m.commitOwner = nil }
    }
    @MainActor final class Coord: NSObject, NSTextFieldDelegate {
        var parent: TitleField; weak var field: NSTextField?; var monitor: Any?
        init(_ p: TitleField) { parent = p }
        func controlTextDidChange(_ n: Notification) {
            guard let f = field else { return }
            let limited = PageName.limitTyped(f.stringValue)
            if limited != f.stringValue {
                f.stringValue = limited
                if let ed = f.currentEditor() as? NSTextView { ed.selectedRange = NSRange(location: (limited as NSString).length, length: 0) }
            }
            parent.text = limited
        }
        func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) { finish(); return true }
            return false
        }
        func finish() { if let f = field, !done { done = true; parent.commit(f.stringValue) } }
        var done = false
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1).animation(T.open(0.16), value: configuration.isPressed)
    }
}

struct Bar: View {
    var w: CGFloat?; var h: CGFloat = 12
    @State private var on = false
    var body: some View {
        RoundedRectangle(cornerRadius: h / 2).fill(T.track).frame(width: w, height: h).opacity(on ? 0.45 : 1)
            .onAppear { if !T.reduceMotion { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true } } }
    }
}

struct Panel<C: View>: View {
    let title: String; var legend: Bool = false; var stretch = false
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(T.ink)
                if legend {
                    Spacer()
                    HStack(spacing: 12) {
                        HStack(spacing: 5) { FeelDot(ring: false, size: 10); Text("Visual") }
                        HStack(spacing: 5) { FeelDot(ring: true, size: 10); Text("Copy") }
                    }.font(.system(size: 11)).foregroundStyle(T.ink2)
                }
            }
            if stretch { content.frame(maxHeight: .infinity) } else { content }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.soft))
    }
}

struct ErrorView: View {
    let message: String; let retry: Bool; let action: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text(message).font(.system(size: 14)).foregroundStyle(T.ink).multilineTextAlignment(.center).frame(maxWidth: 420)
            if retry { Button("Try again", action: action).buttonStyle(.borderedProminent).tint(T.accent) }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.soft))
    }
}

struct InfoMark: View {
    let key: String; @ObservedObject var m: AppModel
    @State private var hover = false
    var body: some View {
        let hot = hover
        Button { m.tipKey = (m.tipKey == key ? nil : key) } label: {
            Text("ⓘ").font(.system(size: 11)).foregroundStyle(m.tipKey == key || hot ? T.ink : T.ink2)
        }
        .buttonStyle(.plain).focusable(false).accessibilityLabel("About \(key)")
        .onHover { h in hover = h; if h { m.tipKey = key } else if m.tipKey == key { m.tipKey = nil } }
    }
}

struct TipBubble<C: View>: View {
    var width: CGFloat = 372
    static var pad: CGFloat { 14 }
    @ViewBuilder var content: C
    @State private var on = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) { content }
            .frame(width: width - 2 * Self.pad, alignment: .leading)
            .padding(.horizontal, Self.pad).padding(.top, 11).padding(.bottom, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.tipBg).shadow(color: T.shadow, radius: 12, y: 8))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(T.hair, lineWidth: 0.5))
            .scaleEffect(on ? 1 : 0.96, anchor: .topLeading).opacity(on ? 1 : 0)
            .onAppear { withAnimation(T.open(0.26)) { on = true } }
            .allowsHitTesting(false)
    }
}

/// 1px hairline under the eyebrow; the 7pt stack spacing on each side plus 1pt of padding gives 8pt above and below.
struct TipDivider: View {
    var body: some View { Rectangle().fill(T.tipRule).frame(height: 1).padding(.vertical, 1) }
}

/// The tooltip heading: the question, left-aligned inside the bubble's equal side padding.
struct TipEyebrow: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 18, weight: .semibold)).foregroundStyle(T.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TipLine: View {
    let label: String; let text: String; var dim = false
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(T.ink)
            Text(text).font(.system(size: 13, weight: .regular)).foregroundStyle(T.tipSub).fixedSize(horizontal: false, vertical: true)
        }
    }
}
