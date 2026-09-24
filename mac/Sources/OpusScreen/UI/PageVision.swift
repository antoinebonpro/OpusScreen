import Foundation
import AppKit

/// Basse vision, reperage du pointeur et confort de lecture.
///
/// Le daltonisme a son propre onglet : c'est le besoin le plus repandu, et le
/// seul qui demande de regler puis de verifier. Il reste ici ce qui aide a VOIR -
/// agrandir, retrouver le pointeur, lire plus longtemps - et les raccourcis vers
/// l'accessibilite de macOS.
public final class PageVision: SettingsPage {

    private var magOn: ToggleRow!
    private var zoom: SliderRow!
    private var magNote: LabelView!
    private var beaconOn: ToggleRow!
    private var beaconSize: SliderRow!
    private var beaconOpacity: SliderRow!
    private var beaconColor: DarkButton!

    /// Fourni par l'application : la page decide, l'application execute.
    public var aidsChanged: (() -> Void)?

    public override var pageTitle: String { "Vision" }
    public override var pageSubtitle: String { "Basse vision, pointeur et lecture" }

    /// Teintes douces appliquees par la BALANCE DES CANAUX, et non par le voile.
    ///
    /// Le voile ne sert que sous 35 % de luminosite : une teinte posee par lui
    /// disparaitrait des que l'ecran remonte a un niveau de lecture normal. La
    /// balance, elle, agit a n'importe quelle luminosite - c'est le seul etage qui
    /// rende ces teintes utilisables pour lire.
    private struct Tint {
        let name: String
        let r: Double, g: Double, b: Double
    }

    private static let readingTints: [Tint] = [
        Tint(name: "Aucune", r: 100, g: 100, b: 100),
        Tint(name: "Bleue", r: 88, g: 94, b: 100),
        Tint(name: "Verte", r: 88, g: 100, b: 92),
        Tint(name: "Ambre", r: 100, g: 96, b: 78),
        Tint(name: "Saumon", r: 100, g: 90, b: 92),
        Tint(name: "Grise", r: 92, g: 92, b: 92),
    ]

    public override init(_ s: Settings, _ d: DisplayController, _ push: @escaping () -> Void) {
        super.init(s, d, push)
        buildLowVision()
        buildReadingTints()
        buildSystemLinks()
    }

    required init?(coder: NSCoder) { fatalError() }

    // ------------------------------------------------------------------ basse vision

    private func buildLowVision() {
        section("Basse vision")

        magOn = ToggleRow("Loupe plein ecran",
                          "Agrandit tout l'affichage et suit le pointeur. Se cumule avec les filtres de couleur.")
        magOn.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.magnifierEnabled = self.magOn.isChecked
            self.aids()
            self.updateMagNote()
            self.updateStates()
            self.commit()
        }
        add(magOn, Theme.spaceSm)

