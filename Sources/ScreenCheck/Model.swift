import SwiftUI
import AppKit
import ScreenCheckCore

/// `key` keeps a row's identity while a live run goes from pending to saved, so the row is updated in place and never re-inserted.
struct HistoryItem: Identifiable {
    let result: RunResult; var imageURL: URL?
    var pending = false; var scoreReady = false
    var key: String? = nil
    var id: String { key ?? result.id }
}

@MainActor
final class AppModel: ObservableObject {
    enum Phase { case idle, loading, ready, error(String, Bool) }
    @Published var phase: Phase = .idle
    @Published var current: RunResult?
    @Published var currentImage: URL?
    @Published var textPending = false
    @Published var history: [HistoryItem] = []
    @Published var historyOpen = false
    @Published var lightbox = false
    @Published var tipKey: String?
    @Published var shown = false
    /// Parts of the card that already have a value; the rest show a shimmer bar.
    @Published var ready: Set<String> = []
    @Published var editing = false
    /// True while a stored result is shown: its values are in place at once, nothing grows or counts up.
    @Published var instant = false
    @Published var undoItem: HistoryItem?
    @Published var demoHover: String?
    @Published var undoProgress: Double?
    /// The card's frame and the screen's visible area, both in the card window's top-left coordinates; tooltips stay inside their overlap.
    var cardFrame: CGRect = .zero
    var screenRect: CGRect = CGRect(x: -10000, y: -10000, width: 20000, height: 20000)
    var tipBounds: CGRect {
        let c = cardFrame == .zero ? screenRect : cardFrame.insetBy(dx: 8, dy: 8)
        let r = c.intersection(screenRect.insetBy(dx: 8, dy: 8))
        return r.isNull || r.isEmpty ? c : r
    }
    /// Dev snapshot hook only: stands in for the core's context fields on runs saved before they existed.
    var demoLabel: String?; var demoNote: String?
    var onLightbox: (Bool) -> Void = { _ in }
    private var fullImages: [String: CGImage] = [:]
    /// The stored full-resolution image of the current run (runs/<id>/image.png), decoded once and kept.
    func fullImage() -> CGImage? {
        var url = currentImage
        if let id = current?.id, !id.isEmpty {
            let stored = History.root.appendingPathComponent(id).appendingPathComponent("image.png")
            if FileManager.default.fileExists(atPath: stored.path) { url = stored }
        }
        guard let url else { return nil }
        if let c = fullImages[url.path] { return c }
        guard let c = Contrast.load(url) else { return nil }
        if fullImages.count > 3 { fullImages.removeAll() }
        fullImages[url.path] = c; return c
    }
    func openLightbox() { lightbox = true; onLightbox(true) }
    func closeLightbox() { lightbox = false; onLightbox(false) }
    var customName: String?
    /// Set when a click outside the card ends a title edit from outside the app; the field saves and stops editing.
    var commitEdit: (() -> Void)?
    private var editEnded = Date.distantPast
    private var liveItem: HistoryItem?
    private var liveKey = ""
    /// Row identity per saved run, so a row keeps its id after the run is saved and a later run never flips it.
    private var stableKeys: [String: String] = [:]
    /// Owner of `commitEdit`, so a dismantled title field only clears its own hook.
    weak var commitOwner: AnyObject?
    var pending = PendingDeletions()
    var undoTask: Task<Void, Never>?
    /// Score appears once every meter is in and the tooltip text is written.
    var textDone: Bool { !textPending }
    var scoresDone: Bool { ready.isSuperset(of: Meters.allReady) }
    var onClose: () -> Void = {}
    var onShow: () -> Void = {}
    var onToggleHistory: () -> Void = {}
    private var task: Task<Void, Never>?
    /// Identifies the run that owns the card; results from a replaced run are dropped.
    private var runToken = UUID()
    private var thumbs: [URL: NSImage] = [:]

    func thumb(_ url: URL) -> NSImage? {
        // The key carries the file's modification time, so a rewritten file is never shown with an old thumbnail.
        let mt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = URL(string: url.absoluteString + "#\(mt)") ?? url
        if let t = thumbs[key] { return t }
        guard let c = Contrast.load(url) else { return nil }
        let s = Contrast.downscaled(c, maxSide: 640)
        let img = NSImage(cgImage: s, size: NSSize(width: s.width, height: s.height))
        thumbs[key] = img
        return img
    }

