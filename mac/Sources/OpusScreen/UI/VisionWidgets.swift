import Foundation
import AppKit

/// Le tableau qui repond a la seule question qui compte : est-ce que je vois
/// maintenant une difference la ou je n'en voyais pas ?
///
/// Chaque ligne montre une paire de couleurs reputee confondue par la deficience
/// choisie, d'abord telle qu'elle est percue aujourd'hui, puis telle qu'elle le
/// serait apres correction. Les deux colonnes passent par la MEME simulation : ce
/// qui est compare, c'est bien ce que verra la personne, pas ce que verrait
/// quelqu'un d'autre.
public final class ConfusionBoard: NSView {

    private let settings: Settings
    private static let rowH: CGFloat = 34
    private static let swatchW: CGFloat = 46
    private static let swatchH: CGFloat = 24

    private var pairs: [Vision.Pair] = []

    /// Emis quand la hauteur a change : la page doit alors se replier.
    public var onHeightChanged: (() -> Void)?

    public init(_ s: Settings) {
        self.settings = s
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 160))
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    /// Recalcule les paires et la hauteur necessaire.
    ///
    /// Le nombre de lignes n'est pas fixe : plus la gravite est faible, moins il
    /// existe de couleurs reellement confondues, et une ligne ou les deux pastilles
    /// tombent sur la meme valeur n'apprend rien. Une hauteur figee laisserait un
    /// grand vide sous le tableau dans ces cas-la.
    public func rebuild() {
        let f = settings.current.filter
        let vision = ColorMatrixEffect.isVisionFilter(f)

        // Sans correction choisie, les paires sont construites a pleine gravite :
        // elles restent alors des couleurs franchement differentes, et la ligne
        // montre bien ce qu'une deficience effacerait.
        pairs = Vision.confusionPairs(vision ? f : .none,
                                      vision ? settings.current.visionSeverity : 100)

        let wanted = 22 + ConfusionBoard.rowH * CGFloat(max(1, pairs.count)) + 10
        if abs(wanted - frame.height) > 0.5 {
            frame.size.height = wanted
            onHeightChanged?()
        }
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, radius: 6, Theme.sunken)

        let f = settings.current.filter
        let vision = ColorMatrixEffect.isVisionFilter(f)

        let sim = ColorMatrixEffect.buildMatrix(100, vision ? f : .none,
                                                settings.current.visionSeverity, 100, .simulation)
        let correction = settings.current.buildMatrix()

        let left: CGFloat = 10
        let colA = max(150, bounds.width / 2 - 90)
        let colB = max(colA + 150, bounds.width - 200)

        Draw.text("Couleurs confondues", in: NSRect(x: left, y: 3, width: colA - left, height: 16),
                  font: Theme.small, color: Theme.dim)
        Draw.text("Aujourd'hui", in: NSRect(x: colA, y: 3, width: colB - colA, height: 16),
                  font: Theme.small, color: Theme.dim)
        Draw.text(vision ? "Avec la correction" : "Sans correction active",
                  in: NSRect(x: colB, y: 3, width: bounds.width - colB - 8, height: 16),
                  font: Theme.small, color: Theme.dim)

        var y: CGFloat = 24

        for p in pairs {
            let beforeA = ColorMatrixEffect.transform(sim, p.a)
            let beforeB = ColorMatrixEffect.transform(sim, p.b)
            let afterA = ColorMatrixEffect.transform(sim, ColorMatrixEffect.transform(correction, p.a))
            let afterB = ColorMatrixEffect.transform(sim, ColorMatrixEffect.transform(correction, p.b))

            Draw.text(p.label, in: NSRect(x: left, y: y + 3, width: colA - left - 8, height: 18),
                      font: Theme.small, color: Theme.fg)

            drawPair(colA, y, beforeA, beforeB)
            drawPair(colB, y, afterA, afterB)

            y += ConfusionBoard.rowH
        }
    }

    private func drawPair(_ x: CGFloat, _ y: CGFloat, _ a: RGB, _ b: RGB) {
        let w = ConfusionBoard.swatchW
        let h = ConfusionBoard.swatchH

        Draw.fill(NSRect(x: x, y: y, width: w, height: h), a.nsColor)
        Draw.fill(NSRect(x: x + w, y: y, width: w, height: h), b.nsColor)
        Draw.stroke(NSRect(x: x, y: y, width: w * 2, height: h), Theme.border)

        // Le trait de separation rappelle qu'il s'agit bien de DEUX couleurs :
        // quand elles sont confondues, rien d'autre ne le montrerait.
        Draw.fill(NSRect(x: x + w - 0.5, y: y + 1, width: 1, height: h - 2), Theme.sunken)

        let de = Vision.deltaE(a, b)
        let distinct = de >= Vision.justNoticeable
        let text = String(format: "%.1f  ", de) + (distinct ? "distinctes" : "identiques")

        Draw.text(text, in: NSRect(x: x + w * 2 + 8, y: y + 3, width: 140, height: 18),
                  font: Theme.small, color: distinct ? Theme.good : Theme.danger)
    }

    // Tableau de lecture, sans action : la tabulation n'a rien a y faire, mais
    // VoiceOver doit pouvoir en lire le verdict.
    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .table }
    public override func accessibilityLabel() -> String? { "Comparateur de couleurs confondues" }

    public override func accessibilityValue() -> Any? {
        let f = settings.current.filter
        let vision = ColorMatrixEffect.isVisionFilter(f)
        let sim = ColorMatrixEffect.buildMatrix(100, vision ? f : .none,
                                                settings.current.visionSeverity, 100, .simulation)
        let correction = settings.current.buildMatrix()

        var lines: [String] = []
        for p in pairs {
            let before = Vision.deltaE(ColorMatrixEffect.transform(sim, p.a),
                                       ColorMatrixEffect.transform(sim, p.b))
            let after = Vision.deltaE(
                ColorMatrixEffect.transform(sim, ColorMatrixEffect.transform(correction, p.a)),
                ColorMatrixEffect.transform(sim, ColorMatrixEffect.transform(correction, p.b)))
            lines.append(String(format: "%@ : aujourd'hui %.1f, avec la correction %.1f",
                                p.label, before, after))
        }
        return lines.joined(separator: ". ")
    }
}

