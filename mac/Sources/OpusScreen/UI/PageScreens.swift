import Foundation
import AppKit

/// Un bloc de reglages par ecran.
///
/// PangoBright savait seulement exclure un ecran ; Iris facture les reglages
/// independants par moniteur. Ici chaque ecran peut suivre le reglage general,
/// s'en ecarter d'un decalage, ou vivre entierement sa vie.
///
/// Les cartes sont construites UNE fois par configuration d'ecrans, puis
/// seulement resynchronisees. Les detruire et les recreer a chaque
/// rafraichissement - donc a chaque mouvement de curseur - faisait disparaitre
/// sous la souris le curseur que l'on tirait.
public final class PageScreens: SettingsPage {

    private var link: ToggleRow!
    private var matrixSource: ComboRow!
    private var perScreen: ToggleRow!
    private var cards: [MonitorCard] = []
    private var sourceIds: [String] = []
    private var host: FlippedView!
    private var builtFor = ""
    private var sourcesFor = ""

    public override var pageTitle: String { "Ecrans" }
    public override var pageSubtitle: String { "Regler chaque moniteur separement" }

    public override init(_ s: Settings, _ d: DisplayController, _ push: @escaping () -> Void) {
        super.init(s, d, push)

        section("General")

        link = ToggleRow("Lier tous les ecrans",
                         "Un seul reglage pour tous. Decochez pour donner a chacun son propre profil.")
        link.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.linkMonitors = self.link.isChecked
            self.syncAndLayout()
            self.commit()
        }
        add(link, Theme.spaceSm)

        let syncAll = DarkButton("Synchroniser tous les ecrans") { [weak self] in
            self?.syncAllMonitors()
        }
        syncAll.frame.size.height = Theme.minTarget
        add(syncAll, Theme.spaceSm)

        note("Remet chaque ecran sur le reglage general : les ecrans sont relies, les "
           + "decalages et les profils propres sont retires. Les ecrans eteints, exclus "
           + "ou verrouilles le restent - c'est un choix, pas un reglage a aligner.")

        let refresh = DarkButton("Redetecter les ecrans") { [weak self] in
            guard let self = self else { return }
            self.display.refreshMonitors()
            ScreenFilter.shared.displaysChanged()
            self.syncAndLayout()
        }
        refresh.frame.size.height = Theme.minTarget
        add(refresh, Theme.spaceSm)

        section("Filtres et saturation")

