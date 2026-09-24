import Foundation
import AppKit

/// Une couleur sRGB a huit bits par canal.
///
/// Le moteur ne manipule pas de `NSColor` : une couleur AppKit porte un espace
/// colorimetrique, et deux couleurs « identiques » dans deux espaces differents ne
/// rendent pas les memes nombres. Tout le calcul de cette application - matrices,
/// ecarts percus, noms de couleurs - suppose du sRGB a huit bits, exactement comme
/// ce que l'ecran recoit. Le type le dit donc explicitement, et la conversion vers
/// AppKit n'a lieu qu'au moment de peindre.
public struct RGB: Equatable, Hashable {
    public var r: Int
    public var g: Int
    public var b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = RGB.clamp(r); self.g = RGB.clamp(g); self.b = RGB.clamp(b)
    }

    public init(white: Int) { self.init(white, white, white) }

    private static func clamp(_ v: Int) -> Int { v < 0 ? 0 : (v > 255 ? 255 : v) }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(255, 255, 255)

    /// Luminance perceptuelle Rec. 709, entre 0 et 1.
    public var luminance: Double {
        (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
    }

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    public var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0, alpha: 1)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0, alpha: 1)
    }

    public init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        self.init(Int((c.redComponent * 255).rounded()),
                  Int((c.greenComponent * 255).rounded()),
                  Int((c.blueComponent * 255).rounded()))
    }

    /// « 255,168,66 » -> couleur. Rend nil si la ligne est abimee.
    public static func parse(_ text: String) -> RGB? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3,
              let r = Int(parts[0]), let g = Int(parts[1]), let b = Int(parts[2]) else { return nil }
        return RGB(r, g, b)
    }

    public var serialized: String { "\(r),\(g),\(b)" }
}
