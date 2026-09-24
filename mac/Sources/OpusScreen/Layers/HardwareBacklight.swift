import Foundation
import CoreGraphics
import IOKit
import IOKit.i2c

/// Pilote le retroeclairage physique de l'ecran - le seul etage qui produit
/// reellement plus de photons, contrairement a la table de couleurs et au voile
/// qui ne font que redistribuer ce que la dalle emet deja.
///
/// Ni PangoBright ni f.lux ne touchent a cette couche. C'est ce qui rend credible
/// le passage au-dessus de 100 % : on commence par vider la reserve materielle
/// avant de solliciter le logiciel.
///
///   - Dalle interne : `DisplayServices`, avec repli sur `IODisplaySetFloatParameter`
///   - Ecrans externes : DDC/CI, le protocole du menu integre du moniteur.
///     Apple Silicon passe par `IOAVService`, Intel par `IOI2CSendRequest`.
///
/// Les demandes sont NOMINATIVES : une consigne vaut pour un ecran designe, pas
/// pour la machine. Ces appels sont lents - le DDC/CI prend parfois 500 ms - donc
/// tout passe par une file dediee avec fusion des demandes, pour que le curseur de
/// l'interface reste fluide.
public enum HardwareBacklight {

    private static let sync = NSLock()
    private static let queue = DispatchQueue(label: "opusscreen.backlight", qos: .utility)
    private static var pending: [String: Int] = [:]
    private static var running = false
    private static var scheduled = false

    private static var perMonitor: [String: String] = [:]
    private static var ddcSupport: [String: Bool] = [:]
    private static var ddcMaximum: [String: Int] = [:]

    /// Etat lisible pour l'interface.
    public static var lastCapabilityDescription = "non teste"

    public static func start() {
        sync.lock(); defer { sync.unlock() }
        running = true
    }

    public static func stop() {
        sync.lock(); defer { sync.unlock() }
        running = false
        pending.removeAll()
    }

    /// Demande un niveau 0-100 POUR UN ECRAN. Retour immediat : le travail se fait
    /// en arriere-plan et seule la derniere demande recue pour cet ecran est
    /// reellement appliquee.
    public static func requestLevel(_ m: MonitorInfo?, _ percent: Int) {
        guard let m = m, !m.stableId.isEmpty else { return }
        if DisplayController.dryRun { return }

        var p = percent
        if p < 0 { p = 0 }
        if p > 100 { p = 100 }

        sync.lock()
        pending[m.stableId] = p
        let needsWake = running && !scheduled
        if needsWake { scheduled = true }
        sync.unlock()

        if needsWake {
            queue.asyncAfter(deadline: .now() + 0.05) { drain() }
        }
    }

    private static func drain() {
        sync.lock()
        scheduled = false
        guard running, !pending.isEmpty else { sync.unlock(); return }
        let batch = pending
        pending.removeAll()
        sync.unlock()

        let monitors = MonitorEnum.all()
        var anySuccess = false

        for (id, level) in batch {
            // L'ecran a ete debranche entre la demande et son traitement.
            guard let target = monitors.first(where: { $0.stableId == id }) else { continue }
            anySuccess = applyToOne(target, level) || anySuccess
        }

        if !anySuccess && !batch.isEmpty {
            lastCapabilityDescription = "non disponible sur ce materiel"
        }
    }

    /// Ce que le materiel de cet ecran sait faire. Vide tant qu'il n'a pas ete sollicite.
    public static func describeFor(_ m: MonitorInfo?) -> String {
        guard let m = m else { return "" }
        sync.lock(); defer { sync.unlock() }
        return perMonitor[m.stableId] ?? ""
    }

    /// Regle un ecran, et un seul.
    ///
    /// L'ordre des tentatives suit ce que l'on sait de l'ecran : la dalle interne
    /// passe par DisplayServices, un ecran externe par le DDC/CI.
    @discardableResult
    private static func applyToOne(_ m: MonitorInfo, _ percent: Int) -> Bool {
        if m.isInternal {
            let ok = setInternalBrightness(m.displayID, percent)
            remember(m, ok ? "dalle interne" : "aucun reglage materiel")
            return ok
        }

        if setExternalBrightness(m, percent) {
            remember(m, "DDC/CI")
            return true
        }

        // Certains Mac declarent leur dalle comme externe - un moniteur Apple
        // branche en Thunderbolt, par exemple. On tente donc le chemin interne
        // pour l'ecran principal avant de renoncer.
        if m.isPrimary && setInternalBrightness(m.displayID, percent) {
            remember(m, "dalle interne")
            return true
        }

        remember(m, "aucun reglage materiel")
        return false
    }

