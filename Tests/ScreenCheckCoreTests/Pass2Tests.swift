import XCTest
@testable import ScreenCheckCore

final class Pass2Tests: XCTestCase {
    func json(_ s: String) -> JSONValue { try! JSONValue.firstObject(in: s) }
    func tb(_ t: String, _ px: Double, _ role: String = "body") -> TextBox { TextBox(text: t, x: 0, y: 0, w: 100, h: 20, fontPx: px, bold: false, role: role, onImage: false) }

    // A: one box never carries two roles after the vote; heading beats logo.
    func testMajorityGivesEachBoxOneRole() {
        let a = json("{\"roles\":{\"heading\":[0],\"logo\":[0],\"primary\":[]}}"), b = json("{\"roles\":{\"heading\":[0],\"logo\":[0],\"primary\":[]}}"), c = json("{\"roles\":{\"heading\":[0],\"logo\":[],\"primary\":[]}}")
        let m = Pipeline.majority([a, b, c])
        XCTAssertEqual(m["roles"]["heading"].array.count, 1)
        XCTAssertEqual(m["roles"]["logo"].array.count, 0)
    }
    func testLargestTextIsNeverALogo() {
        let boxes = [tb("Comp Neo UX", 26), tb("Email", 14), tb("Password", 14), tb("Sign in", 14)]
        let out = OCR.applyRoles(json("{\"logo\":[0]}"), to: boxes)
        XCTAssertNotEqual(out[0].role, "logo")
    }

    // B: the writer never quotes numbers or names another meter.
    func testWhyHasNoScoreNumbersOrOtherMeters() {
        XCTAssertEqual(Pipeline.cleanWhy("Balance scores 88 because the card floats low.", meter: "balance"), "The card floats low.")
        XCTAssertEqual(Pipeline.cleanWhy("The lowest score is order, which lacks hierarchy.", meter: "balance"), "")
        XCTAssertEqual(Pipeline.cleanWhy("Clarity loses points because the balance issue makes the hero uneven.", meter: "clarity"), "")
        XCTAssertEqual(Pipeline.cleanWhy("Body text is under 16 px.", meter: "ease"), "Body text is under 16 px.")
    }

    // C: a CTA visible on the first screen passes.
    func testVisibleCtaPassesFold() {
        let f = Scoring.facts(from: json("{\"primary_y_pt\":640}"), textBoxes: [tb("Get started", 16, "button")])
        var g = f; g.primaryCount = 1
        XCTAssertEqual(Scoring.visionAnswers(g, stats: nil)["h_cta_fold"], true)
        let low = Scoring.facts(from: json("{\"primary_y_pt\":1500}"), textBoxes: [tb("Get started", 16, "button")])
        var h = low; h.primaryCount = 1
        XCTAssertEqual(Scoring.visionAnswers(h, stats: nil)["h_cta_fold"], false)
    }

    // D: banned fix shapes are dropped; a real one survives.
    func testFixGuards() {
        for bad in ["Add placeholder text to the Email field.", "Move the chat widget away from the button.", "Move the nav links to the right.", "Align the nav and hero text on one shared left edge.", "Review the layout.", "Consider simplifying the page.", "Remove or move the promo away from the main action.", "Replace the ribbon with a real product screenshot."] {
            XCTAssertTrue(Pipeline.bannedFix(bad), bad)
        }
        XCTAssertFalse(Pipeline.bannedFix("Make the title white so it leads the card."))
    }
    func testNoFixWithoutRealDeduction() {
        // score below 100 but no failed check and no designer deduction: Why only
        XCTAssertEqual(Pipeline.finalFix("Make it pop.", score: 90, problem: true, failed: [], meter: "balance", hasDeduction: false), "")
    }

