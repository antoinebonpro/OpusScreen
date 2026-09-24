import Foundation
import AppKit

/// Page principale : ce que l'on touche tous les jours.
///
/// Les reglages rares vivent sur les autres pages. Regrouper ici les quatre
/// curseurs reellement quotidiens evite que l'ajout de quatre-vingts options ne
/// rende l'application penible pour l'usage courant.
public final class PageDisplay: SettingsPage {

    private var modes: ModeStrip!
    private var brightness: SliderRow!
    private var temperature: SliderRow!
    private var contrast: SliderRow!
    private var saturation: SliderRow!
    private var planLabel: LabelView!
    private var reachLabel: LabelView!

    /// Confirmation a rebours quand on plonge dans le tres sombre. Declenchee au
    /// relachement seulement : la demander pendant le glissement serait intenable.
    private var lastSafe: Double = 100

    public override var pageTitle: String { "Ecran" }
    public override var pageSubtitle: String { "Les reglages du quotidien" }

    public override init(_ s: Settings, _ d: DisplayController, _ push: @escaping () -> Void) {
        super.init(s, d, push)

        section("Modes")

        modes = ModeStrip()
        modes.frame.size.height = Theme.px(96)
        modes.onChoose = { [weak self] profile in self?.onModeChosen(profile) }
        add(modes, Theme.spaceSm)

        // Ce que cette page atteint reellement. Un mode s'applique a tous les
        // ecrans, mais trois reglages pris ailleurs peuvent en soustraire un - et
        // un ecran qui ne change pas sans que rien ne le dise ressemble a une panne.
        reachLabel = UiKit.caption("")
        add(reachLabel, Theme.spaceXs)

        section("Reglages")

        brightness = SliderRow("Luminosite", GammaEngine.minBrightness, GammaEngine.maxBrightness, "%")
        brightness.mark(at: 100, warnAbove: 135)
        brightness.hint = "5 % a 150 %"
        brightness.onChange = { [weak self] in
            guard let self = self else { return }
            self.settings.current.brightness = SafetyGuard.clampBrightness(self.brightness.value)
            self.commitNoSave()
            self.updatePlan()
        }
        brightness.onCommit = { [weak self] in self?.onBrightnessCommitted() }
        add(brightness, Theme.spaceMd)

        temperature = SliderRow("Temperature de couleur", Double(ColorTemp.minKelvin),
                                Double(ColorTemp.maxKelvin), "K")
        temperature.setAccent(Theme.warm)
        temperature.onChange = { [weak self] in
            guard let self = self else { return }
            self.settings.current.kelvin = Int(self.temperature.value.rounded())
            self.updateHints()
            self.commitNoSave()
        }
        temperature.onCommit = { [weak self] in self?.commit() }
        add(temperature, Theme.spaceMd)

        contrast = SliderRow("Contraste", 50, 150, "%")
        contrast.mark(at: 100)
        contrast.onChange = { [weak self] in
            guard let self = self else { return }
            self.settings.current.contrast = self.contrast.value
            self.commitNoSave()
        }
        contrast.onCommit = { [weak self] in self?.commit() }
        add(contrast, Theme.spaceMd)

        saturation = SliderRow("Saturation", 0, 200, "%")
        saturation.mark(at: 100)
        saturation.setAccent(NSColor(srgbRed: 146 / 255, green: 200 / 255, blue: 132 / 255, alpha: 1))
        saturation.onChange = { [weak self] in
            guard let self = self else { return }
            self.settings.current.saturation = self.saturation.value
            self.commitNoSave()
        }
        saturation.onCommit = { [weak self] in self?.commit() }
        add(saturation, Theme.spaceMd)

        planLabel = UiKit.caption("")
        add(planLabel, Theme.spaceMd)

        let save = DarkButton("Enregistrer ces reglages comme mode...") { [weak self] in
            self?.onSaveProfile()
        }
        save.frame.size.height = Theme.minTarget
        add(save, Theme.spaceSm)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func onModeChosen(_ p: Profile) {
        settings.current.copyFrom(p)
        settings.activeModeName = p.name
        sync()
        commit()
    }

    private func onBrightnessCommitted() {
        let now = settings.current.brightness
        if now < SafetyGuard.confirmBelow && lastSafe >= SafetyGuard.confirmBelow && !settings.skipDarkConfirm {
            let dialog = ConfirmDialog(brightness: now, seconds: 10)
            let keep = dialog.run(over: hostWindow)
            if dialog.dontAskAgain { settings.skipDarkConfirm = true }
            if !keep {
                settings.current.brightness = lastSafe
                loading = true
                brightness.setValueSilent(lastSafe)
                loading = false
                commitNoSave()
                settings.save()
                return
            }
        }
        lastSafe = now
        commit()
    }

    private func onSaveProfile() {
        guard let name = PromptDialog.ask("Enregistrer un mode", "Nom du mode :",
                                          "Mon mode \(settings.customProfiles.count + 1)",
                                          window: hostWindow) else { return }

        var p = settings.current.clone()
        p.name = name

        settings.customProfiles.removeAll { $0.name == p.name }
        settings.customProfiles.append(p)
        settings.activeModeName = p.name
        settings.save()
        syncAndLayout()
    }

    private func updatePlan() {
        planLabel.text = display.describeCurrentPlan()
    }

    /// Nomme les ecrans que cette page n'atteint pas, et pourquoi.
    ///
    /// Un ecran regle a part ignorait en silence tout ce qui se decide ici :
    /// choisir un mode ne changeait rien chez lui, et rien ne disait lequel ni
    /// pourquoi. Les modes s'appliquent desormais partout ; les seules exceptions
    /// sont celles que l'on a demandees, et elles se lisent ici.
    private func updateReach() {
        guard display.monitors.count >= 2 else { reachLabel.text = ""; return }
        let apart = settings.screensNotFollowing(display.monitors)
        reachLabel.text = apart.isEmpty
            ? "Ces reglages s'appliquent a tous les ecrans."
            : "Ces reglages n'atteignent pas :  " + apart.joined(separator: "   -   ") + "   (page Ecrans)"
    }

    private func updateHints() {
        // En mode automatique, le curseur n'est pas manoeuvrable : le dire vaut
        // mieux que de laisser croire a une panne.
        temperature.hint = settings.schedule == .manual
            ? ColorTemp.describe(settings.current.kelvin)
            : "pilotee par l'automatisme"
        saturation.hint = settings.current.saturation < 5 ? "niveaux de gris"
            : (settings.current.saturation > 140 ? "couleurs tres marquees" : "")
        contrast.hint = settings.current.contrast > 100 ? "noirs plus profonds"
            : (settings.current.contrast < 100 ? "image plus douce" : "")
    }

    public override func sync() {
        loading = true
        defer { loading = false }

        brightness.setValueSilent(settings.current.brightness)
        temperature.setValueSilent(Double(settings.current.kelvin))
        contrast.setValueSilent(settings.current.contrast)
        saturation.setValueSilent(settings.current.saturation)
        lastSafe = settings.current.brightness

        var all = Profile.builtInModes()
        all.append(contentsOf: settings.customProfiles)
        modes.setModes(all, active: settings.activeModeName)

        temperature.isEnabled = settings.schedule == .manual
        updateHints()
        updatePlan()
        updateReach()
    }
}

/// Bande de pastilles de modes.
///
/// Chaque pastille affiche un apercu reel de la couleur et de la luminosite
/// qu'elle applique : on choisit avec l'oeil plutot qu'en lisant une liste.
public final class ModeStrip: NSView {

