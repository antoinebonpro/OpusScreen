import Foundation
import CoreGraphics
import AppKit

/// Un ecran physique detecte sur la machine.
///
/// La version Windows retrouvait ses ecrans par l'EDID pour que les reglages
/// memorises reviennent au bon moniteur d'une session a l'autre. macOS expose les
/// memes informations - constructeur, modele, numero de serie - par CoreGraphics ;
/// le piege est identique, et il est traite de la meme facon : deux ecrans du meme
/// modele rendent souvent un numero de serie nul, et se confondraient sous une
/// unique fiche de reglages.
public final class MonitorInfo {
    public var displayID: CGDirectDisplayID = 0
    public var deviceName: String = ""       // "Display 1", pour les diagnostics
    public var friendlyName: String = ""     // "DELL U2412M", ou "Ecran 1" a defaut
    public var stableId: String = ""         // identifiant persistant des reglages
    public var bounds = Native.Rect(left: 0, top: 0, right: 0, bottom: 0)
    public var isPrimary = false
    public var index = 0

    /// Dalle integree d'un portable ou d'un iMac : la seule que DisplayServices atteigne.
    public var isInternal = false

    /// « HDMI », « DisplayPort », « dalle interne »... vide si la sortie est inconnue.
    public var connection: String = ""

    /// Facteur de mise a l'echelle de l'ecran (2 pour une dalle Retina).
    public var scale: CGFloat = 1

    public init() {}

    public var label: String {
        let suffix = isPrimary ? " (principal)" : ""
        return "Ecran \(index + 1) - \(friendlyName)\(suffix)"
    }

    /// Deuxieme ligne des listes : ce qui distingue deux ecrans identiques.
    public var detail: String {
        var size = "\(bounds.width) x \(bounds.height)"
        if !connection.isEmpty { size += "  -  " + connection }
        return size
    }

    /// L'ecran AppKit correspondant, quand il existe encore.
    public var screen: NSScreen? {
        NSScreen.screens.first { s in
            (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        }
    }
}

/// Enumere les ecrans. Responsabilite unique : produire la liste.
public enum MonitorEnum {

    /// Ecrans fictifs, pour tester plusieurs ecrans sur une machine qui n'en a qu'un.
    public static var source: (() -> [MonitorInfo])?

    public static func all() -> [MonitorInfo] {
        if let source = source { return source() }

        var found: [MonitorInfo] = []
        let main = CGMainDisplayID()

        for (i, id) in Native.activeDisplayIDs().enumerated() {
            // Un ecran en miroir n'est pas une surface a part : le regler deux fois
            // reviendrait a appliquer deux voiles sur la meme dalle.
            if CGDisplayIsInMirrorSet(id) != 0 && CGDisplayMirrorsDisplay(id) != 0 { continue }

            let m = MonitorInfo()
            m.displayID = id
            m.index = i
            m.isPrimary = (id == main)
            m.isInternal = CGDisplayIsBuiltin(id) != 0
            m.bounds = Native.Rect(CGDisplayBounds(id))
            m.deviceName = "Display \(i + 1)"
            m.friendlyName = DisplayConfig.friendlyName(id) ?? "Ecran \(i + 1)"
            m.connection = DisplayConfig.connection(id, isInternal: m.isInternal)
            m.scale = m.screen?.backingScaleFactor ?? 1
            m.stableId = DisplayConfig.stableId(id)
            found.append(m)
        }

        // Deux ecrans du meme modele rendent souvent le meme identifiant : le numero
        // de serie de l'EDID vaut alors zero. Sans ce rattrapage, ils partageraient
        // une seule fiche de reglages - le voile de l'un se poserait sur l'autre, et
        // « eteindre cet ecran » en eteindrait deux. C'est la configuration a deux
        // ecrans la plus repandue qui soit.
        var seen: [String: Int] = [:]
        for m in found {
            let n = (seen[m.stableId] ?? 0) + 1
            seen[m.stableId] = n
            if n > 1 { m.stableId += "#u\(CGDisplayUnitNumber(m.displayID))" }
        }
        // Si deux ecrans partagent jusqu'au numero d'unite, on tranche par la position :
        // deux fiches distinctes valent mieux qu'une fiche pour deux.
        var again: [String: Int] = [:]
        for m in found {
            let n = (again[m.stableId] ?? 0) + 1
            again[m.stableId] = n
            if n > 1 { m.stableId += "@\(m.bounds.left),\(m.bounds.top)" }
        }

        return found
    }

    /// L'ecran qui contient ce point, ou l'ecran principal a defaut.
    public static func from(point: CGPoint, in monitors: [MonitorInfo]) -> MonitorInfo? {
        for m in monitors where m.bounds.cgRect.contains(point) { return m }
        return monitors.first { $0.isPrimary } ?? monitors.first
    }
}
