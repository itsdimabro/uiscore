import Foundation
import CoreGraphics
import CryptoKit

public struct Pipeline {
    static let jevYesThreshold = 0.5
    public var keys: Keys
    var client: ModelClient
    public init(keys: Keys) { self.keys = keys; self.client = LiveClient() }
    init(keys: Keys, client: ModelClient) { self.keys = keys; self.client = client }


    /// Hands out partial results in order: state and callback share one lock, so a late stage can never show before an earlier one.
    final class Stages {
        private let lock = NSLock()
        private let t0 = Date()
        private let sink: ((RunResult, Set<String>) -> Void)?
        private let make: (Stages) -> RunResult
        var meters: [String: MeterResult] = [:]
        var ready: Set<String> = []
        var name = ""
        var vision: JSONValue = .null
        var contrast: ContrastReport?
        var stats: PixelStats?
        private(set) var firstMS: Double?
        init(sink: ((RunResult, Set<String>) -> Void)?, make: @escaping (Stages) -> RunResult) { self.sink = sink; self.make = make }
        func emit(meters m: [String: MeterResult] = [:], ready r: Set<String>, update: ((Stages) -> Void)? = nil) {
            lock.lock(); defer { lock.unlock() }
            update?(self)
            for (k, v) in m { meters[k] = v }
            ready.formUnion(r)
            if firstMS == nil { firstMS = Date().timeIntervalSince(t0) * 1000 }
            sink?(make(self), ready)
        }
    }

    /// Runs the whole pipeline. `onScores` fires as soon as scores are ready; the returned result also has the text.
    /// With `useCache` the stored result for the same image bytes is returned and no model is called.
    public func run(imageURL: URL, useCache: Bool = true, fallbackName: String = "Screenshot", cacheDir: URL = Pipeline.cacheDir, historyRoot: URL? = History.root, onScores: ((RunResult) -> Void)? = nil, onPartial: ((RunResult, Set<String>) -> Void)? = nil) async throws -> RunResult {
        let hash = Pipeline.imageHash(imageURL)
        if useCache, let hit = Pipeline.lookup(imageURL: imageURL, cacheDir: cacheDir, historyRoot: historyRoot) {
            onScores?(hit)
            if hit.textComplete { return hit }
            return try await completeText(hit, hash: hash, cacheDir: cacheDir)
        }
        guard !keys.claude.isEmpty else { throw PipelineError.noKey("Claude") }
        guard !keys.jev.isEmpty else { throw PipelineError.noKey("Jev") }
        let t0 = Date()
        let runID = UUID().uuidString
        var T = Timings()

        let loaded = try loadImage(imageURL)
        let full = loaded.full, rd = loaded.reading
        T.ocr = loaded.ocrMS
        let stages = Stages(sink: onPartial) { s in
            RunResult(id: runID, createdAt: Date(), pageName: s.name, imageWidth: full.width, imageHeight: full.height, meters: s.meters,
                      feeling: [:], feelingLow: [:], feelingConfidencePct: [:], readingGrade: rd?.grade, readingGradeCapped: rd?.capped, readingWords: rd?.words ?? 0,
                      text: [:], timings: T, contrastDetail: s.contrast, vision: s.vision, pixelStats: s.stats)
        }
        stages.emit(ready: ["reading"])

        let input = try modelInput(full: full, boxes: loaded.boxes)
        let c6Task = startC6Vote(input.c6Content, hash: hash, cacheDir: cacheDir)
        let label = try await labelVote(input.content)
        T.visionFields = label.ms
        T.vision = Date().timeIntervalSince(t0) * 1000

        let pixels = Pixels(cgImage: full)
        let labelled = applyLabels(votes: label.replies, vision: label.vision, loaded: loaded, pixels: pixels)
        let context = labelled.context, vision = labelled.vision

        let tc = Date()
        var code = codeChecks(labelled: labelled, full: full, pixels: pixels)
        T.code = Date().timeIntervalSince(tc) * 1000

        let designerTask = startDesigner(labelled: labelled, code: code, full: full, reading: rd, input: input, hash: hash, useCache: useCache, cacheDir: cacheDir)
        let pageName = PageName.generated(vision["page_name"].string) ?? fallbackName
        stages.emit(meters: ["contrast": contrastMeter(code: code)], ready: ["contrast"]) { $0.name = pageName; $0.vision = vision; $0.contrast = code.contrast; $0.stats = code.stats }
        let meaning = vision["grouping_clear"].bool
        let layoutMeters = Layout.meters(pixels: pixels, boxes: code.scaled, imageWidth: full.width, meaning: meaning)
        stages.emit(meters: layoutMeters, ready: Set(layoutMeters.keys))
        let lp = Layout.problems(pixels: pixels, boxes: code.scaled, imageWidth: full.width, meaning: meaning)
        let provisional = provisionalWriterFacts(pageName: pageName, labelled: labelled, code: code, layoutMeters: layoutMeters, layoutProblems: lp, reading: rd, imageHeight: full.height)

        if let c6 = await c6Task.value { code.answers["C6"] = Applicability.c6Holds(vote: c6, context: context, demonstrates: code.facts.demonstratesProduct) }
        let notApplicable = notApplicable(code, labelled: labelled)
        emitCodeOnlyMeters(stages, answers: code.answers, notApplicable: notApplicable, context: context)
        let jev = try await askJev(labelled: labelled, code: code, notApplicable: notApplicable)
        T.jev = jev.ms
        let answerer = Answerer(code: code.answers, jev: jev.p)

        // Falls back to the checklist alone when fewer than 2 designer votes were valid.
        let designer = await designerTask.value
        let meters = Designer.blend(scoreMeters(answerer, notApplicable: notApplicable, context: context, codeNote: code.note, layoutMeters: layoutMeters), rating: designer)
        let feeling = scoreFeeling(answerer)
        let fc = feeling.confidence
        let valence = min(fc["vv"]!, fc["cv"]!), arousal = min(fc["vi"]!, fc["ci"]!)

        T.scoresFirst = Date().timeIntervalSince(t0) * 1000
        T.firstValue = stages.firstMS
        var result = RunResult(
            id: runID, createdAt: Date(), pageName: pageName,
            imageWidth: full.width, imageHeight: full.height, meters: meters, feeling: feeling.score,
            feelingLow: ["v": valence < Scoring.lowConfidencePct, "a": arousal < Scoring.lowConfidencePct],
            feelingConfidencePct: ["v": valence, "a": arousal],
            readingGrade: rd?.grade, readingGradeCapped: rd?.capped, readingWords: rd?.words ?? 0, text: [:], timings: T,
            contrastDetail: code.contrast, vision: vision, pixelStats: code.stats)
        result.overall = Scoring.overall(meters: meters.filter { $0.value.applicable != false }.mapValues { $0.score }, reading: rd.map { Int((Self.gradePoints($0.grade) * 10).rounded()) })
        result.imageHash = hash
        result.designerReason = designer?.reason
        result.designerReasons = designer?.reasons
        result.context = context
        let ctxChanged = notApplicable.filter { Applicability.kinds[$0] != nil || !Applicability.contextNotApplicable(context).isDisjoint(with: [$0]) }
        result.contextNote = Applicability.contextNote(context, changed: ctxChanged)
        // Scores are reusable from here on, even while the text is still being written.
        if useCache, let h = hash { Pipeline.store(result, hash: h, dir: cacheDir) }
        onScores?(result)

        let writeStart = Date()
        let written = await writeText(for: result, provisional: provisional, layoutProblems: lp, stats: code.stats, copy: code.facts.allCopy)
        T.write = Date().timeIntervalSince(writeStart) * 1000
        result.text = Self.texts(for: result, written: written, pageText: code.facts.allCopy, overlayPresent: labelled.boxes.contains { $0.role == "overlay" })
        T.total = Date().timeIntervalSince(t0) * 1000
        result.timings = T
        if useCache, let h = hash { Pipeline.store(result, hash: h, dir: cacheDir) }
        return result
    }

