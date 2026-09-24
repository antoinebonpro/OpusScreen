import Foundation
import AppKit

/// La colonne de navigation : un onglet par page, avec son icone.
///
/// Aucun emoji comme icone. Un emoji change de dessin selon la police installee,
/// ignore la couleur du theme et rend mal a seize points. Les onze icones sont
/// donc tracees au vecteur, dans la meme grammaire graphique que le logo : un
/// trait, des extremites arrondies, aucun aplat.
public final class SideNav: NSView {

    public struct Tab {
        public let label: String
        public let glyph: NavGlyph
    }

    private var tabs: [Tab] = []
    private var selection = 0
    private var hover = -1

    public var onSelect: ((Int) -> Void)?

    /// Hauteur reservee a la marque, au-dessus des onglets.
    public var topOffset: CGFloat = Theme.px(64)

    private static var rowHeight: CGFloat { Theme.px(38) }

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Theme.px(196), height: 600))
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public func addTab(_ label: String, _ glyph: NavGlyph) {
        tabs.append(Tab(label: label, glyph: glyph))
        needsDisplay = true
    }

    public var selectedIndex: Int { selection }

    public func select(_ index: Int) {
        guard index >= 0, index < tabs.count, index != selection else { return }
        selection = index
        needsDisplay = true
        onSelect?(index)
    }

    /// Selectionne sans prevenir : sert a poser l'etat initial.
    public func setSelectionSilent(_ index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selection = index
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
        if i >= 0 {
            window?.makeFirstResponder(self)
            select(i)
        }
    }

    private func indexAt(_ p: NSPoint) -> Int {
        guard p.y >= topOffset else { return -1 }
        let i = Int((p.y - topOffset) / SideNav.rowHeight)
        return (i >= 0 && i < tabs.count) ? i : -1
    }

    // ------------------------------------------------------------------ clavier

    public override var acceptsFirstResponder: Bool { true }
    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: select(min(tabs.count - 1, selection + 1))   // bas
        case 126: select(max(0, selection - 1))                // haut
        case 115: select(0)                                    // origine
        case 119: select(tabs.count - 1)                       // fin
        default: super.keyDown(with: event)
        }
    }

    // ------------------------------------------------------------------ dessin

    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, Theme.bg)

        for (i, tab) in tabs.enumerated() {
            let y = topOffset + CGFloat(i) * SideNav.rowHeight
            let row = NSRect(x: Theme.px(8), y: y, width: bounds.width - Theme.px(16),
                             height: SideNav.rowHeight - Theme.px(2))
            let selected = i == selection
            let hovered = i == hover

            if selected {
                Draw.fill(row, radius: 6, Theme.card)
                // Un liseré a gauche : sur un fond sombre, une carte a peine plus
                // claire ne suffit pas a designer l'onglet actif.
                Draw.fill(NSRect(x: row.minX, y: row.minY + 6, width: 3, height: row.height - 12),
                          radius: 1.5, Theme.accent)
            } else if hovered {
                Draw.fill(row, radius: 6, Theme.sunken)
            }

            let ink = selected ? Theme.accent : (hovered ? Theme.fg : Theme.dim)
            tab.glyph.draw(in: NSRect(x: row.minX + Theme.px(12), y: row.midY - Theme.px(9),
                                      width: Theme.px(18), height: Theme.px(18)), color: ink)

            Draw.text(tab.label,
                      in: NSRect(x: row.minX + Theme.px(38), y: row.minY,
                                 width: row.width - Theme.px(46), height: row.height),
                      font: selected ? Theme.bodyBold : Theme.body,
                      color: selected ? Theme.fg : Theme.dim)

            if window?.firstResponder === self && selected {
                Draw.focusRing(row, radius: 6)
            }
        }
    }

    // ------------------------------------------------------------------ accessibilite

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .tabGroup }
    public override func accessibilityLabel() -> String? { "Pages de reglages" }
    public override func accessibilityValue() -> Any? {
        selection >= 0 && selection < tabs.count ? tabs[selection].label : ""
    }
}

/// Les icones de navigation, tracees au vecteur.
public enum NavGlyph {
    case compass, sun, palette, colorblind, vision, clock, apps, screens, eye, keyboard, sliders

