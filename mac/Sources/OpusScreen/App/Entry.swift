import Foundation
import AppKit

/// Point d'entree, et filets de securite.
///
/// L'ordre des operations n'est pas indifferent : les protections sont posees
/// AVANT toute modification de l'affichage, et la reprise apres plantage passe
/// avant tout le reste. Une table de couleurs modifiee survit a la mort du
/// processus qui l'a ecrite ; si la session precedente s'est mal terminee, la
/// premiere chose a faire est de rendre l'ecran.
public enum OpusScreenMain {

    public static func run() {
        let args = Array(Swift.CommandLine.arguments.dropFirst())

        if CommandLineDriver.wantsHelp(args) {
            print(CommandLineDriver.helpText)
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(args: args)
        app.delegate = delegate

        // Accessoire de la barre des menus : pas d'icone de Dock par defaut,
        // comme la plupart des outils de ce genre. Le reglage « montrer dans le
        // Dock » la remet, sans redemarrage.
        app.setActivationPolicy(.accessory)

        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let args: [String]
    private var tray: TrayApp?
    private var settings: Settings?
    private var display: DisplayController?
    private var keyMonitor: Any?

    init(args: [String]) {
        self.args = args
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        if Installer.wantsUninstall(args) {
            uninstallFlow()
            return
        }

        // --- une seule copie : un second lancement passe la main et s'efface ---
        if !Installer.otherInstances().isEmpty {
            handOver()
            return
        }

        // --- filets de securite installes AVANT toute modification de l'affichage ---
        SafetyGuard.installExitHooks()

        // --- si la session precedente s'est mal terminee, l'ecran est peut-etre
        //     reste sombre : on le remet a neuf avant toute chose ---
        SafetyGuard.recoverFromCrash()

        let settings = Settings.load()
        self.settings = settings

        // L'emplacement de l'application a pu changer depuis la derniere session.
        // Reecrire l'inscription au demarrage a chaque lancement la garde exacte.
        LoginItem.apply(settings.startWithSystem)
        DockPresence.apply(settings.showInDock)

        CommandLineDriver.apply(to: settings, args)

        // Lancee a l'ouverture de session ou pilotee par un ordre, l'application
        // ne doit poser AUCUNE question : une modale au demarrage bloquerait tout
        // ce qui suit, y compris les ordres recus. La page Avance garde le bouton
        // « Verifier maintenant » pour le moment ou quelqu'un regarde.
        let quiet = CommandLineDriver.startMinimized(args) || CommandLineDriver.hasCommand(args)
        if !quiet { checkForConflicts(settings) }

        let display = DisplayController(settings)
        self.display = display
        display.hardwareStatus = HardwareBacklight.probe()
        HardwareBacklight.start()

        let tray = TrayApp(settings, display, args)
        self.tray = tray

        installKeyMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quoi qu'il arrive, l'ecran est rendu. C'est la seule chose que cette
        // application ne doit jamais oublier.
        SafetyGuard.emergencyRestore()
        display?.restoreAll()
    }

    /// Le clic sur l'icone du Dock, quand elle est visible, ouvre les reglages.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        tray?.showPanel()
        return true
    }

    // ------------------------------------------------------------------ instance unique

    /// Une instance tourne deja : ce lancement lui passe la main puis s'efface.
    ///
    /// Repondre « OpusScreen est deja en cours d'execution » serait un refus la ou
    /// l'utilisateur attend sa fenetre. On transmet donc l'ordre recu s'il y en a
    /// un, et on demande l'ouverture de la fenetre sinon.
    private func handOver() {
        if CommandLineDriver.hasCommand(args) {
            CommandLineDriver.sendToRunningInstance(args)
        } else {
            CommandLineDriver.sendToRunningInstance(["--show"])
        }
        // Le droit de passer au premier plan se cede : on active l'autre copie
        // avant de partir, sinon sa fenetre s'ouvrirait derriere.
        Installer.otherInstances().first?.activate()
        NSApp.terminate(nil)
    }

    // ------------------------------------------------------------------ conflits

    private func checkForConflicts(_ settings: Settings) {
        guard !settings.ignoreConflicts else { return }

        let conflicts = ConflictDetector.running()
        guard !conflicts.isEmpty else { return }

        let names = ConflictDetector.describe(conflicts) ?? ""
        let detail = conflicts.map { "• \($0.displayName) — \($0.detail)" }.joined(separator: "\n")

        let choice = Alerts.choose(
            names + (conflicts.count > 1 ? " sont actifs." : " est actif."),
            detail + "\n\n"
          + "Il n'existe qu'une table de couleurs par ecran. Si ces elements restent "
          + "actifs, ils ecraseront en permanence les reglages d'OpusScreen, et l'ecran "
          + "clignotera.\n\nOpusScreen reprend deja leurs fonctions.",
            ["Les arreter maintenant", "Les laisser, redemander au prochain lancement",
             "Les laisser, ne plus demander"])

        switch choice {
        case 0:
            ConflictDetector.closeAll(conflicts)
            for m in MonitorEnum.all() { GammaEngine.resetToIdentity(m) }
        case 2:
            settings.ignoreConflicts = true
            settings.save()
        default:
            break   // « plus tard », ou aucune reponse : on redemandera
        }
    }

    // ------------------------------------------------------------------ desinstallation

    private func uninstallFlow() {
        let choice = Alerts.choose(
            "Desinstaller OpusScreen ?",
            "L'application sera mise a la corbeille et retiree du demarrage. "
          + "Vos reglages vivent dans un dossier separe.",
            ["Desinstaller et garder les reglages",
             "Desinstaller et tout effacer",
             "Annuler"])

        switch choice {
        case 0: Installer.uninstall(removeSettings: false)
        case 1: Installer.uninstall(removeSettings: true)
        default: break
        }
        NSApp.terminate(nil)
    }

    // ------------------------------------------------------------------ clavier

    /// Les raccourcis de la fenetre de reglages.
    ///
    /// L'application n'a pas de barre de menus classique : sans ce capteur, ⌘1 a
    /// ⌘0 et Echap n'atteindraient jamais la fenetre.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.tray?.handlePanelKey(event) == true { return nil }
            return event
        }
    }
}
