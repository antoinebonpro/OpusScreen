import Foundation
import AppKit

/// Les boites de dialogue ordinaires.
///
/// Elles passent par `NSAlert` plutot que par une fenetre redessinee : une boite
/// d'alerte est exactement le genre d'element ou l'apparence du systeme vaut mieux
/// que la notre - elle doit se reconnaitre immediatement, et elle doit rester
/// pilotable au clavier sans que nous ayons a le reimplementer.
public enum Alerts {

    @discardableResult
    public static func info(_ message: String, _ detail: String = "",
                            window: NSWindow? = nil) -> NSApplication.ModalResponse {
        show(message, detail, style: .informational, buttons: ["OK"], window: window)
    }

    @discardableResult
    public static func warn(_ message: String, _ detail: String = "",
                            window: NSWindow? = nil) -> NSApplication.ModalResponse {
        show(message, detail, style: .warning, buttons: ["OK"], window: window)
    }

    /// Question a deux reponses. Vrai si la premiere est choisie.
    public static func confirm(_ message: String, _ detail: String = "",
                               yes: String = "Continuer", no: String = "Annuler",
                               window: NSWindow? = nil) -> Bool {
        show(message, detail, style: .warning, buttons: [yes, no], window: window) == .alertFirstButtonReturn
    }

    /// Question a plusieurs reponses. Rend le rang du bouton choisi, ou -1
    /// quand AUCUN bouton n'a repondu.
    ///
    /// Ce -1 n'est pas de la prudence de principe. Une boite modale peut se
    /// refermer sans qu'on ait clique : une autre fenetre passe devant, la
    /// session se verrouille, un ordre arrive par la ligne de commande. Si l'on
    /// traduit ce silence en « dernier bouton », on enregistre une decision que
    /// personne n'a prise - et le dernier bouton est justement, ici comme
    /// ailleurs, celui qui dit « ne plus jamais demander ».
    public static func choose(_ message: String, _ detail: String,
                              _ buttons: [String], window: NSWindow? = nil) -> Int {
        let r = show(message, detail, style: .warning, buttons: buttons, window: window)
        let index = r.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return (index >= 0 && index < buttons.count) ? index : -1
    }

    private static func show(_ message: String, _ detail: String, style: NSAlert.Style,
                             buttons: [String], window: NSWindow?) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = style
        for b in buttons { alert.addButton(withTitle: b) }
        alert.window.appearance = NSAppearance(named: .darkAqua)

        // Une alerte modale exige que l'application soit au premier plan ; sans
        // cela elle s'ouvre derriere et l'utilisateur croit l'application figee.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}

/// Saisie d'une ligne de texte.
public enum PromptDialog {

    public static func ask(_ title: String, _ label: String, _ initial: String,
                           window: NSWindow? = nil) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = label
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Enregistrer")
        alert.addButton(withTitle: "Annuler")
        alert.window.appearance = NSAppearance(named: .darkAqua)

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = initial
        field.font = Theme.body
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Confirmation a rebours sur les reglages sombres.
///
/// C'est la cinquieme protection anti-ecran-noir, et elle est reprise d'un geste
/// que tout le monde connait : le changement de resolution, qui revient tout seul
/// en arriere si l'on ne confirme pas. Sans reponse, on repart de l'etat
/// precedent - c'est-a-dire que quelqu'un qui ne voit plus rien n'a RIEN a faire
/// pour retrouver son ecran.
public final class ConfirmDialog {

    private let window: NSWindow
    private let view: ConfirmView
    private var timer: Timer?
    private var remaining: Int
    private var result = false

    public private(set) var dontAskAgain = false

    public init(brightness: Double, seconds: Int) {
        self.remaining = max(3, seconds)

        let size = NSSize(width: 420, height: 230)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.title = "Reglage tres sombre"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.card
        window.level = WindowLevels.notice

        view = ConfirmView(frame: NSRect(origin: .zero, size: size))
        view.brightness = brightness
        view.remaining = remaining
        window.contentView = view
    }

    /// Affiche et attend. Vrai si l'utilisateur a confirme.
    public func run(over parent: NSWindow?) -> Bool {
        view.onKeep = { [weak self] in self?.finish(true) }
        view.onCancel = { [weak self] in self?.finish(false) }
        view.onDontAsk = { [weak self] value in self?.dontAskAgain = value }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.remaining -= 1
            self.view.remaining = self.remaining
            self.view.needsDisplay = true
            if self.remaining <= 0 { self.finish(false) }
        }
        RunLoop.main.add(timer!, forMode: .common)

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        NSApp.runModal(for: window)
        return result
    }

    private func finish(_ keep: Bool) {
        timer?.invalidate(); timer = nil
        result = keep
        NSApp.stopModal()
        window.orderOut(nil)
    }

    final class ConfirmView: FlippedView {
        var brightness: Double = 10
        var remaining = 10
        var onKeep: (() -> Void)?
        var onCancel: (() -> Void)?
        var onDontAsk: ((Bool) -> Void)?

        private let keep = DarkButton("Garder ce reglage")
        private let cancel = DarkButton("Revenir en arriere")
        private let dontAsk = ToggleSwitch()
        private let dontAskLabel = LabelView("Ne plus demander")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = Theme.card.cgColor

            keep.onClick = { [weak self] in self?.onKeep?() }
            cancel.onClick = { [weak self] in self?.onCancel?() }
            cancel.fillColor = Theme.accentDim

            dontAsk.accessibleLabel = "Ne plus demander"
            dontAsk.onChange = { [weak self] in
                self?.onDontAsk?(self?.dontAsk.isChecked ?? false)
            }

            dontAskLabel.font = Theme.small
            dontAskLabel.color = Theme.dim

            addSubview(keep)
            addSubview(cancel)
            addSubview(dontAsk)
            addSubview(dontAskLabel)

            keep.frame = NSRect(x: 24, y: 168, width: 180, height: Theme.minTarget)
            cancel.frame = NSRect(x: 216, y: 168, width: 180, height: Theme.minTarget)
            dontAsk.frame = NSRect(x: 24, y: 128, width: 44, height: 24)
            dontAskLabel.frame = NSRect(x: 76, y: 128, width: 260, height: 24)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func draw(_ dirtyRect: NSRect) {
            Draw.fill(bounds, Theme.card)

            Draw.text("L'ecran est descendu a \(Int(brightness.rounded())) %.",
                      in: NSRect(x: 24, y: 20, width: bounds.width - 48, height: 26),
                      font: Theme.title, color: Theme.fg)

            Draw.text("Si vous ne voyez plus rien, ne touchez a rien : le reglage precedent "
                    + "revient tout seul dans \(remaining) seconde\(remaining > 1 ? "s" : ""). "
                    + "Ctrl + Alt + Maj + R retablit un ecran normal en toutes circonstances.",
                      in: NSRect(x: 24, y: 54, width: bounds.width - 48, height: 100),
                      font: Theme.body, color: Theme.dim, wrap: true)
        }
    }
}