    private static func remember(_ m: MonitorInfo, _ what: String) {
        sync.lock()
        perMonitor[m.stableId] = what
        sync.unlock()
        if what != "aucun reglage materiel" { lastCapabilityDescription = what }
    }

    // ---------------------------------------------------------------- dalle interne

    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias CanChangeFn = @convention(c) (CGDirectDisplayID) -> Bool

    private static let setBrightnessFn: SetBrightnessFn? = {
        guard let s = Native.symbol(Native.displayServicesPath, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(s, to: SetBrightnessFn.self)
    }()

    private static let getBrightnessFn: GetBrightnessFn? = {
        guard let s = Native.symbol(Native.displayServicesPath, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(s, to: GetBrightnessFn.self)
    }()

    private static let canChangeFn: CanChangeFn? = {
        guard let s = Native.symbol(Native.displayServicesPath, "DisplayServicesCanChangeBrightness") else { return nil }
        return unsafeBitCast(s, to: CanChangeFn.self)
    }()

    /// Regle la dalle integree.
    ///
    /// `DisplayServices` est un cadre PRIVE : il peut disparaitre d'une version de
    /// macOS a l'autre. C'est pourquoi il est charge a l'execution, et pourquoi un
    /// second chemin - le parametre IOKit, public et bien plus ancien - prend le
    /// relais s'il n'est pas la.
    @discardableResult
    static func setInternalBrightness(_ id: CGDirectDisplayID, _ percent: Int) -> Bool {
        let value = Float(max(0, min(100, percent))) / 100.0

        if let fn = setBrightnessFn, fn(id, value) == 0 { return true }

        // Repli public : le parametre de luminosite du service d'affichage.
        let service = ioDisplayService(for: id)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString,
                                          value) == KERN_SUCCESS
    }

    /// Niveau actuel de la dalle integree, 0-100, ou -1 si inconnu.
    public static func internalBrightness(_ id: CGDirectDisplayID) -> Int {
        var value: Float = 0
        if let fn = getBrightnessFn, fn(id, &value) == 0 {
            return Int((value * 100).rounded())
        }
        let service = ioDisplayService(for: id)
        guard service != 0 else { return -1 }
        defer { IOObjectRelease(service) }
        if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString,
                                      &value) == KERN_SUCCESS {
            return Int((value * 100).rounded())
        }
        return -1
    }

    private static func ioDisplayService(for id: CGDirectDisplayID) -> io_service_t {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IODisplayConnect"),
                                           &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        // Un seul `IODisplayConnect` sert la dalle interne ; les machines
        // Apple Silicon n'en exposent pas du tout, et l'iterateur est alors vide.
        return IOIteratorNext(iterator)
    }

    // ---------------------------------------------------------------- DDC/CI

    private static let vcpBrightness: UInt8 = 0x10

    @discardableResult
    private static func setExternalBrightness(_ m: MonitorInfo, _ percent: Int) -> Bool {
        if let known = ddcSupport[m.stableId], !known { return false }

        let maximum = ddcMaximum[m.stableId] ?? 100
        let value = Int((Double(maximum) * Double(max(0, min(100, percent))) / 100.0).rounded())

        let ok = writeVCP(m, code: vcpBrightness, value: value)
        ddcSupport[m.stableId] = ok
        return ok
    }

    /// Ecrit une valeur VCP. Le paquet est celui de la norme DDC/CI :
    /// entete, longueur, code, valeur sur deux octets, somme de controle.
    private static func writeVCP(_ m: MonitorInfo, code: UInt8, value: Int) -> Bool {
        var data: [UInt8] = [
            0x84,                       // longueur du message (0x80 | 4)
            0x03,                       // « set VCP feature »
            code,
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
            0,                          // somme de controle, calculee ci-dessous
        ]
        data[5] = checksum(first: 0x6E ^ 0x51, bytes: Array(data[0..<5]))

        if let av = avService(for: m) {
            return writeI2CAppleSilicon(av, data)
        }
        return writeI2CIntel(m, data)
    }

