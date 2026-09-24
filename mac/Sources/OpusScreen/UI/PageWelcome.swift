import Foundation
import AppKit

/// La page qui explique l'application - a quoi elle sert, ou elle se cache, et
/// comment la garder sous la main.
///
/// Elle existe parce qu'une application sans fenetre permanente pose un probleme
/// que les autres n'ont pas : une fois lancee, elle DISPARAIT. Elle se range dans
/// la barre des menus, que macOS abrege des que la place manque - et sur un
/// portable a encoche, la place manque souvent. L'utilisateur qui vient de la
/// telecharger ne voit plus rien se passer. Le premier geste a lui apprendre
/// n'est donc pas un reglage : c'est ou regarder.
public final class PageWelcome: SettingsPage {

    private var permissionNote: LabelView!
    private var permissionButton: DarkButton!
    private var dockToggle: ToggleRow!
    private var installNote: LabelView!
    private var installButton: DarkButton!

    public override var pageTitle: String { "Decouvrir" }
    public override var pageSubtitle: String { "A quoi sert OpusScreen, et ou la retrouver" }

    public override init(_ s: Settings, _ d: DisplayController, _ push: @escaping () -> Void) {
        super.init(s, d, push)

        section("A quoi sert cette application")

        note("Elle regle la lumiere de votre ecran au-dela de ce que macOS autorise : la "
           + "luminosite descend a 5 % pour une piece sombre et monte a 150 % en plein jour, "
           + "la temperature de couleur retire le bleu le soir, et la partie daltonisme "
           + "ecarte les couleurs que l'oeil confond. Tout se regle ecran par ecran.")

        note("Aucun compte, aucune connexion reseau en dehors de la verification de mise a "
           + "jour, aucune donnee transmise. Les reglages tiennent dans un fichier texte que "
           + "vous pouvez lire, sauvegarder ou supprimer.")

        section("Ou se trouve l'application")

        note("Elle n'a pas de fenetre permanente. Une fois lancee, elle se range dans la BARRE "
           + "DES MENUS, tout en haut a droite, a cote de l'heure. C'est normal qu'elle semble "
           + "avoir disparu : elle travaille.")

        note("Son icone est un oeil, et sa pupille prend la couleur que votre ecran rend a cet "
           + "instant : pale le jour, ambre le soir, grise quand les effets sont suspendus. "
           + "Un regard suffit donc a savoir ce qu'elle fait.")

        note("Si la barre des menus est pleine - c'est vite le cas sur un portable a encoche - "
           + "maintenez ⌘ et FAITES GLISSER l'icone pour la deplacer vers la gauche, la ou elle "
           + "restera visible. C'est le seul geste qui la range ou vous voulez ; aucune "
           + "application ne peut le faire a votre place.")

        dockToggle = ToggleRow("Montrer aussi une icone dans le Dock",
                               "Utile pour lancer l'application au clavier. Par defaut elle ne "
                             + "vit que dans la barre des menus.")
        dockToggle.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.showInDock = self.dockToggle.isChecked
            DockPresence.apply(self.settings.showInDock)
            self.commit()
        }
        add(dockToggle, Theme.spaceSm)

        section("Ou vit l'application elle-meme")

        installNote = note("")

        installButton = DarkButton("Ranger OpusScreen dans les Applications") { [weak self] in
            Installer.offerToInstall()
            self?.syncAndLayout()
        }
        installButton.frame.size.height = Theme.minTarget
        add(installButton, Theme.spaceSm)

        note("Un dossier de passage - Telechargements, le bureau, une image disque - se vide "
           + "un jour. L'application disparaitrait avec son inscription au demarrage, et la "
           + "correction ne reviendrait plus a l'ouverture de session. Vos reglages, eux, "
           + "vivent ailleurs et ne bougent pas.")

        section("Une autorisation a accorder")

        note("La correction du daltonisme, la saturation, les filtres et la loupe passent par "
           + "une capture de l'affichage : macOS demande pour cela l'autorisation "
           + "« Enregistrement de l'ecran ». Rien n'est enregistre, rien ne sort de la machine - "
           + "l'image est lue, transformee et reposee a l'ecran, image par image. Sans cette "
           + "autorisation, la luminosite et la temperature fonctionnent, mais les filtres et "
           + "la loupe restent inactifs et le disent.")

