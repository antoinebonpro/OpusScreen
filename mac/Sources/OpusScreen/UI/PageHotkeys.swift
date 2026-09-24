import Foundation
import AppKit

/// Reconfiguration des raccourcis globaux.
public final class PageHotkeys: SettingsPage {

    private var enabled: ToggleRow!
    private var wheel: ToggleRow!
    private var list: HotkeyList!
    private var panicNote: LabelView!
    private var panicButton: DarkButton!

    /// Appelee quand les raccourcis doivent etre reenregistres aupres du systeme.
    public var rebind: (() -> Void)?

    public override var pageTitle: String { "Raccourcis" }
    public override var pageSubtitle: String { "Piloter sans ouvrir la fenetre" }

    public override init(_ s: Settings, _ d: DisplayController, _ push: @escaping () -> Void) {
        super.init(s, d, push)

        section("General")

        enabled = ToggleRow("Activer les raccourcis globaux", nil)
        enabled.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.hotkeysEnabled = self.enabled.isChecked
            self.list.isEnabledList = self.enabled.isChecked
            self.rebind?()
            self.commit()
        }
        add(enabled, Theme.spaceSm)

        wheel = ToggleRow("Molette sur l'icone de la barre des menus",
                          "Faire rouler la molette au-dessus de l'icone change la luminosite.")
        wheel.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.trayWheelControl = self.wheel.isChecked
            self.commit()
        }
        add(wheel, Theme.spaceSm)

        section("Attributions")

        list = HotkeyList(settings)
        list.frame.size.height = Theme.px(340)
        list.onChange = { [weak self] in
            self?.rebind?()
            self?.commit()
        }
        add(list, Theme.spaceSm)

        note("Cliquez sur une ligne puis pressez la combinaison voulue. Echap annule, "
           + "Suppr desactive le raccourci. Une combinaison sans modificateur est refusee : "
           + "elle capterait la touche dans toutes les applications.")

        let reset = DarkButton("Retablir les raccourcis par defaut") { [weak self] in
            guard let self = self else { return }
            self.settings.hotkeys = Settings.defaultHotkeys()
            self.list.reload()
            self.rebind?()
            self.commit()
        }
        reset.frame.size.height = Theme.minTarget
        add(reset, Theme.spaceSm)

        section("Le raccourci de secours")

        panicNote = note("")

        panicButton = DarkButton("Accorder l'autorisation d'accessibilite") { [weak self] in
            self?.requestAccessibility()
        }
        panicButton.frame.size.height = Theme.minTarget
        add(panicButton, Theme.spaceSm)

        note("⌃⌥⇧R rend l'ecran normal en toutes circonstances, et ce raccourci-la n'est "
           + "pas reconfigurable : c'est le seul dont on doive pouvoir se souvenir quand on "
           + "ne voit plus rien.")

        note("Sans l'autorisation d'accessibilite, il passe par la boucle d'evenements "
           + "ordinaire - ce qui suffit dans tous les cas sauf un : une interface totalement "
           + "bloquee. Avec elle, un fil autonome l'ecoute en permanence et repond meme dans "
           + "ce cas. L'application ne lit aucune autre frappe : elle attend cette "
           + "combinaison et laisse tout le reste passer sans le regarder.")
    }

    required init?(coder: NSCoder) { fatalError() }

    private func requestAccessibility() {
        if !PanicKey.shared.requestAccessibility() {
            // macOS ne montre la demande qu'une fois : ensuite, seule la case a
            // cocher des Reglages Systeme fait foi.
            PanicKey.openAccessibilitySettings()
        }
        syncAndLayout()
    }

    public override func sync() {
        loading = true
        defer { loading = false }

        enabled.setCheckedSilent(settings.hotkeysEnabled)
        wheel.setCheckedSilent(settings.trayWheelControl)
        list.isEnabledList = settings.hotkeysEnabled
        list.reload()

        let independent = PanicKey.shared.independentThreadActive
        panicButton.isEnabled = !independent
        panicButton.title = independent
            ? "Autorisation accordee - le fil de secours est actif"
            : "Accorder l'autorisation d'accessibilite"
        panicNote.text = independent
            ? "Le secours est servi par un fil autonome : il repond meme si l'interface est figee."
            : "Le secours passe pour l'instant par la boucle d'evenements ordinaire."
    }
}

/// Liste des raccourcis, capturant la prochaine combinaison pressee.
public final class HotkeyList: NSView {

    private let settings: Settings
    private var selected = -1
    private var hover = -1
    private var capturing = -1
    private var scroll: CGFloat = 0
    private static let rowH: CGFloat = 32

    public var onChange: (() -> Void)?
    public var isEnabledList = true { didSet { needsDisplay = true } }

