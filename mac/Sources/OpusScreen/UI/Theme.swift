import Foundation
import AppKit

/// Jetons de design centralises.
///
/// Regle issue des recommandations d'interface : centraliser les couleurs plutot
/// que de les ecrire en dur sur chaque controle. Un seul endroit a modifier pour
/// changer le theme, et surtout un seul endroit ou garantir les contrastes.
///
/// Les valeurs sont celles de la version Windows, a l'octet pres : c'est la meme
/// application, elle doit se reconnaitre. Tous les couples texte/fond tiennent le
/// rapport 4,5:1 exige pour du texte courant, et la verification est faite par un
/// test plutot que par l'oeil.
public enum Theme {

    /// Vrai quand le systeme demande un contraste renforce.
    public static var highContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    // --- surfaces ---
    //
    // Base sombre teintee de vert-bleu plutot qu'un gris-bleu neutre. Le registre
    // visait le logiciel technique ; il vise le soin de soi, ce que fait reellement
    // cette application - lumiere, pauses, fatigue oculaire. La teinte est celle du
    // logo, mesuree dans le fichier et non choisie a l'oeil.
    //
    // Le fond reste SOMBRE, et ce n'est pas negociable : une application de confort
    // visuel s'ouvre le soir. Imposer un fond clair a 22 h serait un contresens
    // d'usage - y compris sur un Mac en theme clair.
    public static var bg: NSColor { rgb(14, 21, 23) }
    public static var card: NSColor { rgb(24, 35, 37) }
    public static var cardHover: NSColor { rgb(33, 47, 50) }
    public static var sunken: NSColor { rgb(18, 27, 29) }

    // --- texte ---
    //
    // Blanc adouci plutot que blanc pur : sur un fond sombre, le blanc franc
    // produit un halo qui fatigue en lecture prolongee.
    public static var fg: NSColor { highContrast ? .white : rgb(228, 240, 238) }
    public static var dim: NSColor { highContrast ? rgb(210, 225, 222) : rgb(152, 176, 173) }
    public static var faint: NSColor { highContrast ? rgb(198, 214, 211) : rgb(130, 155, 152) }

    // --- accents ---
    //
    // Turquoise repris du logo, eclairci jusqu'a 8,18:1 sur la carte.
    public static var accent: NSColor { rgb(45, 206, 190) }
    public static var accentDim: NSColor { rgb(22, 104, 96) }
    public static var boost: NSColor { rgb(255, 180, 112) }
    public static var warm: NSColor { rgb(255, 186, 124) }
    public static var good: NSColor { rgb(110, 207, 151) }
    public static var danger: NSColor { rgb(244, 124, 116) }

    // --- traits ---
    //
    // Deux niveaux, et la distinction n'est pas cosmetique : la regle 1.4.11 exige
    // 3:1 pour un trait qui IDENTIFIE un composant - le cadre d'un champ, d'une
    // liste, d'une case. Un simple filet decoratif entre deux blocs n'est soumis a
    // aucun seuil.
    public static var border: NSColor { highContrast ? rgb(150, 170, 168) : rgb(41, 58, 60) }
    public static var borderStrong: NSColor { highContrast ? .white : rgb(96, 124, 126) }
    public static var focus: NSColor { rgb(134, 235, 222) }

    // --- controles ---
    public static var track: NSColor { rgb(38, 53, 56) }
    public static var field: NSColor { rgb(33, 47, 50) }
    public static var knob: NSColor { rgb(232, 244, 242) }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    // --- espacements ---
    //
    // Echelle elargie : la densite maximale est le bon reflexe pour un outil
    // technique, le mauvais pour une application de confort - le tassement se lit
    // comme de l'urgence. Les pages defilent de toute facon.
    public static var spaceXs: CGFloat { px(6) }
    public static var spaceSm: CGFloat { px(10) }
    public static var spaceMd: CGFloat { px(16) }
    public static var spaceLg: CGFloat { px(22) }
    public static var spaceXl: CGFloat { px(32) }

    /// Cible de clic minimale. 36 plutot que 32 : le minimum est un plancher, pas
    /// un objectif, et viser une cible se degrade avec la fatigue - precisement
    /// l'etat dans lequel on ouvre cette application.
    public static var minTarget: CGFloat { px(36) }

    /// Duree des transitions d'interface. En dessous de 150 ms l'oeil percoit un
    /// saut ; 220 ms adoucit sans donner l'impression que l'interface traine.
    public static let motionSeconds = 0.22

    // --- mise a l'echelle ---

    /// Conversion d'une mesure pensee a 96 points par pouce.
    ///
    /// Sur Windows, cette fonction faisait un vrai travail : les polices y sont
    /// exprimees en points et grandissent avec la densite de l'ecran, tandis que
    /// les boites ecrites en pixels ne bougeaient pas - le texte debordait donc sur
    /// tout ecran regle au-dessus de 100 %. AppKit ne connait que des points, et
    /// c'est le systeme qui multiplie : la conversion est ici l'identite, et elle
    /// est conservee pour que les deux mises en page restent comparables ligne a
    /// ligne.
    public static func px(_ at96: Int) -> CGFloat { CGFloat(at96) }
    public static func px(_ at96: CGFloat) -> CGFloat { at96 }

    // --- typographie ---
    //
    // La police du systeme, et non une famille nommee : sur Windows c'etait Segoe
    // UI parce que c'est la police de Windows. Sur macOS, demander autre chose que
    // la police systeme donne une application qui ne ressemble a rien de ce qui
    // l'entoure, et qui rend mal aux petites tailles.

    public static var display: NSFont { .systemFont(ofSize: 25, weight: .bold) }
    public static var title: NSFont { .systemFont(ofSize: 15, weight: .bold) }
    public static var heading: NSFont { .systemFont(ofSize: 11, weight: .semibold) }
    public static var sectionLabel: NSFont { .systemFont(ofSize: 10, weight: .bold) }
    public static var body: NSFont { .systemFont(ofSize: 12, weight: .regular) }
    public static var bodyBold: NSFont { .systemFont(ofSize: 12, weight: .semibold) }

    /// Textes explicatifs et legendes. Ils portent l'essentiel des explications de
    /// l'interface : les reduire revenait a compter sur le fait qu'on ne les lit pas.
    public static var small: NSFont { .systemFont(ofSize: 11, weight: .regular) }
    public static var mono: NSFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }

    /// Rapport de contraste entre deux couleurs. Sert a verifier les couples du
    /// theme plutot qu'a les deviner.
    public static func contrastRatio(_ a: NSColor, _ b: NSColor) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        let hi = max(la, lb), lo = min(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }

    private static func relativeLuminance(_ color: NSColor) -> Double {
        let c = RGB(color)
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    private static func channel(_ v: Int) -> Double {
        let s = Double(v) / 255.0
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
}
