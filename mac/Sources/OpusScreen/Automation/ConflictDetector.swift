import Foundation
import AppKit
import CoreGraphics

/// Detecte ce qui pilote la meme chose que nous.
///
/// Il n'existe qu'une table de conversion par ecran : deux programmes qui y
/// ecrivent chacun de leur cote se remplacent mutuellement en boucle, ce qui donne
/// un ecran qui clignote et des reglages qui « ne tiennent pas ». Comme OpusScreen
/// reprend justement les roles de f.lux et de PangoBright, le cas est frequent au
/// premier lancement.
///
/// macOS ajoute deux concurrents que Windows n'avait pas, et qui ne sont pas des
/// applications : **Night Shift**, qui ecrit exactement la meme table, et les
/// **filtres de couleur** d'accessibilite, qui posent leur propre matrice sur tout
/// l'affichage - par-dessus la notre. Les ignorer aurait laisse l'utilisateur
/// devant un ecran trop chaud ou trop filtre sans explication.
public enum ConflictDetector {

    public enum Kind {
        case application
        case nightShift
        case colorFilter
        case invertColors
    }

    public struct Conflict {
        public let kind: Kind
        public let displayName: String
        public let detail: String
        public let bundleId: String
    }

    /// Identifiant de paquet -> nom lisible.
    private static let knownApps: [String: String] = [
        "org.herf.flux": "f.lux",
        "com.justgetflux.flux": "f.lux",
        "fyi.lunar.lunar": "Lunar",
        "com.alinpanaitiu.lunar": "Lunar",
        "me.guillaumeb.monitorcontrol": "MonitorControl",
        "com.iris.iris": "Iris",
        "com.mahmoudsalah.gammy": "Gammy",
        "com.shadesapp.shades": "Shades",
        "com.dimmer.dimmer": "Dimmer",
        "com.hyperspaceapp.vivid": "Vivid",
        "com.nightowl.nightowl": "NightOwl",
        "com.apple.screenbrightness": "Reglage de luminosite tiers",
    ]

    public static func running() -> [Conflict] {
        var found: [Conflict] = []

        let me = Bundle.main.bundleIdentifier ?? ""
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier?.lowercased(), id != me.lowercased() else { continue }
            guard let name = knownApps[id] else { continue }
            found.append(Conflict(kind: .application, displayName: name,
                                  detail: "pilote la meme table de couleurs",
                                  bundleId: id))
        }

        if NightShift.isEnabled {
            found.append(Conflict(kind: .nightShift, displayName: "Night Shift",
                                  detail: "ecrit la meme table de couleurs que la temperature d'OpusScreen",
                                  bundleId: ""))
        }

        if SystemColorFilters.colorFilterEnabled {
            found.append(Conflict(kind: .colorFilter, displayName: "Filtres de couleur de macOS",
                                  detail: "pose une matrice de couleur par-dessus la notre",
                                  bundleId: ""))
        }

        if SystemColorFilters.invertEnabled {
            found.append(Conflict(kind: .invertColors, displayName: "Inversion des couleurs de macOS",
                                  detail: "inverse l'affichage apres nos filtres",
                                  bundleId: ""))
        }

        return found
    }

    /// Ferme ou desactive ce qui a ete trouve. Retourne le nombre reellement traite.
    ///
    /// On demande d'abord poliment la fermeture ; on ne force qu'ensuite, pour
    /// laisser a l'application concurrente la chance de restaurer sa propre table.
    @discardableResult
    public static func closeAll(_ conflicts: [Conflict]) -> Int {
        var closed = 0
        for c in conflicts {
            switch c.kind {
            case .application:
                for app in NSWorkspace.shared.runningApplications
                where app.bundleIdentifier?.lowercased() == c.bundleId {
                    if app.terminate() { closed += 1 }
                    else if app.forceTerminate() { closed += 1 }
                }
            case .nightShift:
                if NightShift.setEnabled(false) { closed += 1 }
            case .colorFilter:
                if SystemColorFilters.setColorFilterEnabled(false) { closed += 1 }
            case .invertColors:
                if SystemColorFilters.setInvertEnabled(false) { closed += 1 }
            }
        }
        return closed
    }

    public static func describe(_ conflicts: [Conflict]) -> String? {
        guard !conflicts.isEmpty else { return nil }
        var names: [String] = []
        for c in conflicts where !names.contains(c.displayName) { names.append(c.displayName) }
        return names.joined(separator: " et ")
    }
}