    public init(_ s: Settings) {
        self.settings = s
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 340))
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

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
        let i = Int((p.y + scroll) / HotkeyList.rowH)
        if i != hover { hover = i; needsDisplay = true }
    }

    public override func mouseExited(with event: NSEvent) { hover = -1; needsDisplay = true }

    public override func scrollWheel(with event: NSEvent) {
        let maxScroll = max(0, CGFloat(settings.hotkeys.count) * HotkeyList.rowH - bounds.height)
        scroll = min(max(0, scroll - event.scrollingDeltaY), maxScroll)
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabledList else { return }
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((p.y + scroll) / HotkeyList.rowH)
        guard i >= 0, i < settings.hotkeys.count else { return }
        selected = i
        capturing = i
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // ------------------------------------------------------------------ capture

    public override var acceptsFirstResponder: Bool { isEnabledList }
    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }

    public override func resignFirstResponder() -> Bool {
        capturing = -1
        needsDisplay = true
        return true
    }

    /// Pendant la capture, toutes les touches nous reviennent : sinon la fenetre
    /// interpreterait ⌘W ou Tab avant que l'on ait pu les enregistrer.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard capturing >= 0 else { return false }
        keyDown(with: event)
        return true
    }

    public override func keyDown(with event: NSEvent) {
        guard capturing >= 0, capturing < settings.hotkeys.count else {
            navigate(event)
            return
        }

        if event.keyCode == 53 {   // echappement
            capturing = -1
            needsDisplay = true
            return
        }

        if event.keyCode == 117 || event.keyCode == 51 {   // suppression
            settings.hotkeys[capturing].enabled = false
            capturing = -1
            needsDisplay = true
            onChange?()
            return
        }

        let mods = KeyCodes.windowsModifiers(event.modifierFlags)
        if mods == 0 {
            // Sans modificateur, le raccourci capterait la touche dans toutes les
            // applications : on refuse.
            return
        }

        guard let vk = KeyCodes.windowsVK(forMacKeyCode: UInt32(event.keyCode)) else { return }

        let h = settings.hotkeys[capturing]
        h.modifiers = mods
        h.key = vk
        h.enabled = true

        capturing = -1
        needsDisplay = true
        onChange?()
    }

    private func navigate(_ event: NSEvent) {
        let count = settings.hotkeys.count
        guard count > 0 else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 126: selected = max(0, selected - 1)
        case 125: selected = min(count - 1, selected + 1)
        case 49, 36: if selected >= 0 { capturing = selected }
        default: super.keyDown(with: event); return
        }

        let top = CGFloat(selected) * HotkeyList.rowH
        let bottom = top + HotkeyList.rowH
        if top < scroll { scroll = top }
        else if bottom > scroll + bounds.height { scroll = bottom - bounds.height }
        scroll = max(0, scroll)

        needsDisplay = true
    }

    // ------------------------------------------------------------------ dessin

    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, radius: 6, isEnabledList ? Theme.sunken : Theme.bg)

        for (i, h) in settings.hotkeys.enumerated() {
            let y = CGFloat(i) * HotkeyList.rowH - scroll
            if y + HotkeyList.rowH < 0 || y > bounds.height { continue }

            let isSelected = i == selected
            let hovered = i == hover
            let cap = i == capturing

            if cap {
                Draw.fill(NSRect(x: 0, y: y, width: bounds.width, height: HotkeyList.rowH), Theme.accentDim)
            } else if isSelected || hovered {
                Draw.fill(NSRect(x: 0, y: y, width: bounds.width, height: HotkeyList.rowH),
                          isSelected ? Theme.cardHover : Theme.card)
            }

            let fg = isEnabledList ? Theme.fg : Theme.faint
            Draw.text(Settings.actionLabel(h.action),
                      in: NSRect(x: 10, y: y, width: bounds.width / 2, height: HotkeyList.rowH),
                      font: Theme.body, color: fg)

            let right = cap ? "pressez une combinaison..." : (h.enabled ? h.describe() : "desactive")
            let rc = cap ? NSColor.white : (h.enabled ? Theme.accent : Theme.faint)
            Draw.text(right,
                      in: NSRect(x: bounds.width / 2, y: y, width: bounds.width / 2 - 12, height: HotkeyList.rowH),
                      font: cap ? Theme.bodyBold : Theme.body, color: rc, align: .right)

            Draw.fill(NSRect(x: 0, y: y + HotkeyList.rowH - 1, width: bounds.width, height: 1), Theme.border)
        }

        Draw.stroke(bounds, radius: 6, window?.firstResponder === self ? Theme.focus : Theme.border)
    }

    // --- accessibilite ---
    //
    // Annonce l'action ET sa combinaison courante. Le role de liste seul ferait
    // entendre « raccourcis globaux » quinze fois de suite, sans jamais dire lequel.

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .list }
    public override func accessibilityLabel() -> String? { "Raccourcis globaux" }
    public override func accessibilityValue() -> Any? {
        guard selected >= 0, selected < settings.hotkeys.count else { return "" }
        let h = settings.hotkeys[selected]
        return Settings.actionLabel(h.action) + " : "
             + ((h.enabled && h.key != 0) ? h.describe() : "desactive")
    }
    public override func isAccessibilityEnabled() -> Bool { isEnabledList }
}
