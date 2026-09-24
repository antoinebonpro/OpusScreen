import Foundation
import AppKit

/// Les briques d'interface reutilisables.
///
/// Chaque page empile des lignes ; c'est ici que l'on decide a quoi ressemble une
/// ligne. Ajouter un reglage doit tenir en trois lignes de code, sans toucher a
/// la mise en page - c'est ce qui permet a une application d'avoir quatre-vingts
/// reglages sans devenir impraticable a maintenir.
public enum UiKit {

    /// Titre de section.
    public static func sectionTitle(_ text: String) -> LabelView {
        let l = LabelView(text)
        l.font = Theme.sectionLabel
        l.color = Theme.accent
        l.uppercase = true
        l.frame.size.height = Theme.px(18)
        return l
    }

    /// Filet sous un titre de section.
    public static func divider() -> DividerView { DividerView() }

    /// Texte explicatif, sur plusieurs lignes si besoin.
    public static func caption(_ text: String) -> LabelView {
        let l = LabelView(text)
        l.font = Theme.small
        l.color = Theme.faint
        l.wraps = true
        l.frame.size.height = Theme.px(18)
        return l
    }
}

/// Une etiquette, dessinee plutot que confiee a `NSTextField`.
///
/// Un champ de texte non modifiable reste un champ de texte : il se selectionne,
/// il porte un fond, et il s'annonce comme tel. Ici on veut du texte, et rien de
/// plus - y compris pour VoiceOver, qui doit le lire sans proposer de l'editer.
public final class LabelView: NSView {
    public var text: String { didSet { needsDisplay = true } }
    public var font: NSFont = Theme.body { didSet { needsDisplay = true } }
    public var color: NSColor = Theme.fg { didSet { needsDisplay = true } }
    public var align: Draw.Align = .left { didSet { needsDisplay = true } }
    public var wraps = false { didSet { needsDisplay = true } }
    public var uppercase = false { didSet { needsDisplay = true } }

    public init(_ text: String) {
        self.text = text
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: Theme.px(18)))
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    /// Hauteur necessaire a ce texte pour cette largeur.
    public func fittingHeight(for width: CGFloat) -> CGFloat {
        guard wraps else { return max(frame.height, ceil(font.boundingRectForFont.height) + 2) }
        if text.isEmpty { return 0 }
        return Draw.height(of: displayText, font: font, width: width)
    }

    private var displayText: String { uppercase ? text.uppercased() : text }

    public override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        Draw.text(displayText, in: bounds, font: font, color: color, align: align, wrap: wraps)
    }

    public override func isAccessibilityElement() -> Bool { !text.isEmpty }
    public override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    public override func accessibilityValue() -> Any? { displayText }
}

/// Filet horizontal.
public final class DividerView: NSView {
    public init() { super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 1)) }
    required init?(coder: NSCoder) { fatalError() }
    public override var isFlipped: Bool { true }
    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(NSRect(x: 0, y: 0, width: bounds.width, height: 1), Theme.border)
    }
    public override func isAccessibilityElement() -> Bool { false }
}

/// Une ligne de reglage a curseur : intitule, valeur lue, curseur, indication.
public final class SliderRow: NSView {

    public let track = Slider()
    private let label: LabelView
    private let valueLabel = LabelView("")
    private let hintLabel = LabelView("")

    private var unit: String
    private var format = "0"

    public var onChange: (() -> Void)?
    public var onCommit: (() -> Void)?

    private var loading = false

    public init(_ title: String, _ minimum: Double, _ maximum: Double, _ unit: String) {
        self.label = LabelView(title)
        self.unit = unit
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: SliderRow.standardHeight))

        label.font = Theme.bodyBold
        label.color = Theme.fg
        addSubview(label)

        valueLabel.font = Theme.bodyBold
        valueLabel.color = Theme.accent
        valueLabel.align = .right
        addSubview(valueLabel)

        hintLabel.font = Theme.small
        hintLabel.color = Theme.faint
        addSubview(hintLabel)

        track.minimum = minimum
        track.maximum = maximum
        track.accessibleLabel = title
        track.accessibleUnit = unit
        track.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.updateValueLabel()
            self.onChange?()
        }
        track.onCommit = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.onCommit?()
        }
        addSubview(track)

        updateValueLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public static var standardHeight: CGFloat { Theme.px(62) }

    public var title: String {
        get { label.text }
        set { label.text = newValue; track.accessibleLabel = newValue }
    }

    public var hint: String {
        get { hintLabel.text }
        set { hintLabel.text = newValue }
    }

    public var value: Double { track.value }

    public func setValueSilent(_ v: Double) {
        loading = true
        track.setValueSilent(v)
        loading = false
        updateValueLabel()
    }

    /// Format d'affichage de la valeur : « 0 », « 0.0 », « +0;-0;0 »...
    public func setFormat(_ f: String) { format = f; updateValueLabel() }

    public func mark(at marker: Double, warnAbove: Double = Double.nan) {
        track.mark(at: marker, warnAbove: warnAbove)
    }

    public func setAccent(_ color: NSColor) {
        track.fillColor = color
        valueLabel.color = color
    }

    public var isEnabled: Bool {
        get { track.isEnabled }
        set {
            track.isEnabled = newValue
            label.color = newValue ? Theme.fg : Theme.faint
            valueLabel.color = newValue ? Theme.accent : Theme.faint
        }
    }

    private func updateValueLabel() {
        let v = track.value
        var text: String
        switch format {
        case "0.0": text = String(format: "%.1f", v)
        case "0.00": text = String(format: "%.2f", v)
        case "signed": text = (v > 0 ? "+" : "") + String(Int(v.rounded()))
        default: text = String(Int(v.rounded()))
        }
        if !unit.isEmpty { text += " " + unit }
        valueLabel.text = text
    }

    public override func layout() {
        super.layout()
        let w = bounds.width
        let valueWidth = Theme.px(110)
        label.frame = NSRect(x: 0, y: 0, width: max(0, w - valueWidth - 8), height: Theme.px(18))
        valueLabel.frame = NSRect(x: w - valueWidth, y: 0, width: valueWidth, height: Theme.px(18))
        track.frame = NSRect(x: 0, y: Theme.px(20), width: w, height: Theme.px(26))
        hintLabel.frame = NSRect(x: 0, y: Theme.px(46), width: w, height: Theme.px(14))
    }

    public override func isAccessibilityElement() -> Bool { false }
}