/// Night Shift, c'est-a-dire f.lux integre au systeme.
///
/// Il n'y a pas d'interface publique : le service passe par `CBBlueLightClient`,
/// une classe Objective-C du cadre prive CoreBrightness. L'appel est fait par le
/// moteur d'envoi de messages, avec une signature ecrite explicitement, et chaque
/// etape rend faux plutot que de supposer que la suivante existe.
public enum NightShift {

    private static var client: AnyObject? = {
        _ = dlopen(Native.coreBrightnessPath, RTLD_LAZY)
        guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()

    public static var isSupported: Bool { client != nil }

    /// Vrai quand Night Shift rechauffe l'ecran en ce moment.
    public static var isEnabled: Bool {
        guard let client = client else { return false }
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: selector) else { return false }

        // La structure d'etat n'est pas documentee. On reserve largement de quoi
        // la contenir, et l'on ne lit que le second octet - l'indicateur
        // « active » - dont la place est stable depuis l'apparition de la
        // fonction. Sur-dimensionner le tampon est ce qui rend la lecture sure.
        var buffer = [UInt8](repeating: 0, count: 128)
        typealias StatusFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "objc_msgSend") else { return false }
        let send = unsafeBitCast(sym, to: StatusFn.self)

        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return send(client, selector, base)
        }
        guard ok else { return false }
        return buffer[1] != 0
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        guard let client = client else { return false }
        let selector = NSSelectorFromString("setEnabled:")
        guard client.responds(to: selector) else { return false }

        typealias SetFn = @convention(c) (AnyObject, Selector, Bool) -> Bool
        guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "objc_msgSend") else { return false }
        let send = unsafeBitCast(sym, to: SetFn.self)
        return send(client, selector, enabled)
    }

    public static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.displays?displaysNightShiftTab")!
        NSWorkspace.shared.open(url)
    }
}

/// Les filtres de couleur d'accessibilite de macOS.
///
/// Ils font, en beaucoup moins reglable, ce que fait le quatrieme etage de cette
/// application : une matrice posee sur tout l'affichage. Les deux se cumulent, et
/// le resultat n'est celui d'aucun des deux.
public enum SystemColorFilters {

    private static let mediaAccessibilityPath =
        "/System/Library/Frameworks/MediaAccessibility.framework/MediaAccessibility"

    private typealias GetFn = @convention(c) (CFString) -> Bool
    private typealias SetFn = @convention(c) (CFString, Bool) -> Void

    private static let getFn: GetFn? = {
        guard let s = Native.symbol(mediaAccessibilityPath, "MADisplayFilterPrefGetCategoryEnabled")
        else { return nil }
        return unsafeBitCast(s, to: GetFn.self)
    }()

    private static let setFn: SetFn? = {
        guard let s = Native.symbol(mediaAccessibilityPath, "MADisplayFilterPrefSetCategoryEnabled")
        else { return nil }
        return unsafeBitCast(s, to: SetFn.self)
    }()

    // Les deux categories que macOS distingue. Leurs noms se lisent dans le
    // fichier de preferences du systeme : « __Color__- » et « __Inverted__- ».
    private static let colorCategory = "Color" as CFString
    private static let invertCategory = "Inverted" as CFString

    public static var colorFilterEnabled: Bool { getFn?(colorCategory) ?? false }
    public static var invertEnabled: Bool { getFn?(invertCategory) ?? false }

    @discardableResult
    public static func setColorFilterEnabled(_ on: Bool) -> Bool {
        guard let set = setFn else { return false }
        set(colorCategory, on)
        return true
    }

    @discardableResult
    public static func setInvertEnabled(_ on: Bool) -> Bool {
        guard let set = setFn else { return false }
        set(invertCategory, on)
        return true
    }

    public static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display")!
        NSWorkspace.shared.open(url)
    }
}
