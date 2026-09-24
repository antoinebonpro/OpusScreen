import Foundation
import AppKit

/// Un bouton au theme de l'application.
///
/// Les boutons natifs de macOS delegent leur rendu au theme du systeme : sur un
/// fond sombre choisi par l'application - et non par le systeme - ils restent
/// clairs, et le texte devient illisible des qu'on demande une autre couleur. Ils
/// sont donc redessines, comme sur Windows et pour la meme raison.
///
/// Redessiner un controle le rend INVISIBLE aux technologies d'assistance si l'on
/// s'arrete la : il ne reste qu'un rectangle sans nom, sans role et sans valeur.
/// C'est pourquoi chaque controle de ce fichier declare ce qu'il represente.
public final class DarkButton: NSView {

    public var title: String = "" { didSet { needsDisplay = true } }
    public var onClick: (() -> Void)?
    public var font: NSFont = Theme.body { didSet { needsDisplay = true } }
    public var textColor: NSColor? { didSet { needsDisplay = true } }
    public var fillColor: NSColor? { didSet { needsDisplay = true } }

    public var isEnabled: Bool = true {
        didSet { needsDisplay = true }
    }

    private var hovering = false
    private var pressing = false
    private var tracking: NSTrackingArea?

    public init(_ title: String, action: (() -> Void)? = nil) {
        self.title = title
        self.onClick = action
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: Theme.minTarget))
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    public override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    public override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressing = true
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        pressing = false
        needsDisplay = true
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside { onClick?() }
    }

    /// Declenche le bouton sans souris. Les tests et le clavier s'en servent.
    public func performClick() {
        guard isEnabled else { return }
        onClick?()
    }

    public override var acceptsFirstResponder: Bool { isEnabled }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 36 {   // espace, entree
            performClick()
            return
        }
        super.keyDown(with: event)
    }

    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    public override func draw(_ dirtyRect: NSRect) {
        let base = fillColor ?? (pressing ? Theme.accentDim : (hovering && isEnabled ? Theme.cardHover : Theme.field))
        Draw.fill(bounds, radius: 6, isEnabled ? base : Theme.sunken)
        Draw.stroke(bounds, radius: 6, isEnabled ? Theme.border : Theme.sunken)

        let color = isEnabled ? (textColor ?? Theme.fg) : Theme.faint
        Draw.text(title, in: bounds.insetBy(dx: 10, dy: 0), font: font, color: color, align: .center)

        if window?.firstResponder === self { Draw.focusRing(bounds.insetBy(dx: 1, dy: 1), radius: 6) }
    }

    // --- accessibilite ---

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityLabel() -> String? { title }
    public override func accessibilityRole() -> NSAccessibility.Role? { .button }
    public override func accessibilityPerformPress() -> Bool { performClick(); return true }
    public override func isAccessibilityEnabled() -> Bool { isEnabled }
}

/// Une liste deroulante au theme de l'application.
///
/// Elle s'appuie sur le menu du systeme - une liste deroulante entierement
/// redessinee serait un nid a problemes de navigation au clavier - mais son champ
/// ferme est peint par nous, pour qu'il ne detonne pas au milieu d'un fond sombre.
public final class DarkPopUp: NSView {

    public private(set) var items: [String] = []
    public var onChange: (() -> Void)?

    public var selectedIndex: Int = 0 {
        didSet {
            if selectedIndex < 0 { selectedIndex = 0 }
            if selectedIndex >= items.count { selectedIndex = max(0, items.count - 1) }
            needsDisplay = true
        }
    }

    public var selectedText: String {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return "" }
        return items[selectedIndex]
    }

    public var isEnabled = true { didSet { needsDisplay = true } }

    /// Intitule annonce par VoiceOver. Sans lui, la liste s'annoncerait comme
    /// « liste deroulante » sans dire de quoi.
    public var label = ""

    private var hovering = false
    private var tracking: NSTrackingArea?

    public init(items: [String]) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: Theme.minTarget))
        self.items = items
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public func setItems(_ newItems: [String], keepingSelection: Bool = true) {
        let previous = selectedText
        items = newItems
        if keepingSelection, let i = newItems.firstIndex(of: previous) { selectedIndex = i }
        else { selectedIndex = min(selectedIndex, max(0, newItems.count - 1)) }
        needsDisplay = true
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    public override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    public override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled, !items.isEmpty else { return }
        showMenu()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.font = Theme.body
        for (i, text) in items.enumerated() {
            let item = NSMenuItem(title: text, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = (i == selectedIndex) ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: menu.item(at: selectedIndex),
                   at: NSPoint(x: 0, y: bounds.height),
                   in: self)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard sender.tag != selectedIndex else { return }
        selectedIndex = sender.tag
        onChange?()
    }

    public override var acceptsFirstResponder: Bool { isEnabled }
    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 125, 124:   // bas, droite
            if selectedIndex + 1 < items.count { selectedIndex += 1; onChange?() }
        case 126, 123:   // haut, gauche
            if selectedIndex > 0 { selectedIndex -= 1; onChange?() }
        case 49, 36:     // espace, entree
            showMenu()
        default:
            super.keyDown(with: event)
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, radius: 6, isEnabled ? (hovering ? Theme.cardHover : Theme.field) : Theme.sunken)
        Draw.stroke(bounds, radius: 6, isEnabled ? Theme.border : Theme.sunken)

        Draw.text(selectedText, in: bounds.insetBy(dx: 10, dy: 0).offsetBy(dx: 0, dy: 0),
                  font: Theme.body, color: isEnabled ? Theme.fg : Theme.faint)

        // Le chevron, trace au vecteur : un caractere « v » change de dessin selon
        // la police et rend mal aux petites tailles.
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cx = bounds.maxX - 16, cy = bounds.midY
        ctx.setStrokeColor((isEnabled ? Theme.dim : Theme.faint).cgColor)
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: cx - 4, y: cy - 2))
        ctx.addLine(to: CGPoint(x: cx, y: cy + 2))
        ctx.addLine(to: CGPoint(x: cx + 4, y: cy - 2))
        ctx.strokePath()

        if window?.firstResponder === self { Draw.focusRing(bounds.insetBy(dx: 1, dy: 1), radius: 6) }
    }

    // --- accessibilite ---

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .popUpButton }
    public override func accessibilityLabel() -> String? { label }
    public override func accessibilityValue() -> Any? { selectedText }
    public override func isAccessibilityEnabled() -> Bool { isEnabled }
}
