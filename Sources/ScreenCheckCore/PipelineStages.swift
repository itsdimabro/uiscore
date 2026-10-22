import Foundation
import CoreGraphics

typealias CheckAnswer = (yes: Bool, p: Double?, kind: String)
typealias Reading = (grade: Int, words: Int, capped: Bool)

struct LoadedImage {
    let full: CGImage
    let boxes: [TextBox]
    let screenScale: Double
    let ocrMS: Double
    let reading: Reading?
}

struct ModelInput {
    let img: [String: Any]
    let content: [[String: Any]]
    let c6Content: [[String: Any]]
}

struct Labelled {
    let vision: JSONValue
    let context: PageContext
    let boxes: [TextBox]
    let primary: Int?
}

struct CodeStage {
    let scaled: [TextBox]
    let facts: PageFacts
    let contrast: ContrastReport
    let note: String?
    var answers: [String: Bool]
    let stats: PixelStats?
    let screenKind: ScreenKind
}

/// Resolves a check to its code answer, else to Jev's probability.
struct Answerer {
    let code: [String: Bool]
    let jev: [String: Double]
    func answer(_ c: Check) -> CheckAnswer {
        if let y = code[c.id] { return (y, nil, "code") }
        let p = jev[c.id] ?? 0
        return (p >= Pipeline.jevYesThreshold, p, "jev")
    }
    func answers(for meter: String) -> [String: CheckAnswer] {
        Dictionary(uniqueKeysWithValues: Rubric.checks(for: meter).map { ($0.id, answer($0)) })
    }
}

extension Pipeline {
    /// Text boxes come from Apple Vision on the full image: same pixels, same boxes, every run.
    func loadImage(_ url: URL) throws -> LoadedImage {
        guard let full = Contrast.load(url) else { throw PipelineError.unreadableImage }
        let start = Date()
        var boxes = OCR.boxes(in: full)
        // Retina captures: text height in px is twice the CSS px, so every size threshold would be wrong. Sizes are put in points.
        let scale = Contrast.screenScale(url, width: full.width)
        if scale > 1 { for i in boxes.indices { boxes[i].fontPx /= scale } }
        let ms = Date().timeIntervalSince(start) * 1000
        // Reading level uses line geometry only, so it does not wait for the labels.
        let reading = Readability.grade(forCopy: Readability.countedParagraphs(boxes, imageHeight: full.height))
        return LoadedImage(full: full, boxes: boxes, screenScale: scale, ocrMS: ms, reading: reading)
    }

