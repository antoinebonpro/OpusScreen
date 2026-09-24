import Foundation
import AppKit
import CoreGraphics

/// Chef d'orchestre. Traduit une consigne en actions coordonnees sur quatre etages,
/// ecran par ecran :
///
///     retroeclairage materiel -> table de couleurs -> matrice de couleur -> voile
///
/// Les modules en dessous ne se connaissent pas entre eux ; c'est ici, et seulement
/// ici, qu'ils sont assembles. L'interface, elle, ne parle qu'a cette classe.
///
/// Sur Windows, trois des quatre etages seulement etaient reglables ecran par
/// ecran : la matrice de couleur passait par une API qui n'exposait qu'un effet
/// pour tout le bureau. Ici les quatre le sont, puisque la matrice est appliquee
/// par une passe de rendu propre a chaque ecran. Le reglage « ecran de reference »
/// demeure, mais il devient un CHOIX - certaines personnes veulent un filtre
/// unique - la ou il etait une contrainte.
public final class DisplayController {

    private let settings: Settings
    private let overlays = OverlaySet()
    private var monitorList: [MonitorInfo] = []

    // Transition douce : on garde ce qui est affiche et ce que l'on vise.
    private var displayed: [String: Profile] = [:]
    private var fadeTimer: Timer?
    private var fadeStart = Date()
    private var fadeFrom: [String: Profile] = [:]
    private var fadeTo: [String: Profile] = [:]

    // Diagnostics accumules sur une passe complete, jamais sur le dernier ecran vu.
    private var passClip = false
    private var passClamped = false

    public private(set) var gammaClamped = false
    public private(set) var clipping = false
    public private(set) var colorMatrixFailed = false
    public var hardwareStatus = "non teste"

    /// Vrai quand tout effet est suspendu (pause, plein ecran, regle d'application).
    public private(set) var suspended = false
    public private(set) var suspendReason = ""

    /// Vrai quand le seul voile est retire, les autres etages restant en place.
    public private(set) var overlayHeld = false
    public private(set) var overlayHoldReason = ""

    /// Mode a blanc, pour les tests : tout est calcule, rien n'est pose.
    /// Un test qui clique au hasard ne doit jamais toucher a la table de couleurs,
    /// au voile, a la matrice ni au retroeclairage de la machine qui l'execute.
    public static var dryRun = false

    public init(_ settings: Settings) {
        self.settings = settings
        refreshMonitors()
    }

    public var monitors: [MonitorInfo] { monitorList }

    public func refreshMonitors() {
        monitorList = MonitorEnum.all()
        overlays.pruneMissing(monitorList)
        DisplayConfig.invalidateCache()

        for m in monitorList {
            let ms = settings.forMonitor(m)
            ms.friendlyName = m.friendlyName   // le nom peut changer au rebranchement
        }

        // Un ecran debranche laissait derriere lui son dernier etat affiche, ce qui
        // suffisait a faire croire qu'un effet restait actif alors que plus rien
        // n'etait pose.
        let alive = Set(monitorList.map { $0.stableId })
        for id in displayed.keys where !alive.contains(id) { displayed.removeValue(forKey: id) }
    }

    // ------------------------------------------------------------------ suspension

    public func suspend(_ reason: String) {
        if suspended && suspendReason == reason { return }
        suspended = true
        suspendReason = reason
        applyNow(fromSuspend: true)
    }

    public func resume() {
        guard suspended else { return }
        suspended = false
        suspendReason = ""
        apply()
    }

    /// Retire le voile sans toucher aux autres etages.
    public func holdOverlay(_ reason: String) {
        if overlayHeld && overlayHoldReason == reason { return }
        overlayHeld = true
        overlayHoldReason = reason
        applyNow(fromSuspend: false)
    }

    public func releaseOverlay() {
        guard overlayHeld else { return }
        overlayHeld = false
        overlayHoldReason = ""
        apply()
    }

