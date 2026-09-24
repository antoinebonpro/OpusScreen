import Foundation
import AppKit
import CoreGraphics

/// Le piege macOS : la luminosite qui bouge toute seule.
///
/// La version Windows consacrait un module entier au DPST des pilotes Intel -
/// un economiseur d'energie qui fait varier le retroeclairage selon le contenu
/// affiche, en aval de tout ce que l'application controle. Symptome : l'ecran
/// « respire » en permanence et aucun reglage ne tient, ce que l'on attribue
/// naturellement a l'application.
///
/// macOS a exactement le meme piege, sous un autre nom. Deux mecanismes agissent
/// apres la table de couleurs et sont invisibles a toute mesure logicielle :
///
///   - **Regler automatiquement la luminosite** : le capteur de lumiere ambiante
///     pousse et baisse le retroeclairage tout seul. Il se bat directement avec
///     le premier etage de cette application, qui demande au meme retroeclairage
///     de monter au maximum au-dessus de 100 %.
///   - **True Tone** : la temperature de la dalle est corrigee d'apres la lumiere
///     de la piece. Il se bat avec le reglage de temperature.
///
/// Comme sur Windows, l'application les DETECTE, les EXPLIQUE, et propose d'y
/// remedier - ici en les desactivant pour de bon, ce que Windows ne permettait
/// qu'au prix d'une ecriture dans le registre et d'un redemarrage.
public enum AutoBrightness {

    public struct Panel {
        public let displayID: CGDirectDisplayID
        public let name: String
        public let autoBrightness: Bool
        public let supported: Bool
    }

    // ------------------------------------------------------------------ chargement

    private typealias EnabledFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Bool>) -> Int32
    private typealias EnableFn = @convention(c) (CGDirectDisplayID, Bool) -> Int32
    private typealias SmartFn = @convention(c) (CGDirectDisplayID) -> Bool

    private static let enabledFn: EnabledFn? = {
        guard let s = Native.symbol(Native.displayServicesPath,
                                    "DisplayServicesAmbientLightCompensationEnabled") else { return nil }
        return unsafeBitCast(s, to: EnabledFn.self)
    }()

    private static let enableFn: EnableFn? = {
        guard let s = Native.symbol(Native.displayServicesPath,
                                    "DisplayServicesEnableAmbientLightCompensation") else { return nil }
        return unsafeBitCast(s, to: EnableFn.self)
    }()

    private static let smartFn: SmartFn? = {
        guard let s = Native.symbol(Native.displayServicesPath,
                                    "DisplayServicesIsSmartDisplay") else { return nil }
        return unsafeBitCast(s, to: SmartFn.self)
    }()

    /// Faux quand macOS n'expose plus ces fonctions : l'interface se contente
    /// alors d'expliquer et de conduire aux Reglages Systeme.
    public static var detectionAvailable: Bool { enabledFn != nil }

    // ------------------------------------------------------------------ lecture

    /// Les dalles susceptibles d'ajuster leur luminosite toutes seules.
    public static func panels() -> [Panel] {
        var found: [Panel] = []
        for m in MonitorEnum.all() {
            var enabled = false
            var supported = false
            if let fn = enabledFn {
                supported = fn(m.displayID, &enabled) == 0
            }
            // Un ecran sans capteur ne peut rien ajuster : l'annoncer serait
            // inquieter pour rien.
            if !supported && !m.isInternal { continue }
            found.append(Panel(displayID: m.displayID, name: m.friendlyName,
                               autoBrightness: enabled, supported: supported))
        }
        return found
    }

    /// Vrai des qu'un ecran ajuste sa luminosite tout seul.
    public static func isAnyAutoActive() -> Bool {
        panels().contains { $0.supported && $0.autoBrightness }
    }

    /// Etat en une ligne, pour la page Avance.
    public static func describe() -> String {
        guard detectionAvailable else {
            return "non detectable sur cette version de macOS"
        }
        let list = panels().filter { $0.supported }
        if list.isEmpty { return "aucun ecran ne regle sa luminosite tout seul" }

        let active = list.filter { $0.autoBrightness }
        if active.isEmpty { return "desactive sur les \(list.count) ecran(s) concerne(s)" }
        return "ACTIF sur : " + active.map { $0.name }.joined(separator: ", ")
    }

    /// Desactive l'ajustement automatique sur tous les ecrans qui le proposent.
    /// Retourne le nombre d'ecrans reellement traites.
    @discardableResult
    public static func disableAuto() -> Int {
        guard let enable = enableFn else { return 0 }
        var n = 0
        for panel in panels() where panel.supported && panel.autoBrightness {
            if enable(panel.displayID, false) == 0 { n += 1 }
        }
        return n
    }

    /// Le remet en marche : ce que l'on desactive, on doit pouvoir le retablir.
    @discardableResult
    public static func enableAuto() -> Int {
        guard let enable = enableFn else { return 0 }
        var n = 0
        for panel in panels() where panel.supported && !panel.autoBrightness {
            if enable(panel.displayID, true) == 0 { n += 1 }
        }
        return n
    }

    public static func isSmartDisplay(_ id: CGDirectDisplayID) -> Bool {
        smartFn?(id) ?? false
    }

    public static func openDisplaySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.displays")!
        NSWorkspace.shared.open(url)
    }

    public static let explanation =
        "macOS peut regler la luminosite de l'ecran tout seul, d'apres le capteur de lumiere "
      + "de la piece. Ce reglage agit APRES la table de couleurs : aucune application ne peut "
      + "le compenser, et il n'apparait dans aucune mesure logicielle. Le symptome est toujours "
      + "le meme - l'ecran « respire » en permanence, et la luminosite demandee ne tient pas, "
      + "surtout au-dessus de 100 % ou OpusScreen demande justement au retroeclairage de monter "
      + "au maximum.\n\n"
      + "True Tone produit le meme effet sur la temperature : il rechauffe ou refroidit la dalle "
      + "d'apres la lumiere ambiante, et se bat avec le reglage de temperature.\n\n"
      + "Les deux se coupent dans Reglages Systeme, Moniteurs."
}
