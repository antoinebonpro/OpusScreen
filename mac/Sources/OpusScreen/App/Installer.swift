import Foundation
import AppKit
import ServiceManagement

/// Installation, instance unique, et desinstallation.
///
/// Sur Windows, l'application se recopiait d'elle-meme dans un dossier de
/// l'utilisateur, s'inscrivait dans « Applications installees » et gerait son
/// propre desinstalleur - parce que Windows n'offre rien pour cela a un programme
/// d'un seul fichier.
///
/// macOS a une convention, et elle est meilleure : une application est un dossier
/// que l'on glisse dans Applications, et que l'on jette a la corbeille pour s'en
/// debarrasser. On ne la remplace pas ; on l'accompagne. La seule chose a faire
/// est de PROPOSER le deplacement quand l'application tourne depuis
/// Telechargements, ou elle serait effacee par megarde un jour de menage.
public enum Installer {

    public static let bundleIdentifier = "com.opusscreen.OpusScreen"

    public static var currentVersionShort: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    public static var currentVersion: [Int] {
        currentVersionShort.split(separator: ".").map { Int($0) ?? 0 }
    }

    public static var executablePath: String { Bundle.main.bundlePath }

    private static var applicationsPath: String {
        "/Applications/OpusScreen.app"
    }

    /// Vrai quand l'application tourne depuis le dossier Applications.
    public static var isInstalled: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// Vrai quand elle tourne depuis un endroit ou elle risque d'etre effacee.
    public static var isInTransientFolder: Bool {
        let path = Bundle.main.bundlePath
        for folder in ["/Downloads/", "/Desktop/", "/private/var/folders/", "/Volumes/"] {
            if path.contains(folder) { return true }
        }
        return false
    }

    // ------------------------------------------------------------------ instance unique

    /// Les autres copies d'OpusScreen en cours d'execution.
    public static func otherInstances() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// Ferme les autres copies.
    ///
    /// Une seule copie doit tourner : deux instances ecriraient chacune leur table
    /// de couleurs, et l'ecran clignoterait exactement comme avec un concurrent.
    @discardableResult
    public static func closeOtherInstances() -> Int {
        var closed = 0
        for app in otherInstances() {
            if app.terminate() { closed += 1 }
            else if app.forceTerminate() { closed += 1 }
        }
        return closed
    }

    // ------------------------------------------------------------------ rangement

    /// Vrai quand il y a lieu de proposer le rangement.
    public static var shouldOfferToInstall: Bool {
        !isInstalled && isInTransientFolder
            && !UserDefaults.standard.bool(forKey: "opusscreen.skipInstallPrompt")
    }

    /// Propose de ranger l'application dans le dossier Applications.
    ///
    /// Proposer, et non imposer : deplacer l'application d'un utilisateur sans le
    /// lui demander est un geste qu'aucune application n'a a faire.
    ///
    /// **Jamais au demarrage.** Cette question etait posee au premier lancement,
    /// et c'etait une erreur pour une raison qui ne saute pas aux yeux : une
    /// boite modale posee pendant le lancement bloque toute l'application
    /// derriere elle. Une copie lancee a l'ouverture de session, ou pilotee par
    /// la ligne de commande, restait alors muette - elle n'appliquait plus aucun
    /// ordre, et rien ne disait pourquoi. La question se pose donc depuis la
    /// page Decouvrir, quand quelqu'un regarde.
    public static func offerToInstall() {
        guard shouldOfferToInstall else { return }

        // Pas pendant qu'une autre boite modale est ouverte : deux modales
        // empilees, et c'est celle du dessous qui se referme sans reponse.
        guard NSApp.modalWindow == nil else { return }

        let choice = Alerts.choose(
            "Ranger OpusScreen dans les Applications ?",
            "L'application tourne depuis « \(Bundle.main.bundlePath) ». "
          + "Un dossier de passage se vide un jour, et l'application disparaitrait avec "
          + "ses reglages de demarrage.\n\n"
          + "La deplacer dans /Applications la met a l'abri. Vos reglages, eux, vivent "
          + "ailleurs et ne bougent pas.",
            ["Deplacer", "Pas maintenant", "Ne plus demander"])

        switch choice {
        case 0: moveToApplications()
        case 2: UserDefaults.standard.set(true, forKey: "opusscreen.skipInstallPrompt")
        default: break   // « pas maintenant », ou aucune reponse : la question reviendra
        }
    }

    private static func moveToApplications() {
        let source = URL(fileURLWithPath: Bundle.main.bundlePath)
        let target = URL(fileURLWithPath: applicationsPath)
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: target.path) {
                // Une copie plus ancienne est deja rangee la : c'est elle qui cede
                // la place, et c'est le seul cas ou l'on efface quelque chose.
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: source, to: target)

            // On relance la copie rangee, puis on s'efface. L'ordre compte : si le
            // lancement echoue, l'ancienne copie est encore la.
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: target, configuration: config) { app, error in
                guard error == nil, app != nil else {
                    DispatchQueue.main.async {
                        Alerts.warn("Le deplacement a echoue.",
                                    "La copie rangee n'a pas pu etre lancee. "
                                  + "L'application continue depuis son emplacement actuel.")
                    }
                    return
                }
                DispatchQueue.main.async {
                    try? fm.trashItem(at: source, resultingItemURL: nil)
                    NSApp.terminate(nil)
                }
            }
        } catch {
            Alerts.warn("Le deplacement a echoue.", error.localizedDescription)
        }
    }

    // ------------------------------------------------------------------ desinstallation

    /// Retire ce que l'application a pose ailleurs qu'en elle-meme.
    ///
    /// Une application macOS se jette a la corbeille ; ce qu'elle laisse derriere
    /// elle, c'est son entree de demarrage et son dossier de reglages. Les deux se
    /// retirent ici, et les reglages seulement si on le demande.
    public static func uninstall(removeSettings: Bool) {
        LoginItem.apply(false)

        // La table de couleurs d'abord : partir en laissant l'ecran modifie serait
        // le pire des adieux.
        SafetyGuard.emergencyRestore()

        if removeSettings {
            try? FileManager.default.removeItem(atPath: Settings.dataFolder)
        }

        let bundle = URL(fileURLWithPath: Bundle.main.bundlePath)
        try? FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
    }

    public static func wantsUninstall(_ args: [String]) -> Bool {
        args.contains { $0.lowercased() == "--uninstall" }
    }
}

/// Le lancement a l'ouverture de session.
///
/// `SMAppService` remplace les anciens agents de lancement : l'inscription est
/// faite par le systeme, elle apparait dans Reglages Systeme sous le nom de
/// l'application, et l'utilisateur peut la retirer de la. C'est exactement ce que
/// l'on veut - une inscription qui ne se cache pas.
public enum LoginItem {

    @discardableResult
    public static func apply(_ enabled: Bool) -> Bool {
        // Les tests ne doivent pas inscrire la machine qui les execute au
        // demarrage, ni l'en retirer.
        if Settings.dataFolderOverride != nil { return true }

        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            return false
        }
    }

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
