import SwiftUI

/// Where a tooltip goes: above its anchor (below when there is no room above), lined up with the anchor's left or right edge,
/// then pushed back inside `bounds` (the visible card intersected with the screen's visible frame).
enum TipLayout {
    static func origin(anchor a: CGRect, size s: CGSize, bounds b: CGRect, trailing: Bool, gap: CGFloat = 6) -> CGPoint {
        var x = trailing ? a.maxX - s.width : a.minX
        let below = a.maxY + gap, above = a.minY - gap - s.height
        let fitsBelow = below + s.height <= b.maxY, fitsAbove = above >= b.minY
        var y: CGFloat
        if fitsAbove { y = above } else if fitsBelow { y = below }
        else { y = (b.maxY - a.maxY) >= (a.minY - b.minY) ? below : above }
        x = min(x, b.maxX - s.width); x = max(x, b.minX)
        y = min(y, b.maxY - s.height); y = max(y, b.minY)
        return CGPoint(x: x, y: y)
    }
}

/// One tooltip request from a row; the card root draws it so it sits above every panel.
struct TipSpec {
    let key: String; let anchor: Anchor<CGRect>; let trailing: Bool; let width: CGFloat; let content: AnyView
}

struct TipSpecKey: PreferenceKey {
    static var defaultValue: [TipSpec] = []
    static func reduce(value: inout [TipSpec], nextValue: () -> [TipSpec]) { value.append(contentsOf: nextValue()) }
}

extension View {
    /// Asks the card root to show `tip` as a bubble that stays inside the card and the screen.
    func tipOverlay<C: View>(_ m: AppModel, active: Bool, trailing: Bool, width: CGFloat = 372, @ViewBuilder _ tip: @escaping () -> C) -> some View {
        let key = m.tipKey ?? ""
        return anchorPreference(key: TipSpecKey.self, value: .bounds) { a in
            active ? [TipSpec(key: key, anchor: a, trailing: trailing, width: width, content: AnyView(tip()))] : []
        }
    }
}

/// Draws the active tooltip above everything in the card, in global coordinates so the clamp in `TipLayout` applies unchanged.
struct TipHost: View {
    @ObservedObject var m: AppModel
    let specs: [TipSpec]
    @State private var size: CGSize = .zero
    var body: some View {
        GeometryReader { g in
            if let s = specs.last {
                let origin = g.frame(in: .global).origin
                let a = g[s.anchor].offsetBy(dx: origin.x, dy: origin.y)
                let o = TipLayout.origin(anchor: a, size: size, bounds: m.tipBounds, trailing: s.trailing)
                TipBubble(width: s.width) { s.content }
                    .fixedSize()
                    .background(GeometryReader { p in Color.clear.onAppear { DispatchQueue.main.async { size = p.size } }.onChange(of: p.size) { n in DispatchQueue.main.async { size = n } } })
                    .opacity(size == .zero ? 0 : 1)
                    .id(s.key)
                    .offset(x: o.x - origin.x, y: o.y - origin.y)
            }
        }
        .onChange(of: specs.last?.key) { _ in size = .zero }
        .allowsHitTesting(false)
    }
}
