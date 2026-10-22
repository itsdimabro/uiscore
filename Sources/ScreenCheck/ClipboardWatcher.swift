import AppKit
import ScreenCheckCore

/// Notes when the clipboard last changed to an image. Only an integer is polled; image data is read at shortcut time.
final class ClipboardWatcher: ClipboardSource {
    static let shared = ClipboardWatcher()
    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg"), .init("public.heic"), .init("org.webmproject.webp")]
    private(set) var changedAt: Date?
    private var count = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        count = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    func poll() {
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

    func hasImage() -> Bool { Self.hasImage() }
    static func hasImage() -> Bool {
        let types = NSPasteboard.general.types ?? []
        return imageTypes.contains { types.contains($0) } || fileImageURL() != nil
    }

    /// A file holding the clipboard image: the copied file itself, or the bitmap written out as a PNG.
    func imageFile() -> URL? { Self.imageFile() }
    static func imageFile() -> URL? {
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
