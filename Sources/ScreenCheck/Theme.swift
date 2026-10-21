import SwiftUI
import AppKit
import ScreenCheckCore

extension Color {
    /// 0xRRGGBBAA
    init(light: UInt32, dark: UInt32) {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 24) & 255) / 255, green: CGFloat((v >> 16) & 255) / 255,
                    blue: CGFloat((v >> 8) & 255) / 255, alpha: CGFloat(v & 255) / 255)
        }
        self.init(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light)
        })
    }
}

extension Color {
    init(_ c: RGB) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1) }
}

extension T {
    static func score(_ s: Int, _ scheme: ColorScheme) -> Color { Color(ScoreColor.forScore(Double(s), dark: scheme == .dark)) }
    static func grade(_ g: Int, _ scheme: ColorScheme) -> Color { Color(ReadingColor.forGrade(Double(g), dark: scheme == .dark)) }
    /// Left-to-right red -> yellow -> green track gradient with many stops so it reads as continuous.
    static func feelGradient(_ scheme: ColorScheme) -> LinearGradient {
        let n = 24
        return LinearGradient(stops: (0...n).map { i in
            .init(color: Color(ScoreColor.ramp(Double(i) / Double(n), dark: scheme == .dark, track: true)), location: Double(i) / Double(n))
        }, startPoint: .leading, endPoint: .trailing)
    }
}

enum T {
    static let ink = Color(light: 0x1c1c1eff, dark: 0xf1f1eeff)
    static let ink2 = Color(light: 0x5f5f67ff, dark: 0xa6a6a1ff)
    static let card = Color(light: 0xfcfcfbff, dark: 0x1d1d1cff)
    static let soft = Color(light: 0xf3f3f1ff, dark: 0x282827ff)
    static let toastFill = Color(light: 0x0000001a, dark: 0xffffff24)
    static let track = Color(light: 0xdededaff, dark: 0x403f3dff)
    static let accent = Color(light: 0x3d5afeff, dark: 0x7f95ffff)
    static let accentInk = Color(light: 0x2a3fc4ff, dark: 0xa9b8ffff)
    static let tint = Color(light: 0xeef1ffff, dark: 0x7f95ff29)
    static let selected = Color(light: 0x00000014, dark: 0xffffff1c)
    static let hoverSoft = Color(light: 0x0000000a, dark: 0xffffff12)
    static let hover = Color(light: 0xe9e9e6ff, dark: 0x343432ff)
    static let kbd = Color(light: 0xffffffff, dark: 0x333331ff)
    static let hair = Color(light: 0x00000014, dark: 0xffffff17)
    static let tipBg = Color(light: 0xffffffff, dark: 0x323230ff)
    static let tipRule = Color(light: 0x0000000f, dark: 0xffffff14)
    static let tipSub = Color(light: 0x5f5f67ff, dark: 0xb4b4afff)
    static let tipLab = Color(light: 0x2a3fc4ff, dark: 0xa9b8ffff)
    static let scrim = Color(light: 0x18181c80, dark: 0x0000009e)
    static let shadow = Color(light: 0x14141e2e, dark: 0x00000099)

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static func open(_ d: Double = 0.3) -> Animation? { reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: d) }
    static func close(_ d: Double = 0.18) -> Animation? { reduceMotion ? nil : .timingCurve(0.32, 0, 0.67, 0, duration: d) }
}
