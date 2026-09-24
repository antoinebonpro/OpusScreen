import Foundation
import AppKit
import Carbon.HIToolbox

/// Traduction entre les codes de touche des deux systemes.
///
/// Le fichier de reglages stocke des codes WINDOWS. Ce n'est pas de
/// l'archeologie : c'est ce qui permet a une configuration d'aller d'une machine
/// a l'autre sans perdre ses raccourcis. La traduction a lieu au moment de poser
/// le raccourci, et une seule fois, ici.
public enum KeyCodes {

    /// Code virtuel Windows -> code de touche macOS.
    private static let vkToMac: [UInt32: UInt32] = {
        var m: [UInt32: UInt32] = [
            0x26: 126, // fleche haut
            0x28: 125, // fleche bas
            0x25: 123, // fleche gauche
            0x27: 124, // fleche droite
            0x20: 49,  // espace
            0x0D: 36,  // entree
            0x1B: 53,  // echappement
            0x2E: 117, // suppression avant
            0x08: 51,  // suppression arriere
            0x09: 48,  // tabulation
            0x21: 116, // page precedente
            0x22: 121, // page suivante
            0x24: 115, // origine
            0x23: 119, // fin
        ]

        // Lettres : l'ordre du clavier americain, qui est celui des codes macOS.
        let letters: [Character: UInt32] = [
            "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4, "I": 34,
            "J": 38, "K": 40, "L": 37, "M": 46, "N": 45, "O": 31, "P": 35, "Q": 12,
            "R": 15, "S": 1, "T": 17, "U": 32, "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6,
        ]
        for (c, code) in letters {
            if let scalar = c.unicodeScalars.first { m[scalar.value] = code }
        }

        let digits: [UInt32] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
        for i in 0..<10 { m[0x30 + UInt32(i)] = digits[i] }

        let functions: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for i in 0..<functions.count { m[0x70 + UInt32(i)] = functions[i] }

        return m
    }()

    private static let macToVk: [UInt32: UInt32] = {
        var inverse: [UInt32: UInt32] = [:]
        for (vk, mac) in vkToMac { inverse[mac] = vk }
        return inverse
    }()

    public static func macKeyCode(forWindowsVK vk: UInt32) -> UInt32? { vkToMac[vk] }
    public static func windowsVK(forMacKeyCode code: UInt32) -> UInt32? { macToVk[code] }

    /// Modificateurs Windows -> modificateurs Carbon.
    public static func carbonModifiers(_ mods: UInt32) -> UInt32 {
        var out: UInt32 = 0
        if mods & HotkeyBinding.modControl != 0 { out |= UInt32(controlKey) }
        if mods & HotkeyBinding.modAlt != 0 { out |= UInt32(optionKey) }
        if mods & HotkeyBinding.modShift != 0 { out |= UInt32(shiftKey) }
        if mods & HotkeyBinding.modWin != 0 { out |= UInt32(cmdKey) }
        return out
    }

    /// Modificateurs AppKit -> modificateurs Windows, pour la capture.
    public static func windowsModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var out: UInt32 = 0
        if flags.contains(.control) { out |= HotkeyBinding.modControl }
        if flags.contains(.option) { out |= HotkeyBinding.modAlt }
        if flags.contains(.shift) { out |= HotkeyBinding.modShift }
        if flags.contains(.command) { out |= HotkeyBinding.modWin }
        return out
    }
}

/// Les raccourcis globaux, poses aupres du systeme.
///
/// Ils passent par les evenements Carbon, qui restent le seul moyen d'obtenir un
/// raccourci global sans demander l'autorisation d'accessibilite. Le raccourci de
/// SECOURS, lui, est traite a part : voir `PanicKey`.
public final class Hotkeys {

    private var refs: [EventHotKeyRef?] = []
    private var actions: [UInt32: String] = [:]
    private var handler: EventHandlerRef?
    private var nextId: UInt32 = 100

    /// Appele avec l'identifiant d'action du raccourci presse.
    public var onAction: ((String) -> Void)?

    private static var shared: Hotkeys?

    public init() {}

    public func register(_ bindings: [HotkeyBinding]) {
        unregister()
        Hotkeys.shared = self

        installHandlerIfNeeded()

        for b in bindings {
            guard b.enabled, b.key != 0 else { continue }
            // Le secours est deja pris en charge par `PanicKey`, sur son propre fil.
            if b.action == "reset" { continue }
            guard let code = KeyCodes.macKeyCode(forWindowsVK: b.key) else { continue }

            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4F505553), id: nextId)   // « OPUS »
            let status = RegisterEventHotKey(code, KeyCodes.carbonModifiers(b.modifiers),
                                             id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref = ref {
                refs.append(ref)
                actions[nextId] = b.action
                nextId += 1
            }
        }
    }

    public func unregister() {
        for ref in refs { if let ref = ref { UnregisterEventHotKey(ref) } }
        refs.removeAll()
        actions.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let action = Hotkeys.shared?.actions[id.id] {
                DispatchQueue.main.async { Hotkeys.shared?.onAction?(action) }
            }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    deinit { unregister() }
}