    // Final check: nav count is scored but never advised; vague emphasis advice is dropped.
    func testNavCountNeverBecomesFixOrNag() {
        for bad in ["Cut the nav to 7 or fewer items.", "Group nav items under 5-7 headings.", "Make all but the headline less bold.", "Lower the emphasis on all but the 1-3 items that matter."] {
            XCTAssertTrue(Pipeline.bannedFix(bad), bad)
        }
        XCTAssertFalse(Pipeline.bannedFix("Make the title heavier so it leads the card."))
        let nav = Rubric.checks(for: "clarity").first { $0.id == "C4" }!
        XCTAssertEqual(Pipeline.finalFix("", score: 80, problem: true, failed: [nav], meter: "clarity"), "")
        XCTAssertEqual(Pipeline.cleanWhy("The nav has more than seven items. The headline is a slogan.", meter: "clarity"), "The headline is a slogan.")
        XCTAssertEqual(Pipeline.cleanWhy("Too many menu choices in the top nav slow people down.", meter: "familiar"), "")
        XCTAssertEqual(Pipeline.cleanWhy("The nav is quiet.", meter: "order"), "The nav is quiet.")
    }

    func testFallbackFixIsGuardedAndLeakedScoresStripped() {
        let c8 = Rubric.checks(for: "clarity").first { $0.id == "C8" }!
        XCTAssertEqual(Pipeline.finalFix("", score: 89, problem: true, failed: [c8], meter: "clarity"), "")
        let t3 = Rubric.checks(for: "trust").first { $0.id == "T3" }!
        XCTAssertEqual(Pipeline.finalFix("", score: 90, problem: true, failed: [t3], meter: "trust"), "")
        for bad in ["Cut copy until each block has one idea.", "Add 3-6 real customer logos or one sourced number.", "Change the \"Pro further.\" line to say what the phone does."] { XCTAssertTrue(Pipeline.bannedFix(bad), bad) }
        XCTAssertEqual(Pipeline.cleanWhy("Balance is at 75 because the weight drops low.", meter: "balance"), "The weight drops low.")
    }

    // Reviewer findings.
    func testCtaFoldFallbackNeedsMeasurement() {
        var g = Scoring.facts(from: json("{\"primary_y_pct\":80}"), textBoxes: [tb("Go", 16, "button")]); g.primaryCount = 1
        XCTAssertEqual(Scoring.visionAnswers(g, stats: nil)["h_cta_fold"], false)
        var h = Scoring.facts(from: json("{\"primary_y_pct\":40}"), textBoxes: [tb("Go", 16, "button")]); h.primaryCount = 1
        XCTAssertEqual(Scoring.visionAnswers(h, stats: nil)["h_cta_fold"], true)
        var n = Scoring.facts(from: json("{}"), textBoxes: [tb("Go", 16, "button")]); n.primaryCount = 1
        XCTAssertNil(Scoring.visionAnswers(n, stats: nil)["h_cta_fold"])
    }
    func testSubmitAdviceUsesWordsAndPositionOnly() {
        XCTAssertFalse(Pipeline.unsafeSubmitAdvice("Raise the button contrast above 4.5:1."))
        XCTAssertFalse(Pipeline.unsafeSubmitAdvice("Group the setup steps so the button stays last."))
        XCTAssertTrue(Pipeline.unsafeSubmitAdvice("Move the Sign in button above the fields."))
    }
    func testBannedFixIsNarrow() {
        for ok in ["Darken the placeholder text so it passes 4.5:1.", "Show a visible focus state on each field.", "Put an underline on links."] { XCTAssertFalse(Pipeline.bannedFix(ok), ok) }
        XCTAssertTrue(Pipeline.bannedFix("Use placeholders as labels."))
    }
    func testWhyKeepsDecimalsAndUnits() {
        XCTAssertEqual(Pipeline.cleanWhy("Body text is 16px, and the ratio is 4.5:1.", meter: "ease"), "Body text is 16px, and the ratio is 4.5:1.")
        XCTAssertEqual(Pipeline.cleanWhy("Body is 16px. The weight leans left.", meter: "ease"), "Body is 16px.")
    }
    func testFormMatchIsAWord() {
        var f = Scoring.facts(from: json("{}"), textBoxes: [tb("Go", 16, "button")]); f.primaryCount = 1
        XCTAssertFalse(Applicability.notApplicable(kind: .marketing, pageType: "platform", facts: f).contains("h_cta_fold"))
        XCTAssertTrue(Applicability.notApplicable(kind: .marketing, pageType: "sign-in form", facts: f).contains("h_cta_fold"))
    }

