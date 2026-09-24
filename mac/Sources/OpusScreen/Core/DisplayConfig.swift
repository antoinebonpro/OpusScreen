import Foundation
import CoreGraphics
import AppKit
import IOKit

/// Les noms reels des ecrans, leur connectique, et la detection de la dalle interne.
///
/// La version Windows allait chercher tout cela dans l'EDID, parce que
/// `EnumDisplayDevices` ne rendait que « Ecran generique Plug-and-Play ». macOS
/// fait ce travail lui-meme et rend le nom du moniteur tel qu'il est grave dedans.
/// Reste la connectique - HDMI, DisplayPort, dalle interne - que le systeme
/// n'expose nulle part officiellement : elle est lue dans le registre IOKit, et son
/// absence se traduit par un libelle vide plutot que par une invention.
public enum DisplayConfig {

    // ------------------------------------------------------------------ nom

    /// Le nom grave dans l'ecran, tel que macOS le connait.
    public static func friendlyName(_ id: CGDirectDisplayID) -> String? {
        for screen in NSScreen.screens {
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            if number == id {
                let name = screen.localizedName
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    // ------------------------------------------------------------------ identifiant

    /// Identifiant persistant : constructeur, modele, numero de serie.
    ///
    /// Il doit survivre a un debranchement, a un redemarrage et a un changement de
    /// port. Le numero d'unite, lui, ne le garantit pas - il n'est ajoute qu'en
    /// dernier recours, quand deux ecrans rendent la meme fiche d'identite.
    public static func stableId(_ id: CGDirectDisplayID) -> String {
        let vendor = CGDisplayVendorNumber(id)
        let model = CGDisplayModelNumber(id)
        let serial = CGDisplaySerialNumber(id)
        return String(format: "v%08X-m%08X-s%08X", vendor, model, serial)
    }

    // ------------------------------------------------------------------ connectique

    private static var connectionCache: [CGDirectDisplayID: String] = [:]

    public static func connection(_ id: CGDirectDisplayID, isInternal: Bool) -> String {
        if isInternal { return "dalle interne" }
        if let cached = connectionCache[id] { return cached }

        let found = transportFromRegistry(id) ?? ""
        connectionCache[id] = found
        return found
    }

    public static func invalidateCache() {
        connectionCache.removeAll()
        avServiceCache.removeAll()
    }

    /// Lit la sortie physique dans le registre IOKit.
    ///
    /// Sur les machines Apple Silicon, chaque ecran externe a un service
    /// `DCPAVServiceProxy` qui porte un dictionnaire `Transport`. Sur les machines
    /// Intel, l'information n'existe pas sous cette forme : la fonction rend alors
    /// nil, et l'interface se contente de la definition.
    private static func transportFromRegistry(_ id: CGDirectDisplayID) -> String? {
        guard let entry = avServiceEntry(for: id) else { return nil }
        defer { IOObjectRelease(entry) }

        guard let transport = IORegistryEntryCreateCFProperty(
                entry, "Transport" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] else { return nil }

        let upstream = (transport["Upstream"] as? String) ?? ""
        return label(forTransport: upstream)
    }

    private static func label(forTransport raw: String) -> String? {
        switch raw.uppercased() {
        case "DP", "DISPLAYPORT": return "DisplayPort"
        case "HDMI": return "HDMI"
        case "USBC", "USB-C", "TBT", "THUNDERBOLT": return "USB-C / Thunderbolt"
        case "": return nil
        default: return raw
        }
    }

    // ------------------------------------------------------------------ services IOKit

    private static var avServiceCache: [CGDirectDisplayID: io_service_t] = [:]

    /// Le service `DCPAVServiceProxy` qui sert cet ecran externe.
    ///
    /// Il n'existe aucune correspondance officielle entre un identifiant
    /// CoreGraphics et un service du registre. On apparie donc les services
    /// externes aux ecrans externes DANS L'ORDRE, ce qui est la pratique etablie -
    /// et ce qui explique que le DDC/CI soit verifie avant d'etre annonce : un
    /// appariement suppose ne vaut que confirme par une reponse de l'ecran.
    public static func avServiceEntry(for id: CGDirectDisplayID) -> io_service_t? {
        guard CGDisplayIsBuiltin(id) == 0 else { return nil }

        let externals = Native.activeDisplayIDs().filter { CGDisplayIsBuiltin($0) == 0 }
        guard let rank = externals.firstIndex(of: id) else { return nil }

        var services: [io_service_t] = []
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("DCPAVServiceProxy"),
                &iterator) == KERN_SUCCESS else { return nil }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if isExternalAVService(service) { services.append(service) }
            else { IOObjectRelease(service) }
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)

        guard rank < services.count else {
            services.forEach { IOObjectRelease($0) }
            return nil
        }

        let wanted = services[rank]
        for (i, s) in services.enumerated() where i != rank { IOObjectRelease(s) }
        return wanted
    }

    private static func isExternalAVService(_ service: io_service_t) -> Bool {
        guard let location = IORegistryEntryCreateCFProperty(
                service, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String else { return false }
        return location == "External"
    }

    /// Le service `IOFramebuffer` d'un ecran, sur les machines Intel.
    ///
    /// C'est par lui que passe le DDC/CI historique (`IOI2CSendRequest`). Sur les
    /// machines Apple Silicon, ce service n'existe plus sous cette forme et la
    /// fonction rend zero - le DDC passe alors par `IOAVService`.
    public static func framebufferPort(for id: CGDirectDisplayID) -> io_service_t {
        typealias PortFn = @convention(c) (CGDirectDisplayID) -> io_service_t
        guard let sym = Native.symbol(
                "/System/Library/Frameworks/IOKit.framework/IOKit",
                "IOFramebufferPortFromCGDisplayID") else { return 0 }
        let fn = unsafeBitCast(sym, to: PortFn.self)
        return fn(id)
    }
}
