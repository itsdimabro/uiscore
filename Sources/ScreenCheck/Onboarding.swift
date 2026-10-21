import SwiftUI
import AppKit
import KeyboardShortcuts
import ScreenCheckCore

struct KeyRow: Identifiable, Equatable { let id = UUID(); var text: String }

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step = 0
    @Published var forward = true
    @Published var jev = ""
    @Published var rows: [KeyRow] = [KeyRow(text: "")]
    @Published var jevResult: KeyVerdict?
    @Published var results: [UUID: KeyVerdict] = [:]
    @Published var testing = false
    @Published var showIssues = false
    var demo = false
    var onDone: () -> Void = {}

    init(demo: Bool = false) {
        self.demo = demo
        if demo { return }
        jev = KeyStore.get("jev") ?? ""
        let c = KeyStore.claudeKeys()
        if !c.isEmpty { rows = c.map { KeyRow(text: $0) } }
    }

    var claude: [String] { rows.map { $0.text } }
    var issues: [KeyRules.Issue] { KeyRules.validate(jev: jev, claude: claude) }
    func issue(_ f: KeyRules.Field) -> String? { showIssues ? issues.first { $0.field == f }?.message : nil }
    var canContinue: Bool { issues.isEmpty }

    func next() {
        if step == 1 { showIssues = true; guard canContinue else { return }; save() }
        go(min(2, step + 1), forward: true)
    }
    func back() { go(max(0, step - 1), forward: false) }
    /// Direction is published first so the outgoing view's transition already knows it when the step changes.
    private func go(_ to: Int, forward f: Bool) {
        forward = f
        DispatchQueue.main.async { withAnimation(T.open(0.32)) { self.step = to } }
    }
    func save() {
        guard !demo else { return }
        KeyStore.set("jev", jev.trimmingCharacters(in: .whitespacesAndNewlines))
        KeyStore.setClaudeKeys(KeyRules.cleaned(claude))
    }
    func finish() { save(); onDone() }
    func add() { withAnimation(T.open(0.25)) { rows.append(KeyRow(text: "")) } }
    func remove(_ id: UUID) {
        withAnimation(T.close(0.2)) { rows.removeAll { $0.id == id }; if rows.isEmpty { rows = [KeyRow(text: "")] }; results[id] = nil }
    }

    func test() {
        showIssues = true
        guard canContinue, !testing else { return }
        testing = true; jevResult = nil; results = [:]
        let j = jev.trimmingCharacters(in: .whitespacesAndNewlines)
        let todo = rows.map { ($0.id, $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }.filter { !$0.1.isEmpty }
        Task {
            async let jr = KeyCheck.jev(j)
            for (id, k) in todo { let v = await KeyCheck.claude(k); withAnimation(T.open(0.25)) { results[id] = v } }
            let v = await jr
            withAnimation(T.open(0.25)) { jevResult = v; testing = false }
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var m: OnboardingModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Capsule().fill(T.track).frame(height: 4)
                        .overlay(Capsule().fill(T.accent).scaleEffect(x: i <= m.step ? 1 : 0, anchor: .leading))
                        .clipShape(Capsule())
                }
            }.padding(.bottom, 22).animation(T.open(0.32), value: m.step)
            ZStack(alignment: .topLeading) {
                switch m.step {
                case 0: Welcome().transition(slide)
                case 1: KeysStep(m: m).transition(slide)
                default: ShortcutStep(m: m).transition(slide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                if m.step > 0 { Button("Back") { m.back() }.buttonStyle(QuietButton()) }
                Spacer()
                switch m.step {
                case 0: Button("Get started") { m.next() }.buttonStyle(PrimaryButton())
                case 1: Button("Continue") { m.next() }.buttonStyle(PrimaryButton())
                default: Button("Done") { m.finish() }.buttonStyle(PrimaryButton())
                }
            }.padding(.top, 14)
        }
        .padding(28)
        .frame(width: 520, height: 620)
        .background(T.card)
    }
    var slide: AnyTransition {
        let d: CGFloat = m.forward ? 1 : -1
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: 48 * d)), removal: .opacity.combined(with: .offset(x: -48 * d)))
    }
}

struct Heading: View {
    let title: String; let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(T.ink)
            Text(sub).font(.system(size: 13)).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 18)
    }
}

struct Welcome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Heading(title: "Welcome to UIScore", sub: "See how a screen looks and reads, in a few seconds.")
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Take a screenshot or copy any image.").font(.system(size: 14)).foregroundStyle(T.ink)
                }
                HStack(spacing: 8) {
                    Text("Then press").font(.system(size: 14)).foregroundStyle(T.ink)
                    Keycaps(["⌘", "⇧", "V"])
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.soft))
        }
    }
}

struct Keycaps: View {
    let keys: [String]
    init(_ k: [String]) { keys = k }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { k in
                Text(k).font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink).frame(minWidth: 26, minHeight: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(T.kbd)).shadow(color: T.shadow.opacity(0.4), radius: 1.5, y: 1)
            }
        }
    }
}