        perScreen = ToggleRow("Un filtre different par ecran",
                              "Chaque ecran applique sa propre saturation et son propre filtre.")
        perScreen.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.matrixPerScreen = self.perScreen.isChecked
            self.updateMatrixStates()
            self.commit()
        }
        add(perScreen, Theme.spaceSm)

        matrixSource = ComboRow("Ecran de reference", ["Ecran principal"])
        matrixSource.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            let i = self.matrixSource.selectedIndex
            self.settings.matrixSourceId = (i > 0 && i - 1 < self.sourceIds.count) ? self.sourceIds[i - 1] : ""
            self.commit()
        }
        add(matrixSource, Theme.spaceSm)

        note("Sur Windows, la saturation et les filtres - dont la correction du daltonisme - "
           + "passaient par une matrice que le systeme n'exposait que pour le bureau ENTIER : "
           + "ils ne pouvaient pas differer d'un ecran a l'autre, et un ecran de reference "
           + "devait etre designe faute de mieux. Ici la matrice est recalculee ecran par "
           + "ecran : la limite n'existe plus. Le choix demeure pour qui prefere un filtre "
           + "unique - une correction daltonienne qui change d'un ecran a l'autre perturbe "
           + "plus qu'elle n'aide.")

        section("Ecrans detectes")

        host = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: Theme.px(10)))
        add(host, Theme.spaceSm)

        note("Le mode « ecran eteint » reprend le BlackOut de Lunar : l'ecran est occulte "
           + "sans etre deconnecte, les fenetres qui s'y trouvent restent en place.")

        note("« Profil independant » donne a l'ecran ses propres valeurs, mais il reste "
           + "une machine : choisir un mode dans la page Ecran les rafraichit, parce qu'un "
           + "mode est une commande pour tout le poste. Seul un reglage pris ICI, ecran par "
           + "ecran, ne se propage pas - et il tient jusqu'au prochain mode. Un ecran qui ne "
           + "doit JAMAIS bouger - une dalle calibree pour un travail de couleur - se coche "
           + "« ne pas suivre les reglages generaux » : plus rien ne l'atteint, ni les modes, "
           + "ni l'horaire, ni les raccourcis.")
    }

    required init?(coder: NSCoder) { fatalError() }

    // ------------------------------------------------------------------ actions

    /// Tous les ecrans reviennent au reglage general, en un geste.
    private func syncAllMonitors() {
        settings.linkMonitors = true
        for m in display.monitors {
            let ms = settings.forMonitor(m)
            // Un ecran verrouille l'a ete expressement, pour une raison que ce
            // bouton ne connait pas : il n'est pas aligne de force.
            if ms.locked { continue }
            ms.independent = false
            ms.brightnessOffset = 0
        }
        syncAndLayout()
        commit()
    }

    /// Recopie les reglages d'un ecran sur tous les autres.
    private func copyToOthers(_ source: MonitorInfo) {
        let from = settings.forMonitor(source)
        for m in display.monitors where m.stableId != source.stableId {
            let to = settings.forMonitor(m)
            to.independent = from.independent
            to.own = from.own.clone()
            to.brightnessOffset = from.brightnessOffset
            to.enabled = from.enabled
            to.locked = from.locked
        }
        syncAndLayout()
        commit()
    }

    // ------------------------------------------------------------------ construction

    /// Empreinte de ce qui impose de reconstruire : les ecrans, et la liaison.
    private func signature(withLink: Bool) -> String {
        var s = withLink ? (settings.linkMonitors ? "L|" : "I|") : ""
        for m in display.monitors {
            s += m.stableId + "/" + m.friendlyName + "/" + m.detail + "|"
        }
        return s
    }

    /// Recharge la liste des ecrans de reference.
    ///
    /// Le nom seul ne suffit pas quand deux ecrans sont du meme modele - c'est
    /// justement le cas ou le choix compte : la sortie et la definition sont donc
    /// rappelees dans l'intitule.
    private func rebuildSourceList() {
        let sig = signature(withLink: false)
        if sig != sourcesFor {
            sourcesFor = sig
            sourceIds.removeAll()
            var names = ["Ecran principal (automatique)"]
            for m in display.monitors {
                sourceIds.append(m.stableId)
                names.append("Ecran \(m.index + 1) - \(m.friendlyName) (\(m.detail))")
            }
            matrixSource.setItems(names)
        }

        var selected = 0
        for (i, id) in sourceIds.enumerated() where id == settings.matrixSourceId { selected = i + 1 }
        matrixSource.selectedIndex = selected
    }

    private func updateMatrixStates() {
        matrixSource.isEnabled = !settings.matrixPerScreen
    }

    private func rebuildCards() {
        for c in cards { c.removeFromSuperview() }
        cards.removeAll()

        let several = display.monitors.count > 1
        for m in display.monitors {
            let card = MonitorCard(settings, m, settings.forMonitor(m),
                                   allowIndependent: !settings.linkMonitors,
                                   canCopy: several)
            card.onChanged = { [weak self] in
                self?.layoutCards()
                self?.commit()
            }
            card.onLiveChanged = { [weak self] in self?.commitNoSave() }
            card.onCopyRequested = { [weak self] in self?.copyToOthers(m) }
            host.addSubview(card)
            cards.append(card)
        }
        layoutCards()
    }

    /// Empile les cartes, puis la page : une carte qui grandit repousse la note
    /// qui suit.
    private func layoutCards() {
        var y: CGFloat = 0
        let w = max(Theme.px(160), host.bounds.width)
        for card in cards {
            let h = card.computeHeight()
            card.frame = NSRect(x: 0, y: y, width: w, height: h)
            card.layoutChildren()
            y += h + Theme.spaceSm
        }
        let wanted = max(Theme.px(10), y)
        if abs(host.frame.height - wanted) > 0.5 {
            host.frame.size.height = wanted
            super.relayout()
        }
    }

    public override func relayout() {
        super.relayout()
        layoutCards()
    }

    public override func sync() {
        loading = true
        defer { loading = false }

        link.setCheckedSilent(settings.linkMonitors)
        perScreen.setCheckedSilent(settings.matrixPerScreen)
        rebuildSourceList()
        updateMatrixStates()

        let sig = signature(withLink: true)
        if sig != builtFor {
            builtFor = sig
            rebuildCards()
        } else {
            for c in cards { c.sync() }
            layoutCards()
        }
    }
}

