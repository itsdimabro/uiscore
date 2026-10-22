import Foundation
import CoreGraphics
import CryptoKit

extension Pipeline {
    public static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ScreenCheck/results", isDirectory: true)
    }
    /// SHA-256 of the decoded pixels (width, height, 8-bit sRGB RGBA), not of the file bytes: the same picture
    /// read from the clipboard (TIFF or re-encoded PNG) or from a screenshot file hashes the same.
    public static func imageHash(_ url: URL) -> String? {
        if let img = Contrast.load(url), let h = pixelHash(img) { return h }
        guard let d = try? Data(contentsOf: url) else { return nil }   // not a decodable image: fall back to the file bytes
        return "raw-" + SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }
    public static func pixelHash(_ img: CGImage) -> String? {
        let w = img.width, h = img.height
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let base = ctx.data else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var hasher = SHA256()
        hasher.update(data: Data("\(w)x\(h)|".utf8))
        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: base, count: w * 4 * h))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func cacheFile(_ hash: String, _ dir: URL) -> URL { dir.appendingPathComponent(hash + ".json") }
    public static func cached(hash: String, dir: URL = Pipeline.cacheDir) -> RunResult? {
        guard let d = try? Data(contentsOf: cacheFile(hash, dir)) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(RunResult.self, from: d)
    }
    public static func store(_ r: RunResult, hash: String, dir: URL = Pipeline.cacheDir) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(r) { try? d.write(to: cacheFile(hash, dir)) }
    }

    /// Results saved before text stopped being cut end in "…"; they are scored again instead of shown cut off.
    public static func isTruncated(_ r: RunResult) -> Bool {
        r.text.values.contains { $0.why.hasSuffix("…") || $0.fix.hasSuffix("…") }
    }

    /// The stored result for these image bytes, or nil. No model is called.
    /// The image is matched by the hash of its bytes, first in the results cache, then in the saved history runs.
    public static func lookup(imageURL: URL, cacheDir: URL = Pipeline.cacheDir, historyRoot: URL? = History.root) -> RunResult? {
        guard let h = imageHash(imageURL) else { return nil }
        if let hit = cached(hash: h, dir: cacheDir), hit.isScored { return hit }
        if let root = historyRoot { return History.find(imageHash: h, root: root) }
        return nil
    }
}