    func modelInput(full: CGImage, boxes: [TextBox]) throws -> ModelInput {
        let small = Contrast.downscaled(full)
        guard let png = Contrast.pngData(small) else { throw PipelineError.unreadableImage }
        let img: [String: Any] = ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]]
        let k = Double(small.width) / Double(full.width)   // ids are listed to the model in small-image pixels
        let listed = boxes.indices.sorted { boxes[$0].w * boxes[$0].h > boxes[$1].w * boxes[$1].h }.prefix(250).sorted()
        let list = listed.map { i -> String in
            let b = boxes[i]
            return "\(i)|\(Int(b.x * k)),\(Int(b.y * k)),\(Int(b.w * k)),\(Int(b.h * k))|\(String(b.text.prefix(60)))"
        }.joined(separator: "\n")
        let content: [[String: Any]] = [img, ["type": "text", "text": "Image is \(small.width)x\(small.height) px. OCR boxes:\n\(list)"]]
        let c6Text = String(listed.map { String(boxes[$0].text.prefix(60)) }.joined(separator: "\n").prefix(3000))
        let c6Content: [[String: Any]] = [img, ["type": "text", "text": "OCR text on the page:\n" + c6Text]]
        return ModelInput(img: img, content: content, c6Content: c6Content)
    }

    /// C6 (headline says what this is): Sonnet looks at the image. Jev agreed with Opus on 52% of pages, Sonnet on 90%.
    func startC6Vote(_ c6Content: [[String: Any]], hash: String?, cacheDir: URL) -> Task<Bool?, Never> {
        let client = client, key = keys.claude
        return Task<Bool?, Never> {
            // The vote on one image is stored the first time, so scoring the same image again gives the same answer.
            let c6File = hash.map { cacheDir.appendingPathComponent("c6-\($0).txt") }
            if let f = c6File, let t = try? String(contentsOf: f, encoding: .utf8) { return t == "1" }
            let votes: [Bool] = await withTaskGroup(of: Bool?.self) { g in
                for _ in 0..<5 {
                    g.addTask {
                        do { return try await client.claude(keys: key, system: Prompts.c6, content: c6Content, maxTokens: 500, model: Claude.sonnet, cacheSystem: false).json["C6"].bool }
                        catch {
                            if ProcessInfo.processInfo.environment["SCREENCHECK_DEBUG"] != nil { FileHandle.standardError.write(Data("c6 error: \(error)\n".utf8)) }
                            return nil
                        }
                    }
                }
                var v: [Bool] = []
                for await x in g { if let x { v.append(x) } }
                return v
            }
            // 5 votes; a headline counts as plain only with a clear majority (4 of 5), so a 3-2 split cannot flip run to run.
            guard !votes.isEmpty else { return nil }
            let yes = votes.filter { $0 }.count * 5 >= votes.count * 4
            if votes.count >= 4, let f = c6File {
                try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                try? (yes ? "1" : "0").write(to: f, atomically: true, encoding: .utf8)
            }
            return yes
        }
    }

    /// Three identical label calls in parallel; every field takes the majority answer, so one odd reply cannot flip a check.
    /// A reply cut off before its last fields leaves them missing, and missing fields would read as "fine": such a reply is never scored.
    func labelVote(_ content: [[String: Any]]) async throws -> (replies: [JSONValue], vision: JSONValue, ms: Double) {
        let client = client, key = keys.claude
        let replies: [(json: JSONValue, ms: Double)] = await withTaskGroup(of: (json: JSONValue, ms: Double)?.self) { g in
            for _ in 0..<3 { g.addTask { try? await client.claude(keys: key, system: Prompts.label, content: content, maxTokens: 2600, model: Claude.model, cacheSystem: false) } }
            var r: [(json: JSONValue, ms: Double)] = []
            for await x in g { if let x, Self.isComplete(x.json) { r.append(x) } }
            return r
        }
        if replies.isEmpty, await Self.everyKeyRejected(keys.claude) { throw PipelineError.allKeysFailed }
        guard !replies.isEmpty else { throw PipelineError.badModelOutput("label reply incomplete") }
        let votes = replies.map { $0.json }
        return (votes, Self.majority(votes), replies.map { $0.ms }.max() ?? 0)
    }

    /// Applies the model's roles and finds the primary button from its OCR box, not from the model.
    func applyLabels(votes: [JSONValue], vision: JSONValue, loaded: LoadedImage, pixels: Pixels?) -> Labelled {
        var vision = vision
        let full = loaded.full
        let context = PageContext.resolve(votes: votes)
        let boxes = OCR.applyRoles(vision["roles"], to: loaded.boxes)
        let primary = Self.primaryID(vision, count: boxes.count).flatMap { id in pixels.map { Contrast.isFilled($0, box: boxes[id]) } ?? true ? id : nil }
        if let pid = primary {
            let b = boxes[pid]
            if case .object(var o) = vision {
                o["primary_y_pct"] = .number((b.y + b.h / 2) / Double(full.height) * 100)
                o["primary_y_pt"] = .number((b.y + b.h / 2) / max(1, loaded.screenScale))
                vision = .object(o)
            }
        }
        return Labelled(vision: vision, context: context, boxes: boxes, primary: primary)
    }

    func codeChecks(labelled L: Labelled, full: CGImage, pixels: Pixels?) -> CodeStage {
        // Consent bars and chat bubbles are transient overlays: they leave every layout and text meter.
        let scaled = L.boxes.filter { $0.role != "overlay" }
        let stats = pixels.map { PixelStats.compute($0) }
        var facts = Scoring.facts(from: L.vision, textBoxes: scaled)
        facts.imageHeight = full.height
        facts.allBoxes = scaled
        // Unmeasurable text (gradient, photo, neighbouring artwork) counted over all non-logo, non-demo boxes.
        let textOnly = scaled.filter { !Scoring.nonPage.contains($0.role) }
        let unmeasured = pixels.map { px in textOnly.filter { Contrast.clusterSample(px, box: $0) == nil }.count } ?? 0
        facts.unmeasuredShare = textOnly.isEmpty ? 0 : Double(unmeasured) / Double(textOnly.count)
        facts.primaryCount = L.primary == nil ? 0 : 1
        facts.primaryText = L.primary.map { L.boxes[$0].text } ?? ""
        let kind = L.context.adjust(ScreenKind.resolve(vision: L.vision, width: full.width, height: full.height), width: full.width, height: full.height)
        let code = Scoring.codeAnswers(facts, pixels: pixels, appScreen: kind == .app)
        var answers = code.answers
        for (k, v) in Scoring.visionAnswers(facts, stats: stats) where answers[k] == nil { answers[k] = v }
        return CodeStage(scaled: scaled, facts: facts, contrast: code.contrast, note: code.note, answers: answers, stats: stats, screenKind: kind)
    }

    func notApplicable(_ c: CodeStage, labelled L: Labelled) -> Set<String> {
        Applicability.notApplicable(kind: c.screenKind, pageType: L.vision["page_type"].string ?? "", facts: c.facts, context: L.context)
    }

    /// Designer ratings start as soon as the code facts exist and run in parallel with Jev and the writer.
    func startDesigner(labelled L: Labelled, code c: CodeStage, full: CGImage, reading: Reading?, input: ModelInput, hash: String?, useCache: Bool, cacheDir: URL) -> Task<Designer.Rating?, Never> {
        let facts = Designer.facts(context: L.context, width: full.width, height: full.height, contrast: c.contrast, stats: c.stats, readingWords: reading?.words ?? 0)
        let client = client, key = keys.claude, img = input.img
        return Task { await Designer.rate(client: client, keys: key, image: img, facts: facts, hash: useCache ? hash : nil, cacheDir: cacheDir) }
    }

    func contrastMeter(code c: CodeStage) -> MeterResult {
        var ans: [String: CheckAnswer] = [:]
        for ch in Rubric.checks(for: "contrast") { ans[ch.id] = (c.answers[ch.id] ?? false, nil, "code") }
        var r = Scoring.weightedScore("contrast", answers: ans)
        r.note = c.note
        return r
    }

    /// Meters whose checks code already answered do not wait for Jev.
    func emitCodeOnlyMeters(_ stages: Stages, answers: [String: Bool], notApplicable na: Set<String>, context: PageContext) {
        for m in Rubric.meterKeys where m != "contrast" {
            let cs = Rubric.checks(for: m).filter { !na.contains($0.id) }
            guard !cs.isEmpty, cs.allSatisfy({ answers[$0.id] != nil }) else { continue }
            var ans: [String: CheckAnswer] = [:]
            for c in Rubric.checks(for: m) { ans[c.id] = (answers[c.id] ?? false, nil, "code") }
            stages.emit(meters: [m: Scoring.weightedScore(m, answers: ans, cap: nil, notApplicable: na, weights: Applicability.contextWeights(context))], ready: [m])
        }
    }

    /// What the writer is told before Jev answers: every check answered so far; Jev-only checks come later.
    func provisionalWriterFacts(pageName: String, labelled L: Labelled, code c: CodeStage, layoutMeters: [String: MeterResult], layoutProblems lp: [String: [String]], reading rd: Reading?, imageHeight: Int) -> [String: Any] {
        var sc: [String: Any] = [:]
        for m in Rubric.meterKeys {
            let cs = Rubric.checks(for: m)
            let failed = Self.writerFailedText(Array(cs.filter { c.answers[$0.id] == false }.prefix(3)))
            let got = cs.filter { c.answers[$0.id] == true }.reduce(0) { $0 + $1.w }
            let known = cs.filter { c.answers[$0.id] != nil }.reduce(0) { $0 + $1.w }
            sc[m] = ["score": known == 0 ? 0 : Int((Double(got) / Double(known) * 100).rounded()), "failed": failed]
        }
        for (k, v) in layoutMeters { sc[k] = ["score": v.score, "failed": lp[k] ?? [String]()] }
        if let rd { sc["reading"] = ["grade": rd.grade, "score": Int((Self.gradePoints(rd.grade) * 10).rounded())] }
        let weak = c.contrast.boxes.filter { !$0.pass && $0.ratio != nil }.prefix(2).map { "\(Self.truncate($0.text, max: 24)) \(String(format: "%.1f", $0.ratio!)):1" }
        var f: [String: Any] = ["page": pageName, "copy": String(c.facts.allCopy.prefix(500)),
                                "look": Self.truncate(L.vision["visual_description"].string ?? "", max: 240), "meters": sc]
        if !weak.isEmpty { f["weak_text"] = Array(weak) }
        f["feeling_facts"] = Self.feelingFacts(stats: c.stats, copy: c.facts.allCopy)
        if let rd { f["reading_facts"] = Readability.hardest(paras: Readability.countedParagraphs(c.scaled, imageHeight: imageHeight)).merging(["grade": rd.grade, "capped": rd.capped]) { a, _ in a } }
        return f
    }

    /// Only the checks code could not answer go to Jev.
    func askJev(labelled L: Labelled, code c: CodeStage, notApplicable na: Set<String>) async throws -> (p: [String: Double], ms: Double) {
        var state: [String: JSONValue] = [:]
        if case .object(let o) = L.vision { state = o }
        // Free text from the model (name, description, role ids) wobbles between runs and would sway Jev's answers.
        for k in ["roles", "visual_description", "page_name", "primary_y_pct", "primary_y_pt", "heaviest_weight", "logo_position", "main_text_alignment", "real_imagery", "text_on_busy_bg"] { state[k] = nil }
        state["all_copy"] = .string(c.facts.allCopy)
        state["text_box_count"] = .number(Double(c.facts.boxes.count))
        var qs: [String: String] = [:]
        let wording = Applicability.contextWording(L.context)
        for ch in Rubric.checks where c.answers[ch.id] == nil && !na.contains(ch.id) { qs[ch.id] = wording[ch.id] ?? ch.jev }
        if qs.isEmpty { return ([:], 0) }
        return try await client.jev(key: keys.jev, state: .object(state), questions: qs)
    }

    func scoreMeters(_ a: Answerer, notApplicable na: Set<String>, context: PageContext, codeNote: String?, layoutMeters: [String: MeterResult]) -> [String: MeterResult] {
        var meters: [String: MeterResult] = [:]
        for m in Rubric.meterKeys {
            var r = Scoring.weightedScore(m, answers: a.answers(for: m), cap: nil, notApplicable: na, weights: Applicability.contextWeights(context))
            if m == "contrast" { r.note = codeNote }
            meters[m] = r
        }
        for (k, v) in layoutMeters { meters[k] = v }
        return meters
    }

    /// Feeling scores and the confidence behind each of the four feeling checks groups.
    func scoreFeeling(_ a: Answerer) -> (score: [String: Int], confidence: [String: Int]) {
        var score: [String: Int] = [:], conf: [String: Int] = [:]
        for k in Rubric.feelingKeys {
            let cs = Rubric.checks(for: k)
            let rs = cs.map { c -> CheckResult in let r = a.answer(c); return CheckResult(id: c.id, yes: r.yes, p: r.p, weight: c.w, kind: r.kind) }
            score[k] = Feeling.score(rs, checks: cs)
            conf[k] = Int((rs.reduce(0.0) { $0 + Double($1.weight) * ($1.p.map { max($0, 1 - $0) } ?? 1) } / Double(max(1, cs.reduce(0) { $0 + $1.w })) * 100).rounded())
        }
        return (score, conf)
    }

    /// The writer sees the final blended scores, the failed checks (code and Jev) and the designer's deduction.
    func writeText(for result: RunResult, provisional: [String: Any], layoutProblems lp: [String: [String]], stats: PixelStats?, copy: String) async -> JSONValue? {
        var facts = provisional
        var sc = (facts["meters"] as? [String: Any]) ?? [:]
        var failed: [String: [String]] = [:]
        for k in Meters.order where k != "reading" {
            failed[k] = Rubric.checks(for: k).filter { !Self.navCountIDs.contains($0.id) }.filter { c in result.meters[k]?.checks.first { $0.id == c.id }?.yes == false }.prefix(3).map { Self.plainCheck[$0.id] ?? $0.q }
        }
        for (k, v) in lp { failed[k] = v }
        for (k, v) in Pipeline.writerMeterFacts(meters: result.meters.filter { $0.value.applicable != false }, failed: failed) { sc[k] = v }
        facts["meters"] = sc
        facts["feeling_facts"] = Self.feelingFacts(stats: stats, copy: copy)
        return await askWriter(facts)
    }

    func askWriter(_ facts: [String: Any]) async -> JSONValue? {
        guard let data = try? JSONSerialization.data(withJSONObject: facts), let str = String(data: data, encoding: .utf8) else { return nil }
        return try? await client.claude(keys: keys.claude, system: Prompts.write, content: [["type": "text", "text": str]], maxTokens: 900, model: Claude.model, cacheSystem: false).json
    }
}
