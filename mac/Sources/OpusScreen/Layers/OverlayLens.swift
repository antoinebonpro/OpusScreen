import Foundation
import AppKit

/// La « fade lens » de PangoBright, reimplementee.
///
/// Le principe releve sur Windows : une fenetre par ecran, toujours au-dessus,
/// transparente aux clics, remplie de la couleur de fondu, dont l'opacite est
/// pilotee en continu. C'est la seule technique qui descend vraiment bas, mais
/// elle ne peut par nature que retirer de la lumiere - jamais en ajouter.
///
/// Ici elle ne sert que sous le plancher gamma (35 %) : au-dessus, la table de
/// couleurs fait tout, ce qui evite d'avoir une fenetre posee sur le bureau sans
/// raison.
public final class OverlayLens {
    private let panel: NSPanel
    private var alpha: CGFloat = 0
    private var tintColor: RGB = .black
    private var keeper: Timer?

    public init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.level = WindowLevels.veil
        panel.isOpaque = false
        panel.backgroundColor = .black
        panel.alphaValue = 0
        panel.hasShadow = false
        panel.ignoresMouseEvents = true     // les clics traversent
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        // Retire le voile de toute capture d'ecran. Double benefice : l'analyse de
        // contenu ne se mesure pas elle-meme - ce qui interdit toute oscillation -
        // et les captures de l'utilisateur sortent propres, defaut bien connu de
        // PangoBright.
        panel.sharingType = .none

        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]

        SafetyGuard.registerOverlay(panel)

        // PangoBright utilisait une minuterie pour se remettre au premier plan :
        // sans cela, toute fenetre passant au-dessus apres nous couvrirait le voile.
        keeper = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.keepOnTop()
        }
    }

    private func keepOnTop() {
        guard alpha > 0 else { return }
        panel.level = WindowLevels.veil
        panel.orderFrontRegardless()
    }

    /// Vrai quand le voile est effectivement pose.
    ///
    /// Distinct de « la fenetre existe » : elle existe encore quelques instants
    /// apres avoir ete rangee, le temps que le serveur de fenetres en prenne
    /// acte. Ce qui compte ici est la decision de l'application.
    public var isShowing: Bool { alpha > 0 && panel.isVisible }

    public func cover(_ m: MonitorInfo) {
        panel.setFrame(Native.quartzToAppKit(m.bounds.cgRect), display: false)
    }

    public var tint: RGB {
        get { tintColor }
        set {
            tintColor = newValue
            panel.backgroundColor = newValue.nsColor
        }
    }

    /// transmission = 1.0 -> voile totalement absent ; 0.15 -> ne laisse passer que 15 %.
    /// Le voile est reellement masque quand il ne sert a rien, pour ne pas laisser
    /// tourner une fenetre au-dessus de tout sans raison.
    public func setTransmission(_ transmission: Double) {
        var a = (1.0 - transmission) * 255.0
        if a < 0 { a = 0 }
        if a > 250 { a = 250 }   // garde-fou : jamais totalement opaque
        alpha = CGFloat(a.rounded()) / 255.0

        if alpha <= 0.0001 {
            panel.alphaValue = 0
            if panel.isVisible { panel.orderOut(nil) }
        } else {
            panel.alphaValue = alpha
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    public func dispose() {
        keeper?.invalidate()
        keeper = nil
        SafetyGuard.unregisterOverlay(panel)
        panel.alphaValue = 0
        panel.orderOut(nil)
        panel.close()
    }
}

/// Gere un voile par ecran et les garde alignes sur la liste des ecrans.
public final class OverlaySet {
    private var lenses: [String: OverlayLens] = [:]

    public init() {}

    public func update(_ m: MonitorInfo, transmission: Double, tint: RGB) {
        var lens = lenses[m.stableId]
        if lens == nil {
            if transmission >= 1.0 { return }   // rien a montrer : inutile de creer la fenetre
            lens = OverlayLens()
            lenses[m.stableId] = lens
        }
        guard let lens = lens else { return }
        lens.cover(m)
        lens.tint = tint
        lens.setTransmission(transmission)
    }

    public func hideAll() {
        for (_, l) in lenses { l.setTransmission(1.0) }
    }

    /// Supprime les voiles des ecrans qui ne sont plus la (debranchement).
    public func pruneMissing(_ current: [MonitorInfo]) {
        let alive = Set(current.map { $0.stableId })
        for (id, lens) in lenses where !alive.contains(id) {
            lens.dispose()
            lenses.removeValue(forKey: id)
        }
    }

    public func dispose() {
        for (_, l) in lenses { l.setTransmission(1.0); l.dispose() }
        lenses.removeAll()
    }
}
