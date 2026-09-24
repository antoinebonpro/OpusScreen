import Foundation
import AppKit

/// Regles par application : Lunar les reserve a sa version payante.
///
/// Le principe est simple mais change l'usage : on cesse d'arbitrer entre « bon
/// pour les yeux » et « couleurs justes », puisque chaque application obtient ce
/// qui lui convient.
public final class PageApps: SettingsPage {

    private var enabled: ToggleRow!
    private var battery: ToggleRow!
    private var fullscreen: ComboRow!
    private var list: RuleList!
    private var current: LabelView!

    public var watcher: AppWatcher?

    public override var pageTitle: String { "Applications" }
    public override var pageSubtitle: String { "Un reglage different selon le logiciel actif" }

    /// Dans l'ordre de `FullscreenSuspend`.
    private static let fullscreenChoices = [
        "Ne rien changer",
        "Retirer le voile seulement",
        "Suspendre tous les effets",
    ]

    public override init(_ s: Settings, _ d: DisplayController, _ push: @escaping () -> Void) {
        super.init(s, d, push)

        section("Suspension automatique")

        fullscreen = ComboRow("En plein ecran", PageApps.fullscreenChoices)
        fullscreen.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.onFullscreen = FullscreenSuspend(rawValue: max(0, self.fullscreen.selectedIndex)) ?? .overlayOnly
            self.commit()
        }
        add(fullscreen, Theme.spaceSm)

        note("Le voile est une fenetre semi-transparente posee par-dessus l'ecran : il ne "
           + "sert qu'en dessous de 35 % de luminosite, et c'est le seul etage qu'un jeu ou "
           + "une video plein ecran supporte mal. La table de couleurs, elle, est appliquee "
           + "par la carte graphique en sortie et traverse le plein ecran sans dommage - "
           + "c'est elle qui porte la luminosite au-dela de 100 %, la ou un film sombre en a "
           + "le plus besoin.")