    /// Lit une valeur VCP : rend (courant, maximum) ou nil.
    static func readVCP(_ m: MonitorInfo, code: UInt8) -> (current: Int, maximum: Int)? {
        var request: [UInt8] = [0x82, 0x01, code, 0]
        request[3] = checksum(first: 0x6E ^ 0x51, bytes: Array(request[0..<3]))

        var reply = [UInt8](repeating: 0, count: 11)

        if let av = avService(for: m) {
            guard writeI2CAppleSilicon(av, request) else { return nil }
            usleep(50_000)
            guard readI2CAppleSilicon(av, &reply) else { return nil }
        } else {
            guard readI2CIntel(m, request, &reply) else { return nil }
        }

        // Reponse attendue : 0x6E, 0x88, 0x02, resultat, code, type, maxHi, maxLo, curHi, curLo
        guard reply.count >= 10 else { return nil }
        let offset = reply[0] == 0x6E ? 1 : 0
        guard reply.count >= offset + 9 else { return nil }
        guard reply[offset] == 0x88 || reply[offset] == 0x8E else { return nil }

        let maximum = Int(reply[offset + 5]) << 8 | Int(reply[offset + 6])
        let current = Int(reply[offset + 7]) << 8 | Int(reply[offset + 8])
        guard maximum > 0 else { return nil }
        return (current, maximum)
    }

    private static func checksum(first: UInt8, bytes: [UInt8]) -> UInt8 {
        var chk = first
        for b in bytes { chk ^= b }
        return chk
    }

    // ---- Apple Silicon : IOAVService ----

    private typealias AVCreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias AVWriteFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias AVReadFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32

    private static let ioKitPath = "/System/Library/Frameworks/IOKit.framework/IOKit"

    private static let avCreateFn: AVCreateFn? = {
        guard let s = Native.symbol(ioKitPath, "IOAVServiceCreateWithService") else { return nil }
        return unsafeBitCast(s, to: AVCreateFn.self)
    }()

    private static let avWriteFn: AVWriteFn? = {
        guard let s = Native.symbol(ioKitPath, "IOAVServiceWriteI2C") else { return nil }
        return unsafeBitCast(s, to: AVWriteFn.self)
    }()

    private static let avReadFn: AVReadFn? = {
        guard let s = Native.symbol(ioKitPath, "IOAVServiceReadI2C") else { return nil }
        return unsafeBitCast(s, to: AVReadFn.self)
    }()

    private static var avCache: [String: CFTypeRef] = [:]

    private static func avService(for m: MonitorInfo) -> CFTypeRef? {
        if let cached = avCache[m.stableId] { return cached }
        guard let create = avCreateFn else { return nil }
        guard let entry = DisplayConfig.avServiceEntry(for: m.displayID) else { return nil }
        defer { IOObjectRelease(entry) }
        guard let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { return nil }
        avCache[m.stableId] = service
        return service
    }

