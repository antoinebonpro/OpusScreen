import Foundation
import AppKit

/// Onglet dedie au daltonisme.
///
/// La correction vivait autrefois en haut de la page Vision, melee a la loupe, a
/// l'anneau du pointeur et aux teintes de lecture. Or c'est de loin le besoin le
/// plus repandu de l'application - pres d'un homme sur douze - et le seul qui se
/// regle en plusieurs etapes : dire quelle deficience, a quel degre, puis
/// VERIFIER que les couleurs confondues se separent. Il merite son onglet, et
/// d'etre joignable d'un clic depuis la colonne.
///
/// La page commence par ce qui se fait le plus souvent : allumer ou couper la
/// correction, et choisir en un clic la couleur mal percue. Le reglage fin et le
/// comparateur viennent ensuite, pour qui veut aller plus loin.
public final class PageColorBlind: SettingsPage {

    private var active: ToggleRow!
    private var type: ComboRow!
    private var usage: ComboRow!
    private var severity: SliderRow!
    private var strength: SliderRow!
    private var clinical: LabelView!
    private var confusionsLabel: LabelView!
    private var status: LabelView!
    private var board: ConfusionBoard!
    private var readerToggle: ToggleRow!
    private var startupToggle: ToggleRow!
    private var copyButton: DarkButton!
    private var presets: ComboRow!
    private var presetNote: LabelView!
    private var examNote: LabelView!
    private var startupNote: LabelView!

    private var tiles: [DarkButton] = []
    private var tileHost: FlippedView!
    private var presetButtons: [DarkButton] = []
    private var presetHost: FlippedView!
    private var presetsSignature = ""

    /// Derniere correction choisie : l'interrupteur la retrouve quand on le rallume.
    private var lastFilter: ColorFilter = .deuteranopia

    /// Fournis par l'application : la page decide, l'application execute.
    public var aidsChanged: (() -> Void)?
    public var copyColorUnderCursor: (() -> String)?

    public override var pageTitle: String { "Daltonisme" }
    public override var pageSubtitle: String { "Corriger, verifier et identifier les couleurs" }

    private static let types: [ColorFilter] = [.none, .protanopia, .deuteranopia, .tritanopia]
    private static let deficiencies: [ColorFilter] = [.protanopia, .deuteranopia, .tritanopia]

    public override init(_ s: Settings, _ d: DisplayController, _ push: @escaping () -> Void) {
        super.init(s, d, push)
        buildExam()
        buildQuickStart()
        buildTuning()
        buildComparator()
        buildPresets()
        buildStartup()
        buildColorIdentifier()
    }

    required init?(coder: NSCoder) { fatalError() }

    // ------------------------------------------------------------------ test guide

    private func buildExam() {
        section("Test de vision")

        let run = DarkButton("Lancer le test guide (2 minutes)") { [weak self] in self?.runExam() }
        run.font = Theme.bodyBold
        run.frame.size.height = Theme.minTarget + 8
        add(run, Theme.spaceSm)

        examNote = UiKit.caption("")
        add(examNote, Theme.spaceXs)

        note("Des planches ou se cache un chiffre trouvent le TYPE, puis des comparaisons de "
           + "couleurs mesurent la GRAVITE en resserrant l'ecart jusqu'a votre limite. Le reglage "
           + "obtenu vaut mieux qu'un reglage devine : une correction calibree sur une deficience "
           + "complete rend l'ecran criard a qui n'en a qu'une partie. Pendant le test, la "
           + "correction en cours est retiree, puis retablie a la sortie.")
    }

    private func runExam() {
        let dialog = VisionExamDialog(settings, display)
        let applied = dialog.run(over: hostWindow)
        syncAndLayout()
        if applied { commit() }
    }

    // ------------------------------------------------------------------ en un clic

    private func buildQuickStart() {
        section("Correction")

        active = ToggleRow("Correction des couleurs active",
                           "Coupe et retablit la correction choisie. ⌃⌥D fait de meme, fenetre fermee.")
        active.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.setFilter(self.active.isChecked ? self.lastFilter : .none)
        }
        add(active, Theme.spaceSm)