        permissionButton = DarkButton("Accorder l'autorisation d'enregistrement de l'ecran") { [weak self] in
            self?.requestPermission()
        }
        permissionButton.frame.size.height = Theme.minTarget
        add(permissionButton, Theme.spaceSm)

        permissionNote = note("")

        section("Les trois gestes du quotidien")

        note("MOLETTE sur l'icone : la luminosite monte et descend, sans rien ouvrir. C'est le "
           + "geste le plus utile de l'application.")

        note("CLIC sur l'icone : le menu, avec les modes, la luminosite, les ecrans et les "
           + "aides a la vision.")

        note("⌥ CLIC sur l'icone : ouvre directement cette fenetre de reglages, sans passer "
           + "par le menu.")

        section("Si jamais l'ecran devient illisible")

        note("⌃⌥⇧R retablit un ecran strictement normal. Le raccourci est pose aupres du "
           + "systeme, pas dans la fenetre : il repond meme si l'interface ne repond plus. "
           + "S'il ne suffisait pas, l'application se termine d'elle-meme apres avoir rendu "
           + "l'ecran - un ecran rendu vaut mieux qu'une application qui tient.")

        note("Et si la machine s'eteint brutalement pendant qu'un reglage est actif, "
           + "l'application le detecte au demarrage suivant et rend l'ecran d'elle-meme.")

        section("Le fichier de reglages")

        let openFolder = DarkButton("Ouvrir le dossier des reglages") { [weak self] in
            self?.openSettingsFolder()
        }
        openFolder.frame.size.height = Theme.minTarget
        add(openFolder, Theme.spaceSm)

        note("Il est au format texte, et il est le MEME que celui de la version Windows : une "
           + "configuration exportee depuis un PC s'importe ici telle quelle, et inversement. "
           + "Quelqu'un qui travaille sur les deux ne regle ses quatre-vingts curseurs qu'une "
           + "fois.")
    }

    required init?(coder: NSCoder) { fatalError() }

    private func requestPermission() {
        if ScreenFilter.shared.requestPermission() {
            permissionButton.title = "Autorisation accordee"
            permissionButton.isEnabled = false
        } else {
            // macOS ne montre la demande qu'une fois par installation : au refus,
            // la seule voie est le panneau des Reglages Systeme.
            ScreenFilter.openScreenRecordingSettings()
        }
        syncAndLayout()
    }

    private func openSettingsFolder() {
        try? FileManager.default.createDirectory(atPath: Settings.dataFolder,
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: Settings.dataFolder))
    }

    public override func sync() {
        loading = true
        defer { loading = false }

        dockToggle.setCheckedSilent(settings.showInDock)

        installButton.isEnabled = Installer.shouldOfferToInstall
        installNote.text = Installer.isInstalled
            ? "L'application est rangee dans le dossier Applications : rien a faire."
            : (Installer.isInTransientFolder
                ? "Elle tourne depuis « \(Installer.executablePath) », un dossier de passage."
                : "Elle tourne depuis « \(Installer.executablePath) ».")

        let granted = ScreenFilter.shared.available
        permissionButton.isEnabled = !granted
        permissionButton.title = granted
            ? "Autorisation accordee"
            : "Accorder l'autorisation d'enregistrement de l'ecran"
        permissionNote.text = granted
            ? "L'autorisation est accordee : les filtres et la loupe fonctionnent."
            : "Non accordee pour l'instant - " + ScreenFilter.shared.unavailableReason
              + ". Le bouton ouvre la demande, ou les Reglages Systeme si macOS l'a deja posee une fois."
    }
}

/// L'icone du Dock, mise ou retiree a la demande.
///
/// L'application est un accessoire de la barre des menus : elle n'a pas d'icone
/// de Dock par defaut, comme la plupart des outils de ce genre. Certaines
/// personnes la veulent quand meme - pour la lancer au clavier, ou simplement
/// pour la retrouver - et le changement est immediat, sans redemarrage.
public enum DockPresence {
    public static func apply(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        if visible { NSApp.activate(ignoringOtherApps: true) }
    }
}
