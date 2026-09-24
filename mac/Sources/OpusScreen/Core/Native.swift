import Foundation
import CoreGraphics
import AppKit

/// Tout ce qui touche au systeme passe par ici.
///
/// La version Windows rassemblait ses declarations P/Invoke dans un seul fichier,
/// pour la meme raison : un appel systeme egare au milieu d'une page de reglages
/// est un appel que personne ne relit. Sur macOS, les fonctions publiques viennent
/// de CoreGraphics ; les quelques fonctions PRIVEES - retroeclairage de la dalle
/// interne, DDC/CI - sont chargees a l'execution par dlsym, et leur absence se
/// constate proprement au lieu d'empecher l'application de se lancer.
public enum Native {

    // ------------------------------------------------------------------ table de couleurs

    /// Une table de conversion : 256 entrees par canal.
    ///
    /// CoreGraphics travaille en flottants entre 0 et 1, Windows en entiers 16 bits.
    /// La representation interne reste celle de la version Windows - la meme que
    /// celle des documents d'architecture et des tests - et la conversion a lieu au
    /// tout dernier moment, a la pose.
    public struct RampTable: Equatable {
        public var red: [UInt16]
        public var green: [UInt16]
        public var blue: [UInt16]

        public static let size = 256

        public init() {
            red = [UInt16](repeating: 0, count: RampTable.size)
            green = [UInt16](repeating: 0, count: RampTable.size)
            blue = [UInt16](repeating: 0, count: RampTable.size)
        }

        public static func allocate() -> RampTable { RampTable() }

        public static func identity() -> RampTable {
            var t = RampTable()
            for i in 0..<size {
                let v = UInt16((Double(i) / 255.0 * 65535.0).rounded())
                t.red[i] = v
                t.green[i] = v
                t.blue[i] = v
            }
            return t
        }

        /// Les trois tableaux de flottants attendus par CoreGraphics.
        public func asFloats() -> (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue]) {
            var fr = [CGGammaValue](repeating: 0, count: RampTable.size)
            var fg = [CGGammaValue](repeating: 0, count: RampTable.size)
            var fb = [CGGammaValue](repeating: 0, count: RampTable.size)
            for i in 0..<RampTable.size {
                fr[i] = CGGammaValue(Double(red[i]) / 65535.0)
                fg[i] = CGGammaValue(Double(green[i]) / 65535.0)
                fb[i] = CGGammaValue(Double(blue[i]) / 65535.0)
            }
            return (fr, fg, fb)
        }

        public static func fromFloats(_ r: [CGGammaValue], _ g: [CGGammaValue], _ b: [CGGammaValue]) -> RampTable {
            var t = RampTable()
            for i in 0..<size {
                t.red[i] = clamp16(i < r.count ? Double(r[i]) : 0)
                t.green[i] = clamp16(i < g.count ? Double(g[i]) : 0)
                t.blue[i] = clamp16(i < b.count ? Double(b[i]) : 0)
            }
            return t
        }