    private static func writeI2CAppleSilicon(_ service: CFTypeRef, _ data: [UInt8]) -> Bool {
        guard let write = avWriteFn else { return false }
        var buffer = data
        let size = UInt32(buffer.count)
        return buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return write(service, 0x37, 0x51, base, size) == 0
        }
    }

    private static func readI2CAppleSilicon(_ service: CFTypeRef, _ reply: inout [UInt8]) -> Bool {
        guard let read = avReadFn else { return false }
        let size = UInt32(reply.count)
        return reply.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return read(service, 0x37, 0x51, base, size) == 0
        }
    }

    // ---- Intel : IOI2CSendRequest ----

    private static func withI2CConnection(_ m: MonitorInfo,
                                          _ body: (IOI2CConnectRef) -> Bool) -> Bool {
        let framebuffer = DisplayConfig.framebufferPort(for: m.displayID)
        guard framebuffer != 0 else { return false }
        defer { IOObjectRelease(framebuffer) }

        var count: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(framebuffer, &count) == KERN_SUCCESS, count > 0 else { return false }

        for bus in 0..<Int(count) {
            var interface: io_service_t = 0
            guard IOFBCopyI2CInterfaceForBus(framebuffer, IOOptionBits(bus), &interface) == KERN_SUCCESS,
                  interface != 0 else { continue }
            defer { IOObjectRelease(interface) }

            var connect: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(interface, IOOptionBits(0), &connect) == KERN_SUCCESS,
                  let connect = connect else { continue }
            defer { IOI2CInterfaceClose(connect, IOOptionBits(0)) }

            if body(connect) { return true }
        }
        return false
    }

    private static func writeI2CIntel(_ m: MonitorInfo, _ data: [UInt8]) -> Bool {
        withI2CConnection(m) { connect in
            var payload = data
            let sendCount = UInt32(payload.count)
            var request = IOI2CRequest()
            request.commFlags = 0
            request.sendAddress = 0x6E
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
            request.replyBytes = 0
            request.sendBytes = sendCount

            return payload.withUnsafeMutableBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return false }
                request.sendBuffer = vm_address_t(UInt(bitPattern: base))
                let result = IOI2CSendRequest(connect, IOOptionBits(0), &request)
                return result == KERN_SUCCESS && request.result == KERN_SUCCESS
            }
        }
    }

    private static func readI2CIntel(_ m: MonitorInfo, _ data: [UInt8], _ reply: inout [UInt8]) -> Bool {
        var out = reply
        let ok = withI2CConnection(m) { connect in
            var payload = data
            let sendCount = UInt32(payload.count)
            let replyCount = UInt32(out.count)
            var request = IOI2CRequest()
            request.commFlags = 0
            request.sendAddress = 0x6E
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.replyAddress = 0x6F
            request.replyTransactionType = IOOptionBits(kIOI2CDDCciReplyTransactionType)
            request.sendBytes = sendCount
            request.replyBytes = replyCount
            request.minReplyDelay = 50

            return payload.withUnsafeMutableBytes { sendRaw -> Bool in
                out.withUnsafeMutableBytes { replyRaw -> Bool in
                    guard let sendBase = sendRaw.baseAddress,
                          let replyBase = replyRaw.baseAddress else { return false }
                    request.sendBuffer = vm_address_t(UInt(bitPattern: sendBase))
                    request.replyBuffer = vm_address_t(UInt(bitPattern: replyBase))
                    let result = IOI2CSendRequest(connect, IOOptionBits(0), &request)
                    return result == KERN_SUCCESS && request.result == KERN_SUCCESS
                }
            }
        }
        if ok { reply = out }
        return ok
    }

    // ---------------------------------------------------------------- sondage

    /// Sonde le materiel une seule fois, sans rien modifier, pour savoir quoi
    /// afficher dans l'interface. Le resultat est detaille par ecran : sur une
    /// configuration mixte - portable plus ecran externe - un simple
    /// « disponible » ne dirait pas lequel des deux repond.
    @discardableResult
    public static func probe() -> String {
        if DisplayController.dryRun {
            lastCapabilityDescription = "non teste (mode a blanc)"
            return lastCapabilityDescription
        }

        var found: [String] = []

        for m in MonitorEnum.all() {
            if m.isInternal {
                if internalBrightness(m.displayID) >= 0 {
                    remember(m, "dalle interne")
                    found.append(m.friendlyName + " : dalle interne")
                } else {
                    remember(m, "aucun reglage materiel")
                }
                continue
            }

            if let read = readVCP(m, code: vcpBrightness) {
                ddcSupport[m.stableId] = true
                ddcMaximum[m.stableId] = read.maximum
                remember(m, "DDC/CI")
                found.append(m.friendlyName + " : DDC/CI")
            } else {
                ddcSupport[m.stableId] = false
                remember(m, "aucun reglage materiel")
            }
        }

        lastCapabilityDescription = found.isEmpty
            ? "non disponible sur ce materiel"
            : found.joined(separator: ", ")
        return lastCapabilityDescription
    }
}
