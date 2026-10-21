import Foundation

public struct RGB: Equatable {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public var bytes: (Int, Int, Int) { (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }
}

/// Score and grade colours. Everything runs on one red -> yellow -> green ramp built in OKLCH
/// (constant lightness per appearance), so the middle stays a clean yellow instead of going muddy.
public enum ScoreColor {
    /// Score at and above this is plain green; below it the ramp runs down to `redBelow`.
    public static let greenFrom = 80.0
    /// Score below this is plain red.
    public static let redBelow = 50.0

    /// OKLCH hue stops along the ramp, position 0 = red, 1 = green.
    static let hueStops: [(p: Double, h: Double)] = [(0, 27), (0.5, 95), (0.733, 118), (1, 142)]
    static let lightness = (light: 0.57, dark: 0.76)
    static let chroma = 0.17

    /// Position on the ramp (0 red ... 1 green) for a 0-100 score.
    public static func position(forScore s: Double) -> Double {
        min(1, max(0, (s - redBelow) / (greenFrom - redBelow)))
    }

    public static func forScore(_ s: Double, dark: Bool) -> RGB { ramp(position(forScore: s), dark: dark) }

    /// Lightness for decorative gradients (the Feeling tracks): no 3:1 bar requirement, so yellow can stay clean.
    static let trackLightness = (light: 0.76, dark: 0.78)

    public static func ramp(_ p: Double, dark: Bool, track: Bool = false) -> RGB {
        let p = min(1, max(0, p))
        var h = hueStops.last!.h
        for i in 1..<hueStops.count where p <= hueStops[i].p {
            let a = hueStops[i - 1], b = hueStops[i]
            h = a.h + (b.h - a.h) * (p - a.p) / (b.p - a.p)
            break
        }
        let l = track ? (dark ? trackLightness.dark : trackLightness.light) : (dark ? lightness.dark : lightness.light)
        return oklch(l, chroma, h)
    }

    /// OKLCH -> sRGB; chroma is reduced until the colour fits the gamut.
    static func oklch(_ L: Double, _ C: Double, _ h: Double) -> RGB {
        func lin(_ C: Double) -> [Double] {
            let a = C * cos(h * .pi / 180), b = C * sin(h * .pi / 180)
            let l = pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
            let m = pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
            let s = pow(L - 0.0894841775 * a - 1.291485548 * b, 3)
            return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s]
        }
        func fits(_ v: [Double]) -> Bool { v.allSatisfy { $0 >= -1e-6 && $0 <= 1 + 1e-6 } }
        var c = C
        if !fits(lin(c)) {
            var lo = 0.0, hi = C
            for _ in 0..<30 { let mid = (lo + hi) / 2; if fits(lin(mid)) { lo = mid } else { hi = mid } }
            c = lo
        }
        func enc(_ x: Double) -> Double { let x = min(1, max(0, x)); return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }
        let v = lin(c)
        return RGB(enc(v[0]), enc(v[1]), enc(v[2]))
    }
}

/// Reading-level donut colour. Lower grade is better.
public enum ReadingColor {
    /// Grade at or below this is green (WCAG 3.1.5: lower secondary education, grades 7-9).
    public static let greenUpTo = 9.0
    /// Grade at or above this is red.
    public static let redFrom = 12.0

    /// 0 = green end, 1 = red end of the gradient.
    public static func position(forGrade g: Double) -> Double {
        min(1, max(0, (g - greenUpTo) / (redFrom - greenUpTo)))
    }
    /// Green (<=9) -> yellow-green -> yellow (mid) -> red (>=12), same ramp as the score colours reversed.
    public static func forGrade(_ g: Double, dark: Bool) -> RGB {
        ScoreColor.ramp(1 - position(forGrade: g), dark: dark)
    }
}
