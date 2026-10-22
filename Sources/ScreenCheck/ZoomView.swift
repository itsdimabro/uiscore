import AppKit
import SwiftUI
import ScreenCheckCore

/// Full-resolution image viewer. The image lives on one CALayer that is only moved and scaled, never re-decoded.
/// Wheel = zoom about the cursor, trackpad two-finger scroll = pan, pinch = zoom, drag = pan, Cmd/Ctrl +/-/0 = zoom/fit, Esc = close.
final class ZoomView: NSView {
    private let layerImage = CALayer()
    private var image: CGImage?
    private var scale: CGFloat = 1       // points per image pixel
    private var center = CGPoint.zero    // image pixel shown at the view's centre
    var onClose: () -> Void = {}
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layerImage.magnificationFilter = .nearest
        layerImage.minificationFilter = .trilinear
        layerImage.anchorPoint = .zero
        layer?.addSublayer(layerImage)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(image: CGImage) {
        self.image = image
        layerImage.contents = image
        fit()
    }
    private var fitScale: CGFloat {
        guard let i = image, bounds.width > 0 else { return 1 }
        return min(bounds.width / CGFloat(i.width), bounds.height / CGFloat(i.height))
    }
    func fit() {
        guard let i = image else { return }
        scale = fitScale; center = CGPoint(x: CGFloat(i.width) / 2, y: CGFloat(i.height) / 2); apply()
    }
    private func clampScale(_ s: CGFloat) -> CGFloat { min(max(s, fitScale * 0.5), 32) }
    private func apply(animated: Bool = false) {
        guard let i = image else { return }
        let w = CGFloat(i.width) * scale, h = CGFloat(i.height) * scale
        let maxX = max(0, (w - 40) / 2 / scale + CGFloat(i.width) / 2 - CGFloat(i.width) / 2)
        _ = maxX
        center.x = min(max(center.x, 0), CGFloat(i.width)); center.y = min(max(center.y, 0), CGFloat(i.height))
        CATransaction.begin(); CATransaction.setDisableActions(!animated)
        layerImage.bounds = CGRect(x: 0, y: 0, width: CGFloat(i.width), height: CGFloat(i.height))
        let backing = window?.backingScaleFactor ?? 2
        layerImage.contentsScale = backing
        // Layer is flipped by the parent (isFlipped), so contents need no flip when geometry is set this way.
        layerImage.isGeometryFlipped = true
        layerImage.position = CGPoint(x: bounds.midX - center.x * scale, y: bounds.midY - center.y * scale)
        layerImage.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
        _ = (w, h)
    }
    override func layout() { super.layout(); if image != nil { if abs(scale - fitScale) < 1e-6 { fit() } else { apply() } } }

    private func zoom(by f: CGFloat, at p: CGPoint) {
        let old = scale, new = clampScale(old * f)
        guard new != old else { return }
        let px = center.x + (p.x - bounds.midX) / old, py = center.y + (p.y - bounds.midY) / old
        scale = new
        center = CGPoint(x: px - (p.x - bounds.midX) / new, y: py - (p.y - bounds.midY) / new)
        apply()
    }
    private func local(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func magnify(with e: NSEvent) { zoom(by: 1 + e.magnification, at: local(e)) }
    override func scrollWheel(with e: NSEvent) {
        if e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.command) {
            center.x -= e.scrollingDeltaX / scale; center.y -= e.scrollingDeltaY / scale; apply()
        } else {
            let d = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY / 120 : e.scrollingDeltaY / 12
            zoom(by: exp(d), at: local(e))
        }
    }
    override func mouseDragged(with e: NSEvent) { center.x -= e.deltaX / scale; center.y -= e.deltaY / scale; apply() }
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { fit() }
    }
    override func keyDown(with e: NSEvent) { if !handle(e) { super.keyDown(with: e) } }
    private func handle(_ e: NSEvent) -> Bool {
        if e.keyCode == 53 { onClose(); return true }
        let m = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard m.contains(.command) || m.contains(.control) else { return false }
        let mid = CGPoint(x: bounds.midX, y: bounds.midY)
        switch e.charactersIgnoringModifiers {
        case "+", "=": zoom(by: 1.25, at: mid); return true
        case "-", "_": zoom(by: 0.8, at: mid); return true
        case "0": fit(); return true
        default: return false
        }
    }
    override func viewDidMoveToWindow() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let s = self, s.window?.isKeyWindow == true else { return e }
            return s.handle(e) ? nil : e
        }
    }
    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
}