    // Final pass: plain Why fallback, no stale problems at 100, one change per Fix.
    func testFallbackWhyIsPlain() {
        let c8 = Rubric.checks(for: "clarity").first { $0.id == "C8" }!
        let w = Pipeline.fallbackWhy(score: 89, failed: [c8], designer: nil, designerReason: "")
        XCTAssertFalse(w.contains("Points lost"))
        XCTAssertFalse(w.contains("?"))
        XCTAssertTrue(w.hasSuffix("."))
        XCTAssertEqual(Pipeline.fallbackWhy(score: 63, failed: [], designer: 63, designerReason: "Balance is the lowest at 6: the weight leans left."), "The weight leans left.")
        XCTAssertTrue(Pipeline.fallbackWhy(score: 83, failed: [], designer: nil, designerReason: "").isEmpty)   // nothing real to say: say nothing
        XCTAssertEqual(Pipeline.fallbackWhy(score: 100, failed: [], designer: 100, designerReason: ""), "")
    }
    func testDesignerDeductionNamedInEaseWhy() {
        let r = stub(meters: ["ease": MeterResult(score: 75, lowConfidence: false, confidencePct: 100, checks: [], note: nil, designer: 75, applicable: nil)], designerReason: "The page is dense.")
        let t = Pipeline.texts(for: r, written: try! JSONValue.firstObject(in: "{\"ease\":[\"Too many words.\",\"\",1]}"))
        XCTAssertTrue(t["ease"]!.why.contains("dense"), t["ease"]!.why)
    }
    func testNoProblemWhyAtFullScore() {
        let r = stub(meters: ["ease": MeterResult(score: 100, lowConfidence: false, confidencePct: 100, checks: [], note: nil, applicable: nil)], designerReason: "")
        let t = Pipeline.texts(for: r, written: try! JSONValue.firstObject(in: "{\"ease\":[\"The body text is under 16 px.\",\"\",0]}"))
        XCTAssertFalse(t["ease"]!.why.contains("under 16"))
    }
    func testOneChangePerFix() {
        for bad in ["Put the body copy on a flat, solid background and make it at least 16 px.", "Make the \"iPhone 18 Pro\" heading one step smaller or lighter.", "Enlarge the title; shrink the logo."] { XCTAssertTrue(Pipeline.bannedFix(bad), bad) }
        XCTAssertFalse(Pipeline.bannedFix("Set the body text to at least 16 px."))
        XCTAssertFalse(Pipeline.bannedFix("Make the title white and bold."))
    }

    func stub(meters: [String: MeterResult], designerReason: String) -> RunResult {
        var r = RunResult(id: "s", createdAt: Date(), pageName: "P", imageWidth: 1, imageHeight: 1, meters: meters, feeling: [:], feelingLow: [:], feelingConfidencePct: [:], readingGrade: nil, readingWords: 0, text: [:], timings: Timings(), contrastDetail: nil, vision: .null, pixelStats: nil)
        r.designerReason = designerReason
        r.designerReasons = designerReason.isEmpty ? nil : Dictionary(uniqueKeysWithValues: Designer.meters.map { ($0, designerReason) })
        return r
    }