    // ------------------------------------------------------------------ application

    /// Applique l'etat courant, avec fondu si l'option est active.
    public func apply() {
        syncFollowers()

        if !settings.smoothTransitions || settings.transitionSpeedMs < 60 {
            applyNow(fromSuspend: false)
            return
        }

        fadeFrom.removeAll()
        fadeTo.removeAll()
        var anyChange = false

        for m in monitorList {
            let target = resolveTarget(m)
            let from = displayed[m.stableId] ?? target.clone()

            fadeFrom[m.stableId] = from.clone()
            fadeTo[m.stableId] = target.clone()
            if !DisplayController.same(from, target) { anyChange = true }
        }

        if !anyChange { applyNow(fromSuspend: false); return }

        fadeStart = Date()
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.onFadeTick()
        }
        RunLoop.main.add(fadeTimer!, forMode: .common)
    }

    private func onFadeTick() {
        let elapsed = Date().timeIntervalSince(fadeStart) * 1000.0
        var t = elapsed / Double(max(60, settings.transitionSpeedMs))
        if t >= 1.0 {
            t = 1.0
            fadeTimer?.invalidate()
            fadeTimer = nil
        }

        // Adoucissement en cosinus : demarrage et arrivee sans a-coup.
        let eased = 0.5 - 0.5 * cos(Double.pi * t)

        beginPass()
        for m in monitorList {
            guard let a = fadeFrom[m.stableId], let b = fadeTo[m.stableId] else { continue }
            applyToMonitor(m, DisplayController.lerp(a, b, eased))
        }
        endPass()

        if t >= 1.0 { finishApply() }
    }

    /// Repercute le reglage general sur les ecrans qui le suivent, avant de
    /// resoudre quoi que ce soit.
    ///
    /// Ce point de passage est unique et volontairement place ici : toute
    /// commande generale - un mode, un curseur, un raccourci, l'horaire,
    /// l'adaptation au contenu - finit par demander une application, et aucune
    /// ne peut donc oublier de faire suivre les ecrans. Les reglages pris ecran
    /// par ecran, eux, ne touchent pas au profil general : ils traversent ce
    /// point sans rien y declencher.
    private func syncFollowers() {
        settings.syncFollowingScreens()
    }

    /// Applique immediatement, sans fondu.
    public func applyNow(fromSuspend: Bool) {
        syncFollowers()
        fadeTimer?.invalidate()
        fadeTimer = nil
        beginPass()
        for m in monitorList { applyToMonitor(m, resolveTarget(m)) }
        endPass()
        finishApply()
    }

    /// Les indicateurs d'ecretage et de bridage decrivent une CONFIGURATION, pas un
    /// ecran : ils sont donc remis a zero avant chaque passe puis cumules sur tous
    /// les ecrans. Sans cela, le dernier ecran parcouru effacait le diagnostic du
    /// premier - et sur deux ecrans, l'avertissement disparaissait une fois sur deux.
    private func beginPass() {
        passClip = false
        passClamped = false
    }

    private func endPass() {
        clipping = passClip
        gammaClamped = passClamped
    }

    private func finishApply() {
        if DisplayController.dryRun { return }

        applyColorMatrix()

        var anythingActive = displayed.values.contains { !$0.isNeutral() }
        for m in monitorList where settings.forMonitor(m).blackout { anythingActive = true }

        if anythingActive { SafetyGuard.markDirty() } else { SafetyGuard.clearDirtyFlag() }
    }

    /// Quatrieme etage. Une matrice par ecran, ou une seule pour tous selon le
    /// reglage - et c'est bien un reglage, pas une limite de l'API.
    private func applyColorMatrix() {
        guard settings.useColorMatrix else {
            ColorMatrixEffect.reset()
            colorMatrixFailed = false
            return
        }

        var wanted: [CGDirectDisplayID: [Float]] = [:]
        var anyWanted = false

        if settings.matrixPerScreen {
            for m in monitorList {
                let p = resolveTarget(m)
                wanted[m.displayID] = p.buildMatrix()
                if !ColorMatrixEffect.isNeutralRequest(p.saturation, p.filter, p.visionSeverity,
                                                       p.filterStrength, p.mode) { anyWanted = true }
            }
        } else {
            let reference = matrixProfile()
            let m = reference.buildMatrix()
            for monitor in monitorList { wanted[monitor.displayID] = m }
            anyWanted = !ColorMatrixEffect.isNeutralRequest(reference.saturation, reference.filter,
                                                            reference.visionSeverity,
                                                            reference.filterStrength, reference.mode)
        }

        let ok = ScreenFilter.shared.setMatrices(wanted)
        colorMatrixFailed = !ok && anyWanted
    }

    /// Ce que cet ecran doit afficher, tout compris.
    private func resolveTarget(_ m: MonitorInfo) -> Profile {
        let ms = settings.forMonitor(m)

        if suspended || !ms.enabled { return Profile() }   // profil neutre
        if ms.blackout {
            var black = Profile()
            black.brightness = GammaEngine.minBrightness
            black.tint = .black
            return black
        }
        return settings.effectiveFor(m)
    }

    /// L'ecran dont les reglages de couleur pilotent la matrice partagee.
    public func matrixSourceMonitor() -> MonitorInfo? {
        if !settings.matrixSourceId.isEmpty {
            for m in monitorList where m.stableId == settings.matrixSourceId { return m }
        }
        for m in monitorList where m.isPrimary { return m }
        return monitorList.first
    }

    private func matrixProfile() -> Profile {
        guard let m = matrixSourceMonitor() else { return Profile() }
        return resolveTarget(m)
    }

    private func applyToMonitor(_ m: MonitorInfo, _ p: Profile) {
        let ms = settings.forMonitor(m)

        let plan = GammaEngine.plan(
            p.brightness,
            allowOverlay: settings.useOverlay && !overlayHeld,
            allowHardware: settings.useHardwareBacklight && !suspended)

        passClip = passClip || plan.clips

        if DisplayController.dryRun { displayed[m.stableId] = p.clone(); return }

        // Consigne NOMINATIVE. Un niveau global envoye depuis une boucle par ecran
        // ferait imposer au dernier ecran traite sa luminosite materielle a tous.
        if plan.hardwareTarget >= 0 {
            HardwareBacklight.requestLevel(m, plan.hardwareTarget)
        }

        let ramp = GammaEngine.buildRamp(plan, p)
        let r = GammaEngine.apply(m, ramp)
        if r.success && r.clamped { passClamped = true }

        // Le mode « ecran eteint » pousse le voile bien au-dela du plan normal.
        let transmission = (ms.blackout && !suspended && !overlayHeld) ? 0.02 : plan.overlayTransmission
        overlays.update(m, transmission: transmission, tint: p.tint)

        displayed[m.stableId] = p.clone()
    }

    // ------------------------------------------------------------------ interpolation

    private static func lerp(_ a: Profile, _ b: Profile, _ t: Double) -> Profile {
        var p = Profile()
        p.name = b.name
        p.brightness = a.brightness + (b.brightness - a.brightness) * t
        p.kelvin = Int((Double(a.kelvin) + (Double(b.kelvin) - Double(a.kelvin)) * t).rounded())
        p.contrast = a.contrast + (b.contrast - a.contrast) * t
        p.gammaCurve = a.gammaCurve + (b.gammaCurve - a.gammaCurve) * t
        p.redGain = a.redGain + (b.redGain - a.redGain) * t
        p.greenGain = a.greenGain + (b.greenGain - a.greenGain) * t
        p.blueGain = a.blueGain + (b.blueGain - a.blueGain) * t
        p.saturation = a.saturation + (b.saturation - a.saturation) * t
        p.visionSeverity = a.visionSeverity + (b.visionSeverity - a.visionSeverity) * t
        p.filterStrength = a.filterStrength + (b.filterStrength - a.filterStrength) * t
        // Le filtre ne s'interpole pas : il bascule a mi-parcours.
        p.filter = t < 0.5 ? a.filter : b.filter
        p.mode = t < 0.5 ? a.mode : b.mode
        p.tint = t < 0.5 ? a.tint : b.tint
        return p
    }

    private static func same(_ a: Profile, _ b: Profile) -> Bool {
        abs(a.brightness - b.brightness) < 0.01
            && a.kelvin == b.kelvin
            && abs(a.contrast - b.contrast) < 0.01
            && abs(a.gammaCurve - b.gammaCurve) < 0.01
            && abs(a.redGain - b.redGain) < 0.01
            && abs(a.greenGain - b.greenGain) < 0.01
            && abs(a.blueGain - b.blueGain) < 0.01
            && abs(a.saturation - b.saturation) < 0.01
            && abs(a.visionSeverity - b.visionSeverity) < 0.01
            && abs(a.filterStrength - b.filterStrength) < 0.01
            && a.filter == b.filter && a.mode == b.mode && a.tint == b.tint
    }

    // ------------------------------------------------------------------ restauration

    public func restoreAll() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        if DisplayController.dryRun { displayed.removeAll(); return }
        overlays.hideAll()
        ColorMatrixEffect.reset()
        for m in monitorList { GammaEngine.resetToIdentity(m) }
        displayed.removeAll()
        clipping = false
        gammaClamped = false
        SafetyGuard.clearDirtyFlag()
    }

    /// Reapplique si un autre programme a ecrase notre table de couleurs.
    ///
    /// macOS la remet aussi de lui-meme dans plusieurs cas : sortie de veille,
    /// changement de resolution, verrouillage de session. Cette passe reguliere
    /// est donc plus qu'une precaution contre la concurrence.
    public func reapplyIfNeeded() {
        if fadeTimer != nil { return }
        syncFollowers()
        beginPass()
        var touched = false
        for m in monitorList {
            let p = resolveTarget(m)
            if p.isNeutral() && !settings.forMonitor(m).blackout { continue }
            applyToMonitor(m, p)
            touched = true
        }
        if touched { endPass() }
    }

    // ------------------------------------------------------------------ diagnostics

    /// Explique en une ligne ce que fait le reglage courant.
    public func describeCurrentPlan() -> String {
        if suspended { return "suspendu - " + suspendReason }

        let p = matrixProfile()
        let plan = GammaEngine.plan(p.brightness,
                                    allowOverlay: settings.useOverlay && !overlayHeld,
                                    allowHardware: settings.useHardwareBacklight)

        var parts: [String] = []
        if plan.hardwareTarget >= 0 { parts.append("retroeclairage au maximum") }
        if abs(plan.gammaExponent - 1.0) > 0.001 {
            parts.append(String(format: "courbe gamma %.2f", plan.gammaExponent))
        }
        if abs(plan.linearGain - 1.0) > 0.001 {
            parts.append(String(format: "gain %.2fx", plan.linearGain))
        }
        if plan.overlayTransmission < 1.0 {
            parts.append("voile \(Int(((1 - plan.overlayTransmission) * 100).rounded())) %")
        }
        if !ColorMatrixEffect.isNeutralRequest(p.saturation, p.filter, p.visionSeverity,
                                               p.filterStrength, p.mode) {
            parts.append("matrice de couleur")
        }

        if overlayHeld { parts.append("voile retire - " + overlayHoldReason) }

        if parts.isEmpty { return "ecran normal, aucune modification" }
        return parts.joined(separator: " + ")
    }

    public func anyGammaSupport() -> Bool {
        monitorList.contains { GammaEngine.supportsGamma($0) }
    }

    public func dispose() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        restoreAll()
        overlays.dispose()
        ScreenMagnifier.stop()
        ColorMatrixEffect.shutdown()
    }
}
