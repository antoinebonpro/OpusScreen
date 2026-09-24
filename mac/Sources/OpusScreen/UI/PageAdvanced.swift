import Foundation
import AppKit

/// Etages du moteur, comportement systeme, diagnostics et transfert de
/// configuration. Tout ce qu'on ne regarde qu'une fois - d'ou sa place en
/// derniere page.
public final class PageAdvanced: SettingsPage {

    private var hardware: ToggleRow!
    private var overlay: ToggleRow!
    private var matrix: ToggleRow!
    private var smooth: ToggleRow!
    private var speed: SliderRow!
    private var startup: ToggleRow!
    private var trayPercent: ToggleRow!
    private var darkConfirm: ToggleRow!
    private var conflicts: ToggleRow!
    private var updates: ToggleRow!
    private var diagnostics: LabelView!
    private var autoNote: LabelView!
    private var autoButton: DarkButton!
    private var updateNote: LabelView!
    private var matrixNote: LabelView!

    public override var pageTitle: String { "Avance" }
    public override var pageSubtitle: String { "Moteur, systeme et diagnostics" }

    public override init(_ s: Settings, _ d: DisplayController, _ push: @escaping () -> Void) {
        super.init(s, d, push)

        section("Etages du moteur")

        hardware = ToggleRow("Retroeclairage physique",
                             "DDC/CI sur ecran externe, reglage systeme sur la dalle interne. "
                           + "Le seul etage qui emet vraiment plus de lumiere.")
        hardware.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.useHardwareBacklight = self.hardware.isChecked
            self.commit()
        }
        add(hardware, Theme.spaceSm)