/// Bande de pastilles : chaque teinte est montree telle qu'elle rendra.
public final class TintStrip: NSView {

    private struct Item {
        let name: String
        let r: Double, g: Double, b: Double
    }

    private var items: [Item] = []
    private var hover = -1

    /// Teinte sur laquelle porte le clavier. Distincte du survol : la souris et le
    /// clavier ne designent pas forcement la meme case au meme moment.
    private var cursor = 0

    public var onPick: ((Int) -> Void)?

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 56))
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public func addTint(_ name: String, _ r: Double, _ g: Double, _ b: Double) {
        items.append(Item(name: name, r: r, g: g, b: b))
        needsDisplay = true
    }

    private var cellWidth: CGFloat { items.isEmpty ? bounds.width : bounds.width / CGFloat(items.count) }

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
        let i = cellWidth > 0 ? Int(p.x / cellWidth) : -1
        if i != hover { hover = i; needsDisplay = true }
    }

    public override func mouseExited(with event: NSEvent) { hover = -1; needsDisplay = true }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = cellWidth > 0 ? Int(p.x / cellWidth) : -1
        guard i >= 0, i < items.count else { return }
        cursor = i
        window?.makeFirstResponder(self)
        onPick?(i)
    }

    // Cette bande etait atteignable au Tab et ne repondait ensuite a aucune touche :
    // un cul-de-sac au clavier, dans la page meme qui parle d'accessibilite.
    public override var acceptsFirstResponder: Bool { true }
    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    public override func keyDown(with event: NSEvent) {
        guard !items.isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 123: cursor = max(0, cursor - 1)
        case 124: cursor = min(items.count - 1, cursor + 1)
        case 115: cursor = 0
        case 119: cursor = items.count - 1
        case 49, 36: onPick?(cursor)
        default: super.keyDown(with: event); return
        }
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, Theme.card)

        let w = cellWidth
        for (i, it) in items.enumerated() {
            // La pastille montre la teinte appliquee a un blanc de page : c'est
            // sur du texte noir sur blanc qu'elle sera jugee, pas sur une pastille
            // de couleur pure.
            let c = RGB(Int((255 * it.r / 100).rounded()),
                        Int((255 * it.g / 100).rounded()),
                        Int((255 * it.b / 100).rounded()))

            let cell = NSRect(x: CGFloat(i) * w + 3, y: 2, width: w - 6, height: 32)
            Draw.fill(cell, radius: 4, c.nsColor)

            let marked = i == hover || (window?.firstResponder === self && i == cursor)
            Draw.stroke(cell, radius: 4, marked ? Theme.accent : Theme.border, width: marked ? 2 : 1)

            // Anneau de focus, distinct du survol : il doit rester visible meme
            // quand la souris designe une autre case.
            if window?.firstResponder === self && i == cursor { Draw.focusRing(cell, radius: 4) }

            Draw.text("Aa", in: cell, font: Theme.small,
                      color: NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1), align: .center)
            Draw.text(it.name, in: NSRect(x: CGFloat(i) * w, y: 36, width: w, height: 16),
                      font: Theme.small, color: marked ? Theme.fg : Theme.dim, align: .center)
        }
    }

    // --- accessibilite ---
    //
    // Le lecteur d'ecran doit annoncer la teinte designee, pas « bande de teintes ».
    // Sans valeur, l'utilisateur entendrait le meme mot en parcourant les six cases.

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .list }
    public override func accessibilityLabel() -> String? { "Teintes de lecture" }
    public override func accessibilityValue() -> Any? {
        cursor >= 0 && cursor < items.count ? items[cursor].name : ""
    }
    public override func accessibilityPerformPress() -> Bool { onPick?(cursor); return true }
}