        zoom = SliderRow("Agrandissement", ScreenMagnifier.minZoom, ScreenMagnifier.maxZoom, "x")
        zoom.setFormat("0.0")
        zoom.mark(at: 2)
        zoom.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.magnifierZoom = self.zoom.value
            self.aids()
        }
        zoom.onCommit = { [weak self] in self?.commit() }
        add(zoom, Theme.spaceSm)

        magNote = UiKit.caption("")
        add(magNote, Theme.spaceXs)

        note("La loupe partage sa passe de calcul avec les filtres de couleur : "
           + "l'agrandissement et la correction du daltonisme se cumulent. Ni la loupe de "
           + "macOS ni ses filtres de couleur ne savent le faire - la premiere ignore les "
           + "reglages de couleur, les seconds ignorent la loupe.")

        beaconOn = ToggleRow("Anneau autour du pointeur",
                             "Un cercle de couleur franche entoure le curseur, sans rien masquer au centre.")
        beaconOn.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.beaconEnabled = self.beaconOn.isChecked
            self.aids()
            self.updateStates()
            self.commit()
        }
        add(beaconOn, Theme.spaceSm)

        beaconSize = SliderRow("Taille de l'anneau", Double(CursorBeacon.minSize),
                               Double(CursorBeacon.maxSize), "pt")
        beaconSize.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.beaconSize = Int(self.beaconSize.value)
            self.aids()
        }
        beaconSize.onCommit = { [weak self] in self?.commit() }
        add(beaconSize, Theme.spaceSm)

        beaconOpacity = SliderRow("Opacite de l'anneau", 10, 100, "%")
        beaconOpacity.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.beaconOpacity = Int(self.beaconOpacity.value)
            self.aids()
        }
        beaconOpacity.onCommit = { [weak self] in self?.commit() }
        add(beaconOpacity, Theme.spaceSm)

        beaconColor = DarkButton("Couleur de l'anneau...") { [weak self] in self?.pickBeaconColor() }
        beaconColor.frame.size.height = Theme.minTarget
        add(beaconColor, Theme.spaceSm)

        note("Perdre le pointeur de vue est le premier obstacle rapporte en basse vision, "
           + "et un curseur simplement agrandi reste de la meme couleur que ce qu'il survole. "
           + "L'anneau, lui, se detache de n'importe quel fond. Il ne recoit aucun clic et "
           + "n'apparait ni dans les captures d'ecran ni dans les partages.")
    }

    private func pickBeaconColor() {
        let panel = NSColorPanel.shared
        panel.color = settings.beaconColor.nsColor
        panel.setTarget(self)
        panel.setAction(#selector(beaconColorChanged(_:)))
        panel.isContinuous = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func beaconColorChanged(_ sender: NSColorPanel) {
        settings.beaconColor = RGB(sender.color)
        updateBeaconButton()
        aids()
        commitNoSave()
    }

    private func updateBeaconButton() {
        let c = settings.beaconColor
        beaconColor.fillColor = c.nsColor
        beaconColor.textColor = c.luminance > 0.55 ? .black : .white
        beaconColor.title = "Couleur de l'anneau : \(c.r),\(c.g),\(c.b)"
    }

    private func updateMagNote() {
        if !ScreenMagnifier.available {
            magNote.text = "L'agrandissement n'est pas disponible : " + ScreenFilter.shared.unavailableReason
                         + ". Le bouton ci-dessous ouvre le Zoom d'accessibilite de macOS a la place."
        } else if settings.magnifierEnabled {
            magNote.text = "La loupe est active. ⌃⌥Z l'arrete, ⌃⌥⇧R aussi, en meme temps que tout le reste."
        } else {
            magNote.text = "⌃⌥Z active et arrete la loupe sans ouvrir cette fenetre."
        }
    }

    // ------------------------------------------------------------------ teintes de lecture

    private func buildReadingTints() {
        section("Teintes de lecture")

        let strip = TintStrip()
        strip.frame.size.height = Theme.px(56)
        for t in PageVision.readingTints { strip.addTint(t.name, t.r, t.g, t.b) }
        strip.onPick = { [weak self] index in
            guard let self = self, index < PageVision.readingTints.count else { return }
            let t = PageVision.readingTints[index]
            self.settings.current.redGain = t.r
            self.settings.current.greenGain = t.g
            self.settings.current.blueGain = t.b
            self.commit()
        }
        add(strip, Theme.spaceSm)

        note("Une legere teinte posee sur toute la page aide certaines personnes a lire "
           + "plus longtemps sans fatigue - dyslexie, migraine visuelle, sensibilite au "
           + "contraste. La teinte efficace n'est pas la meme d'une personne a l'autre et "
           + "ne se devine pas : elle se choisit a l'essai, sur un texte reel. "
           + "Le reglage fin reste dans la page Couleur.")
    }

    // ------------------------------------------------------------------ macOS

    private func buildSystemLinks() {
        section("Accessibilite de macOS")

        addLink("Zoom d'accessibilite...",
                "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Zoom")
        addLink("Pointeur : taille, contour et couleur...",
                "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Pointer")
        addLink("Affichage : contraste, transparence, taille du texte...",
                "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display")
        addLink("VoiceOver...",
                "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_VoiceOver")

        note("OpusScreen agit sur la lumiere et la couleur ; la taille des elements, le "
           + "curseur et le lecteur d'ecran restent du ressort de macOS, qui les applique a "
           + "toutes les applications a la fois. Les reproduire ici les aurait limites a "
           + "cette seule fenetre.")
    }

    private func addLink(_ label: String, _ uri: String) {
        let b = DarkButton(label) {
            if let url = URL(string: uri) { NSWorkspace.shared.open(url) }
        }
        b.frame.size.height = Theme.minTarget
        add(b, Theme.spaceXs)
    }

    // ------------------------------------------------------------------ etat

    private func aids() {
        guard !loading else { return }
        aidsChanged?()
    }

    private func updateStates() {
        zoom.isEnabled = settings.magnifierEnabled
        beaconSize.isEnabled = settings.beaconEnabled
        beaconOpacity.isEnabled = settings.beaconEnabled
        beaconColor.isEnabled = settings.beaconEnabled
    }

    public override func sync() {
        loading = true
        defer { loading = false }

        magOn.setCheckedSilent(settings.magnifierEnabled)
        zoom.setValueSilent(settings.magnifierZoom)
        beaconOn.setCheckedSilent(settings.beaconEnabled)
        beaconSize.setValueSilent(Double(settings.beaconSize))
        beaconOpacity.setValueSilent(Double(settings.beaconOpacity))

        updateBeaconButton()
        updateMagNote()
        updateStates()
    }
}