/// Le raccourci de secours : ⌃⌥⇧R.
///
/// Sur Windows, il vivait sur un fil autonome avec sa propre file de messages,
/// pour repondre meme si l'interface etait figee. macOS n'offre pas exactement
/// cela : les raccourcis Carbon sont distribues par la boucle principale, donc
/// par le fil qui peut justement etre bloque.
///
/// Deux chemins sont donc poses, et le meilleur disponible est utilise :
///
///   1. Un CAPTEUR D'EVENEMENTS sur un fil dedie, avec sa propre boucle. C'est
///      l'equivalent exact du fil de secours de Windows : il repond quoi qu'il
///      arrive au fil principal. Il demande l'autorisation d'accessibilite.
///   2. A defaut, le raccourci Carbon ordinaire, qui couvre tous les cas sauf
///      celui d'une interface totalement bloquee.
///
/// Dans les deux cas la restauration elle-meme - tables de couleurs - se fait
/// sans passer par l'interface, et le processus se termine si le fil principal ne
/// repond pas dans les trois secondes.
public final class PanicKey {

    public static let shared = PanicKey()

    private var thread: Thread?
    private var tap: CFMachPort?
    private var carbonRef: EventHotKeyRef?
    private var carbonHandler: EventHandlerRef?
    private var running = false

    /// Appele apres la restauration, sur le fil principal.
    public var onTriggered: (() -> Void)?

    /// Vrai quand le capteur autonome est en place - le vrai filet, celui qui
    /// survit a une interface bloquee.
    public private(set) var independentThreadActive = false

    private init() {}

    private static let panicKeyCode: CGKeyCode = 15   // R
    private static let panicFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift]

    public func start() {
        guard !running else { return }
        running = true

        if AXIsProcessTrusted() {
            startTapThread()
        }
        startCarbonFallback()
    }

    public func stop() {
        running = false
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        independentThreadActive = false
        if let ref = carbonRef { UnregisterEventHotKey(ref); carbonRef = nil }
    }

    /// Demande l'autorisation d'accessibilite, en expliquant pourquoi.
    ///
    /// Elle n'est demandee que pour ce raccourci : l'application ne lit aucune
    /// frappe, elle attend une combinaison precise et laisse tout le reste passer.
    @discardableResult
    public func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted && !independentThreadActive { startTapThread() }
        return trusted
    }

    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // ------------------------------------------------------------------ le fil dedie

    private func startTapThread() {
        guard thread == nil else { return }
        let t = Thread { [weak self] in self?.tapLoop() }
        t.name = "OpusScreen-Secours"
        t.qualityOfService = .userInteractive
        t.start()
        thread = t
    }

    private func tapLoop() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,          // on ecoute, on n'intercepte rien
            eventsOfInterest: mask,
            callback: { _, _, event, _ in
                let flags = event.flags
                let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                if code == PanicKey.panicKeyCode
                    && flags.contains(.maskControl)
                    && flags.contains(.maskAlternate)
                    && flags.contains(.maskShift) {
                    PanicKey.shared.fire()
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil) else { return }

        tap = port
        independentThreadActive = true

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        // Sa propre boucle, sur son propre fil : c'est tout l'interet.
        while running && !Thread.current.isCancelled {
            CFRunLoopRunInMode(.defaultMode, 1.0, false)
        }
        independentThreadActive = false
    }

    // ------------------------------------------------------------------ le repli

    private func startCarbonFallback() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        if carbonHandler == nil {
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                if id.id == 0xB0FF { PanicKey.shared.fire() }
                return noErr
            }, 1, &spec, nil, &carbonHandler)
        }

        let id = EventHotKeyID(signature: OSType(0x4F505553), id: 0xB0FF)
        RegisterEventHotKey(UInt32(PanicKey.panicKeyCode),
                            UInt32(controlKey | optionKey | shiftKey),
                            id, GetApplicationEventTarget(), 0, &carbonRef)
    }

    // ------------------------------------------------------------------ declenchement

    private var lastFire = Date.distantPast

    fileprivate func fire() {
        // Le capteur et le raccourci Carbon peuvent repondre tous les deux a la
        // meme frappe : une restauration suffit.
        guard Date().timeIntervalSince(lastFire) > 0.5 else { return }
        lastFire = Date()

        SafetyGuard.emergencyRestoreWithWatchdog()
        DispatchQueue.main.async { [weak self] in self?.onTriggered?() }
    }
}
