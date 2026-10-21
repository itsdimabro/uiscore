import SwiftUI
import AppKit
import KeyboardShortcuts
import ScreenCheckCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var panel: FloatingPanel!
    var statusItem: NSStatusItem!
    var settings: NSWindow?
    var onboarding: NSWindow?
    /// Where the card was last dragged to; kept for this run of the app only.
    var savedOrigin: NSPoint?
    let lightboxPanel = LightboxPanel()

    func applicationDidFinishLaunching(_ n: Notification) {
        if ProcessInfo.processInfo.environment["SCREENCHECK_IMPORT_KEYS"] == "1" { importKeys() }
        NSApp.setActivationPolicy(.accessory)
        migrateShortcut()
        installEditMenu()
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: CardView.windowSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isMovableByWindowBackground = true; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: CardView(m: model).background(EscCatcher(onEsc: { [weak self] in self?.model.escape() }, onUndo: { [weak self] in self?.model.undoItem != nil ? { self?.model.undoDelete(); return true }() : false })))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        lightboxPanel.zoom.onClose = { [weak self] in self?.model.closeLightbox() }
        model.onLightbox = { [weak self] open in
            guard let self else { return }
            if open, let img = self.model.fullImage(), let s = self.panel.screen ?? NSScreen.main {
                let r = self.model.current
                self.lightboxPanel.present(image: img, caption: "\(r?.pageName ?? "")   \(img.width) × \(img.height)", on: s)
            } else if open { self.model.lightbox = false }
            else { self.lightboxPanel.dismiss { self.panel.makeKeyAndOrderFront(nil) } }
        }
        model.onShow = { [weak self] in self?.showPanel() }
        model.onToggleHistory = { [weak self] in self?.clearFocus() }
        model.onClose = { [weak self] in self?.panel.orderOut(nil) }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let p = self?.panel, p.isVisible { self?.savedOrigin = p.frame.origin; self?.updateScreenRect() } }
        }

        ClipboardWatcher.shared.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checkmark.seal", accessibilityDescription: "UIScore")
        let menu = NSMenu()
        menu.addItem(item("Check latest image", #selector(check)))
        menu.addItem(item("History", #selector(history)))
        menu.addItem(item("Settings…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit)))
        statusItem.menu = menu
        KeyboardShortcuts.onKeyUp(for: .check) { [weak self] in Task { @MainActor in self?.check() } }
        let env = ProcessInfo.processInfo.environment
        if let a = env["SCREENCHECK_APPEARANCE"] { NSApp.appearance = NSAppearance(named: a == "dark" ? .darkAqua : .aqua) }
        if env["SCREENCHECK_DEMO_RUN"] != nil { model.reloadHistory(); if let h = model.history.first { model.select(h); model.show() } }
        if let out = env["SCREENCHECK_SNAPSHOT"] { startSnapshotWatcher(out, tip: env["SCREENCHECK_TIP"], history: env["SCREENCHECK_HISTORY"] != nil) }
        if ProcessInfo.processInfo.environment["SCREENCHECK_AUTORUN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(ProcessInfo.processInfo.environment["SCREENCHECK_AUTORUN_DELAY"] ?? "") ?? 0.5)) { [weak self] in self?.check() }
        }
        if let out = env["SCREENCHECK_ONBOARD_SNAPSHOT"] { snapshotOnboarding(out, step: Int(env["SCREENCHECK_ONBOARD_STEP"] ?? "0") ?? 0); return }
        if KeyStore.keys().claude.isEmpty || KeyStore.keys().jev.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.openOnboarding() } }
    }
    /// A saved shortcut equal to the old default (Control+Option+S) is replaced by Command+Shift+V, once.
    func migrateShortcut() {
        let key = "KeyboardShortcuts_check"
        if ShortcutMigration.isOldDefault(stored: UserDefaults.standard.string(forKey: key)) {
            KeyboardShortcuts.setShortcut(.init(.v, modifiers: [.command, .shift]), for: .check)
        }
    }
    /// Dev/test hook: renders the card to a PNG once the run is complete (no Screen Recording permission needed).
    func startSnapshotWatcher(_ out: String, tip: String?, history: Bool) {
        var stage = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let v = self.panel.contentView else { return }
                guard let r = self.model.current, r.timings.total > 0, !self.model.textPending || ProcessInfo.processInfo.environment["SCREENCHECK_PARTIAL"] != nil else { return }
                stage += 1
                if stage == 1 {
                    if ProcessInfo.processInfo.environment["SCREENCHECK_DEMO_CTX"] != nil, var c = self.model.current {
                        self.model.demoLabel = "SaaS"; self.model.demoNote = "A product dashboard inside the app. It is built to be used, so it is judged on how direct it is, not on persuasion."
                        c.text["valence"] = self.mt("Dark, calm surface with one bright accent. Reads as neutral to slightly pleasant.", "")
                        c.text["intensity"] = self.mt("Few colours and wide spacing keep it low-energy; only the blue button draws the eye.", "")
                        c.text["reading"] = self.mt("Grade 11. Hard words: \"authentication\", \"provisioning\", \"configuration\".", "Replace \"provisioning\" with \"setup\".")
                        c.readingGrade = 11
                        self.model.current = c
                    }
                    if let g = ProcessInfo.processInfo.environment["SCREENCHECK_GRADE"].flatMap(Int.init), var c = self.model.current { c.readingGrade = g; self.model.current = c }
                    if ProcessInfo.processInfo.environment["SCREENCHECK_DEMO_NA"] != nil, var c = self.model.current {
                        for k in ["order", "familiar", "clarity"] { c.meters[k]?.applicable = false; c.text[k]?.why = "This doesn't apply to this kind of screen."; c.text[k]?.fix = "" }
                        self.model.current = c
                    }
                    if ProcessInfo.processInfo.environment["SCREENCHECK_PARTIAL"] != nil { self.model.instant = false; self.model.textPending = true; self.model.ready = ["reading", "contrast", "balance"] }
                    if history { self.model.toggleHistory() }; if let tip { self.model.tipKey = tip }
                    if ProcessInfo.processInfo.environment["SCREENCHECK_EDIT"] != nil { self.model.editing = true }
                    return
                }
                if stage == 3 {
                    if let u = ProcessInfo.processInfo.environment["SCREENCHECK_UNDO_DEMO"], let f = Double(u), let h = self.model.history.first { self.model.undoItem = h; self.model.undoProgress = f }
                    if ProcessInfo.processInfo.environment["SCREENCHECK_INFO_HOVER"] != nil { self.model.tipKey = "contrast" }
                    if let h = ProcessInfo.processInfo.environment["SCREENCHECK_HOVER"], let i = Int(h), self.model.history.indices.contains(i) { self.model.demoHover = self.model.history[i].id }
                }
                if stage < (ProcessInfo.processInfo.environment["SCREENCHECK_PARTIAL"] != nil ? 8 : 6) { return }
                var target: NSView = v
                if ProcessInfo.processInfo.environment["SCREENCHECK_LIGHTBOX"] != nil, let lv = self.lightboxPanel.contentView {
                    if !self.model.lightbox { self.model.openLightbox(); stage = 4; return }
                    lv.layoutSubtreeIfNeeded(); target = lv
                }
                target.layoutSubtreeIfNeeded()
                if let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) {
                    target.cacheDisplay(in: target.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
                t.invalidate(); NSApp.terminate(nil)
            }
        }
    }
    /// Dev hook: re-saves keys from env through KeyStore so this app owns the Keychain items, then exits.
    func importKeys() {
        let env = ProcessInfo.processInfo.environment
        guard let c = env["ANTHROPIC_API_KEY"], !c.isEmpty, let j = env["JEV_API_KEY"], !j.isEmpty else {
            FileHandle.standardError.write(Data("import: ANTHROPIC_API_KEY and JEV_API_KEY required\n".utf8)); exit(1)
        }
        KeyStore.set("jev", ""); KeyStore.set("claude-keys", "")
        KeyStore.set("jev", j); KeyStore.setClaudeKeys([c])
        print("import: jev \(KeyStore.get("jev") != nil ? "saved" : "FAILED"), claude-keys \(KeyStore.claudeKeys().count) saved")
        exit(0)
    }
    /// A menu-bar app has no main menu, so Cmd+V/C/X/A/Z never reach text fields. This one is never visible but carries the key equivalents.
    /// Dev hook helper: MeterText has no public initialiser, so build it through its Codable form.
    func mt(_ why: String, _ fix: String) -> MeterText {
        let d = try! JSONSerialization.data(withJSONObject: ["why": why, "fix": fix])
        return try! JSONDecoder().decode(MeterText.self, from: d)
    }
    func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem); appItem.submenu = NSMenu()
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        func add(_ t: String, _ a: String, _ k: String, _ mods: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: t, action: Selector(a), keyEquivalent: k); i.keyEquivalentModifierMask = mods; edit.addItem(i)
        }
        add("Undo", "undo:", "z"); add("Redo", "redo:", "z", [.command, .shift]); edit.addItem(.separator())
        add("Cut", "cut:", "x"); add("Copy", "copy:", "c"); add("Paste", "paste:", "v"); add("Select All", "selectAll:", "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
    func item(_ t: String, _ a: Selector) -> NSMenuItem { let i = NSMenuItem(title: t, action: a, keyEquivalent: ""); i.target = self; return i }

    func showPanel() {
        let size = CardView.windowSize
        if let o = savedOrigin { panel.setFrame(NSRect(origin: o, size: size), display: true) }
        else if let s = NSScreen.main {
            // Closed card (700 wide) is centred; its top sits 80 pt below the top of the screen.
            let f = s.visibleFrame, inset = CardView.inset
            panel.setFrame(NSRect(x: f.midX + 350 + inset - size.width, y: f.maxY - 80 + inset - size.height, width: size.width, height: size.height), display: true)
        }
        updateScreenRect()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        clearFocus()
    }
    /// The screen's visible area in the card window's top-left coordinates, so tooltips never leave the screen.
    func updateScreenRect() {
        guard let s = panel.screen ?? NSScreen.main else { return }
        let v = s.visibleFrame, f = panel.frame
        model.screenRect = CGRect(x: v.minX - f.minX, y: f.maxY - v.maxY, width: v.width, height: v.height)
    }
    /// Nothing in the card holds initial focus, so no focus ring is drawn.
    func clearFocus() {
        panel.initialFirstResponder = nil
        panel.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in if self?.model.editing == false { self?.panel.makeFirstResponder(nil) } }
    }
    @objc func check() {
        let keys = KeyStore.keys()
        if keys.claude.isEmpty || keys.jev.isEmpty { openOnboarding(); return }
        if let p = ProcessInfo.processInfo.environment["SCREENCHECK_IMAGE"] { model.checkLatest(imageOverride: URL(fileURLWithPath: p)) } else { model.checkLatest() }
    }
    @objc func history() { model.reloadHistory(); model.show(); if !model.historyOpen { model.toggleHistory() } }
    @objc func openSettings() {
        if settings == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "UIScore Settings"; w.contentView = NSHostingView(rootView: SettingsView { [weak self] in self?.openOnboarding(step: 1) }); w.isReleasedWhenClosed = false; settings = w
        }
        settings?.center(); NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    func makeOnboardingWindow(_ m: OnboardingModel) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.isMovableByWindowBackground = true
        w.contentView = NSHostingView(rootView: OnboardingView(m: m)); w.isReleasedWhenClosed = false
        return w
    }
    func openOnboarding(step: Int = 0) {
        if onboarding == nil {
            let m = OnboardingModel(); m.step = step
            m.onDone = { [weak self] in self?.onboarding?.close(); self?.onboarding = nil }
            onboarding = makeOnboardingWindow(m)
        }
        onboarding?.center(); NSApp.activate(ignoringOtherApps: true); onboarding?.makeKeyAndOrderFront(nil)
    }
    /// Dev/test hook: renders one onboarding step with sample keys (never reads or writes the Keychain).
    func snapshotOnboarding(_ out: String, step: Int) {
        let m = OnboardingModel(demo: true); m.step = step
        if step == 1 {
            m.jev = "jev-demo-0000-1234"; m.jevResult = .ok
            m.rows = [KeyRow(text: "sk-ant-api03-demo-AAAA1111"), KeyRow(text: "sk-ant-api03-demo-BBBB2222"), KeyRow(text: "sk-ant-api03-demo-CCCC3333")]
            m.results = [m.rows[0].id: .ok, m.rows[1].id: .noCredit, m.rows[2].id: .rejected]
        }
        let w = makeOnboardingWindow(m); onboarding = w
        w.center(); w.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard let v = w.contentView?.superview ?? w.contentView else { NSApp.terminate(nil); return }
            v.layoutSubtreeIfNeeded()
            if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            }
            NSApp.terminate(nil)
        }
    }
    @objc func quit() { model.finalizePending(); NSApp.terminate(nil) }
}

struct EscCatcher: NSViewRepresentable {
    let onEsc: () -> Void
    let onUndo: () -> Bool
    func makeNSView(context: Context) -> NSView { let v = KeyView(); v.onEsc = onEsc; v.onUndo = onUndo; return v }
    func updateNSView(_ v: NSView, context: Context) {}
    final class KeyView: NSView {
        var onEsc: (() -> Void)?
        var onUndo: (() -> Bool)?
        var monitor: Any?
        override func viewDidMoveToWindow() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                if e.keyCode == 53, self?.window?.isKeyWindow == true { self?.onEsc?(); return nil }
                if e.keyCode == 6, e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, self?.window?.isKeyWindow == true, self?.onUndo?() == true { return nil }
                return e
            }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = Delegate()
    app.delegate = delegate
    app.run()
}
