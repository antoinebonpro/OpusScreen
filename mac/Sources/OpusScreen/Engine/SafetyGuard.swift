import Foundation
import AppKit
import CoreGraphics

/// Filet de securite contre le scenario « ecran noir dont on ne peut plus sortir ».
///
/// Une table de couleurs modifiee survit a la mort du processus qui l'a ecrite : si
/// l'application plante alors que l'ecran est a 5 %, l'ecran RESTE a 5 %. C'est vrai
/// sur Windows, c'est vrai sur macOS, et c'est le principal danger de cette
/// categorie d'outil. Cinq protections independantes :
///
///   1. Un fil de secours autonome, avec sa propre boucle d'evenements, qui reste
///      capable de tout remettre a zero meme si l'interface est figee.
///      Raccourci de panique : Ctrl + Alt + Maj + R
///   2. Un fichier temoin sur disque : s'il est encore la au demarrage, c'est que
///      la session precedente s'est mal terminee -> on repart d'un ecran normal.
///   3. Restauration sur tous les chemins de sortie, y compris signal fatal,
///      fermeture de session et arret du processus.
///   4. Bornes dures : jamais en dessous de 5 % effectifs, voile jamais opaque.
///   5. Confirmation a rebours sur les reglages sombres, sans reponse on revient
///      tout seul en arriere.
///
/// Une difference avec Windows merite d'etre dite. La-bas, le voile s'effacait
/// depuis n'importe quel fil : `SetLayeredWindowAttributes` traverse les fils.
/// Sur macOS, une fenetre ne se manipule que depuis le fil principal. Si celui-ci
/// est bloque, la table de couleurs est tout de meme rendue - elle l'est par
/// CoreGraphics, sans passer par l'interface - puis le fil de secours laisse trois
/// secondes au fil principal pour retirer ses fenetres. Passe ce delai, il termine
/// le processus : un processus mort n'a plus de fenetre, et l'ecran est deja rendu.
public enum SafetyGuard {

    /// Appele par le fil de secours quand la panique est declenchee.
    public static var panicTriggered: (() -> Void)?

    private static let lock = NSLock()
    private static var overlayWindows: [NSWindow] = []

    private static var flagPath: String {
        (Settings.dataFolder as NSString).appendingPathComponent("active.flag")
    }

    // ------------------------------------------------------------- 2. fichier temoin

    /// A appeler tout au debut du programme. Si le temoin de la session precedente
    /// est encore la, l'ecran est probablement reste modifie : on le remet a neuf.
    @discardableResult
    public static func recoverFromCrash() -> Bool {
        guard FileManager.default.fileExists(atPath: flagPath) else { return false }
        Native.restoreAllGamma()
        for m in MonitorEnum.all() { GammaEngine.resetToIdentity(m) }
        clearDirtyFlag()
        return true
    }

    public static func markDirty() {
        try? FileManager.default.createDirectory(atPath: Settings.dataFolder,
                                                 withIntermediateDirectories: true)
        try? ISO8601DateFormatter().string(from: Date())
            .write(toFile: flagPath, atomically: true, encoding: .utf8)
    }

    public static func clearDirtyFlag() {
        try? FileManager.default.removeItem(atPath: flagPath)
    }

    // ------------------------------------------------------------- fenetres connues

    public static func registerOverlay(_ window: NSWindow) {
        lock.lock(); defer { lock.unlock() }
        if !overlayWindows.contains(window) { overlayWindows.append(window) }
    }

    public static func unregisterOverlay(_ window: NSWindow) {
        lock.lock(); defer { lock.unlock() }
        overlayWindows.removeAll { $0 === window }
    }

    // ------------------------------------------------------------- 3. restauration totale

    /// Remet tout a l'etat neuf.
    ///
    /// Concue pour etre appelable depuis n'importe quel fil : ce qui peut se faire
    /// sans l'interface se fait tout de suite et sur place, le reste est demande au
    /// fil principal. Chaque etape est isolee, pour qu'un echec n'empeche jamais
    /// les suivantes.
    public static func emergencyRestore() {
        // a) les tables de couleurs d'abord : c'est ce qui survit au processus, et
        //    CoreGraphics les accepte depuis n'importe quel fil.
        Native.restoreAllGamma()
        for m in MonitorEnum.all() { GammaEngine.resetToIdentity(m) }

        // b) la matrice de couleur et la loupe : un filtre inverse ou un bureau
        //    agrandi huit fois rendent l'ecran tout aussi impraticable qu'un ecran
        //    noir. Elles vivent dans l'interface, donc sur le fil principal.
        let cleanup = {
            ScreenFilter.shared.panicStop()
            lock.lock()
            let windows = overlayWindows
            lock.unlock()
            for w in windows {
                w.alphaValue = 0
                w.orderOut(nil)
            }
        }

        if Thread.isMainThread {
            cleanup()
        } else {
            DispatchQueue.main.async(execute: cleanup)
        }

        clearDirtyFlag()
    }

    /// Restauration de derniere extremite : celle du raccourci de panique.
    ///
    /// Elle ajoute au traitement normal une surveillance du fil principal. S'il ne
    /// repond pas, c'est que l'interface est bloquee - exactement le cas pour
    /// lequel ce raccourci existe - et le processus est termine apres avoir rendu
    /// l'ecran. Mieux vaut une application a relancer qu'un bureau impraticable.
    public static func emergencyRestoreWithWatchdog() {
        emergencyRestore()

        let answered = DispatchSemaphore(value: 0)
        DispatchQueue.main.async { answered.signal() }

        DispatchQueue.global(qos: .userInitiated).async {
            if answered.wait(timeout: .now() + 3) == .timedOut {
                // Le fil principal ne repond plus : on rend l'ecran une derniere
                // fois, et on part. Les fenetres disparaissent avec le processus.
                Native.restoreAllGamma()
                for m in MonitorEnum.all() { GammaEngine.resetToIdentity(m) }
                clearDirtyFlag()
                exit(0)
            }
        }
    }

    // ------------------------------------------------------------- filets de sortie

    private static var hooksInstalled = false

    /// Pose les filets qui rattrapent une sortie anormale : signaux fatals,
    /// fermeture de session, fin du processus.
    public static func installExitHooks() {
        guard !hooksInstalled else { return }
        hooksInstalled = true

        atexit {
            Native.restoreAllGamma()
            SafetyGuard.clearDirtyFlag()
        }

        // Les signaux fatals ne peuvent pas appeler n'importe quoi ; `CGDisplayRestoreColorSyncSettings`
        // est un appel systeme simple, et c'est exactement celui dont on a besoin.
        for sig in [SIGINT, SIGTERM, SIGHUP, SIGSEGV, SIGABRT, SIGILL, SIGFPE, SIGBUS] {
            signal(sig) { received in
                Native.restoreAllGamma()
                SafetyGuard.clearDirtyFlag()
                signal(received, SIG_DFL)
                raise(received)
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
            emergencyRestore()
        }
    }

    // ------------------------------------------------------------- 4. bornes dures

    /// Aucun reglage ne peut sortir de cette plage, quelle qu'en soit l'origine.
    public static func clampBrightness(_ value: Double) -> Double {
        if value.isNaN { return 100.0 }
        if value < GammaEngine.minBrightness { return GammaEngine.minBrightness }
        if value > GammaEngine.maxBrightness { return GammaEngine.maxBrightness }
        return value
    }

    /// En dessous de ce seuil on demande confirmation avant de laisser le reglage en place.
    public static let confirmBelow = 20.0
}
