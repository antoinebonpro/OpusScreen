import Foundation
import AppKit

/// Rappels de repos oculaire, sur la regle 20-20-20 : toutes les 20 minutes,
/// regarder a 6 metres pendant 20 secondes. Fonctionnalite payante chez CareUEyes
/// et Iris.
///
/// Le rappel s'affiche sans jamais voler le focus : interrompre une frappe ou un
/// raccourci en cours serait pire que le probleme qu'on cherche a resoudre.
public final class BreakReminder {

    private var tick: Timer?
    private var lastBreak = Date()
    private var sessionStart = Date()
    private var window: BreakWindow?
    private var blinkWindow: BlinkWindow?
    private var lastBlink = Date()

    public var enabled = false
    public var intervalMinutes = 20
    public var durationSeconds = 20
    public var dimDuringBreak = false      // assombrir doucement pendant la pause
    public var playSound = false

    /// Rappel de clignement, contre la secheresse oculaire.
    ///
    /// Devant un ecran, la frequence de clignement chute de plus de moitie et le
    /// clignement devient souvent incomplet : c'est la premiere cause de secheresse
    /// oculaire liee au travail sur ecran, et elle touche particulierement les
    /// personnes deja fragiles des yeux. Le rappel est volontairement minuscule et
    /// bref - un rappel qui interrompt ne sera pas garde plus de deux jours.
    public var blinkReminders = false
    public var blinkIntervalMinutes = 5

    /// Emis au debut et a la fin d'une pause, pour laisser l'appelant assombrir.
    public var breakStateChanged: ((Bool) -> Void)?

    public var screenTime: TimeInterval { Date().timeIntervalSince(sessionStart) }

    public var untilNextBreak: TimeInterval {
        let elapsed = Date().timeIntervalSince(lastBreak)
        let total = TimeInterval(intervalMinutes * 60)
        return max(0, total - elapsed)
    }