    func reloadHistory() {
        var items = History.load().filter { $0.0.id != pending.id }.map { HistoryItem(result: $0.0, imageURL: $0.1, key: stableKeys[$0.0.id]) }
        if let l = liveItem, l.result.id.isEmpty || !items.contains(where: { $0.result.id == l.result.id }) { items.insert(l, at: 0) }
        history = items
    }

    /// The new run gets its History row the moment the card opens, with skeleton values.
    private func beginLive() {
        liveKey = UUID().uuidString
        var p = RunResult.placeholder; p.createdAt = Date()
        liveItem = HistoryItem(result: p, imageURL: nil, pending: true, key: liveKey)
        withAnimation(T.open(0.35)) { reloadHistory() }
    }
    private func setLive(_ r: RunResult, scoreReady: Bool) {
        guard var l = liveItem else { return }
        stableKeys[r.id] = liveKey
        l = HistoryItem(result: r, imageURL: currentImage ?? l.imageURL, pending: true, scoreReady: scoreReady || l.scoreReady, key: liveKey)
        liveItem = l
        if let i = history.firstIndex(where: { $0.id == liveKey }) { history[i] = l } else { history.insert(l, at: 0) }
    }
    private func setLiveImage(_ url: URL) {
        guard var l = liveItem else { return }
        l.imageURL = url; liveItem = l
        if let i = history.firstIndex(where: { $0.id == liveKey }) { history[i].imageURL = url }
    }

    func delete(_ item: HistoryItem) {
        if item.pending { return }
        if let done = pending.delete(item.result.id) { History.remove(id: done) }
        withAnimation(T.open(0.25)) { history.removeAll { $0.id == item.id }; undoItem = item }
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(PendingDeletions.window * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if let done = self.pending.expire() { History.remove(id: done) }
            withAnimation(T.close(0.25)) { self.undoItem = nil }
        }
    }
    func undoDelete() {
        guard pending.undo() != nil else { return }
        undoTask?.cancel()
        withAnimation(T.open(0.25)) { undoItem = nil }
        reloadHistory()
    }
    /// Makes a waiting delete final (used when the app quits).
    func finalizePending() { if let i = pending.expire(now: .distantFuture) { History.remove(id: i) } }

    func rename(_ name: String) {
        let n = PageName.limitTyped(name).trimmingCharacters(in: .whitespacesAndNewlines)
        editing = false; editEnded = Date()
        guard !n.isEmpty, var r = current else { return }
        customName = n; r.pageName = n; current = r
        History.rename(id: r.id, to: n); reloadHistory()
    }

    func show() {
        onShow()
        if shown { return }
        DispatchQueue.main.async { [self] in withAnimation(T.open(0.42)) { shown = true } }
    }
    func close() {
        withAnimation(T.close()) { shown = false; tipKey = nil }; if lightbox { closeLightbox() }
        DispatchQueue.main.asyncAfter(deadline: .now() + (T.reduceMotion ? 0 : 0.2)) { [self] in if !shown { onClose() } }
    }

    /// A click outside the card: ends a title edit (saving it), otherwise closes the card like Esc or the X.
    func outsideClick() {
        if editing { commitEdit?(); return }
        if lightbox { closeLightbox(); return }
        if Date().timeIntervalSince(editEnded) < 0.2 || !shown { return }
        close()
    }

    func escape() {
        if lightbox { closeLightbox(); return }
        if editing { editing = false; return }
        close()
    }

    func toggleHistory() {
        reloadHistory()
        withAnimation(historyOpen ? T.close(0.2) : T.open(0.32)) { historyOpen.toggle() }
        onToggleHistory()
    }

    func select(_ item: HistoryItem) {
        instant = true
        withAnimation(T.open(0.25)) { current = item.result; currentImage = item.imageURL; textPending = false; phase = .ready; ready = Meters.allReady; editing = false }
    }

    /// Dev timing hook: SCREENCHECK_TIMING=1 prints how long each stage took after the shortcut.
    private func mark(_ what: String, _ t0: Date) {
        guard ProcessInfo.processInfo.environment["SCREENCHECK_TIMING"] != nil else { return }
        FileHandle.standardError.write(Data(String(format: "timing %@ %.0f ms\n", what, Date().timeIntervalSince(t0) * 1000).utf8))
    }