struct KeysStep: View {
    @ObservedObject var m: OnboardingModel
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Heading(title: "Add your keys", sub: "Keys are like passwords. They stay in your Mac's Keychain.")
                Card(title: "Jev key", note: "Needed", link: ("Where do I get this?", "https://console.typesafe.ai/keys")) {
                    KeyField(text: $m.jev, placeholder: "Paste your Jev key", verdict: m.jevResult, who: "Jev", issue: m.issue(.jev))
                }
                Card(title: "Claude API keys", note: "At least one", link: ("Where do I get this?", "https://console.anthropic.com/settings/keys")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(m.rows.enumerated()), id: \.element.id) { i, row in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(i + 1)").font(.system(size: 11, weight: .medium)).foregroundStyle(T.ink2).frame(width: 14, height: 30)
                                KeyField(text: $m.rows[i].text, placeholder: "sk-ant-…", verdict: m.results[row.id], who: "Claude", issue: m.issue(.claude(i)))
                                if m.rows.count > 1 {
                                    Button { m.remove(row.id) } label: { Image(systemName: "minus.circle").font(.system(size: 14)).foregroundStyle(T.ink2).frame(width: 24, height: 30) }
                                        .buttonStyle(PressStyle()).accessibilityLabel("Remove key \(i + 1)")
                                }
                            }.transition(.opacity)
                        }
                        Button { m.add() } label: { Text("+ Add another key").font(.system(size: 12, weight: .medium)).foregroundStyle(T.accentInk) }
                            .buttonStyle(.plain).padding(.leading, 22).padding(.top, 2)
                        Text("If key 1 runs out or is busy, the next one is used.").font(.system(size: 11)).foregroundStyle(T.ink2).padding(.leading, 22)
                    }
                }
                HStack(spacing: 10) {
                    Button { m.test() } label: { Text(m.testing ? "Testing…" : "Test keys") }.buttonStyle(QuietButton()).disabled(m.testing)
                    Text("Uses a tiny amount of credit.").font(.system(size: 11)).foregroundStyle(T.ink2)
                }.padding(.top, 2)
            }
        }
    }
}

struct Card<C: View>: View {
    let title: String; let note: String; let link: (String, String)
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(T.ink)
                Text(note).font(.system(size: 11)).foregroundStyle(T.ink2)
                Spacer()
                Link(link.0, destination: URL(string: link.1)!).font(.system(size: 12)).foregroundStyle(T.accentInk)
            }
            content
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.soft))
        .padding(.bottom, 10)
    }
}

struct KeyField: View {
    @Binding var text: String
    let placeholder: String; let verdict: KeyVerdict?; let who: String; let issue: String?
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Group {
                    if editing || text.isEmpty { TextField(placeholder, text: $text, onEditingChanged: { editing = $0 }) }
                    else { Text(KeyRules.mask(text)).foregroundStyle(T.ink).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture { editing = true } }
                }
                .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(T.kbd))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(issue != nil ? Color.red.opacity(0.7) : T.hair, lineWidth: issue != nil ? 1 : 0.5))
                if let v = verdict { Image(systemName: v == .ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(v == .ok ? Color.green : Color.red).font(.system(size: 16)).accessibilityLabel(v == .ok ? "Works" : "Failed") }
            }
            if let v = verdict { Text((v == .ok ? "✓ " : "✗ ") + v.plain(who)).font(.system(size: 11)).foregroundStyle(v == .ok ? T.ink2 : Color.red) }
            else if let issue { Text(issue).font(.system(size: 11)).foregroundStyle(Color.red) }
        }
    }
}

struct ShortcutStep: View {
    @ObservedObject var m: OnboardingModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Heading(title: "Pick your shortcut", sub: "Press it after you take a screenshot or copy an image.")
            VStack(alignment: .leading, spacing: 10) {
                Text("Shortcut").font(.system(size: 15, weight: .bold)).foregroundStyle(T.ink)
                if m.demo { Keycaps(["⌘", "⇧", "V"]) } else { KeyboardShortcuts.Recorder(for: .check) }
                Text("Change it any time in Settings.").font(.system(size: 11)).foregroundStyle(T.ink2)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.soft)).padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 8) {
                Text("Desktop access").font(.system(size: 15, weight: .bold)).foregroundStyle(T.ink)
                Text("UIScore scores your newest image: the one you just copied, or your newest screenshot file. If your Mac asks to let it use your Desktop folder, click Allow.")
                    .font(.system(size: 13)).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.soft))
        }
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 18).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(T.accent))
            .scaleEffect(c.isPressed ? 0.96 : 1).animation(T.open(0.16), value: c.isPressed)
    }
}
struct QuietButton: ButtonStyle {
    @Environment(\.isEnabled) private var on
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink).padding(.horizontal, 14).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(T.kbd)).shadow(color: T.shadow.opacity(0.4), radius: 1.5, y: 1)
            .opacity(on ? 1 : 0.5).scaleEffect(c.isPressed ? 0.96 : 1).animation(T.open(0.16), value: c.isPressed)
    }
}
