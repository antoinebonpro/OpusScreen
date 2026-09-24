import Foundation
import AppKit

/// Curseur dessine a la main.
///
/// Le curseur natif ne se theme pas et, surtout, ne sait pas montrer qu'une
/// partie de la course est particuliere - or ici il faut rendre visible la zone
/// au-dela de 100 %, la ou l'on quitte le territoire des deux applications
/// d'origine.
public final class Slider: NSView {

    private var minimumValue: Double = 0
    private var maximumValue: Double = 100
    private var currentValue: Double = 50
    private var dragging = false
    private var markerValue = Double.nan
    private var warnAbove = Double.nan

    public var onChange: (() -> Void)?
    /// Emis au relachement : c'est la que l'on confirme un reglage risque.
    public var onCommit: (() -> Void)?

    // Jetons du theme, et non des valeurs ecrites ici : une couleur ecrite dans
    // un controle est une couleur que le theme ne pilote pas.
    public var railColor = Theme.track
    public var fillColor = Theme.accent
    public var warnColor = Theme.boost
    public var knobColor = Theme.knob

    /// Intitule et unite, pour que VoiceOver annonce autre chose qu'un nombre nu.
    public var accessibleLabel = ""
    public var accessibleUnit = ""

    public var isEnabled = true { didSet { needsDisplay = true } }

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: Theme.px(34)))
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    // ------------------------------------------------------------------ valeurs

    public var minimum: Double {
        get { minimumValue }
        set { minimumValue = newValue; if maximumValue < minimumValue { maximumValue = minimumValue }; clamp(); needsDisplay = true }
    }

    public var maximum: Double {
        get { maximumValue }
        set { maximumValue = newValue; if maximumValue < minimumValue { minimumValue = maximumValue }; clamp(); needsDisplay = true }
    }

    /// Course du curseur, jamais nulle.
    ///
    /// Le calcul de position divise par cette course. Deux bornes egales - ce qui
    /// arrive le temps d'une ligne, a la construction - donnaient une division par
    /// zero, donc une coordonnee aberrante : le bouton partait hors de la vue.
    private var span: Double { max(1e-9, maximumValue - minimumValue) }

    public var value: Double {
        get { currentValue }
        set {
            let v = min(max(newValue, minimumValue), maximumValue)
            guard v != currentValue else { return }
            currentValue = v
            needsDisplay = true
            onChange?()
        }
    }

    public func setValueSilent(_ v: Double) {
        currentValue = min(max(v, minimumValue), maximumValue)
        needsDisplay = true
    }

    private func clamp() {
        currentValue = min(max(currentValue, minimumValue), maximumValue)
    }

    /// Repere sur la course, et seuil au-dela duquel le remplissage change de
    /// couleur. `marker` = valeur neutre, `warn` = entree en territoire ecrete.
    public func mark(at marker: Double, warnAbove warn: Double) {
        markerValue = marker
        warnAbove = warn
        needsDisplay = true
    }

    // ------------------------------------------------------------------ souris

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        dragging = true
        window?.makeFirstResponder(self)
        moveTo(event)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isEnabled, dragging else { return }
        moveTo(event)
    }

    public override func mouseUp(with event: NSEvent) {
        guard isEnabled, dragging else { return }
        dragging = false
        onCommit?()
    }

    public override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { return }
        let step = (maximumValue - minimumValue) / 100
        value = currentValue + Double(event.scrollingDeltaY > 0 ? step : -step) * 2
        onCommit?()
    }

    private func moveTo(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let usable = bounds.width - knobSize
        guard usable > 0 else { return }
        let t = min(max((p.x - knobSize / 2) / usable, 0), 1)
        value = minimumValue + Double(t) * span
    }

    // ------------------------------------------------------------------ clavier

    public override var acceptsFirstResponder: Bool { isEnabled }
    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { super.keyDown(with: event); return }

        let small = niceStep()
        let large = small * 10

        switch event.keyCode {
        case 123, 125:                      // gauche, bas
            value = currentValue - small; onCommit?()
        case 124, 126:                      // droite, haut
            value = currentValue + small; onCommit?()
        case 116:                           // page precedente
            value = currentValue + large; onCommit?()
        case 121:                           // page suivante
            value = currentValue - large; onCommit?()
        case 115:                           // origine
            value = minimumValue; onCommit?()
        case 119:                           // fin
            value = maximumValue; onCommit?()
        default:
            super.keyDown(with: event)
        }
    }

    /// Un pas qui a du sens pour la grandeur reglee : 1 pour un pourcentage,
    /// 100 pour des kelvins. Un pas unique donnerait soit un curseur qui n'avance
    /// pas, soit un curseur qui saute.
    private func niceStep() -> Double {
        let range = maximumValue - minimumValue
        if range > 2000 { return 100 }
        if range > 200 { return 10 }
        if range <= 12 { return 0.5 }
        return 1
    }

    // ------------------------------------------------------------------ dessin

    private var knobSize: CGFloat { Theme.px(18) }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let railHeight: CGFloat = Theme.px(6)
        let y = (bounds.height - railHeight) / 2
        let usable = bounds.width - knobSize
        let left = knobSize / 2

        let rail = NSRect(x: left, y: y, width: usable, height: railHeight)
        Draw.fill(rail, radius: railHeight / 2, isEnabled ? railColor : Theme.sunken)

        let t = CGFloat((currentValue - minimumValue) / span)
        let knobX = left + usable * t

        // Remplissage : il change de couleur au-dela du seuil d'alerte, la ou le
        // reglage quitte le domaine sans perte.
        let filled = NSRect(x: left, y: y, width: max(0, knobX - left), height: railHeight)
        let overWarn = !warnAbove.isNaN && currentValue > warnAbove
        Draw.fill(filled, radius: railHeight / 2,
                  isEnabled ? (overWarn ? warnColor : fillColor) : Theme.border)

        // Repere de la valeur neutre.
        if !markerValue.isNaN && markerValue > minimumValue && markerValue < maximumValue {
            let mt = CGFloat((markerValue - minimumValue) / span)
            let mx = left + usable * mt
            ctx.setStrokeColor(Theme.borderStrong.cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: mx, y: y - 4))
            ctx.addLine(to: CGPoint(x: mx, y: y + railHeight + 4))
            ctx.strokePath()
        }

        // Le bouton.
        let knob = NSRect(x: knobX - knobSize / 2, y: (bounds.height - knobSize) / 2,
                          width: knobSize, height: knobSize)
        ctx.setFillColor((isEnabled ? knobColor : Theme.faint).cgColor)
        ctx.fillEllipse(in: knob)
        ctx.setStrokeColor(Theme.bg.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: knob.insetBy(dx: 0.75, dy: 0.75))

        if window?.firstResponder === self {
            Draw.focusRing(knob, radius: knobSize / 2)
        }
    }

    // ------------------------------------------------------------------ accessibilite
    //
    // Un controle entierement dessine a la main est INVISIBLE pour VoiceOver :
    // le systeme ne voit qu'une vue sans role, sans nom et sans valeur. Une
    // application dont la raison d'etre est l'accessibilite ne peut pas se
    // permettre d'etre elle-meme inaccessible.

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    public override func accessibilityLabel() -> String? { accessibleLabel }
    public override func isAccessibilityEnabled() -> Bool { isEnabled }

    public override func accessibilityValue() -> Any? {
        let text = currentValue == currentValue.rounded()
            ? String(Int(currentValue))
            : String(format: "%.1f", currentValue)
        return accessibleUnit.isEmpty ? text : text + " " + accessibleUnit
    }

    public override func accessibilityMinValue() -> Any? { minimumValue }
    public override func accessibilityMaxValue() -> Any? { maximumValue }

    public override func accessibilityPerformIncrement() -> Bool {
        value = currentValue + niceStep(); onCommit?(); return true
    }

    public override func accessibilityPerformDecrement() -> Bool {
        value = currentValue - niceStep(); onCommit?(); return true
    }

    public override func setAccessibilityValue(_ accessibilityValue: Any?) {
        if let d = accessibilityValue as? Double { value = d; onCommit?() }
        else if let s = accessibilityValue as? String, let d = Double(s) { value = d; onCommit?() }
    }
}