        overlay = ToggleRow("Voile logiciel",
                            "Sert uniquement sous 35 %. C'est lui qui permet de descendre jusqu'a 5 %.")
        overlay.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.useOverlay = self.overlay.isChecked
            self.commit()
        }
        add(overlay, Theme.spaceSm)

        matrix = ToggleRow("Matrice de couleur",
                           "Necessaire a la saturation, aux filtres et a la loupe. "
                         + "Demande l'autorisation d'enregistrement de l'ecran.")
        matrix.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.useColorMatrix = self.matrix.isChecked
            self.commit()
            self.syncAndLayout()
        }
        add(matrix, Theme.spaceSm)

        matrixNote = note("")

        let permission = DarkButton("Ouvrir les reglages d'enregistrement de l'ecran") {
            ScreenFilter.openScreenRecordingSettings()
        }
        permission.frame.size.height = Theme.minTarget
        add(permission, Theme.spaceSm)

        section("Transitions")

        smooth = ToggleRow("Fondu entre deux reglages",
                           "Evite le saut brutal quand un mode ou une regle change l'ecran.")
        smooth.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.smoothTransitions = self.smooth.isChecked
            self.speed.isEnabled = self.smooth.isChecked
            self.commit()
        }
        add(smooth, Theme.spaceSm)

        speed = SliderRow("Duree du fondu", 60, 3000, "ms")
        speed.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.transitionSpeedMs = Int(self.speed.value)
            self.commitNoSave()
        }
        speed.onCommit = { [weak self] in self?.commit() }
        add(speed, Theme.spaceSm)

        section("Systeme")

        startup = ToggleRow("Lancer a l'ouverture de session", nil)
        startup.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.startWithSystem = self.startup.isChecked
            LoginItem.apply(self.settings.startWithSystem)
            self.commit()
            self.syncAndLayout()
        }
        add(startup, Theme.spaceSm)

        trayPercent = ToggleRow("Afficher le pourcentage a cote de l'icone", nil)
        trayPercent.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.showTrayPercentage = self.trayPercent.isChecked
            self.commit()
        }
        add(trayPercent, Theme.spaceSm)

        darkConfirm = ToggleRow("Demander confirmation sous 20 %",
                                "Retour automatique au reglage precedent si vous ne repondez pas.")
        darkConfirm.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.skipDarkConfirm = !self.darkConfirm.isChecked
            self.commit()
        }
        add(darkConfirm, Theme.spaceSm)

        conflicts = ToggleRow("Signaler ce qui pilote la meme chose",
                              "f.lux, Lunar, Night Shift, filtres de couleur de macOS...")
        conflicts.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.ignoreConflicts = !self.conflicts.isChecked
            self.commit()
        }
        add(conflicts, Theme.spaceSm)

        let checkConflicts = DarkButton("Verifier maintenant") { [weak self] in
            self?.checkConflictsNow()
        }
        checkConflicts.frame.size.height = Theme.minTarget
        add(checkConflicts, Theme.spaceSm)

        section("Mises a jour")

        updates = ToggleRow("Verifier les mises a jour",
                            "Une fois par jour. Rien ne s'installe sans votre accord.")
        updates.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.checkUpdates = self.updates.isChecked
            Updater.lastStatus = self.settings.checkUpdates ? "" : "Verification desactivee."
            self.commit()
            self.syncAndLayout()
        }
        add(updates, Theme.spaceSm)

        let checkNow = DarkButton("Verifier maintenant") {
            Updater.requestCheck()
        }
        checkNow.frame.size.height = Theme.minTarget
        add(checkNow, Theme.spaceSm)

        note("C'est la seule connexion d'OpusScreen : elle demande a GitHub le numero de la "
           + "derniere version publiee, et rien d'autre n'est envoye.")

        updateNote = note("")

        section("Configuration")

        let export = DarkButton("Exporter la configuration...") { [weak self] in self?.onExport() }
        export.frame.size.height = Theme.minTarget
        add(export, Theme.spaceSm)

        let importButton = DarkButton("Importer une configuration...") { [weak self] in self?.onImport() }
        importButton.frame.size.height = Theme.minTarget
        add(importButton, Theme.spaceXs)

        let folder = DarkButton("Ouvrir le dossier des reglages") {
            try? FileManager.default.createDirectory(atPath: Settings.dataFolder,
                                                     withIntermediateDirectories: true)
            NSWorkspace.shared.open(URL(fileURLWithPath: Settings.dataFolder))
        }
        folder.frame.size.height = Theme.minTarget
        add(folder, Theme.spaceXs)

        note("Le format est celui de la version Windows : une configuration exportee depuis "
           + "un PC s'importe ici telle quelle, et inversement.")

        section("Luminosite automatique du systeme")

        autoNote = note("")

        autoButton = DarkButton("Arreter la luminosite automatique") { [weak self] in
            self?.onFixAutoBrightness()
        }
        autoButton.frame.size.height = Theme.minTarget
        add(autoButton, Theme.spaceSm)

        let displaySettings = DarkButton("Ouvrir les reglages des moniteurs") {
            AutoBrightness.openDisplaySettings()
        }
        displaySettings.frame.size.height = Theme.minTarget
        add(displaySettings, Theme.spaceXs)

        note(AutoBrightness.explanation)

        section("Diagnostics")

        diagnostics = LabelView("")
        diagnostics.font = Theme.mono
        diagnostics.color = Theme.dim
        diagnostics.wraps = true
        add(diagnostics, Theme.spaceSm)

        let factory = DarkButton("Tout remettre a zero et redemarrer les reglages") { [weak self] in
            self?.onFactoryReset()
        }
        factory.frame.size.height = Theme.minTarget
        factory.textColor = Theme.danger
        add(factory, Theme.spaceMd)
    }

    required init?(coder: NSCoder) { fatalError() }

    // ------------------------------------------------------------------ actions

    private func checkConflictsNow() {
        let found = ConflictDetector.running()
        guard !found.isEmpty else {
            Alerts.info("Rien ne pilote la meme chose qu'OpusScreen.",
                        "Ni Night Shift, ni les filtres de couleur de macOS, ni aucune "
                      + "application connue pour ecrire dans la table de couleurs.",
                        window: hostWindow)
            return
        }

        let detail = found.map { "• \($0.displayName) — \($0.detail)" }.joined(separator: "\n")
        let yes = Alerts.confirm(
            (ConflictDetector.describe(found) ?? "") + " en cours",
            detail + "\n\nIl n'existe qu'une table de couleurs par ecran : ce qui y ecrit en "
                   + "meme temps que nous se remplace en boucle, et l'ecran clignote.\n\n"
                   + "Les arreter maintenant ?",
            yes: "Les arreter", no: "Les laisser", window: hostWindow)

        if yes {
            let n = ConflictDetector.closeAll(found)
            Alerts.info("\(n) element(s) traite(s).", "", window: hostWindow)
            commit()
        }
    }

    private func onExport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "opusscreen-config.ini"
        panel.allowedContentTypes = []
        panel.title = "Exporter la configuration"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.export().write(to: url, atomically: true, encoding: .utf8)
            Alerts.info("Configuration exportee.", url.path, window: hostWindow)
        } catch {
            Alerts.warn("Export impossible.", error.localizedDescription, window: hostWindow)
        }
    }

    private func onImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Importer une configuration"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let imported = Settings.fromText(text)
            settings.copyFrom(imported)
            settings.save()
            Alerts.info("Configuration importee.",
                        "Les reglages sont appliques immediatement.", window: hostWindow)
            (hostWindow?.delegate as? ControlPanel)?.syncAll()
            commit()
        } catch {
            Alerts.warn("Import impossible.", error.localizedDescription, window: hostWindow)
        }
    }

    private func onFixAutoBrightness() {
        guard AutoBrightness.detectionAvailable else {
            Alerts.info("Ce reglage n'est pas detectable sur cette version de macOS.",
                        "Il se coupe dans Reglages Systeme, Moniteurs : "
                      + "« Regler automatiquement la luminosite » et « True Tone ».",
                        window: hostWindow)
            return
        }

        if !AutoBrightness.isAnyAutoActive() {
            let n = AutoBrightness.enableAuto()
            Alerts.info(n > 0 ? "Luminosite automatique retablie sur \(n) ecran(s)."
                              : "La luminosite automatique est deja desactivee.",
                        AutoBrightness.describe(), window: hostWindow)
            syncAndLayout()
            return
        }

        let yes = Alerts.confirm("Arreter la luminosite automatique ?",
                                 AutoBrightness.explanation + "\n\nEtat actuel : "
                               + AutoBrightness.describe(),
                                 yes: "Arreter", no: "Laisser", window: hostWindow)
        guard yes else { return }

        let n = AutoBrightness.disableAuto()
        if n > 0 {
            Alerts.info("C'est fait sur \(n) ecran(s).",
                        "Le meme bouton la retablira si vous changez d'avis.", window: hostWindow)
        } else {
            Alerts.warn("Le systeme a refuse.",
                        "Le reglage se coupe dans Reglages Systeme, Moniteurs.", window: hostWindow)
        }
        syncAndLayout()
    }

    private func onFactoryReset() {
        guard Alerts.confirm("Tout remettre a zero ?",
                             "Tous les reglages, modes personnalises et regles seront perdus.",
                             yes: "Tout effacer", no: "Annuler", window: hostWindow) else { return }

        settings.copyFrom(Settings())
        settings.hotkeys = Settings.defaultHotkeys()
        settings.save()
        (hostWindow?.delegate as? ControlPanel)?.syncAll()
        commit()
    }

    // ------------------------------------------------------------------ etat

    public override func sync() {
        loading = true
        defer { loading = false }

        hardware.setCheckedSilent(settings.useHardwareBacklight)
        overlay.setCheckedSilent(settings.useOverlay)
        matrix.setCheckedSilent(settings.useColorMatrix)
        matrix.isEnabled = ColorMatrixEffect.available
        smooth.setCheckedSilent(settings.smoothTransitions)
        speed.setValueSilent(Double(settings.transitionSpeedMs))
        speed.isEnabled = settings.smoothTransitions
        startup.setCheckedSilent(settings.startWithSystem)
        trayPercent.setCheckedSilent(settings.showTrayPercentage)
        darkConfirm.setCheckedSilent(!settings.skipDarkConfirm)
        conflicts.setCheckedSilent(!settings.ignoreConflicts)
        updates.setCheckedSilent(settings.checkUpdates)

        matrixNote.text = ColorMatrixEffect.available
            ? "Disponible. C'est l'etage le plus couteux en calcul : il ne s'arme que lorsqu'un "
            + "filtre, une saturation ou la loupe le demandent, et se demonte des qu'ils cessent."
            : "Indisponible : " + ColorMatrixEffect.unavailableReason + "."

        updateNote.text = "Version installee : " + Installer.currentVersionShort
            + (Updater.lastStatus.isEmpty ? "." : ". " + Updater.lastStatus)
            + "\nEmplacement : " + Installer.executablePath

        var lines: [String] = []
        lines.append("Ecrans detectes            : \(display.monitors.count)")
        for m in display.monitors {
            lines.append("  \(m.friendlyName)  \(m.bounds.width)x\(m.bounds.height)"
                       + "  gamma=\(GammaEngine.supportsGamma(m) ? "oui" : "non")")
        }
        lines.append("Retroeclairage physique    : " + HardwareBacklight.lastCapabilityDescription)
        lines.append("Enregistrement de l'ecran  : " + (ScreenFilter.shared.available ? "autorise" : "refuse"))
        lines.append("Matrice de couleur         : " + (ColorMatrixEffect.available
            ? (ColorMatrixEffect.isActive ? "active" : "disponible") : "indisponible"))
        lines.append("Fil de secours autonome    : " + (PanicKey.shared.independentThreadActive ? "actif" : "repli"))
        lines.append("Contraste renforce         : " + (Theme.highContrast ? "actif" : "inactif"))
        lines.append("Night Shift                : " + (NightShift.isEnabled ? "ACTIF (conflit)" : "inactif"))
        lines.append("Filtres de couleur macOS   : " + (SystemColorFilters.colorFilterEnabled ? "ACTIFS (conflit)" : "inactifs"))
        lines.append("Luminosite automatique     : " + AutoBrightness.describe())
        lines.append("Etat courant               : " + display.describeCurrentPlan())
        diagnostics.text = lines.joined(separator: "\n")

        let active = AutoBrightness.isAnyAutoActive()
        autoButton.textColor = active ? Theme.boost : Theme.fg
        autoButton.title = active ? "Arreter la luminosite automatique"
                                  : "Retablir la luminosite automatique"
        autoNote.text = active
            ? "Attention : macOS ajuste la luminosite d'apres la lumiere de la piece. L'ecran "
            + "semble alors « respirer » et aucun reglage ne tient - OpusScreen n'y peut rien, "
            + "cela se passe apres la table de couleurs."
            : "La luminosite automatique est desactivee : rien ne vient perturber les reglages. "
            + "Etat detaille : " + AutoBrightness.describe() + "."
    }
}