/// Une ligne a interrupteur : intitule, description, et l'interrupteur a droite.
public final class ToggleRow: NSView {

    public let toggle = ToggleSwitch()
    private let label: LabelView
    private let descriptionLabel = LabelView("")

    public var onChange: (() -> Void)?
    private var loading = false

    public init(_ title: String, _ description: String?) {
        self.label = LabelView(title)
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: Theme.px(34)))

        label.font = Theme.body
        label.color = Theme.fg
        addSubview(label)

        descriptionLabel.text = description ?? ""
        descriptionLabel.font = Theme.small
        descriptionLabel.color = Theme.faint
        descriptionLabel.wraps = true
        addSubview(descriptionLabel)

        toggle.accessibleLabel = title
        toggle.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.onChange?()
        }
        addSubview(toggle)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public var title: String {
        get { label.text }
        set { label.text = newValue; toggle.accessibleLabel = newValue }
    }

    public var descriptionText: String {
        get { descriptionLabel.text }
        set { descriptionLabel.text = newValue }
    }

    public var isChecked: Bool {
        get { toggle.isChecked }
        set { toggle.isChecked = newValue }
    }

    public func setCheckedSilent(_ v: Bool) {
        loading = true
        toggle.setCheckedSilent(v)
        loading = false
    }

    public var isEnabled: Bool {
        get { toggle.isEnabled }
        set {
            toggle.isEnabled = newValue
            label.color = newValue ? Theme.fg : Theme.faint
            descriptionLabel.color = newValue ? Theme.faint : Theme.border
        }
    }

    /// Hauteur necessaire, description comprise.
    public func fittingHeight(for width: CGFloat) -> CGFloat {
        let textWidth = max(60, width - Theme.px(56))
        var h = Theme.px(22)
        if !descriptionLabel.text.isEmpty {
            h += Draw.height(of: descriptionLabel.text, font: Theme.small, width: textWidth) + Theme.px(2)
        }
        return max(Theme.px(30), h)
    }

    public override func layout() {
        super.layout()
        let w = bounds.width
        let switchWidth = Theme.px(44)
        let textWidth = max(60, w - switchWidth - Theme.px(12))

        label.frame = NSRect(x: 0, y: 0, width: textWidth, height: Theme.px(20))
        if descriptionLabel.text.isEmpty {
            descriptionLabel.frame = NSRect(x: 0, y: Theme.px(20), width: textWidth, height: 0)
        } else {
            let h = Draw.height(of: descriptionLabel.text, font: Theme.small, width: textWidth)
            descriptionLabel.frame = NSRect(x: 0, y: Theme.px(20), width: textWidth, height: h)
        }
        toggle.frame = NSRect(x: w - switchWidth, y: Theme.px(1),
                              width: switchWidth, height: Theme.px(24))
    }

    public override func isAccessibilityElement() -> Bool { false }
}

/// Une ligne a liste deroulante : intitule au-dessus, liste en dessous.
public final class ComboRow: NSView {

    public let box: DarkPopUp
    private let label: LabelView

    public var onChange: (() -> Void)?
    private var loading = false

    public init(_ title: String, _ items: [String]) {
        self.label = LabelView(title)
        self.box = DarkPopUp(items: items)
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: ComboRow.standardHeight))

        label.font = Theme.body
        label.color = Theme.fg
        addSubview(label)

        box.label = title
        box.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.onChange?()
        }
        addSubview(box)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public static var standardHeight: CGFloat { Theme.px(58) }

    public var selectedIndex: Int {
        get { box.selectedIndex }
        set {
            loading = true
            box.selectedIndex = newValue
            loading = false
        }
    }

    public var selectedText: String { box.selectedText }

    public func setItems(_ items: [String]) {
        loading = true
        box.setItems(items)
        loading = false
    }

    public var isEnabled: Bool {
        get { box.isEnabled }
        set {
            box.isEnabled = newValue
            label.color = newValue ? Theme.fg : Theme.faint
        }
    }

    public override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Theme.px(18))
        box.frame = NSRect(x: 0, y: Theme.px(20), width: bounds.width, height: Theme.minTarget)
    }

    public override func isAccessibilityElement() -> Bool { false }
}