    func testOneChangeWithAndInObjectPasses() {
        XCTAssertFalse(Pipeline.bannedFix("Darken the label and hint text."))
        XCTAssertFalse(Pipeline.bannedFix("Set the title and subtitle to white."))
        XCTAssertTrue(Pipeline.bannedFix("Darken the label and make the hint text larger."))
        XCTAssertTrue(Pipeline.bannedFix("Darken the label, then raise the hint size."))
    }
    func testPageTextIgnoresWobblingDemoLabels() {
        func b(_ i: Int, _ x: Double, _ y: Double, _ role: String) -> TextBox { TextBox(text: "t\(i)", x: x, y: y, w: 80, h: 16, fontPx: 14, bold: false, role: role, onImage: false) }
        let head = [b(0, 10, 10, "heading"), b(1, 10, 50, "body"), b(2, 10, 80, "body"), b(3, 10, 110, "body")]
        let demoA = [b(4, 300, 300, "demo"), b(5, 300, 330, "demo"), b(6, 400, 360, "demo"), b(7, 500, 400, "demo")]
        var demoB = demoA; demoB[1].role = "body"          // one demo box unlabelled in another run, still inside the demo area
        XCTAssertEqual(Layout.pageText(head + demoA).count, 4)
        XCTAssertEqual(Layout.pageText(head + demoB).count, 4)
    }