    /// Shows a stored result at once: no loading state, no model call for the scores. The values fill in from the moment the card opens.
    /// A run whose tooltip text is not written yet keeps filling the text in.
    func showStored(_ r: RunResult, image: URL) {
        instant = false
        current = r; currentImage = image; textPending = !r.textComplete; phase = .ready; ready = Meters.allReady; editing = false
        if !History.exists(id: r.id) { try? History.save(r, image: image) }
        liveItem = nil
        reloadHistory()
        show()
    }

    /// Writes the missing tooltip text of a stored run; the scores on the card are not touched.
    private func completeText(_ r: RunResult, image: URL, token: UUID) async {
        guard let done = try? await Pipeline(keys: KeyStore.keys()).run(imageURL: image) else { return }
        guard runToken == token else { return }
        var f = done
        if let n = customName { f.pageName = n }
        withAnimation(T.open(0.4)) { current = f; textPending = !f.textComplete }
        if f.textComplete { try? History.save(f, image: image); reloadHistory() }
    }

    func checkLatest(imageOverride: URL? = nil) {
        task?.cancel()
        let token = UUID(); runToken = token
        let t0 = Date()
        customName = nil; editing = false; liveItem = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // 1. Look the image up by the hash of its bytes (results cache, then saved runs) before any loading state.
                var quick: ScreenshotFinder.Found?
                if let o = imageOverride { quick = ScreenshotFinder.Found(url: o, fromClipboard: false) } else { quick = await ScreenshotFinder.find(wait: false) }
                guard self.runToken == token else { return }
                if let q = quick {
                    let hit = await Task.detached(priority: .userInitiated) { Pipeline.lookup(imageURL: q.url) }.value
                    guard self.runToken == token else { return }
                    if let hit {
                        self.showStored(hit, image: q.url); self.mark("cached open", t0)
                        if !hit.textComplete { await self.completeText(hit, image: q.url, token: token) }
                        return
                    }
                }
                // 2. Not seen before: the skeleton shows only until the first value exists.
                self.currentImage = nil; self.instant = false; self.beginLive()
                withAnimation(T.open()) { self.phase = .loading; self.textPending = false; self.current = nil; self.ready = [] }
                self.show()
                let found: ScreenshotFinder.Found?
                if imageOverride != nil { found = quick } else { found = await ScreenshotFinder.find() }
                guard self.runToken == token else { return }
                guard let url = imageOverride ?? found?.url else { throw PipelineError.noScreenshot }
                self.currentImage = url; self.setLiveImage(url)
                let keys = KeyStore.keys()
                let apply = { (r: RunResult) -> RunResult in var r = r; if let n = self.customName { r.pageName = n }; return r }
                var sawFirst = false
                let result = try await Pipeline(keys: keys).run(imageURL: url, fallbackName: "Screenshot", onScores: { scores in
                    Task { @MainActor in
                        guard self.runToken == token else { return }
                        withAnimation(T.open(0.5)) { self.current = apply(scores); self.setLive(apply(scores), scoreReady: true); self.phase = .ready; self.textPending = !scores.text.values.contains { !$0.why.isEmpty }; self.ready = Meters.allReady }
                        self.mark("all scores", t0)
                    }
                }, onPartial: { partial, set in
                    Task { @MainActor in
                        guard self.runToken == token else { return }
                        if !sawFirst { sawFirst = true; self.mark("first value", t0) }
                        withAnimation(T.open(0.5)) { self.current = apply(partial); self.setLive(apply(partial), scoreReady: false); self.textPending = true; self.ready = set }
                    }
                })
                guard self.runToken == token else { return }
                let final = apply(result)
                try? History.save(final, image: url)
                withAnimation(T.open(0.4)) { self.current = final; self.textPending = false; self.ready = Meters.allReady }
                self.mark("all values", t0)
                self.liveItem = nil; self.reloadHistory()
            } catch is CancellationError {
                guard self.runToken == token else { return }
                self.liveItem = nil; self.reloadHistory()
            } catch {
                guard self.runToken == token else { return }
                let e = error as? PipelineError
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                withAnimation(T.open()) { self.phase = .error(msg, e?.isRetryable ?? true); self.textPending = false; self.liveItem = nil; self.reloadHistory() }
                self.show()
            }
        }
    }
}