        private static func clamp16(_ v: Double) -> UInt16 {
            let scaled = (v * 65535.0).rounded()
            if scaled < 0 { return 0 }
            if scaled > 65535 { return 65535 }
            return UInt16(scaled)
        }
    }

    // ------------------------------------------------------------------ gamma CoreGraphics

    /// Pose la table sur un ecran. Retourne faux si le systeme l'a refusee.
    ///
    /// Contrairement a Windows, macOS ne rabote pas les courbes trop eloignees de la
    /// lineaire : il n'y a donc pas d'equivalent du deblocage `GdiIcmGammaRange`.
    /// En revanche la table est bien PAR ECRAN, la ou Windows n'en a qu'une par
    /// carte graphique - c'est le seul point ou le portage gagne quelque chose.
    @discardableResult
    public static func setGammaRamp(_ displayID: CGDirectDisplayID, _ ramp: RampTable) -> Bool {
        let f = ramp.asFloats()
        var r = f.r, g = f.g, b = f.b
        let err = CGSetDisplayTransferByTable(displayID, UInt32(RampTable.size), &r, &g, &b)
        return err == .success
    }

    /// Relit la table en place, pour pouvoir la remettre ensuite.
    public static func getGammaRamp(_ displayID: CGDirectDisplayID) -> RampTable? {
        var r = [CGGammaValue](repeating: 0, count: RampTable.size)
        var g = [CGGammaValue](repeating: 0, count: RampTable.size)
        var b = [CGGammaValue](repeating: 0, count: RampTable.size)
        var count: UInt32 = 0
        let err = CGGetDisplayTransferByTable(displayID, UInt32(RampTable.size), &r, &g, &b, &count)
        guard err == .success, count > 0 else { return nil }
        return RampTable.fromFloats(r, g, b)
    }

    /// Rend a l'ecran sa table d'origine, celle du profil ColorSync.
    public static func restoreGamma(_ displayID: CGDirectDisplayID) {
        CGSetDisplayTransferByFormula(displayID, 0, 1, 1, 0, 1, 1, 0, 1, 1)
    }

    /// Rend a TOUS les ecrans leur table d'origine. Le filet de securite ultime.
    public static func restoreAllGamma() {
        CGDisplayRestoreColorSyncSettings()
    }

    // ------------------------------------------------------------------ chargement tardif

    /// Ouvre une bibliotheque systeme et y cherche un symbole.
    ///
    /// Les fonctions ainsi trouvees sont privees : elles peuvent disparaitre d'une
    /// version de macOS a l'autre. Les chercher a l'execution plutot que de les
    /// declarer a la compilation garantit que leur disparition se traduit par une
    /// fonction indisponible et annoncee, jamais par une application qui refuse de
    /// demarrer.
    public static func symbol(_ path: String, _ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        return dlsym(handle, name)
    }

    public static let displayServicesPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    public static let coreBrightnessPath =
        "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"

    // ------------------------------------------------------------------ geometrie

    /// Rectangle en coordonnees ecran de Quartz (origine en haut a gauche).
    public struct Rect: Equatable {
        public var left: Int, top: Int, right: Int, bottom: Int

        public init(left: Int, top: Int, right: Int, bottom: Int) {
            self.left = left; self.top = top; self.right = right; self.bottom = bottom
        }

        public init(_ r: CGRect) {
            left = Int(r.minX.rounded()); top = Int(r.minY.rounded())
            right = Int(r.maxX.rounded()); bottom = Int(r.maxY.rounded())
        }

        public var width: Int { right - left }
        public var height: Int { bottom - top }
        public var cgRect: CGRect {
            CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(width), height: CGFloat(height))
        }
    }

    // ------------------------------------------------------------------ curseur

    /// Position du pointeur en coordonnees Quartz, origine en haut a gauche.
    ///
    /// AppKit rend l'origine en BAS a gauche ; melanger les deux conventions est
    /// l'erreur classique du portage, et elle se voit tout de suite : l'anneau du
    /// pointeur se place symetriquement de l'autre cote de l'ecran.
    public static func cursorPosition() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Le meme point, en coordonnees AppKit.
    public static func cursorPositionAppKit() -> CGPoint {
        let p = NSEvent.mouseLocation
        return p
    }

    /// Convertit un rectangle Quartz en rectangle AppKit, ecran principal pour repere.
    public static func quartzToAppKit(_ r: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                ?? NSScreen.screens.first else { return r }
        let totalHeight = primary.frame.maxY
        return CGRect(x: r.origin.x, y: totalHeight - r.origin.y - r.height,
                      width: r.width, height: r.height)
    }

    // ------------------------------------------------------------------ bureau virtuel

    /// Rectangle englobant tous les ecrans, en coordonnees Quartz.
    public static func virtualScreen() -> CGRect {
        var union = CGRect.null
        for id in activeDisplayIDs() {
            union = union.union(CGDisplayBounds(id))
        }
        return union.isNull ? CGRect(x: 0, y: 0, width: 1920, height: 1080) : union
    }

    /// Identifiants de tous les ecrans actifs.
    public static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