    // Text pass.
    func testCachedDesignerVotesReusedWithoutCalls() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dz-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let r = Designer.Rating(scores: Dictionary(uniqueKeysWithValues: Designer.meters.map { ($0, 6.4) }), reason: "x")
        try JSONEncoder().encode(r).write(to: dir.appendingPathComponent("designer-abc-\(Designer.version).json"))
        // no keys and no image: any API call would fail, so a result proves the cache was used
        let got = await Designer.rate(keys: [], image: [:], facts: "", hash: "abc", cacheDir: dir)
        XCTAssertEqual(got, r)
    }
    func meterD(_ s: Int, _ d: Int?) -> MeterResult { MeterResult(score: s, lowConfidence: false, confidencePct: 100, checks: [], note: nil, designer: d, applicable: nil) }
    func testDesignerOnlyMeterShowsItsOwnReasonAndNoOthers() {
        var r = stub(meters: ["balance": meterD(63, 63), "ease": meterD(75, 75), "order": meterD(85, 85)], designerReason: "")
        r.designerReasons = ["balance": "The grid leans to the left.", "ease": "The page is dense.", "order": "The title is weak."]
        let t = Pipeline.texts(for: r, written: try! JSONValue.firstObject(in: "{\"balance\":[\"Writer balance.\",\"\",1]}"))
        XCTAssertEqual(t["balance"]!.why, "The grid leans to the left.")
        XCTAssertEqual(t["ease"]!.why, "The page is dense.")
        XCTAssertEqual(t["order"]!.why, "The title is weak.")
        for k in ["balance", "ease", "order"] { XCTAssertFalse(t[k]!.why.hasPrefix(Pipeline.genericWhyPrefix), k) }
    }
    func testWhyLeadingFragmentAndRawCheckText() {
        XCTAssertEqual(Pipeline.cleanWhy("; the banner near the button cost points.", meter: "clarity"), "The banner near the button cost points.")
        XCTAssertEqual(Pipeline.cleanWhy("Only 3 or fewer elements are shouted. The nav is loud.", meter: "order"), "The nav is loud.")
        XCTAssertEqual(Pipeline.cleanWhy("Smallest font_px is 12 or more.", meter: "ease"), "")
        let e9 = Rubric.checks(for: "ease").first { $0.id == "E9" }!
        let w = Pipeline.fallbackWhy(score: 88, failed: [e9], designer: nil, designerReason: "")
        XCTAssertFalse(w.contains("font_px")); XCTAssertFalse(w.contains("Points were lost"))
    }
    func testFixQuotesMustBeOnPage() {
        XCTAssertFalse(Pipeline.quotesOnPage("Change the link to Explore iPhone Duo features.", page: "Learn more iPhone"))
        XCTAssertFalse(Pipeline.quotesOnPage("Rename \"Explore Duo\" to a plain verb.", page: "Learn more iPhone"))
        XCTAssertTrue(Pipeline.quotesOnPage("Rename \"Learn more\" to a plain verb.", page: "Learn more iPhone"))
        XCTAssertTrue(Pipeline.quotesOnPage("Make the title brighter.", page: ""))
    }
    func testVagueFixesBanned() {
        for bad in ["Set the hero text and the two pill buttons to share one centre line.", "Raise the smallest text to 12-14px.", "Raise the smallest text to 12 px."] { XCTAssertTrue(Pipeline.bannedFix(bad), bad) }
        XCTAssertFalse(Pipeline.bannedFix("Set the main body text to 16 px."))
    }

    func testLateTextFindings() {
        XCTAssertEqual(Pipeline.cleanWhy("The balance score lost points because the weight sits low.", meter: "balance"), "The weight sits low.")
        XCTAssertTrue(Pipeline.bannedFix("Set the \"Available starting 10.23\" line to 14 px."))
        XCTAssertFalse(Pipeline.bannedFix("Set the main body text to 16 px."))
    }

    func testLastGuards() {
        for bad in ["Lower the weak \"Sign in\" link contrast to a darker blue.", "Reduce the contrast of the headline.",
                    "Place the logo row on one shared horizontal line with equal spacing.", "Place the product copy inside a single panel with a shared left edge.", "Put the text in one panel.",
                    "Change the headline \"Hello,\" to a plain line naming the iPhone Duo.", "Rewrite the headline to say what the phone does.", "Change the headline to Buy the best phone."] { XCTAssertTrue(Pipeline.bannedFix(bad), bad) }
        XCTAssertFalse(Pipeline.bannedFix("Darken the \"Sign in\" link to raise its contrast."))
        XCTAssertFalse(Pipeline.bannedFix("Raise the contrast of the \"Sign in\" link."))
        XCTAssertFalse(Pipeline.bannedFix("Make the title brighter so it matches the button."))
        XCTAssertFalse(Pipeline.bannedFix("Change the headline to \"Hello\"."))
        XCTAssertTrue(Pipeline.bannedFix("Change the headline to \"Hello\".", page: "Learn more"))
        XCTAssertFalse(Pipeline.bannedFix("Change the headline to \"Hello\".", page: "Hello there"))
    }

    // Structural: Fix = vetted rubric sentence of the heaviest failed check; writer's Fix is ignored.
    func testFixComesFromHeaviestFailedRubricCheck() {
        let ease = Rubric.checks(for: "ease")
        let e10 = ease.first { $0.id == "E10" }!, e1 = ease.first { $0.id == "E1" }!
        let r = stub(meters: ["ease": MeterResult(score: 70, lowConfidence: false, confidencePct: 100, checks: [CheckResult(id: "E10", yes: false, p: nil, weight: 10, kind: "code"), CheckResult(id: "E1", yes: false, p: nil, weight: 12, kind: "code")], note: nil)], designerReason: "")
        let t = Pipeline.texts(for: r, written: try! JSONValue.firstObject(in: "{\"ease\":[\"Text is small.\",\"Do something invented.\",1]}"))
        XCTAssertEqual(t["ease"]!.fix, e1.fix)   // E1 weighs 12 > E10 10
        XCTAssertNotEqual(t["ease"]!.fix, "Do something invented.")
        _ = e10
    }
    func testDesignerOnlyDeductionHasNoFix() {
        let r = stub(meters: ["order": meterD(80, 70)], designerReason: "The title is weak.")
        let t = Pipeline.texts(for: r, written: try! JSONValue.firstObject(in: "{\"order\":[\"The title is weak.\",\"Make the title bigger.\",1]}"))
        XCTAssertEqual(t["order"]!.fix, "")
        XCTAssertFalse(t["order"]!.why.isEmpty)
    }
    func testEveryRubricFixIsConcreteOrBlank() {
        for c in Rubric.checks where !["vv","vi","cv","ci"].contains(c.meter) {
            XCTAssertFalse(Pipeline.bannedFix(c.fix), c.id + ": " + c.fix)
            XCTAssertFalse(c.fix.lowercased().contains(" or fewer.") && ["C4", "f_navcount"].contains(c.id), c.id)
            XCTAssertTrue(c.fix.isEmpty || c.fix.hasSuffix("."), c.id)
        }
        for id in ["C4", "f_navcount", "C6", "T2", "T3", "E9", "C8"] { XCTAssertEqual(Rubric.checks.first { $0.id == id }!.fix, "", id) }
    }
    func testNothingWorthChangingNeverShown() {
        XCTAssertEqual(Pipeline.cleanWhy("The weight leans left. Nothing is worth changing.", meter: "balance"), "The weight leans left.")
        XCTAssertEqual(Pipeline.cleanWhy("A small deduction remains; nothing is worth changing.", meter: "balance"), "")
        let r = stub(meters: ["balance": meterD(80, nil)], designerReason: "")
        let t = Pipeline.texts(for: r, written: nil)
        XCTAssertFalse(t["balance"]!.why.lowercased().contains("worth changing"))
        XCTAssertTrue(t["balance"]!.why.isEmpty)
    }
    func testWhyDropsOtherMetersTopics() {
        XCTAssertEqual(Pipeline.cleanWhy("The weight sits on the right. The primary button is vague.", meter: "balance"), "The weight sits on the right.")
        XCTAssertEqual(Pipeline.cleanWhy("Body text is 16px.", meter: "ease"), "Body text is 16px.")
    }
    func testWhyDropsRatingTalk() {
        XCTAssertEqual(Pipeline.cleanWhy("The weight leans left. It doesn't reach 9.", meter: "balance"), "The weight leans left.")
        XCTAssertEqual(Pipeline.cleanWhy("Balance is the lowest here. The weight leans left.", meter: "balance"), "The weight leans left.")
        XCTAssertEqual(Pipeline.cleanWhy("The designer found it heavy. The weight leans left.", meter: "balance"), "The weight leans left.")
        XCTAssertEqual(Pipeline.cleanWhy("It rates 7 for weight.", meter: "balance"), "")
    }
    func testGenericFallbackNotAppendedToRealWhy() {
        let r = stub(meters: ["balance": MeterResult(score: 80, lowConfidence: false, confidencePct: 100, checks: [], note: nil, designer: 80, applicable: nil)], designerReason: "")
        let t = Pipeline.texts(for: r, written: try! JSONValue.firstObject(in: "{\"balance\":[\"The weight leans left.\",\"\",0]}"))
        XCTAssertEqual(t["balance"]!.why, "The weight leans left.")
    }
}