        status = UiKit.caption("")
        add(status, Theme.spaceXs)

        // Trois tuiles plutot qu'une liste : le choix se fait en un clic, et le nom
        // dit ce que l'on vit (« rouge mal percu ») avant le terme medical.
        tileHost = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: Theme.minTarget + 4))
        for f in PageColorBlind.deficiencies {
            let b = DarkButton(Vision.plainName(f)) { [weak self] in self?.setFilter(f) }
            b.frame.size.height = Theme.minTarget
            tileHost.addSubview(b)
            tiles.append(b)
        }
        add(tileHost, Theme.spaceSm)

        note("Choisissez la couleur que vous distinguez mal. En cas de doute, le vert "
           + "(deuteranomalie) est de loin le cas le plus frequent : commencez par lui, "
           + "puis verifiez plus bas que les paires de couleurs se separent.")
    }

    // ------------------------------------------------------------------ reglage fin

    private func buildTuning() {
        section("Reglage fin")

        type = ComboRow("Ce que je distingue mal", PageColorBlind.types.map { Vision.plainName($0) })
        type.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.setFilter(PageColorBlind.types[max(0, self.type.selectedIndex)])
        }
        add(type, Theme.spaceSm)

        clinical = UiKit.caption("")
        add(clinical, Theme.spaceXs)

        confusionsLabel = UiKit.caption("")
        add(confusionsLabel, Theme.spaceXs)

        severity = SliderRow("Gravite", 0, 100, "%")
        severity.mark(at: 100)
        severity.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.current.visionSeverity = self.severity.value
            self.updateTexts()
            self.live()
        }
        severity.onCommit = { [weak self] in self?.commit() }
        add(severity, Theme.spaceSm)

        note("La dichromatie - un type de cone totalement absent - est le cas rare. "
           + "Le cas frequent est l'anomalie : le cone existe mais reagit a cote, et la "
           + "confusion n'est que partielle. Une correction calibree sur la dichromatie "
           + "sur-corrige alors, et l'ecran devient criard sans etre plus lisible. "
           + "Descendez la gravite jusqu'a ce que les paires ci-dessous se separent tout "
           + "juste : c'est le reglage juste.")

        strength = SliderRow("Intensite de la correction", 0, 150, "%")
        strength.mark(at: 100, warnAbove: 120)
        strength.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.current.filterStrength = self.strength.value
            self.updateTexts()
            self.live()
        }
        strength.onCommit = { [weak self] in self?.commit() }
        add(strength, Theme.spaceSm)

        usage = ComboRow("Usage", ["Corriger : ecarter les couleurs que je confonds",
                                   "Simuler : montrer ce que percoit cette vision"])
        usage.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.current.mode = self.usage.selectedIndex == 1 ? .simulation : .correction
            self.syncAndLayout()
            self.commit()
        }
        add(usage, Theme.spaceSm)

        note("Le mode simulation ne sert pas la personne daltonienne : il sert a qui "
           + "concoit une interface, un graphique ou un support de cours et veut verifier "
           + "qu'il reste lisible.")
    }

    // ------------------------------------------------------------------ comparateur

    private func buildComparator() {
        section("Verification")

        board = ConfusionBoard(settings)
        board.onHeightChanged = { [weak self] in self?.relayout() }
        add(board, Theme.spaceSm)

        note("A gauche, deux couleurs telles que vous les percevez aujourd'hui. A droite, "
           + "les memes une fois la correction appliquee, puis percues par cette meme vision. "
           + "L'ecart est chiffre en Delta E : en dessous de 2,3 l'oeil humain ne distingue "
           + "plus rien, au-dela il distingue. Le reglage est bon quand le nombre de droite "
           + "est nettement plus grand que celui de gauche.")
    }

    // ------------------------------------------------------------------ reglages enregistres

    private func buildPresets() {
        section("Mes reglages")

        presets = ComboRow("Reglage enregistre", ["(aucun)"])
        presets.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.updatePresetNote()
        }
        add(presets, Theme.spaceSm)

        presetNote = UiKit.caption("")
        add(presetNote, Theme.spaceXs)

        presetHost = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: Theme.minTarget + 4))
        presetButtons.append(makePresetButton("Appliquer") { [weak self] in self?.applySelectedPreset() })
        presetButtons.append(makePresetButton("Enregistrer le reglage actuel...") { [weak self] in self?.saveCurrent() })
        presetButtons.append(makePresetButton("Renommer...") { [weak self] in self?.renameSelected() })
        presetButtons.append(makePresetButton("Supprimer") { [weak self] in self?.deleteSelected() })
        add(presetHost, Theme.spaceSm)

        note("Un reglage enregistre ne retient que la correction des couleurs - type, gravite, "
           + "intensite, usage. Le rappeler ne touche donc ni la luminosite, ni la temperature : "
           + "ce serait une mauvaise surprise pour un reglage nomme « lecture ». Tout est ecrit "
           + "dans le fichier de configuration et vous attend au prochain demarrage.")
    }

    private func makePresetButton(_ title: String, _ action: @escaping () -> Void) -> DarkButton {
        let b = DarkButton(title, action: action)
        b.frame.size.height = Theme.minTarget
        presetHost.addSubview(b)
        return b
    }

    /// Repartit la rangee selon la LONGUEUR de chaque libelle, et non en parts egales.
    ///
    /// Quatre boutons a un quart de la largeur chacun : « Appliquer » nageait dans
    /// le sien pendant que « Enregistrer le reglage actuel... » y perdait la moitie
    /// de son texte. Un quart de la place pour un tiers du texte ne tient a aucune
    /// echelle. Chaque bouton recoit donc d'abord ce que son texte demande ; ce qui
    /// reste se partage a parts egales.
    private func layoutPresetButtons() {
        let n = presetButtons.count
        guard n > 0 else { return }
        let gap = Theme.spaceXs
        let available = presetHost.bounds.width - gap * CGFloat(n - 1)
        guard available > CGFloat(n) else { return }

        var needed: [CGFloat] = []
        var total: CGFloat = 0
        for b in presetButtons {
            let w = Draw.width(of: b.title, font: b.font) + Theme.px(24)
            needed.append(w)
            total += w
        }

        var widths = [CGFloat](repeating: 0, count: n)
        if total <= available {
            let extra = (available - total) / CGFloat(n)
            for i in 0..<n { widths[i] = needed[i] + extra }
        } else {
            // Trop etroit pour tout le monde : on partage au prorata plutot que
            // d'affamer le plus long.
            for i in 0..<n { widths[i] = max(Theme.px(70), available * needed[i] / total) }
        }

        var x: CGFloat = 0
        for i in 0..<n {
            presetButtons[i].frame = NSRect(x: x, y: Theme.px(2), width: widths[i], height: Theme.minTarget)
            x += widths[i] + gap
        }
    }

    private func layoutTiles() {
        let n = tiles.count
        guard n > 0 else { return }
        let gap = Theme.spaceSm
        let w = max(Theme.px(80), (tileHost.bounds.width - gap * CGFloat(n - 1)) / CGFloat(n))
        for (i, b) in tiles.enumerated() {
            b.frame = NSRect(x: CGFloat(i) * (w + gap), y: 2, width: w, height: Theme.minTarget)
        }
    }

    private func selectedPreset() -> VisionPreset? {
        let i = presets.selectedIndex
        return (i >= 0 && i < settings.visionPresets.count) ? settings.visionPresets[i] : nil
    }

    private func applySelectedPreset() {
        guard let p = selectedPreset() else { return }
        p.applyTo(&settings.current)
        if ColorMatrixEffect.isVisionFilter(p.filter) { lastFilter = p.filter }
        syncAndLayout()
        commit()
    }

    private func saveCurrent() {
        let suggestion = ColorMatrixEffect.isVisionFilter(settings.current.filter)
            ? Vision.plainName(settings.current.filter) : "Mon reglage"
        guard let name = PromptDialog.ask("Enregistrer ce reglage", "Nom du reglage :",
                                          suggestion, window: hostWindow) else { return }
        savePreset(name)
    }

    /// Enregistre les reglages courants sous ce nom. Public : les tests s'en servent.
    public func savePreset(_ name: String) {
        guard !name.isEmpty else { return }
        let preset = VisionPreset.fromProfile(name, settings.current)
        settings.visionPresets.removeAll { $0.name == preset.name }
        settings.visionPresets.append(preset)
        syncAndLayout()
        selectPreset(preset.name)
        settings.save()
    }

    private func renameSelected() {
        guard let p = selectedPreset() else { return }
        guard let name = PromptDialog.ask("Renommer", "Nouveau nom :", p.name, window: hostWindow) else { return }
        p.name = name
        syncAndLayout()
        selectPreset(name)
        settings.save()
    }

    private func deleteSelected() {
        guard let p = selectedPreset() else { return }
        guard Alerts.confirm("Supprimer le reglage « \(p.name) » ?", "",
                             yes: "Supprimer", no: "Annuler", window: hostWindow) else { return }
        settings.visionPresets.removeAll { $0 === p }
        syncAndLayout()
        settings.save()
    }

    private func selectPreset(_ name: String) {
        if let i = settings.visionPresets.firstIndex(where: { $0.name == name }) {
            presets.selectedIndex = i
        }
        updatePresetNote()
    }

    private func updatePresetNote() {
        let p = selectedPreset()
        presetNote.text = p?.describe() ?? "Aucun reglage enregistre pour l'instant."
        let any = p != nil
        presetButtons[0].isEnabled = any
        presetButtons[2].isEnabled = any
        presetButtons[3].isEnabled = any
    }

    /// Recharge la liste des reglages enregistres, et seulement si elle a change :
    /// la vider a chaque rafraichissement refermerait la liste ouverte sous les
    /// yeux de l'utilisateur, et perdrait sa selection.
    private func refreshPresetList() {
        let signature = settings.visionPresets.map { $0.name }.joined(separator: "|")
        if signature != presetsSignature {
            presetsSignature = signature
            let keep = presets.selectedIndex
            let names = settings.visionPresets.isEmpty
                ? ["(aucun reglage enregistre)"]
                : settings.visionPresets.map { $0.name }
            presets.setItems(names)
            presets.selectedIndex = min(max(0, keep), names.count - 1)
        }
        updatePresetNote()
    }

    // ------------------------------------------------------------------ demarrage

    private func buildStartup() {
        section("Au demarrage")

        startupToggle = ToggleRow("Lancer OpusScreen a l'ouverture de session",
                                  "Votre correction est alors posee des l'ouverture de session, sans y penser.")
        startupToggle.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.startWithSystem = self.startupToggle.isChecked
            LoginItem.apply(self.settings.startWithSystem)
            self.updateStartupNote()
            self.commit()
        }
        add(startupToggle, Theme.spaceSm)

        startupNote = UiKit.caption("")
        add(startupNote, Theme.spaceXs)
    }

    private func updateStartupNote() {
        if !settings.startWithSystem {
            startupNote.text = "OpusScreen ne demarre pas avec la session : la correction ne revient "
                             + "qu'une fois l'application lancee a la main."
            return
        }
        startupNote.text = ColorMatrixEffect.isVisionFilter(settings.current.filter)
            ? "Ce reglage est repose a chaque ouverture de session, automatiquement."
            : "OpusScreen demarre avec la session. Aucune correction n'est active pour l'instant."
    }

    // ------------------------------------------------------------------ identificateur

    private func buildColorIdentifier() {
        section("Identifier une couleur")

        readerToggle = ToggleRow("Etiquette qui suit le pointeur",
                                 "Nomme en continu la couleur survolee, avec sa valeur exacte.")
        readerToggle.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.colorReaderEnabled = self.readerToggle.isChecked
            self.aidsChanged?()
            self.commit()
        }
        add(readerToggle, Theme.spaceSm)

        copyButton = DarkButton("Copier la couleur sous le pointeur") { [weak self] in
            guard let self = self, let copy = self.copyColorUnderCursor else { return }
            let what = copy()
            self.copyButton.title = what.isEmpty ? "Copier la couleur sous le pointeur" : "Copie : " + what
        }
        copyButton.frame.size.height = Theme.minTarget
        add(copyButton, Theme.spaceSm)

        note("La couleur annoncee est celle que l'application a reellement dessinee, "
           + "avant la table de couleurs de la carte graphique et avant les filtres : "
           + "les reglages en cours ne faussent donc jamais la reponse. "
           + "⌃⌥C affiche l'etiquette, ⌃⌥⇧C copie la valeur.")
    }

    // ------------------------------------------------------------------ etat

    /// Point d'entree unique de tous les choix de filtre - interrupteur, tuiles,
    /// liste. Passer d'un filtre esthetique a une correction de vision, ou
    /// l'inverse, ne doit pas effacer l'autre : seuls les filtres de vision sont
    /// pilotes ici.
    private func setFilter(_ chosen: ColorFilter) {
        if chosen == .none {
            if ColorMatrixEffect.isVisionFilter(settings.current.filter) {
                lastFilter = settings.current.filter
                settings.current.filter = .none
            }
        } else {
            settings.current.filter = chosen
            lastFilter = chosen
        }
        syncAndLayout()
        commit()
    }

    private func live() {
        board?.rebuild()
        commitNoSave()
    }

    private func updateTexts() {
        let f = ColorMatrixEffect.isVisionFilter(settings.current.filter) ? settings.current.filter : ColorFilter.none

        clinical.text = Vision.clinicalName(f)
        confusionsLabel.text = Vision.confusions(f)
        severity.hint = Vision.severityWord(settings.current.visionSeverity)

        strength.hint = settings.current.filterStrength > 115 ? "couleurs poussees, verifiez le confort"
            : (settings.current.filterStrength < 40 ? "correction discrete" : "")

        let matrixReady = settings.useColorMatrix && ColorMatrixEffect.available
        if !matrixReady {
            status.text = "Indisponible : " + (ColorMatrixEffect.available
                ? "l'etage matrice est coupe dans l'onglet Avance."
                : ColorMatrixEffect.unavailableReason + " (voir la page Decouvrir).")
        } else if f == .none {
            status.text = "Aucune correction appliquee."
        } else {
            status.text = (settings.current.mode == .simulation ? "Simulation : " : "Correction : ")
                + Vision.plainName(f).lowercased()
                + String(format: ", gravite %.0f %%.", settings.current.visionSeverity)
        }

        board?.rebuild()
    }

    private func updateStates() {
        let f = settings.current.filter
        let vision = ColorMatrixEffect.isVisionFilter(f)
        let matrixReady = settings.useColorMatrix && ColorMatrixEffect.available

        active.isEnabled = matrixReady
        type.isEnabled = matrixReady
        for b in tiles { b.isEnabled = matrixReady }
        severity.isEnabled = vision && matrixReady
        usage.isEnabled = vision && matrixReady
        strength.isEnabled = vision && matrixReady && settings.current.mode == .correction

        // La tuile de la correction en cours est mise en avant : on voit d'un coup
        // d'oeil ce qui est applique, sans lire la liste.
        for (i, b) in tiles.enumerated() {
            let on = vision && PageColorBlind.deficiencies[i] == f
            b.fillColor = on ? Theme.accentDim : nil
        }
    }

    public override func relayout() {
        super.relayout()
        layoutTiles()
        layoutPresetButtons()
    }

    public override func sync() {
        loading = true
        defer { loading = false }

        let f = ColorMatrixEffect.isVisionFilter(settings.current.filter) ? settings.current.filter : ColorFilter.none
        if f != .none { lastFilter = f }

        active.setCheckedSilent(f != .none)
        type.selectedIndex = PageColorBlind.types.firstIndex(of: f) ?? 0

        severity.setValueSilent(settings.current.visionSeverity)
        strength.setValueSilent(settings.current.filterStrength)
        usage.selectedIndex = settings.current.mode == .simulation ? 1 : 0

        readerToggle.setCheckedSilent(settings.colorReaderEnabled)
        startupToggle.setCheckedSilent(settings.startWithSystem)

        refreshPresetList()
        updateTexts()
        updateStates()
        updateStartupNote()

        examNote.text = settings.lastExamSummary.isEmpty
            ? "Jamais passe. Deux minutes suffisent, et le resultat s'applique en un clic."
            : "Dernier test : " + settings.lastExamSummary + "."
    }
}