    public init() {
        tick = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.onTick()
        }
        RunLoop.main.add(tick!, forMode: .common)
    }

    public func resetTimer() { lastBreak = Date() }

    public func resetSession() {
        sessionStart = Date()
        lastBreak = Date()
    }

    private func onTick() {
        checkBlink()

        guard enabled, window == nil else { return }
        guard Date().timeIntervalSince(lastBreak) >= TimeInterval(intervalMinutes * 60) else { return }
        triggerBreak()
    }

    private func checkBlink() {
        guard blinkReminders, blinkWindow == nil, window == nil else { return }
        let due = TimeInterval(max(1, blinkIntervalMinutes) * 60)
        guard Date().timeIntervalSince(lastBlink) >= due else { return }
        triggerBlink()
    }

    /// Affiche le rappel de clignement, qui s'efface tout seul.
    public func triggerBlink() {
        guard blinkWindow == nil else { return }
        lastBlink = Date()
        let w = BlinkWindow { [weak self] in
            self?.blinkWindow = nil
            self?.lastBlink = Date()
        }
        blinkWindow = w
        w.present()
    }

    /// Declenche une pause immediatement.
    public func triggerBreak() {
        guard window == nil else { return }
        lastBreak = Date()

        if dimDuringBreak { breakStateChanged?(true) }
        if playSound { NSSound(named: "Submarine")?.play() }

        let w = BreakWindow(seconds: durationSeconds) { [weak self] in
            guard let self = self else { return }
            self.window = nil
            self.lastBreak = Date()
            if self.dimDuringBreak { self.breakStateChanged?(false) }
        }
        window = w
        w.present()
    }

    public func dispose() {
        tick?.invalidate(); tick = nil
        window?.dismiss()
        blinkWindow?.dismiss()
    }

    // ------------------------------------------------------------------ le clignement

    /// Un bandeau minuscule, en haut de l'ecran principal, qui s'efface au bout de
    /// trois secondes.
    ///
    /// Il ne prend pas le focus, ne recoit pas les clics et n'apparait pas dans les
    /// captures : il peut donc surgir pendant une visioconference ou une saisie sans
    /// consequence. C'est la condition pour qu'un rappel aussi frequent reste
    /// supportable.
    final class BlinkWindow {
        private let panel: NSPanel
        private var life: Timer?
        private let onClose: () -> Void

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose

            let size = NSSize(width: 196, height: 34)
            panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            panel.level = WindowLevels.notice
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.sharingType = .none
            panel.alphaValue = 225.0 / 255.0
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                        .fullScreenAuxiliary, .ignoresCycle]

            let view = BlinkView(frame: NSRect(origin: .zero, size: size))
            panel.contentView = view

            if let screen = NSScreen.main {
                let work = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: work.midX - size.width / 2,
                                             y: work.maxY - size.height - 12))
            }
        }

        func present() {
            panel.orderFrontRegardless()
            life = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.dismiss()
            }
        }

        func dismiss() {
            life?.invalidate(); life = nil
            panel.orderOut(nil)
            panel.close()
            onClose()
        }

        final class BlinkView: NSView {
            override var isFlipped: Bool { true }

            override func draw(_ dirtyRect: NSRect) {
                guard let ctx = NSGraphicsContext.current?.cgContext else { return }
                Draw.fill(bounds, radius: 8, Theme.card)
                Draw.stroke(bounds, radius: 8, Theme.border)

                // Un oeil ferme, dessine au trait : la meme grammaire graphique que
                // les icones de navigation, et aucun emoji.
                ctx.setStrokeColor(Theme.accent.cgColor)
                ctx.setLineWidth(1.8)
                ctx.setLineCap(.round)
                ctx.addArc(center: CGPoint(x: 22, y: 17), radius: 10,
                           startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
                ctx.strokePath()
                ctx.move(to: CGPoint(x: 14, y: 22)); ctx.addLine(to: CGPoint(x: 11, y: 26))
                ctx.move(to: CGPoint(x: 22, y: 25)); ctx.addLine(to: CGPoint(x: 22, y: 29))
                ctx.move(to: CGPoint(x: 30, y: 22)); ctx.addLine(to: CGPoint(x: 33, y: 26))
                ctx.strokePath()

                Draw.text("Clignez des yeux",
                          in: NSRect(x: 44, y: 0, width: bounds.width - 52, height: bounds.height),
                          font: Theme.body, color: Theme.fg)
            }
        }
    }

    // ------------------------------------------------------------------ la pause

    /// Petite carte en bas a droite, avec un anneau de progression et le compte a
    /// rebours. Ne prend jamais le focus.
    final class BreakWindow {
        private let panel: NSPanel
        private let view: BreakView
        private var timer: Timer?
        private let total: Int
        private var remaining: Int
        private let onClose: () -> Void

        init(seconds: Int, onClose: @escaping () -> Void) {
            self.total = max(5, seconds)
            self.remaining = self.total
            self.onClose = onClose

            let size = NSSize(width: 320, height: 132)
            panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            panel.level = WindowLevels.notice
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.sharingType = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                        .fullScreenAuxiliary, .ignoresCycle]

            view = BreakView(frame: NSRect(origin: .zero, size: size))
            view.total = total
            view.remaining = remaining
            panel.contentView = view

            if let screen = NSScreen.main {
                let work = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: work.maxX - size.width - 24,
                                             y: work.minY + 24))
            }
            view.onClick = { [weak self] in self?.dismiss() }
        }

        func present() {
            panel.orderFrontRegardless()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.remaining -= 1
                if self.remaining <= 0 { self.dismiss(); return }
                self.view.remaining = self.remaining
                self.view.needsDisplay = true
            }
            RunLoop.main.add(timer!, forMode: .common)
        }

        func dismiss() {
            timer?.invalidate(); timer = nil
            panel.orderOut(nil)
            panel.close()
            onClose()
        }

        final class BreakView: NSView {
            var total = 20
            var remaining = 20
            var onClick: (() -> Void)?

            override var isFlipped: Bool { true }

            override func mouseDown(with event: NSEvent) { onClick?() }

            override func draw(_ dirtyRect: NSRect) {
                guard let ctx = NSGraphicsContext.current?.cgContext else { return }
                Draw.fill(bounds, radius: 10, Theme.card)
                Draw.stroke(bounds, radius: 10, Theme.border)

                // anneau de progression
                let d: CGFloat = 62, cx: CGFloat = 26, cy: CGFloat = 34
                let center = CGPoint(x: cx + d / 2, y: cy + d / 2)

                ctx.setStrokeColor(Theme.sunken.cgColor)
                ctx.setLineWidth(6)
                ctx.addArc(center: center, radius: d / 2, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                ctx.strokePath()

                let fraction = CGFloat(remaining) / CGFloat(max(1, total))
                ctx.setStrokeColor(Theme.good.cgColor)
                ctx.setLineWidth(6)
                ctx.setLineCap(.round)
                ctx.addArc(center: center, radius: d / 2,
                           startAngle: -.pi / 2,
                           endAngle: -.pi / 2 + .pi * 2 * fraction,
                           clockwise: false)
                ctx.strokePath()

                Draw.text("\(remaining)", in: NSRect(x: cx, y: cy, width: d, height: d),
                          font: Theme.heading, color: Theme.fg, align: .center)

                Draw.text("Pause pour les yeux", in: NSRect(x: 108, y: 24, width: 200, height: 20),
                          font: Theme.title, color: Theme.fg)
                Draw.text("Regardez au loin, a 6 metres environ.",
                          in: NSRect(x: 110, y: 52, width: 200, height: 18),
                          font: Theme.small, color: Theme.dim)
                Draw.text("Cliquez pour passer.", in: NSRect(x: 110, y: 72, width: 200, height: 18),
                          font: Theme.small, color: Theme.dim)
                Draw.text("Regle 20-20-20", in: NSRect(x: 110, y: 98, width: 200, height: 18),
                          font: Theme.small, color: Theme.faint)
            }
        }
    }
}