        battery = ToggleRow("Ne pas monter au-dessus de 100 % sur batterie",
                            "Le boost pousse le retroeclairage au maximum, ce qui vide l'accumulateur.")
        battery.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.disableOnBattery = self.battery.isChecked
            self.commit()
        }
        add(battery, Theme.spaceSm)

        section("Regles par application")

        enabled = ToggleRow("Activer les regles par application", nil)
        enabled.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.appRulesEnabled = self.enabled.isChecked
            self.list.isEnabledList = self.enabled.isChecked
            self.commit()
        }
        add(enabled, Theme.spaceSm)

        current = UiKit.caption("")
        add(current, Theme.spaceXs)

        list = RuleList(settings)
        list.frame.size.height = Theme.px(190)
        list.onChange = { [weak self] in self?.commit() }
        add(list, Theme.spaceSm)

        let addCurrent = DarkButton("Ajouter l'application au premier plan") { [weak self] in
            self?.onAddCurrent()
        }
        addCurrent.frame.size.height = Theme.minTarget
        add(addCurrent, Theme.spaceSm)

        let addKnown = DarkButton("Ajouter depuis la liste des applications courantes...") { [weak self] in
            self?.onAddKnown()
        }
        addKnown.frame.size.height = Theme.minTarget
        add(addKnown, Theme.spaceXs)

        let remove = DarkButton("Supprimer la regle selectionnee") { [weak self] in
            guard let self = self else { return }
            let i = self.list.selectedIndex
            guard i >= 0, i < self.settings.appRules.count else { return }
            self.settings.appRules.remove(at: i)
            self.list.reload()
            self.commit()
        }
        remove.frame.size.height = Theme.minTarget
        add(remove, Theme.spaceXs)

        note("Cliquez dans la moitie droite d'une regle pour changer le mode qu'elle applique. "
           + "En l'absence de regle, les reglages generaux s'appliquent.")

        note("Sur macOS les applications sont designees par leur IDENTIFIANT DE PAQUET - "
           + "« com.apple.safari » - et non par le nom du fichier. C'est le seul nom qui ne "
           + "change ni avec la langue du systeme, ni si l'application est renommee dans le "
           + "Finder.")
    }

    required init?(coder: NSCoder) { fatalError() }

    private func onAddCurrent() {
        let proc = watcher?.currentProcess ?? ""
        let me = (Bundle.main.bundleIdentifier ?? "").lowercased()
        if proc.isEmpty || proc == me {
            Alerts.info("Aucune autre application au premier plan.",
                        "Laissez cette fenetre ouverte, cliquez sur l'application voulue, "
                      + "puis revenez ici : son nom apparaitra juste au-dessus de la liste.",
                        window: hostWindow)
            return
        }
        addRule(proc, "Normal")
    }

    private func onAddKnown() {
        let entries = KnownApps.suggestions()
        let alert = NSAlert()
        alert.messageText = "Applications courantes"
        alert.informativeText = "Choisissez celle a laquelle associer un mode."
        alert.addButton(withTitle: "Ajouter")
        alert.addButton(withTitle: "Annuler")
        alert.window.appearance = NSAppearance(named: .darkAqua)

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 26))
        for e in entries { popup.addItem(withTitle: "\(e.label)   (\(e.process))") }
        alert.accessoryView = popup

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let e = entries[max(0, popup.indexOfSelectedItem)]
        addRule(e.process, e.suggested)
    }

    private func addRule(_ process: String, _ modeName: String) {
        if settings.appRules.contains(where: { $0.processName == process }) {
            list.reload()
            return
        }
        let r = AppRule()
        r.processName = process
        r.profileName = modeName
        settings.appRules.append(r)
        list.reload()
        commit()
    }

    public override func sync() {
        loading = true
        defer { loading = false }

        enabled.setCheckedSilent(settings.appRulesEnabled)
        fullscreen.selectedIndex = settings.onFullscreen.rawValue
        battery.setCheckedSilent(settings.disableOnBattery)
        list.isEnabledList = settings.appRulesEnabled
        list.reload()

        let proc = watcher?.currentProcess ?? ""
        let me = (Bundle.main.bundleIdentifier ?? "").lowercased()
        current.text = (proc.isEmpty || proc == me)
            ? "Application au premier plan : (cette fenetre)"
            : "Application au premier plan : " + (watcher?.currentName ?? proc) + "   (" + proc + ")"
    }
}

/// Liste des regles, avec choix du mode par clic.
public final class RuleList: NSView {

    private let settings: Settings
    private var selected = -1
    private var hover = -1
    private var scroll: CGFloat = 0
    private static let rowH: CGFloat = 30

    public var onChange: (() -> Void)?

    public var isEnabledList = true { didSet { needsDisplay = true } }