    /// Writes the tooltip text for a stored run that has scores but no (or cut-off) text. Scores are not touched.
    func completeText(_ stored: RunResult, hash: String?, cacheDir: URL) async throws -> RunResult {
        var r = stored
        var sc: [String: Any] = [:]
        for k in Meters.order {
            let failed = Rubric.checks(for: k).filter { c in !Self.navCountIDs.contains(c.id) }.filter { c in r.meters[k]?.checks.first { $0.id == c.id }?.yes == false }.prefix(3).map { Self.plainCheck[$0.id] ?? $0.q }
            if k == "reading" { sc[k] = ["grade": r.readingGrade ?? 0, "score": Int(((r.readingGrade.map { Self.gradePoints($0) * 10 }) ?? 100).rounded())]; continue }
            sc[k] = ["score": r.meters[k]?.score ?? 0, "failed": Array(failed)]
        }
        var facts: [String: Any] = ["page": r.pageName, "look": Self.truncate(r.vision["visual_description"].string ?? "", max: 240), "meters": sc]
        facts["feeling_facts"] = Self.feelingFacts(stats: r.pixelStats, copy: "")
        var w: JSONValue?
        if let data = try? JSONSerialization.data(withJSONObject: facts), let str = String(data: data, encoding: .utf8) {
            w = try? await client.claude(keys: keys.claude, system: Prompts.write, content: [["type": "text", "text": str]], maxTokens: 900, model: Claude.model, cacheSystem: false).json
        }
        r.text = Self.texts(for: r, written: w)
        if let h = hash, r.textComplete { Pipeline.store(r, hash: h, dir: cacheDir) }
        return r
    }

    /// Reading points (0-10): grade 9 or lower = 10 (WCAG 3.1.5), falling linearly to 0 at grade 12 and above.
    public static func gradePoints(_ g: Int) -> Double {
        let g = Double(g)
        if g <= 9 { return 10 }
        if g >= 12 { return 0 }
        return 10 * (12 - g) / 3
    }
}