    private var modes: [Profile] = []
    private var active = ""
    private var hover = -1
    private var cursor = 0
    private var scroll: CGFloat = 0

    public var onChoose: ((Profile) -> Void)?

    private static let chipW: CGFloat = 88
    private static let chipH: CGFloat = 76
    private static let gap: CGFloat = 8

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 96))
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public func setModes(_ list: [Profile], active: String) {
        modes = list
        self.active = active
        if let i = list.firstIndex(where: { $0.name == active }) { cursor = i }
        needsDisplay = true
    }

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
        let i = indexAt(convert(event.locationInWindow, from: nil))
        if i != hover { hover = i; needsDisplay = true }
    }

    public override func mouseExited(with event: NSEvent) { hover = -1; needsDisplay = true }

    public override func mouseDown(with event: NSEvent) {
        let i = indexAt(convert(event.locationInWindow, from: nil))
        guard i >= 0, i < modes.count else { return }
        cursor = i
        window?.makeFirstResponder(self)
        onChoose?(modes[i])
    }

    public override func scrollWheel(with event: NSEvent) {
        let total = CGFloat(modes.count) * (ModeStrip.chipW + ModeStrip.gap)
        let maxScroll = max(0, total - bounds.width)
        scroll = min(max(0, scroll - event.scrollingDeltaX - event.scrollingDeltaY), maxScroll)
        needsDisplay = true
    }

    private func indexAt(_ p: NSPoint) -> Int {
        guard p.y >= 0, p.y <= ModeStrip.chipH else { return -1 }
        let step = ModeStrip.chipW + ModeStrip.gap
        let i = Int((p.x + scroll) / step)
        let within = (p.x + scroll).truncatingRemainder(dividingBy: step)
        if within > ModeStrip.chipW { return -1 }
        return (i >= 0 && i < modes.count) ? i : -1
    }

    // ------------------------------------------------------------------ clavier

    public override var acceptsFirstResponder: Bool { true }
    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    public override func keyDown(with event: NSEvent) {
        guard !modes.isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 123: cursor = max(0, cursor - 1); ensureVisible()
        case 124: cursor = min(modes.count - 1, cursor + 1); ensureVisible()
        case 115: cursor = 0; ensureVisible()
        case 119: cursor = modes.count - 1; ensureVisible()
        case 49, 36: onChoose?(modes[cursor])
        default: super.keyDown(with: event); return
        }
        needsDisplay = true
    }

    private func ensureVisible() {
        let step = ModeStrip.chipW + ModeStrip.gap
        let left = CGFloat(cursor) * step
        let right = left + ModeStrip.chipW
        if left < scroll { scroll = left }
        else if right > scroll + bounds.width { scroll = right - bounds.width }
        scroll = max(0, scroll)
    }

    // ------------------------------------------------------------------ dessin

    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, Theme.card)

        for (i, p) in modes.enumerated() {
            let x = CGFloat(i) * (ModeStrip.chipW + ModeStrip.gap) - scroll
            if x + ModeStrip.chipW < 0 || x > bounds.width { continue }

            let selected = p.name == active
            let hovered = i == hover
            let focused = window?.firstResponder === self && i == cursor

            let r = NSRect(x: x, y: 0, width: ModeStrip.chipW, height: ModeStrip.chipH)
            Draw.fill(r, radius: 6, selected || hovered ? Theme.cardHover : Theme.sunken)

            // apercu : la couleur reellement produite par ce mode
            let swatch = ModeStrip.swatch(for: p)
            let sw = NSRect(x: x + 26, y: 12, width: 36, height: 22)
            Draw.fill(sw, radius: 3, swatch.nsColor)

            if p.brightness > 100 {
                Draw.stroke(sw, radius: 3, Theme.boost, width: 2)
            }

            Draw.text(p.name, in: NSRect(x: x + 3, y: 38, width: ModeStrip.chipW - 6, height: 16),
                      font: selected ? Theme.bodyBold : Theme.small,
                      color: selected ? Theme.fg : Theme.dim, align: .center)

            Draw.text("\(Int(p.brightness)) % - \(p.kelvin) K",
                      in: NSRect(x: x + 3, y: 54, width: ModeStrip.chipW - 6, height: 14),
                      font: Theme.small, color: Theme.faint, align: .center)

            Draw.stroke(r, radius: 6, selected ? Theme.accent : Theme.border, width: selected ? 2 : 1)
            if focused { Draw.focusRing(r, radius: 6) }
        }

        // indication de defilement quand la bande deborde
        let total = CGFloat(modes.count) * (ModeStrip.chipW + ModeStrip.gap)
        if total > bounds.width {
            Draw.text("Molette ou ← → pour faire defiler",
                      in: NSRect(x: 0, y: ModeStrip.chipH + 2, width: bounds.width, height: 16),
                      font: Theme.small, color: Theme.faint, align: .right)
        }
    }

    /// La couleur que ce mode rend, pour l'apercu de la pastille.
    static func swatch(for p: Profile) -> RGB {
        let mult = ColorTemp.multipliers(p.kelvin)
        let lum = min(1.35, p.brightness / 100.0)
        let base = 58.0 + 150.0 * min(1.0, lum)
        var c = RGB(Int((base * mult[0]).rounded()),
                    Int((base * mult[1]).rounded()),
                    Int((base * mult[2]).rounded()))

        if p.filter == .grayscale || p.saturation < 10 {
            let g = Int((c.luminance * 255).rounded())
            c = RGB(white: g)
        } else if p.filter == .invert {
            c = RGB(255 - c.r, 255 - c.g, 255 - c.b)
        }
        return c
    }

    // --- accessibilite ---

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .list }
    public override func accessibilityLabel() -> String? { "Modes prets a l'emploi" }
    public override func accessibilityValue() -> Any? {
        cursor >= 0 && cursor < modes.count ? modes[cursor].name + " - " + modes[cursor].summary() : ""
    }
    public override func accessibilityPerformPress() -> Bool {
        guard cursor >= 0, cursor < modes.count else { return false }
        onChoose?(modes[cursor])
        return true
    }
}
