import Foundation
import ScreenCheckCore

let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first else { FileHandle.standardError.write(Data("usage: screencheck-cli <image.png> [--no-cache] [--out result.json]\n".utf8)); exit(2) }
if args.contains("--layout") {
    guard let img = Contrast.load(URL(fileURLWithPath: path)), let px = Pixels(cgImage: img) else { exit(1) }
    struct Out: Codable { var balance: BalanceMetrics; var alignment: AlignmentMetrics }
    let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
    if args.contains("--boxes") { for b in OCR.boxes(in: img) { print(Int(b.x), Int(b.y), Int(b.w), Int(b.h), b.text.prefix(30)) } }
    print(String(data: try enc.encode(Out(balance: Layout.balance(Layout.weightGrid(px)), alignment: Layout.alignment(OCR.boxes(in: img), imageWidth: img.width))), encoding: .utf8)!)
    exit(0)
}
let keys = KeyStore.keys()
if args.contains("--check-keys") {
    for (i, k) in keys.claude.enumerated() { print("Claude key \(i + 1): \(await KeyCheck.claude(k).plain("Claude"))") }
    print("Jev key: \(await KeyCheck.jev(keys.jev).plain("Jev"))")
    exit(0)
}
let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
do {
    let r = try await Pipeline(keys: keys).run(imageURL: URL(fileURLWithPath: path), useCache: !args.contains("--no-cache")) { s in
        FileHandle.standardError.write(Data(String(format: "scores ready at %.2f s\n", s.timings.scoresFirst / 1000).utf8))
    }
    let data = try enc.encode(r)
    if let i = args.firstIndex(of: "--out"), i + 1 < args.count { try data.write(to: URL(fileURLWithPath: args[i + 1])) }
    print(String(data: data, encoding: .utf8)!)
    let t = r.timings
    FileHandle.standardError.write(Data(String(format: "timings: ocr %.2fs vision(label %.2fs, wall %.2fs) code %.3fs jev %.2fs | scores-first %.2fs | write %.2fs | total %.2fs\n",
        t.ocr/1000, t.visionFields/1000, t.vision/1000, t.code/1000, t.jev/1000, t.scoresFirst/1000, t.write/1000, t.total/1000).utf8))
} catch {
    FileHandle.standardError.write(Data("error: \((error as? LocalizedError)?.errorDescription ?? "\(error)")\n".utf8)); exit(1)
}
