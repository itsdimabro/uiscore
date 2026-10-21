import SwiftUI

/// Where a tooltip goes: below its anchor (above when there is no room below), lined up with the anchor's left or right edge,
/// then pushed back inside `bounds` (the visible card intersected with the screen's visible frame).
enum TipLayout {
    static func origin(anchor a: CGRect, size s: CGSize, bounds b: CGRect, trailing: Bool, gap: CGFloat = 6) -> CGPoint {
        var x = trailing ? a.maxX - s.width : a.minX
        let below = a.maxY + gap, above = a.minY - gap - s.height
        let fitsBelow = below + s.height <= b.maxY, fitsAbove = above >= b.minY
        var y: CGFloat
        if fitsBelow { y = below } else if fitsAbove { y = above }
        else { y = (b.maxY - a.maxY) >= (a.minY - b.minY) ? below : above }
        x = min(x, b.maxX - s.width); x = max(x, b.minX)
        y = min(y, b.maxY - s.height); y = max(y, b.minY)
        return CGPoint(x: x, y: y)
    }
}

private struct TipSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

extension View {
    /// Shows `tip` as a bubble that stays inside the card and the screen.
    func tipOverlay<C: View>(_ m: AppModel, active: Bool, trailing: Bool, width: CGFloat = 372, @ViewBuilder _ tip: @escaping () -> C) -> some View {
        modifier(TipOverlay(m: m, active: active, trailing: trailing, width: width, tip: tip))
    }
}

struct TipOverlay<C: View>: ViewModifier {
    let m: AppModel; let active: Bool; let trailing: Bool; let width: CGFloat
    @ViewBuilder let tip: () -> C
    @State private var size: CGSize = .zero
    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {  // anchor frame read below
            if active {
                GeometryReader { g in
                    let a = g.frame(in: .global)
                    let o = TipLayout.origin(anchor: a, size: size, bounds: m.tipBounds, trailing: trailing)
                    TipBubble(width: width) { tip() }
                        .fixedSize()
                        .background(GeometryReader { s in Color.clear.onAppear { DispatchQueue.main.async { size = s.size } }.onChange(of: s.size) { n in DispatchQueue.main.async { size = n } } })
                        .offset(x: o.x - a.minX, y: o.y - a.minY)
                }
            }
        }
    }
}
