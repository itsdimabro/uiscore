import Foundation
import Security
import AppKit

public enum ScreenshotFinder {
    static let exts: Set<String> = ["png", "jpg", "jpeg", "heic"]

    public static func screenshotFolder() -> URL {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["read", "com.apple.screencapture", "location"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        if (try? p.run()) != nil {
            p.waitUntilExit()
            let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if p.terminationStatus == 0, !s.isEmpty { return URL(fileURLWithPath: (s as NSString).expandingTildeInPath) }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    /// Newest image by modification date in `folder`.
    public static func newest(in folder: URL, notOlderThan: TimeInterval? = nil, now: Date = Date()) -> URL? {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        let imgs = items.compactMap { u -> (URL, Date)? in
            guard exts.contains(u.pathExtension.lowercased()),
                  let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let d = v.contentModificationDate else { return nil }
            return (u, d)
        }
        guard let best = imgs.max(by: { $0.1 < $1.1 }) else { return nil }
        if let age = notOlderThan, now.timeIntervalSince(best.1) > age { return nil }
        return best.0
    }

    public enum Choice: Equatable { case screenshot, clipboard, none }

    /// Which image is newest. `clipboardChanged` is when this app saw the clipboard change to an image;
    /// nil means the image was already there when the app started, so its age is unknown: it only wins if there is no screenshot.
    public static func pick(screenshot: Date?, clipboardHasImage: Bool, clipboardChanged: Date?) -> Choice {
        switch (screenshot, clipboardHasImage) {
        case (nil, false): return .none
        case (nil, true): return .clipboard
        case (_, false): return .screenshot
        case (let s?, true):
            guard let c = clipboardChanged else { return .screenshot }
            return c > s ? .clipboard : .screenshot
        }
    }

    public struct Found { public let url: URL; public let fromClipboard: Bool; public init(url: URL, fromClipboard: Bool) { self.url = url; self.fromClipboard = fromClipboard } }

    static func mtime(_ u: URL) -> Date? { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }

    /// The newest image (screenshot file or clipboard image). Waits up to 1.5 s for a just-taken screenshot file to appear.
    public static func find(wait: Bool = true) async -> Found? {
        let folder = screenshotFolder()
        let watcher = ClipboardWatcher.shared
        let start = Date()
        while true {
            watcher.poll()
            let shot = newest(in: folder)
            let choice = pick(screenshot: shot.flatMap(mtime), clipboardHasImage: ClipboardWatcher.hasImage(), clipboardChanged: watcher.changedAt)
            let fresh: Bool = {
                switch choice {
                case .screenshot: return Date().timeIntervalSince(shot.flatMap(mtime) ?? .distantPast) < 20
                case .clipboard: return Date().timeIntervalSince(watcher.changedAt ?? .distantPast) < 1.5
                case .none: return false
                }
            }()
            if fresh || !wait || Date().timeIntervalSince(start) >= 1.5 {
                switch choice {
                case .screenshot: return shot.map { Found(url: $0, fromClipboard: false) }
                case .clipboard: return ClipboardWatcher.imageFile().map { Found(url: $0, fromClipboard: true) }
                case .none: return nil
                }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}

/// Notes when the clipboard last changed to an image. Only an integer is polled; image data is read at shortcut time.
public final class ClipboardWatcher {
    public static let shared = ClipboardWatcher()
    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg"), .init("public.heic"), .init("org.webmproject.webp")]
    public private(set) var changedAt: Date?
    private var count = NSPasteboard.general.changeCount
    private var timer: Timer?

    public func start() {
        guard timer == nil else { return }
        count = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    public func poll() {
        let c = NSPasteboard.general.changeCount
        guard c != count else { return }
        count = c
        changedAt = Self.hasImage() ? Date() : nil
    }

    static func fileImageURL() -> URL? {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] ?? []
        return urls.first { ScreenshotFinder.exts.contains($0.pathExtension.lowercased()) || $0.pathExtension.lowercased() == "webp" }
    }

    public static func hasImage() -> Bool {
        let types = NSPasteboard.general.types ?? []
        return imageTypes.contains { types.contains($0) } || fileImageURL() != nil
    }

    /// A file holding the clipboard image: the copied file itself, or the bitmap written out as a PNG.
    public static func imageFile() -> URL? {
        if let u = fileImageURL() { return u }
        let pb = NSPasteboard.general
        for t in imageTypes {
            guard let d = pb.data(forType: t), let rep = NSBitmapImageRep(data: d), let png = rep.representation(using: .png, properties: [:]) else { continue }
            // A new name every time, so an old thumbnail can never be matched to a new image.
            let tmp = FileManager.default.temporaryDirectory
            for old in (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [] where old.lastPathComponent.hasPrefix("screencheck-clipboard") { try? FileManager.default.removeItem(at: old) }
            let u = tmp.appendingPathComponent("screencheck-clipboard-\(UUID().uuidString).png")
            if (try? png.write(to: u)) != nil { return u }
        }
        return nil
    }
}

public enum KeyStore {
    static let service = "ScreenCheck"
    /// Dev, test and snapshot runs never touch the Keychain: every ad-hoc build is a new app to it and would raise a password prompt.
    static var offKeychain: Bool {
        let e = ProcessInfo.processInfo.environment
        return e["SCREENCHECK_ENV_KEYS"] == "1" || e["SCREENCHECK_SNAPSHOT"] != nil || e["SCREENCHECK_ONBOARD_SNAPSHOT"] != nil
    }
    public static func get(_ name: String) -> String? {
        if offKeychain { return nil }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: name, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    public static func set(_ name: String, _ value: String) {
        if offKeychain { return }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name]
        SecItemDelete(base as CFDictionary)
        if value.isEmpty { return }
        var add = base; add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
    static let listName = "claude-keys"
    public static func encodeList(_ l: [String]) -> String { (try? JSONEncoder().encode(l)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]" }
    public static func decodeList(_ s: String) -> [String] { (try? JSONDecoder().decode([String].self, from: Data(s.utf8))) ?? [] }
    /// The ordered Claude key list. Older installs kept one key under "anthropic"; it is read as a list of one.
    public static func claudeKeys() -> [String] {
        if let s = get(listName) { return decodeList(s) }
        if let old = get("anthropic"), !old.isEmpty { return [old] }
        return []
    }
    public static func setClaudeKeys(_ l: [String]) {
        set(listName, l.isEmpty ? "" : encodeList(l))
        set("anthropic", "")
    }
    /// Keychain first, then environment (dev only).
    public static func keys() -> Keys {
        let env = ProcessInfo.processInfo.environment
        // Test runs from a shell set SCREENCHECK_ENV_KEYS=1: the Keychain is not touched, so no access prompt can block them.
        // Snapshot renders never call a model; placeholder keys keep the debug binary off the Keychain, whose prompt blocked them.
        if env["SCREENCHECK_SNAPSHOT"] != nil && env["SCREENCHECK_ENV_KEYS"] != "1" { return Keys(claude: ["snapshot"], jev: "snapshot") }
        if env["SCREENCHECK_ENV_KEYS"] == "1" { return Keys(claude: (env["ANTHROPIC_API_KEY"] ?? "").isEmpty ? [] : [env["ANTHROPIC_API_KEY"]!], jev: env["JEV_API_KEY"] ?? "") }
        var c = claudeKeys()
        if c.isEmpty, let e = env["ANTHROPIC_API_KEY"], !e.isEmpty { c = [e] }
        return Keys(claude: c, jev: get("jev") ?? env["JEV_API_KEY"] ?? "")
    }
}

public enum History {
    public static var root: URL {
        if let d = ProcessInfo.processInfo.environment["SCREENCHECK_RUNS_DIR"] { return URL(fileURLWithPath: d, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenCheck/runs", isDirectory: true)
    }
    public static func save(_ r: RunResult, image: URL, root: URL = History.root) throws {
        let dir = root.appendingPathComponent(r.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(r).write(to: dir.appendingPathComponent("result.json"))
        let dst = dir.appendingPathComponent("image.png")
        try? FileManager.default.removeItem(at: dst)
        if image.pathExtension.lowercased() == "png" { try FileManager.default.copyItem(at: image, to: dst) }
        else if let c = Contrast.load(image), let d = Contrast.pngData(c) { try d.write(to: dst) }
    }
    /// Rewrites one run's stored name. Returns false when the run is not there.
    @discardableResult
    public static func rename(id: String, to name: String, root: URL = History.root) -> Bool {
        let f = root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("result.json")
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let d = try? Data(contentsOf: f), var r = try? dec.decode(RunResult.self, from: d) else { return false }
        r.pageName = name
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let out = try? enc.encode(r) else { return false }
        return (try? out.write(to: f)) != nil
    }
    private static var hashMemo: [String: String] = [:]
    private static let memoLock = NSLock()
    /// Pixel hash of a stored run: the hash saved in result.json, or computed from image.png once and kept in memory.
    static func hash(of r: RunResult, image: URL) -> String? {
        if let h = r.imageHash { return h }
        memoLock.lock(); defer { memoLock.unlock() }
        let key = r.id
        if let h = hashMemo[key] { return h }
        guard let h = Pipeline.imageHash(image) else { return nil }
        hashMemo[key] = h
        return h
    }
    /// The saved run whose image has these pixels (hash), newest first. A run counts once its scores exist.
    public static func find(imageHash h: String, root: URL = History.root) -> RunResult? {
        for (r, img) in load(root: root) where r.isScored {
            if hash(of: r, image: img) == h { return r }
        }
        return nil
    }
    public static func exists(id: String, root: URL = History.root) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("result.json").path)
    }
    public static func remove(id: String, root: URL = History.root) {
        guard !id.isEmpty, !id.contains("/") else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id, isDirectory: true))
    }
    public static func load(root: URL = History.root) -> [(RunResult, URL)] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { d in
            guard let data = try? Data(contentsOf: d.appendingPathComponent("result.json")),
                  let r = try? dec.decode(RunResult.self, from: data) else { return nil }
            return (r, d.appendingPathComponent("image.png"))
        }.sorted { $0.0.createdAt > $1.0.createdAt }
    }
}

/// Runs that were deleted but can still be brought back. One slot: a new delete makes the previous one final.
public struct PendingDeletions {
    public static let window: TimeInterval = 4
    public private(set) var id: String?
    private var at: Date?
    public init() {}
    /// Returns the run that just became final, if any.
    public mutating func delete(_ newID: String, now: Date = Date()) -> String? {
        let prior = id
        id = newID; at = now
        return prior
    }
    /// Gives the run back, only while the window is open.
    public mutating func undo(now: Date = Date()) -> String? {
        guard let i = id, let t = at, now.timeIntervalSince(t) < Self.window else { return nil }
        id = nil; at = nil
        return i
    }
    /// The run whose window has run out, if any; it is cleared.
    public mutating func expire(now: Date = Date()) -> String? {
        guard let i = id, let t = at, now.timeIntervalSince(t) >= Self.window else { return nil }
        id = nil; at = nil
        return i
    }
}

public enum ShortcutMigration {
    /// The stored KeyboardShortcuts value for "check" is JSON like {"carbonKeyCode":1,"carbonModifiers":6144}.
    /// True when it is the old default, Control+Option+S.
    public static func isOldDefault(stored: String?) -> Bool {
        guard let s = stored, let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] else { return false }
        return (o["carbonKeyCode"] as? Int) == 1 && (o["carbonModifiers"] as? Int) == 6144
    }
}