/// Bloc de reglages d'un ecran.
public final class MonitorCard: NSView {

    private let settings: Settings
    private let monitor: MonitorInfo
    private let ms: MonitorSettings

    private let titleLabel: LabelView
    private let detailLabel = LabelView("")
    private let enabledRow: ToggleRow
    private let blackoutRow: ToggleRow
    private let independentRow: ToggleRow
    private let lockedRow: ToggleRow
    private let offsetRow: SliderRow
    private let ownBrightRow: SliderRow
    private let ownKelvinRow: SliderRow
    private let copyButton: DarkButton

    private var loading = false

    public var onChanged: (() -> Void)?
    public var onLiveChanged: (() -> Void)?
    public var onCopyRequested: (() -> Void)?

    public init(_ s: Settings, _ m: MonitorInfo, _ ms: MonitorSettings,
                allowIndependent: Bool, canCopy: Bool) {
        self.settings = s
        self.monitor = m
        self.ms = ms

        titleLabel = LabelView(m.label)
        enabledRow = ToggleRow("Appliquer les effets sur cet ecran", nil)
        blackoutRow = ToggleRow("Ecran eteint", nil)
        independentRow = ToggleRow("Profil independant", nil)
        lockedRow = ToggleRow("Ne pas suivre les reglages generaux", nil)
        offsetRow = SliderRow("Decalage de luminosite", -50, 50, "pts")
        ownBrightRow = SliderRow("Luminosite propre", GammaEngine.minBrightness, GammaEngine.maxBrightness, "%")
        ownKelvinRow = SliderRow("Temperature propre", Double(ColorTemp.minKelvin), Double(ColorTemp.maxKelvin), "K")
        copyButton = DarkButton("Copier sur les autres ecrans")

        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 200))

        wantsLayer = true
        layer?.backgroundColor = Theme.sunken.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = Theme.border.cgColor

        titleLabel.font = Theme.bodyBold
        titleLabel.color = Theme.fg
        addSubview(titleLabel)

        // L'identifiant materiel etait affiche ici. Il ne dit rien a personne et,
        // pire, il etait identique pour deux ecrans du meme modele : la seule
        // information censee les distinguer les confondait. La sortie physique et
        // le mode de reglage materiel, eux, se verifient d'un coup d'oeil derriere
        // la machine.
        let extra = HardwareBacklight.describeFor(m)
        detailLabel.text = m.detail + (extra.isEmpty ? "" : "  -  " + extra)
        detailLabel.font = Theme.small
        detailLabel.color = Theme.faint
        addSubview(detailLabel)

        enabledRow.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.ms.enabled = self.enabledRow.isChecked
            self.updateStates()
            self.fire()
        }
        addSubview(enabledRow)

        blackoutRow.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.ms.blackout = self.blackoutRow.isChecked
            self.updateStates()
            self.fire()
        }
        addSubview(blackoutRow)

        independentRow.isHidden = !allowIndependent
        independentRow.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            // Partir de ce que l'ecran affiche a cet instant. Sans cela, cocher la
            // case le faisait sauter au dernier profil propre memorise - souvent un
            // profil neutre jamais regle, donc un changement brutal que personne
            // n'avait demande.
            if self.independentRow.isChecked { self.ms.own.copyFrom(self.settings.effectiveFor(self.monitor)) }
            self.ms.independent = self.independentRow.isChecked
            self.updateStates()
            self.fire()
        }
        addSubview(independentRow)

        lockedRow.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            if self.lockedRow.isChecked { self.ms.own.copyFrom(self.settings.effectiveFor(self.monitor)) }
            self.ms.locked = self.lockedRow.isChecked
            self.updateStates()
            self.fire()
        }
        addSubview(lockedRow)

        offsetRow.mark(at: 0)
        offsetRow.setFormat("signed")
        offsetRow.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.ms.brightnessOffset = self.offsetRow.value
            self.onLiveChanged?()
        }
        offsetRow.onCommit = { [weak self] in self?.fire() }
        addSubview(offsetRow)

        ownBrightRow.mark(at: 100, warnAbove: 135)
        ownBrightRow.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.ms.own.brightness = self.ownBrightRow.value
            self.onLiveChanged?()
        }
        ownBrightRow.onCommit = { [weak self] in self?.fire() }
        addSubview(ownBrightRow)

        ownKelvinRow.setAccent(Theme.warm)
        ownKelvinRow.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.ms.own.kelvin = Int(self.ownKelvinRow.value)
            self.onLiveChanged?()
        }
        ownKelvinRow.onCommit = { [weak self] in self?.fire() }
        addSubview(ownKelvinRow)

        copyButton.isHidden = !canCopy
        copyButton.onClick = { [weak self] in self?.onCopyRequested?() }
        addSubview(copyButton)

        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    private func fire() {
        guard !loading else { return }
        onChanged?()
    }

    /// Vrai quand cet ecran affiche ses propres valeurs plutot que le reglage
    /// general : soit parce qu'il a un profil independant, soit parce qu'il est
    /// verrouille - et le verrou vaut meme quand les ecrans sont lies.
    private var independent: Bool {
        ms.locked || (ms.independent && !independentRow.isHidden)
    }

    public func computeHeight() -> CGFloat {
        let w = max(Theme.px(160), bounds.width - Theme.px(28))
        var h = Theme.px(12) + Theme.px(20) + Theme.px(18) + Theme.spaceSm
        h += enabledRow.fittingHeight(for: w)
        h += blackoutRow.fittingHeight(for: w)
        h += lockedRow.fittingHeight(for: w)
        if !independentRow.isHidden { h += independentRow.fittingHeight(for: w) }
        if independent { h += SliderRow.standardHeight * 2 + Theme.spaceSm }
        else { h += SliderRow.standardHeight + Theme.spaceSm }
        if !copyButton.isHidden { h += Theme.minTarget + Theme.spaceSm }
        return h + Theme.px(12)
    }

    private func updateStates() {
        let indep = independent
        offsetRow.isHidden = indep
        ownBrightRow.isHidden = !indep
        ownKelvinRow.isHidden = !indep

        let on = ms.enabled && !ms.blackout
        offsetRow.isEnabled = on
        ownBrightRow.isEnabled = on
        ownKelvinRow.isEnabled = on
        lockedRow.isEnabled = on

        // Un ecran verrouille garde ses valeurs quoi qu'il arrive : le profil
        // independant n'a plus rien a decider pour lui.
        independentRow.isEnabled = on && !ms.locked

        layer?.borderColor = (ms.blackout ? Theme.danger : Theme.border).cgColor
        layoutChildren()
    }

    public func sync() {
        loading = true
        defer { loading = false }

        enabledRow.setCheckedSilent(ms.enabled)
        blackoutRow.setCheckedSilent(ms.blackout)
        independentRow.setCheckedSilent(ms.independent)
        lockedRow.setCheckedSilent(ms.locked)
        offsetRow.setValueSilent(ms.brightnessOffset)
        ownBrightRow.setValueSilent(ms.own.brightness)
        ownKelvinRow.setValueSilent(Double(ms.own.kelvin))
        updateStates()
    }

    public func layoutChildren() {
        let w = max(Theme.px(80), bounds.width - Theme.px(28))
        let x = Theme.px(14)
        var y = Theme.px(12)

        titleLabel.frame = NSRect(x: x, y: y, width: w, height: Theme.px(20)); y += Theme.px(20)
        detailLabel.frame = NSRect(x: x, y: y, width: w, height: Theme.px(18))
        y += Theme.px(18) + Theme.spaceSm

        func place(_ row: ToggleRow) {
            guard !row.isHidden else { return }
            let h = row.fittingHeight(for: w)
            row.frame = NSRect(x: x, y: y, width: w, height: h)
            row.needsLayout = true
            y += h
        }

        place(enabledRow)
        place(blackoutRow)
        if !independentRow.isHidden { place(independentRow) }
        place(lockedRow)
        y += Theme.spaceSm

        if independent {
            ownBrightRow.frame = NSRect(x: x, y: y, width: w, height: SliderRow.standardHeight)
            ownBrightRow.needsLayout = true
            ownKelvinRow.frame = NSRect(x: x, y: y + SliderRow.standardHeight,
                                        width: w, height: SliderRow.standardHeight)
            ownKelvinRow.needsLayout = true
            y += SliderRow.standardHeight * 2
        } else {
            offsetRow.frame = NSRect(x: x, y: y, width: w, height: SliderRow.standardHeight)
            offsetRow.needsLayout = true
            y += SliderRow.standardHeight
        }
        y += Theme.spaceSm

        if !copyButton.isHidden {
            copyButton.frame = NSRect(x: x, y: y, width: min(w, Theme.px(260)), height: Theme.minTarget)
        }
    }

    public override func isAccessibilityElement() -> Bool { false }
}