/// Interrupteur dessine a la main : une pastille qui glisse dans un rail.
public final class ToggleSwitch: NSView {

    public var onChange: (() -> Void)?
    public var accessibleLabel = ""
    public var isEnabled = true { didSet { needsDisplay = true } }

    private var checkedValue = false
    private var knobPosition: CGFloat = 0
    private var animation: Timer?

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Theme.px(44), height: Theme.px(24)))
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public var isChecked: Bool {
        get { checkedValue }
        set {
            guard newValue != checkedValue else { return }
            checkedValue = newValue
            animateKnob()
            onChange?()
        }
    }

    public func setCheckedSilent(_ v: Bool) {
        checkedValue = v
        knobPosition = v ? 1 : 0
        needsDisplay = true
    }

    private func animateKnob() {
        animation?.invalidate()
        let target: CGFloat = checkedValue ? 1 : 0
        let start = knobPosition
        let began = Date()
        animation = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let elapsed = Date().timeIntervalSince(began) / Theme.motionSeconds
            if elapsed >= 1 {
                self.knobPosition = target
                t.invalidate()
                self.animation = nil
            } else {
                // Adoucissement en cosinus : la pastille part et arrive sans a-coup.
                let eased = CGFloat(0.5 - 0.5 * cos(Double.pi * elapsed))
                self.knobPosition = start + (target - start) * eased
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(animation!, forMode: .common)
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        isChecked = !checkedValue
    }

    public override var acceptsFirstResponder: Bool { isEnabled }
    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { super.keyDown(with: event); return }
        if event.keyCode == 49 || event.keyCode == 36 { isChecked = !checkedValue; return }
        super.keyDown(with: event)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let radius = bounds.height / 2
        let rail = bounds.insetBy(dx: 1, dy: 1)

        let off = isEnabled ? Theme.track : Theme.sunken
        let on = isEnabled ? Theme.accent : Theme.border
        let color = blend(off, on, knobPosition)

        Draw.fill(rail, radius: radius, color)
        Draw.stroke(rail, radius: radius, Theme.border)

        let knobDiameter = bounds.height - Theme.px(8)
        let travel = bounds.width - knobDiameter - Theme.px(8)
        let x = Theme.px(4) + travel * knobPosition
        let knob = NSRect(x: x, y: Theme.px(4), width: knobDiameter, height: knobDiameter)

        ctx.setFillColor((isEnabled ? Theme.knob : Theme.faint).cgColor)
        ctx.fillEllipse(in: knob)

        if window?.firstResponder === self { Draw.focusRing(bounds.insetBy(dx: 1, dy: 1), radius: radius) }
    }

    private func blend(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        let ca = RGB(a), cb = RGB(b)
        return RGB(Int(CGFloat(ca.r) + (CGFloat(cb.r) - CGFloat(ca.r)) * t),
                   Int(CGFloat(ca.g) + (CGFloat(cb.g) - CGFloat(ca.g)) * t),
                   Int(CGFloat(ca.b) + (CGFloat(cb.b) - CGFloat(ca.b)) * t)).nsColor
    }

    // --- accessibilite ---

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    public override func accessibilityLabel() -> String? { accessibleLabel }
    public override func accessibilityValue() -> Any? { checkedValue ? 1 : 0 }
    public override func isAccessibilityEnabled() -> Bool { isEnabled }
    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        isChecked = !checkedValue
        return true
    }
}
