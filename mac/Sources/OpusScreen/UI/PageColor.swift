import Foundation
import AppKit

/// Reglages fins de la couleur : balance des canaux, forme de la courbe, filtres
/// d'accessibilite, teinte du voile.
///
/// Les trois premiers passent par la table de couleurs. Les filtres, eux, exigent
/// la matrice : une table ne peut pas calculer un rouge qui depend du vert.
public final class PageColor: SettingsPage {

    private var red: SliderRow!
    private var green: SliderRow!
    private var blue: SliderRow!
    private var gamma: SliderRow!
    private var filter: ComboRow!
    private var filterNote: LabelView!
    private var tintButton: DarkButton!
    private var preview: ColorPreview!

    public override var pageTitle: String { "Couleur" }
    public override var pageSubtitle: String { "Balance des canaux, courbe et filtres" }

    private static let filters: [ColorFilter] = [
        .none, .grayscale, .invert, .invertKeepHue, .sepia,
        .protanopia, .deuteranopia, .tritanopia,
    ]

    public override init(_ s: Settings, _ d: DisplayController, _ push: @escaping () -> Void) {
        super.init(s, d, push)

        section("Apercu")

        preview = ColorPreview(s)
        preview.frame.size.height = Theme.px(58)
        add(preview, Theme.spaceSm)

        section("Balance des canaux")

        red = makeGain("Rouge", NSColor(srgbRed: 226 / 255, green: 106 / 255, blue: 106 / 255, alpha: 1))
        red.onChange = { [weak self] in
            guard let self = self else { return }
            self.settings.current.redGain = self.red.value; self.live()
        }
        red.onCommit = { [weak self] in self?.commit() }
        add(red, Theme.spaceSm)

        green = makeGain("Vert", NSColor(srgbRed: 112 / 255, green: 200 / 255, blue: 130 / 255, alpha: 1))
        green.onChange = { [weak self] in
            guard let self = self else { return }
            self.settings.current.greenGain = self.green.value; self.live()
        }
        green.onCommit = { [weak self] in self?.commit() }
        add(green, Theme.spaceSm)

        blue = makeGain("Bleu", NSColor(srgbRed: 104 / 255, green: 154 / 255, blue: 246 / 255, alpha: 1))
        blue.onChange = { [weak self] in
            guard let self = self else { return }
            self.settings.current.blueGain = self.blue.value; self.live()
        }
        blue.onCommit = { [weak self] in self?.commit() }
        add(blue, Theme.spaceSm)

        let flat = DarkButton("Remettre la balance a plat") { [weak self] in
            guard let self = self else { return }
            self.settings.current.redGain = 100
            self.settings.current.greenGain = 100
            self.settings.current.blueGain = 100
            self.syncAndLayout()
            self.commit()
        }
        flat.frame.size.height = Theme.minTarget
        add(flat, Theme.spaceSm)

        note("Sert a corriger une dominante de dalle, ou a pousser la reduction du bleu "
           + "plus loin que ne le permet la seule temperature.")

        section("Courbe")

        gamma = SliderRow("Gamma", 50, 200, "%")
        gamma.mark(at: 100)
        gamma.onChange = { [weak self] in
            guard let self = self else { return }
            self.settings.current.gammaCurve = self.gamma.value
            self.updateGammaHint()
            self.live()
        }
        gamma.onCommit = { [weak self] in self?.commit() }
        add(gamma, Theme.spaceSm)

        note("Au-dessus de 100 %, les tons sombres remontent sans toucher au blanc : "
           + "utile pour distinguer les details d'une image sombre.")

        section("Filtres")

        filter = ComboRow("Filtre de couleur",
                          PageColor.filters.map { Profile.filterName($0).capitalizedFirst })
        filter.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.current.filter = PageColor.filters[max(0, self.filter.selectedIndex)]
            self.updateFilterNote()
            self.live()
            self.commit()
            self.syncAndLayout()
        }
        add(filter, Theme.spaceSm)

        filterNote = note("")

        section("Teinte du voile")

        tintButton = DarkButton("Choisir la couleur du voile...") { [weak self] in
            self?.pickTint()
        }
        tintButton.frame.size.height = Theme.minTarget
        add(tintButton, Theme.spaceSm)

        note("Le voile n'entre en jeu que sous 35 % de luminosite. Le noir est le choix "
           + "neutre ; une teinte ambre pousse plus loin la reduction du bleu le soir. "
           + "C'est le « fade-out color » de PangoBright.")
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeGain(_ label: String, _ accent: NSColor) -> SliderRow {
        let r = SliderRow(label, 0, 150, "%")
        r.mark(at: 100)
        r.setAccent(accent)
        return r
    }

    private func live() {
        preview.needsDisplay = true
        commitNoSave()
    }

    private func updateGammaHint() {
        gamma.hint = settings.current.gammaCurve > 100 ? "ombres relevees"
            : (settings.current.gammaCurve < 100 ? "ombres ecrasees" : "reponse standard")
    }

    private func updateFilterNote() {
        switch settings.current.filter {
        case .none:
            filterNote.text = "Aucun melange de canaux : la matrice de couleur reste inactive."
        case .grayscale:
            filterNote.text = "Conversion en luminance Rec. 709. Pratique pour juger d'un contraste "
                            + "sans se laisser influencer par les couleurs."
        case .invert:
            filterNote.text = "Inverse toutes les couleurs. C'est le « mode programmation » d'Iris : "
                            + "il rend sombres les pages web claires, mais transforme aussi les "
                            + "photos en negatifs."
        case .invertKeepHue:
            filterNote.text = "Inverse le clair et le sombre en gardant les teintes ou elles sont : "
                            + "les documents passent au sombre sans que les photos virent au negatif."
        case .sepia:
            filterNote.text = "Teinte chaude et douce pour la lecture prolongee."
        default:
            filterNote.text = "Assistance daltonisme, reglee sur « "
                            + Vision.severityWord(settings.current.visionSeverity)
                            + " ». Les couleurs habituellement confondues sont ecartees l'une de "
                            + "l'autre ; les gris restent neutres. La gravite, l'intensite et le "
                            + "comparateur de couleurs sont dans la page Daltonisme."
        }
    }