/// The image viewer: a floating card-style window centred on the card's screen, sized to the image (never past 1:1 at the
/// screen's scale, never over 85% of the visible frame). Same corner radius, shadow and square X as the card.
final class LightboxPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    let zoom = ZoomView(frame: .zero)
    /// Called for a click in the transparent margin, outside the visible viewer box.
    var onOutsideClick: () -> Void = {}
    /// Bumped on every present and dismiss, so a finished fade only acts if nothing newer started.
    private var generation = 0
    private var dismissing = false
    /// Transparent room around the box so its shadow is never cut.
    static let margin: CGFloat = 96
    private static let radius: CGFloat = 22
    private let box = NSView()
    private let clip = NSView()
    private let closeButton = NSHostingView(rootView: SquareButton(icon: "xmark", label: "Close", active: false) {})

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let root = NSView(); root.wantsLayer = true
        box.wantsLayer = true; clip.wantsLayer = true
        box.layer?.cornerRadius = Self.radius; box.layer?.cornerCurve = .continuous
        box.layer?.shadowRadius = 28; box.layer?.shadowOffset = CGSize(width: 0, height: -14); box.layer?.shadowOpacity = 1
        clip.layer?.cornerRadius = Self.radius; clip.layer?.cornerCurve = .continuous; clip.layer?.masksToBounds = true
        clip.layer?.borderWidth = 0.5
        box.autoresizingMask = [.width, .height]
        clip.autoresizingMask = [.width, .height]
        zoom.autoresizingMask = [.width, .height]
        clip.addSubview(zoom); box.addSubview(clip); root.addSubview(box)
        // Same inset as the card's X: 18 pt from the top and right edges.
        closeButton.frame = NSRect(x: 0, y: 0, width: 36, height: 36)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        box.addSubview(closeButton)
        contentView = root
        refreshColors()
    }
    func setCloseAction(_ f: @escaping () -> Void) {
        closeButton.rootView = SquareButton(icon: "xmark", label: "Close", active: false, action: f)
    }
    private func refreshColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        func c(_ w: CGFloat, _ a: CGFloat) -> CGColor { NSColor(white: w, alpha: a).cgColor }
        box.layer?.backgroundColor = dark ? NSColor(srgbRed: 0x1d / 255, green: 0x1d / 255, blue: 0x1c / 255, alpha: 1).cgColor
                                          : NSColor(srgbRed: 0xfc / 255, green: 0xfc / 255, blue: 0xfb / 255, alpha: 1).cgColor
        box.layer?.shadowColor = dark ? c(0, 0.6) : NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x1e / 255, alpha: 0.18).cgColor
        clip.layer?.borderColor = dark ? c(1, 0.09) : c(0, 0.08)
    }
    override func becomeKey() { super.becomeKey(); refreshColors() }
    /// The margin is transparent but still belongs to this window; a click there must not be swallowed, it closes the viewer.
    override func sendEvent(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if !box.frame.contains(e.locationInWindow) { onOutsideClick(); return }
        default: break
        }
        super.sendEvent(e)
    }

    func present(image: CGImage, on screen: NSScreen) {
        let vf = screen.visibleFrame, k = screen.backingScaleFactor
        let nat = CGSize(width: CGFloat(image.width) / k, height: CGFloat(image.height) / k)
        let f = min(1, vf.width * 0.85 / nat.width, vf.height * 0.85 / nat.height)
        let size = CGSize(width: max(nat.width * f, 280), height: max(nat.height * f, 200)).applying(.identity)
        let m = Self.margin
        let content = NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2, width: size.width, height: size.height).integral
        setFrame(content.insetBy(dx: -m, dy: -m), display: false)
        let bounds = NSRect(x: m, y: m, width: content.width, height: content.height)
        box.frame = bounds; clip.frame = box.bounds; zoom.frame = clip.bounds
        closeButton.frame.origin = CGPoint(x: bounds.width - 18 - 36, y: bounds.height - 18 - 36)
        box.layer?.shadowPath = CGPath(roundedRect: box.bounds, cornerWidth: Self.radius, cornerHeight: Self.radius, transform: nil)
        zoom.set(image: image)
        refreshColors()
        generation += 1; dismissing = false
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil); makeFirstResponder(zoom)
        animate(in: true) {}
    }
    func dismiss(_ done: @escaping () -> Void) {
        guard isVisible, !dismissing else { return }
        dismissing = true; generation += 1
        let g = generation
        animate(in: false) { [weak self] in
            guard let self, self.generation == g else { return }
            self.dismissing = false
            self.orderOut(nil); done()
        }
    }

    /// Fade and a slight scale about the box's centre; opening eases out, closing eases in.
    private func animate(in opening: Bool, _ done: @escaping () -> Void) {
        guard let l = box.layer else { done(); return }
        let d: CFTimeInterval = T.reduceMotion ? 0 : (opening ? 0.25 : 0.18)
        let s: CGFloat = 0.96
        let a = l.anchorPoint, w = l.bounds.width, h = l.bounds.height
        func xf(_ s: CGFloat) -> CATransform3D {
            let t = CATransform3DMakeTranslation((0.5 - a.x) * w * (1 - s), (0.5 - a.y) * h * (1 - s), 0)
            return CATransform3DScale(t, s, s, 1)
        }
        let from = opening ? 0 : 1, to = 1 - from
        let fromT = opening ? xf(s) : CATransform3DIdentity, toT = opening ? CATransform3DIdentity : xf(s)
        let timing = opening ? CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1) : CAMediaTimingFunction(controlPoints: 0.32, 0, 0.67, 0)
        CATransaction.begin()
        CATransaction.setCompletionBlock(done)
        l.opacity = Float(to); l.transform = toT
        if d > 0 {
            let o = CABasicAnimation(keyPath: "opacity"); o.fromValue = from; o.toValue = to
            let t = CABasicAnimation(keyPath: "transform"); t.fromValue = fromT; t.toValue = toT
            for x in [o, t] { x.duration = d; x.timingFunction = timing; l.add(x, forKey: x.keyPath) }
        }
        CATransaction.commit()
        // The close button and image live in subviews of the box, so they fade with it; the layer opacity is inherited.
    }
}
