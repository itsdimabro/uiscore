import AppKit
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
        layerImage.magnificationFilter = .nearest
        layerImage.minificationFilter = .trilinear
        layerImage.anchorPoint = .zero
        layerImage.shadowOpacity = 0.4; layerImage.shadowRadius = 24; layerImage.shadowOffset = CGSize(width: 0, height: -12)
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
        let margin: CGFloat = 48
        let s = min((bounds.width - margin) / CGFloat(i.width), (bounds.height - margin) / CGFloat(i.height))
        return s
    }
    func fit() {
        guard let i = image else { return }
        scale = fitScale; center = CGPoint(x: CGFloat(i.width) / 2, y: CGFloat(i.height) / 2); apply()
    }
    private func clampScale(_ s: CGFloat) -> CGFloat { min(max(s, fitScale * 0.5), 32) }
    private func apply(animated: Bool = false) {
        guard let i = image else { return }
        // Never pan the image fully out of view.
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
        layerImage.shadowPath = CGPath(rect: layerImage.bounds, transform: nil)
        CATransaction.commit()
        _ = (w, h)
    }
    override func layout() { super.layout(); if image != nil { if abs(scale - fitScale) < 1e-6 { fit() } else { apply() } } }

    private func zoom(by f: CGFloat, at p: CGPoint) {
        let old = scale, new = clampScale(old * f)
        guard new != old else { return }
        // keep the image pixel under the cursor fixed
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
        else if let i = image {
            // A click outside the image closes it.
            let r = CGRect(x: bounds.midX - center.x * scale, y: bounds.midY - center.y * scale, width: CGFloat(i.width) * scale, height: CGFloat(i.height) * scale)
            if !r.contains(local(e)) { onClose() }
        }
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

/// A borderless panel over the screen's visible area that shows the stored full-resolution image.
final class LightboxPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    let zoom = ZoomView(frame: .zero)
    private let dim = NSVisualEffectView()
    private let tag = NSTextField(labelWithString: "")
    private let esc = NSTextField(labelWithString: " esc ")

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let root = NSView(); root.wantsLayer = true
        dim.material = .underWindowBackground; dim.blendingMode = .behindWindow; dim.state = .active
        dim.frame = root.bounds; dim.autoresizingMask = [.width, .height]
        root.addSubview(dim)
        let scrim = NSView(); scrim.wantsLayer = true; scrim.layer?.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 0.55).cgColor
        scrim.frame = root.bounds; scrim.autoresizingMask = [.width, .height]; root.addSubview(scrim)
        zoom.frame = root.bounds; zoom.autoresizingMask = [.width, .height]; root.addSubview(zoom)
        tag.font = .systemFont(ofSize: 12); tag.textColor = NSColor(white: 0.92, alpha: 1)
        tag.frame = NSRect(x: 20, y: 14, width: 600, height: 18); tag.autoresizingMask = [.maxXMargin, .maxYMargin]
        root.addSubview(tag)
        esc.font = .systemFont(ofSize: 11, weight: .medium); esc.textColor = .labelColor; esc.alignment = .center
        esc.drawsBackground = true; esc.backgroundColor = NSColor(white: 1, alpha: 0.9); esc.wantsLayer = true; esc.layer?.cornerRadius = 4
        esc.frame = NSRect(x: root.bounds.width - 52, y: root.bounds.height - 40, width: 34, height: 20); esc.autoresizingMask = [.minXMargin, .minYMargin]
        root.addSubview(esc)
        contentView = root
    }
    func present(image: CGImage, caption: String, on screen: NSScreen) {
        setFrame(screen.visibleFrame, display: true)
        zoom.set(image: image)
        tag.stringValue = caption
        alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil); makeFirstResponder(zoom)
        NSAnimationContext.runAnimationGroup { $0.duration = T.reduceMotion ? 0 : 0.25; $0.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1); animator().alphaValue = 1 }
    }
    func dismiss(_ done: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ $0.duration = T.reduceMotion ? 0 : 0.18; animator().alphaValue = 0 }, completionHandler: { [weak self] in self?.orderOut(nil); done() })
    }
}