    public func draw(in rect: NSRect, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.translateBy(x: rect.minX, y: rect.minY)
        let s = min(rect.width, rect.height) / 18.0
        ctx.scaleBy(x: s, y: s)

        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch self {
        case .compass:
            ctx.strokeEllipse(in: CGRect(x: 1.5, y: 1.5, width: 15, height: 15))
            ctx.move(to: CGPoint(x: 12, y: 6))
            ctx.addLine(to: CGPoint(x: 10, y: 10))
            ctx.addLine(to: CGPoint(x: 6, y: 12))
            ctx.addLine(to: CGPoint(x: 8, y: 8))
            ctx.closePath()
            ctx.strokePath()

        case .sun:
            ctx.strokeEllipse(in: CGRect(x: 6, y: 6, width: 6, height: 6))
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                ctx.move(to: CGPoint(x: 9 + cos(a) * 6.2, y: 9 + sin(a) * 6.2))
                ctx.addLine(to: CGPoint(x: 9 + cos(a) * 8.2, y: 9 + sin(a) * 8.2))
            }
            ctx.strokePath()

        case .palette:
            // Une palette : un ovale entaille, et trois godets.
            ctx.strokeEllipse(in: CGRect(x: 1.5, y: 2.5, width: 15, height: 13))
            for p in [CGPoint(x: 6, y: 6.5), CGPoint(x: 9.5, y: 5.5), CGPoint(x: 12.5, y: 8)] {
                ctx.fillEllipse(in: CGRect(x: p.x - 1.1, y: p.y - 1.1, width: 2.2, height: 2.2))
            }

        case .colorblind:
            // Deux disques qui se recouvrent : la confusion de deux couleurs.
            ctx.strokeEllipse(in: CGRect(x: 1.5, y: 4, width: 10, height: 10))
            ctx.strokeEllipse(in: CGRect(x: 6.5, y: 4, width: 10, height: 10))

        case .vision:
            // Un oeil avec une loupe : ce que la page fait.
            ctx.move(to: CGPoint(x: 1.5, y: 9))
            ctx.addCurve(to: CGPoint(x: 16.5, y: 9),
                         control1: CGPoint(x: 5.5, y: 2.5), control2: CGPoint(x: 12.5, y: 2.5))
            ctx.addCurve(to: CGPoint(x: 1.5, y: 9),
                         control1: CGPoint(x: 12.5, y: 15.5), control2: CGPoint(x: 5.5, y: 15.5))
            ctx.strokePath()
            ctx.fillEllipse(in: CGRect(x: 7, y: 7, width: 4, height: 4))

        case .clock:
            ctx.strokeEllipse(in: CGRect(x: 1.5, y: 1.5, width: 15, height: 15))
            ctx.move(to: CGPoint(x: 9, y: 5))
            ctx.addLine(to: CGPoint(x: 9, y: 9))
            ctx.addLine(to: CGPoint(x: 12, y: 11))
            ctx.strokePath()

        case .apps:
            for (x, y) in [(2.0, 2.0), (10.0, 2.0), (2.0, 10.0), (10.0, 10.0)] {
                let r = CGRect(x: x, y: y, width: 6, height: 6)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
            }
            ctx.strokePath()

        case .screens:
            ctx.addPath(CGPath(roundedRect: CGRect(x: 1.5, y: 3, width: 11, height: 8),
                               cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
            ctx.addPath(CGPath(roundedRect: CGRect(x: 7.5, y: 7, width: 9, height: 7),
                               cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
            ctx.strokePath()

        case .eye:
            ctx.move(to: CGPoint(x: 1.5, y: 9))
            ctx.addCurve(to: CGPoint(x: 16.5, y: 9),
                         control1: CGPoint(x: 5.5, y: 2.5), control2: CGPoint(x: 12.5, y: 2.5))
            ctx.addCurve(to: CGPoint(x: 1.5, y: 9),
                         control1: CGPoint(x: 12.5, y: 15.5), control2: CGPoint(x: 5.5, y: 15.5))
            ctx.strokePath()
            ctx.strokeEllipse(in: CGRect(x: 6.5, y: 6.5, width: 5, height: 5))

        case .keyboard:
            ctx.addPath(CGPath(roundedRect: CGRect(x: 1.5, y: 4, width: 15, height: 10),
                               cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
            ctx.strokePath()
            for (x, y) in [(4.0, 7.0), (7.5, 7.0), (11.0, 7.0), (4.0, 10.5)] {
                ctx.fillEllipse(in: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4))
            }
            ctx.move(to: CGPoint(x: 7, y: 10.8))
            ctx.addLine(to: CGPoint(x: 13.5, y: 10.8))
            ctx.strokePath()

        case .sliders:
            for (y, knob) in [(5.0, 11.5), (9.0, 6.0), (13.0, 9.5)] {
                ctx.move(to: CGPoint(x: 2, y: y))
                ctx.addLine(to: CGPoint(x: 16, y: y))
                ctx.strokePath()
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: CGRect(x: knob - 1.8, y: y - 1.8, width: 3.6, height: 3.6))
            }
        }
    }
}
