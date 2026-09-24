import Foundation
import AppKit

/// Anneau lumineux qui entoure le pointeur.
///
/// Perdre le pointeur de vue est le premier obstacle rapporte en basse vision,
/// et il empire avec la taille des ecrans : un curseur de 32 pixels sur un bureau
/// de plusieurs millions n'est pas une cible, c'est une aiguille. macOS propose
/// bien d'agrandir le curseur, mais un curseur plus gros reste de la meme couleur
/// que ce qu'il survole. Un anneau de couleur franche, lui, se detache de tout.
///
/// La fenetre est percee en son centre : il n'y a donc aucun pixel au milieu, et
/// rien ne recouvre ce que l'on cherche a regarder.
public final class CursorBeacon {

    public static let minSize = 36
    public static let maxSize = 180

    private var window: NSPanel?
    private var view: BeaconView?
    private var follow: Timer?
    private var moveMonitor: Any?

    private var sizeValue = 72
    private var colorValue = RGB(255, 168, 66)
    private var opacityValue = 70   // en pourcentage

    public init() {}

    public var isVisible: Bool { window?.isVisible ?? false }

    public var size: Int {
        get { sizeValue }
        set {
            let v = max(CursorBeacon.minSize, min(CursorBeacon.maxSize, newValue))
            guard v != sizeValue else { return }
            sizeValue = v
            reshape()
        }
    }

    public var color: RGB {
        get { colorValue }
        set { colorValue = newValue; view?.ink = newValue; view?.needsDisplay = true }
    }

    /// Opacite en pourcentage. Jamais opaque : l'anneau ne doit rien cacher.
    public var opacity: Int {
        get { opacityValue }
        set {
            opacityValue = max(10, min(100, newValue))
            applyOpacity()
        }
    }

    public func show() {
        if window == nil { build() }

        // La forme, la couleur et l'opacite sont reappliquees a chaque affichage,
        // et pas seulement a la creation : la restauration d'urgence met l'opacite
        // de toutes les fenetres connues a zero, et l'anneau serait sinon revenu
        // parfaitement invisible - un interrupteur allume devant un ecran inchange.
        reshape()
        view?.ink = colorValue
        applyOpacity()
        window?.orderFrontRegardless()

        startFollowing()
        centerOnCursor()
    }

    public func hide() {
        stopFollowing()
        window?.orderOut(nil)
    }

    public func setVisible(_ on: Bool) { on ? show() : hide() }

    // ------------------------------------------------------------------ la fenetre

    private func build() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: sizeValue, height: sizeValue),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = WindowLevels.aid
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true     // aucun clic n'est intercepte
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        // L'anneau est une aide a l'ecran, pas un element du document : il n'a
        // rien a faire dans une capture ni dans un partage d'ecran.
        panel.sharingType = .none

        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]

        let content = BeaconView(frame: NSRect(x: 0, y: 0, width: sizeValue, height: sizeValue))
        content.ink = colorValue
        panel.contentView = content

        window = panel
        view = content
        SafetyGuard.registerOverlay(panel)
    }

    private func reshape() {
        guard let window = window else { return }
        var frame = window.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        frame.size = NSSize(width: sizeValue, height: sizeValue)
        frame.origin = NSPoint(x: center.x - CGFloat(sizeValue) / 2,
                               y: center.y - CGFloat(sizeValue) / 2)
        window.setFrame(frame, display: false)
        view?.frame = NSRect(x: 0, y: 0, width: sizeValue, height: sizeValue)
        view?.needsDisplay = true
    }

    private func applyOpacity() {
        var a = Double(opacityValue) * 2.55
        if a < 26 { a = 26 }
        if a > 235 { a = 235 }   // jamais opaque
        window?.alphaValue = CGFloat(a) / 255.0
    }

    // ------------------------------------------------------------------ suivi

    /// Deux mecanismes pour suivre le pointeur, et ce n'est pas une precaution
    /// inutile : le moniteur global d'evenements ne recoit rien quand la souris ne
    /// bouge pas, mais il est immediat ; la minuterie, elle, rattrape les
    /// deplacements causes par autre chose qu'un mouvement de souris - un
    /// deplacement au clavier, un changement d'ecran.
    private func startFollowing() {
        if follow == nil {
            follow = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.centerOnCursor()
            }
            RunLoop.main.add(follow!, forMode: .common)
        }
        if moveMonitor == nil {
            moveMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
                self?.centerOnCursor()
            }
        }
    }

    private func stopFollowing() {
        follow?.invalidate()
        follow = nil
        if let m = moveMonitor { NSEvent.removeMonitor(m); moveMonitor = nil }
    }

    private func centerOnCursor() {
        guard let window = window, window.isVisible else { return }
        let p = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: p.x - CGFloat(sizeValue) / 2,
                                      y: p.y - CGFloat(sizeValue) / 2))
    }

    public func dispose() {
        stopFollowing()
        if let w = window {
            SafetyGuard.unregisterOverlay(w)
            w.orderOut(nil)
            w.close()
        }
        window = nil
        view = nil
    }

    // ------------------------------------------------------------------ le dessin

    private final class BeaconView: NSView {
        var ink = RGB(255, 168, 66)

        override var isFlipped: Bool { false }

        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let side = min(bounds.width, bounds.height)
            let thickness = max(3.0, side / 9.0)

            ctx.clear(bounds)
            ctx.setShouldAntialias(true)

            // L'anneau est obtenu en retirant le disque central : rien n'est peint
            // au milieu, donc rien ne masque la cible.
            let outer = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 0.75, dy: 0.75)
            let inner = outer.insetBy(dx: thickness, dy: thickness)

            let path = CGMutablePath()
            path.addEllipse(in: outer)
            path.addEllipse(in: inner)

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip(using: .evenOdd)
            ctx.setFillColor(ink.cgColor)
            ctx.fill(outer)
            ctx.restoreGState()

            // Un bord sombre rend l'anneau lisible sur un fond de la meme teinte.
            ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.59))
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: outer)
            ctx.strokeEllipse(in: inner)
        }
    }
}