    public init(_ s: Settings) {
        self.settings = s
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 190))
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public var selectedIndex: Int { selected }

    public func reload() { needsDisplay = true }

    // ------------------------------------------------------------------ souris

    private var tracking: NSTrackingArea?

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    public override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((p.y + scroll) / RuleList.rowH)
        if i != hover { hover = i; needsDisplay = true }
    }

    public override func mouseExited(with event: NSEvent) { hover = -1; needsDisplay = true }

    public override func scrollWheel(with event: NSEvent) {
        let maxScroll = max(0, CGFloat(settings.appRules.count) * RuleList.rowH - bounds.height)
        scroll = min(max(0, scroll - event.scrollingDeltaY), maxScroll)
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabledList else { return }
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((p.y + scroll) / RuleList.rowH)
        guard i >= 0, i < settings.appRules.count else { return }
        selected = i
        window?.makeFirstResponder(self)

        // Le clic dans la moitie droite fait tourner le mode applique.
        if p.x > bounds.width / 2 {
            cycleMode(at: i)
        }
        needsDisplay = true
    }

    private func cycleMode(at index: Int) {
        let names = modeNames()
        let r = settings.appRules[index]
        let currentIndex = names.firstIndex(of: r.profileName) ?? -1
        let next = (currentIndex + 1) % (names.count + 1)
        if next == names.count {
            r.disable = true
        } else {
            r.disable = false
            r.profileName = names[next]
        }
        onChange?()
    }

    private func modeNames() -> [String] {
        Profile.builtInModes().map { $0.name } + settings.customProfiles.map { $0.name }
    }

    // ------------------------------------------------------------------ clavier
    //
    // Cette liste ne s'atteignait qu'a la souris : ni tabulation, ni clavier, ni
    // annonce. Une regle par application se supprime et se modifie depuis ici -
    // la rendre inaccessible revenait a reserver la fonction entiere a qui peut
    // viser une ligne de trente points.

    public override var acceptsFirstResponder: Bool { isEnabledList }
    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    public override func keyDown(with event: NSEvent) {
        let count = settings.appRules.count
        guard count > 0 else { super.keyDown(with: event); return }

        switch event.keyCode {
        case 126: selected = max(0, selected - 1)
        case 125: selected = min(count - 1, selected + 1)
        case 115: selected = 0
        case 119: selected = count - 1
        case 49, 36:
            if selected >= 0 { cycleMode(at: selected) }
        default: super.keyDown(with: event); return
        }

        // La ligne choisie doit rester visible : sans cela, la selection sortirait
        // du cadre des la quatrieme regle et le clavier piloterait a l'aveugle.
        let top = CGFloat(selected) * RuleList.rowH
        let bottom = top + RuleList.rowH
        if top < scroll { scroll = top }
        else if bottom > scroll + bounds.height { scroll = bottom - bounds.height }
        scroll = max(0, scroll)

        needsDisplay = true
    }

    // ------------------------------------------------------------------ dessin

    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, radius: 6, isEnabledList ? Theme.sunken : Theme.bg)

        if settings.appRules.isEmpty {
            Draw.text("Aucune regle. Ajoutez-en une ci-dessous.", in: bounds,
                      font: Theme.body, color: Theme.faint, align: .center)
        }

        for (i, r) in settings.appRules.enumerated() {
            let y = CGFloat(i) * RuleList.rowH - scroll
            if y + RuleList.rowH < 0 || y > bounds.height { continue }

            let selectedRow = i == selected
            let hovered = i == hover

            if selectedRow || hovered {
                Draw.fill(NSRect(x: 0, y: y, width: bounds.width, height: RuleList.rowH),
                          selectedRow ? Theme.cardHover : Theme.card)
            }

            let fg = isEnabledList ? Theme.fg : Theme.faint
            Draw.text(r.processName,
                      in: NSRect(x: 10, y: y, width: bounds.width / 2 - 14, height: RuleList.rowH),
                      font: Theme.body, color: fg)

            let right = r.disable ? "aucun effet" : r.profileName
            Draw.text(right,
                      in: NSRect(x: bounds.width / 2, y: y, width: bounds.width / 2 - 12, height: RuleList.rowH),
                      font: Theme.body, color: r.disable ? Theme.faint : Theme.accent, align: .right)

            Draw.fill(NSRect(x: 0, y: y + RuleList.rowH - 1, width: bounds.width, height: 1), Theme.border)
        }

        // Anneau de focus : la meme convention que la liste des raccourcis, pour
        // qu'un parcours au clavier montre toujours ou il en est.
        Draw.stroke(bounds, radius: 6, window?.firstResponder === self ? Theme.focus : Theme.border)
    }

    // --- accessibilite ---

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .list }
    public override func accessibilityLabel() -> String? { "Regles par application" }
    public override func accessibilityValue() -> Any? {
        guard selected >= 0, selected < settings.appRules.count else { return "" }
        let r = settings.appRules[selected]
        return r.processName + " : " + (r.disable ? "aucun effet" : r.profileName)
    }
    public override func isAccessibilityEnabled() -> Bool { isEnabledList }
}