final class CalibrationTests: XCTestCase {
    func box(_ t: String, _ y: Double, _ px: Double, role: String = "body", bold: Bool = false) -> TextBox { TextBox(text: t, x: 40, y: y, w: 300, h: px, fontPx: px, bold: bold, role: role, onImage: false) }

    func testContrastHasFourSubRubricsSummingTo100() {
        let ids = Rubric.checks(for: "contrast").map { $0.id }
        for id in ["c_aa", "c_size", "c_weight", "c_space"] { XCTAssertTrue(ids.contains(id), id) }
        XCTAssertEqual(Rubric.checks(for: "contrast").reduce(0) { $0 + $1.w }, 100)
    }
    func testButtonLabelNeedsThreeToOne() {
        var d = [UInt8](repeating: 255, count: 120 * 40 * 4)
        for y in 0..<40 { for x in 0..<120 { let i = (y * 120 + x) * 4; let v: UInt8 = (x + y) % 3 == 0 && x > 10 && x < 100 && y > 10 && y < 30 ? 255 : 0x33; d[i] = v; d[i+1] = v; d[i+2] = v } }
        let px = Pixels(width: 120, height: 40, data: d)
        let b = TextBox(text: "Go now", x: 5, y: 5, w: 110, h: 30, fontPx: 14, bold: false, role: "button", onImage: false)
        XCTAssertEqual(Contrast.report(px, boxes: [b], expected: 1).boxes[0].need, 3.0)
    }
    func testSizeContrastNeedsHeadlineWellAboveBody() {
        let flat = [box("Headline words", 0, 18), box("A sentence of body text long enough", 40, 16), box("Another sentence of body text here", 70, 16)]
        let big = [box("Headline words", 0, 48), box("A sentence of body text long enough", 70, 16), box("Another sentence of body text here", 100, 16)]
        XCTAssertEqual(Scoring.codeAnswers(Scoring.facts(from: .null, textBoxes: flat), pixels: nil).answers["c_size"], false)
        XCTAssertEqual(Scoring.codeAnswers(Scoring.facts(from: .null, textBoxes: big), pixels: nil).answers["c_size"], true)
    }
    func testGroupingAlignmentIsMinorAndMeaningIsScored() {
        let cs = Layout.groupingChecks(GroupingMetrics())
        XCTAssertEqual(cs.first { $0.id == "g_align" }?.weight, 10)
        XCTAssertTrue(cs.contains { $0.id == "g_meaning" })
        XCTAssertEqual(cs.reduce(0) { $0 + $1.weight }, 100)
    }
    func testAlignmentNamedOnlyWhenItIsTheOnlyFailure() {
        func m(_ meaning: Bool?) -> [String] {
            let b = (0..<8).map { TextBox(text: "word", x: 40 + Double($0 % 3) * 31, y: Double($0) * 22, w: 200, h: 16, fontPx: 16, bold: false, role: "body", onImage: false) }
            return Layout.problems(pixels: nil, boxes: b, imageWidth: 800, meaning: meaning)["grouping"] ?? []
        }
        XCTAssertFalse(m(false).contains { $0.contains("left, right or centre") })
    }
    func testBalanceToleratesAsymmetricHero() {
        var b = BalanceMetrics(); b.centroidX = -0.35; b.centroidY = 0.1; b.leftRight = 0.4; b.symmetry = 0.65
        XCTAssertEqual(Layout.balanceScore(b), 100)
    }
    func testEaseNeverClaimsAbsoluteTextSize() {
        XCTAssertEqual(Pipeline.groundedWhy("The body text is under 16 px. Lines run long.", meter: "ease", overlayPresent: false), "Lines run long.")
        XCTAssertEqual(Pipeline.groundedWhy("The text is too small.", meter: "ease", overlayPresent: false), "")
    }
    func testNoClaimedElementThatIsAbsent() {
        XCTAssertEqual(Pipeline.groundedWhy("Ad-like items clutter the page.", meter: "trust", overlayPresent: false), "")
        XCTAssertEqual(Pipeline.groundedWhy("A cookie banner competes with the button.", meter: "clarity", overlayPresent: true), "A cookie banner competes with the button.")
        XCTAssertEqual(Pipeline.groundedWhy("Groups lack a card or panel.", meter: "grouping", overlayPresent: false), "")
        XCTAssertEqual(Pipeline.groundedWhy("Items do not line up on a shared edge.", meter: "grouping", overlayPresent: false), "")
    }
    func testContrastExplainsItsFailures() {
        let r = RunResult.placeholder
        let w = Pipeline.contrastWhy(r, failedIDs: ["c_size", "c_weight"], score: 72, fallback: "")
        XCTAssertTrue(w.contains("larger") && w.contains("heavier"), w)
        XCTAssertFalse(Pipeline.contrastWhy(r, failedIDs: [], score: 100, fallback: "").isEmpty)
    }
    func testDemoTextIsNotReadingLoadAndOverlayLeavesLayout() {
        let boxes = [box("Real copy here", 0, 16), box("demo words", 30, 12, role: "demo"), box("cookie words", 60, 12, role: "overlay")]
        XCTAssertFalse(Scoring.facts(from: .null, textBoxes: boxes).allCopy.contains("demo words"))
        XCTAssertEqual(Scoring.content(boxes).count, 1)
    }
    func testDemoAndLogosCountAsTrust() {
        var f = Scoring.facts(from: .null, textBoxes: [])
        f.allBoxes = (0..<5).map { box("logo\($0)", Double($0) * 30, 14, role: "logo") }
        XCTAssertEqual(Scoring.visionAnswers(f, stats: nil)["T2"], true)
        f.allBoxes = (0..<4).map { box("ui\($0)", Double($0) * 30, 12, role: "demo") }
        XCTAssertEqual(Scoring.visionAnswers(f, stats: nil)["T3"], true)
    }
}