    private func pickTint() {
        let panel = NSColorPanel.shared
        panel.color = settings.current.tint.nsColor
        panel.setTarget(self)
        panel.setAction(#selector(tintChanged(_:)))
        panel.isContinuous = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func tintChanged(_ sender: NSColorPanel) {
        settings.current.tint = RGB(sender.color)
        updateTintButton()
        commitNoSave()
    }

    private func updateTintButton() {
        let c = settings.current.tint
        tintButton.fillColor = (c == .black) ? Theme.sunken : c.nsColor
        tintButton.textColor = (c != .black && c.luminance > 0.55) ? .black : Theme.fg
        tintButton.title = (c == .black)
            ? "Noir (neutre) - cliquer pour changer"
            : "Teinte \(c.r),\(c.g),\(c.b) - cliquer pour changer"
    }

    public override func sync() {
        loading = true
        defer { loading = false }

        red.setValueSilent(settings.current.redGain)
        green.setValueSilent(settings.current.greenGain)
        blue.setValueSilent(settings.current.blueGain)
        gamma.setValueSilent(settings.current.gammaCurve)

        let idx = PageColor.filters.firstIndex(of: settings.current.filter) ?? 0
        filter.selectedIndex = idx
        filter.isEnabled = settings.useColorMatrix && ColorMatrixEffect.available

        updateGammaHint()
        updateFilterNote()
        updateTintButton()

        if !ColorMatrixEffect.available {
            filterNote.text = "La matrice de couleur n'est pas disponible : "
                            + ColorMatrixEffect.unavailableReason
                            + ". Les filtres qui melangent les canaux sont inactifs - voir la "
                            + "page Decouvrir pour accorder l'autorisation."
        } else if !settings.useColorMatrix {
            filterNote.text = "L'etage « matrice de couleur » est desactive dans l'onglet Avance."
        }

        preview.needsDisplay = true
    }
}

/// Bande d'apercu : degrade de gris et pastilles de couleur, telles qu'elles
/// sortiront apres la table de couleurs et la matrice. Permet de juger un reglage
/// sans avoir a l'appliquer a tout l'affichage.
public final class ColorPreview: NSView {

    private let settings: Settings

    public init(_ s: Settings) {
        self.settings = s
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 58))
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, Theme.card)

        let p = settings.current
        let plan = GammaEngine.plan(p.brightness,
                                    allowOverlay: settings.useOverlay,
                                    allowHardware: settings.useHardwareBacklight)
        let ramp = GammaEngine.buildRamp(plan, p)

        let steps = 32
        let w = max(1, bounds.width / CGFloat(steps))

        // degrade de gris passe dans la table
        for i in 0..<steps {
            let src = i * 255 / (steps - 1)
            let c = through(ramp, src, src, src)
            Draw.fill(NSRect(x: CGFloat(i) * w, y: 0, width: w + 1, height: 30), c.nsColor)
        }

        // pastilles de couleur de reference
        let refs = [RGB(220, 60, 60), RGB(230, 150, 40), RGB(220, 210, 70),
                    RGB(70, 190, 90), RGB(60, 140, 230), RGB(150, 90, 210), RGB(240, 240, 240)]
        let cw = max(1, bounds.width / CGFloat(refs.count))
        for (i, ref) in refs.enumerated() {
            let c = through(ramp, ref.r, ref.g, ref.b)
            Draw.fill(NSRect(x: CGFloat(i) * cw, y: 32, width: cw + 1, height: 24), c.nsColor)
        }

        Draw.stroke(bounds, Theme.border)
    }

    /// Passe une couleur dans la table puis dans la matrice, pour l'apercu.
    ///
    /// La matrice est celle du moteur, pas une reecriture : une version recopiee a
    /// cote avait fini par diverger, et l'apercu ignorait purement et simplement
    /// les filtres pour daltoniens - ceux que l'on a justement le plus besoin de
    /// comparer avant de les appliquer.
    private func through(_ ramp: Native.RampTable, _ r: Int, _ g: Int, _ b: Int) -> RGB {
        var rr = Double(ramp.red[clamp255(r)]) / 65535.0
        var gv = Double(ramp.green[clamp255(g)]) / 65535.0
        var bv = Double(ramp.blue[clamp255(b)]) / 65535.0

        if settings.useColorMatrix {
            ColorMatrixEffect.transform(settings.current.buildMatrix(), &rr, &gv, &bv)
        }
        return RGB(Int((rr * 255).rounded()), Int((gv * 255).rounded()), Int((bv * 255).rounded()))
    }

    private func clamp255(_ v: Int) -> Int { v < 0 ? 0 : (v > 255 ? 255 : v) }

    // Purement visuel : rien a y faire au clavier, mais VoiceOver doit pouvoir
    // l'annoncer pour ce qu'il est plutot que de buter sur un rectangle sans nom.
    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .image }
    public override func accessibilityLabel() -> String? { "Apercu des couleurs" }
    public override func accessibilityValue() -> Any? {
        "Degrade de gris et pastilles de reference, tels qu'ils sortiront apres les reglages en cours."
    }
}
