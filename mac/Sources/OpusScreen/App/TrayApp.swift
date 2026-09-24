import Foundation
import AppKit
import IOKit.ps

/// Coordonne l'ensemble : icone de la barre des menus, menu, raccourcis, horloge,
/// adaptation au contenu, regles par application, pauses et evenements systeme.
///
/// Toute la logique de rendu vit dans `DisplayController` ; ici on decide seulement
/// QUAND appliquer, et avec quelles valeurs.
public final class TrayApp: NSObject, NSMenuDelegate {

    private let settings: Settings
    private let display: DisplayController

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var slowTick: Timer?
    private var fastTick: Timer?

    private let adaptive = ContentAdaptive()
    private let watcher = AppWatcher()
    private let breaks = BreakReminder()
    private let reader = ColorReader()
    private let beacon = CursorBeacon()
    private let hotkeys = Hotkeys()

    private var panel: ControlPanel?
    private var pauseUntil: Date?
    private var appliedRule = ""

    /// Derniere correction de vision utilisee, pour que le raccourci de bascule
    /// puisse la retablir. Sans memoire, eteindre puis rallumer ferait perdre le
    /// reglage - et il n'y a aucune raison de demander a quelqu'un de re-choisir
    /// sa propre deficience a chaque fois.
    private var lastVisionFilter: ColorFilter = .none

    private static let steps: [Double] = [150, 140, 130, 120, 110, 100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 5]

    // ------------------------------------------------------------------ cycle de vie

    public init(_ settings: Settings, _ display: DisplayController, _ args: [String]) {
        self.settings = settings
        self.display = display
        super.init()

        buildStatusItem()
        menu.delegate = self

        hookSystemEvents()
        rebindHotkeys()

        PanicKey.shared.onTriggered = { [weak self] in self?.onPanic() }
        PanicKey.shared.start()

        adaptive.suggestedBrightness = { [weak self] value in
            DispatchQueue.main.async { self?.applyAdaptive(value) }
        }
        watcher.foregroundChanged = { [weak self] process in self?.onForegroundChanged(process) }
        watcher.fullscreenChanged = { [weak self] _ in
            self?.applyFullscreenPolicy()
            self?.updateIcon()
        }
        breaks.breakStateChanged = { [weak self] inBreak in self?.onBreakState(inBreak) }

        slowTick = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.onSlowTick()
        }
        fastTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.watcher.poll()
            self.checkPauseExpiry()
            self.checkPendingCommand()
        }
        RunLoop.main.add(slowTick!, forMode: .common)
        RunLoop.main.add(fastTick!, forMode: .common)

        Updater.checkRequested = { [weak self] in self?.checkForUpdates(manual: true) }
        Updater.lastStatus = settings.checkUpdates
            ? (settings.lastUpdateCheck == .distantPast ? "Premiere verification dans une minute." : "")
            : "Verification desactivee."

        syncEnginesFromSettings()
        applyAll()

        if Updater.wasJustUpdated(args) {
            Notice.show("OpusScreen est a jour",
                        "Version \(Installer.currentVersionShort) installee. Vos reglages sont conserves.")
        }

        // Le panneau s'ouvre au tout premier lancement - sinon rien ne semble se
        // passer - puis seulement si l'utilisateur n'a pas demande le contraire.
        // --show passe outre : c'est une demande explicite de la fenetre.
        let quiet = (CommandLineDriver.startMinimized(args) || CommandLineDriver.hasCommand(args))
                    && !CommandLineDriver.wantsShow(args)
        if !quiet && (settings.isFirstRun || !settings.startMinimized || CommandLineDriver.wantsShow(args)) {
            showPanel()
        }

        // Aucune boite modale ici : voir `Installer.offerToInstall`. Une
        // banniere qui s'efface toute seule dit ce qu'il y a a dire sans
        // immobiliser l'application derriere une question.
        if settings.isFirstRun && Installer.shouldOfferToInstall {
            Notice.show("OpusScreen n'est pas range",
                        "Il tourne depuis un dossier de passage. La page Decouvrir propose "
                      + "de le deplacer dans Applications.")
        }
    }

    // ------------------------------------------------------------------ icone

    private func buildStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(onStatusClick)
        // La molette n'atteint pas un element de barre des menus par defaut :
        // il faut la demander explicitement, sans quoi le geste le plus utile de
        // l'application - monter et baisser la lumiere sans rien ouvrir - n'existe
        // pas sur macOS.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp, .scrollWheel])
        updateIcon()
    }

    @objc private func onStatusClick() {
        guard let event = NSApp.currentEvent else { openMenu(); return }

        switch event.type {
        case .scrollWheel:
            guard settings.trayWheelControl else { return }
            let delta = event.scrollingDeltaY
            guard abs(delta) > 0.1 else { return }
            nudgeBrightness(delta > 0 ? 5 : -5)

        case .rightMouseUp:
            openMenu()

        default:
            // ⌥ clic ouvre directement les reglages : c'est le geste des habitues,
            // et il evite de traverser le menu pour la seule chose qu'ils veulent.
            if event.modifierFlags.contains(.option) { showPanel() } else { openMenu() }
        }
    }

    private func openMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Rendu tout de suite : sans cela le bouton n'emet plus d'action et la
        // molette cesserait de fonctionner des le premier passage par le menu.
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    /// Icone redessinee a chaque changement : sa couleur suit la temperature, son
    /// remplissage la luminosite. L'etat se lit sans ouvrir quoi que ce soit.
    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let image = TrayGlyph.draw(size: 18, profile: settings.current,
                                   suspended: display.suspended, adaptive: settings.adaptiveEnabled)
        // `isTemplate` mettrait l'icone en monochrome : c'est la convention macOS,
        // et c'est precisement ce qu'il ne faut pas ici - la couleur de la pupille
        // EST l'information.
        image.isTemplate = false
        button.image = image

        button.title = settings.showTrayPercentage && !display.suspended
            ? " \(Int(settings.current.brightness.rounded())) %"
            : ""
        button.font = Theme.small

        button.toolTip = display.suspended
            ? "OpusScreen - suspendu"
            : "OpusScreen - \(Int(settings.current.brightness.rounded())) % - \(settings.current.kelvin) K"
    }

    // ------------------------------------------------------------------ menu

    public func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: display.suspended
            ? "OpusScreen - suspendu"
            : "OpusScreen - \(Int(settings.current.brightness.rounded())) % - \(settings.current.kelvin) K",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if let info = availableUpdate {
            let item = NSMenuItem(title: "Installer la version \(info.shortVersion)...",
                                  action: #selector(onInstallUpdate), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        // --- modes ---
        let modes = NSMenuItem(title: "Modes", action: nil, keyEquivalent: "")
        let modesMenu = NSMenu()
        var all = Profile.builtInModes()
        all.append(contentsOf: settings.customProfiles)
        for (i, p) in all.enumerated() {
            let item = NSMenuItem(title: p.name + "   " + p.summary(),
                                  action: #selector(onPickMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = p.name == settings.activeModeName ? .on : .off
            modesMenu.addItem(item)
        }
        modes.submenu = modesMenu
        menu.addItem(modes)

        // --- luminosite ---
        let levels = NSMenuItem(title: "Luminosite", action: nil, keyEquivalent: "")
        let levelsMenu = NSMenu()
        for step in TrayApp.steps {
            let label = step == 150 ? "150 %  (boost maximum)"
                      : step == 100 ? "100 %  (normal)"
                      : step == 5 ? "5 %  (minimum)"
                      : "\(Int(step)) %"
            let item = NSMenuItem(title: label, action: #selector(onPickBrightness(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(step)
            item.state = abs(step - settings.current.brightness) < 0.5 ? .on : .off
            levelsMenu.addItem(item)
        }
        levels.submenu = levelsMenu
        menu.addItem(levels)

        // --- ecrans ---
        let screens = NSMenuItem(title: "Ecrans", action: nil, keyEquivalent: "")
        screens.submenu = buildScreenSubmenu()
        menu.addItem(screens)

        // --- vision ---
        let vision = NSMenuItem(title: "Vision", action: nil, keyEquivalent: "")
        vision.submenu = buildVisionSubmenu()
        menu.addItem(vision)

        menu.addItem(.separator())

        let adaptiveItem = NSMenuItem(title: "Suivre le contenu affiche",
                                      action: #selector(onToggleAdaptive), keyEquivalent: "")
        adaptiveItem.target = self
        adaptiveItem.state = settings.adaptiveEnabled ? .on : .off
        menu.addItem(adaptiveItem)

        let solar = NSMenuItem(title: "Suivre le soleil", action: #selector(onToggleSolar), keyEquivalent: "")
        solar.target = self
        solar.state = settings.schedule != .manual ? .on : .off
        menu.addItem(solar)

        // --- suspension ---
        if display.suspended {
            let resume = NSMenuItem(title: "Reprendre", action: #selector(onResume), keyEquivalent: "")
            resume.target = self
            menu.addItem(resume)
        } else {
            let pause = NSMenuItem(title: "Suspendre", action: nil, keyEquivalent: "")
            let pauseMenu = NSMenu()
            for (label, minutes) in [("30 minutes", 30), ("1 heure", 60), ("Jusqu'a nouvel ordre", -1)] {
                let item = NSMenuItem(title: label, action: #selector(onPause(_:)), keyEquivalent: "")
                item.target = self
                item.tag = minutes
                pauseMenu.addItem(item)
            }
            pause.submenu = pauseMenu
            menu.addItem(pause)
        }

        let breakItem = NSMenuItem(title: "Pause pour les yeux", action: #selector(onBreakNow), keyEquivalent: "")
        breakItem.target = self
        menu.addItem(breakItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Reglages...", action: #selector(onShowPanel), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let reset = NSMenuItem(title: "Tout reinitialiser   ⌃⌥⇧R",
                               action: #selector(onResetEverything), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        let quit = NSMenuItem(title: "Quitter OpusScreen", action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func buildScreenSubmenu() -> NSMenu {
        let sub = NSMenu()
        display.refreshMonitors()

        for (i, m) in display.monitors.enumerated() {
            let ms = settings.forMonitor(m)

            let item = NSMenuItem(title: m.label, action: #selector(onToggleScreen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = ms.enabled ? .on : .off
            sub.addItem(item)

            let black = NSMenuItem(title: "     Eteindre cet ecran",
                                   action: #selector(onToggleBlackout(_:)), keyEquivalent: "")
            black.target = self
            black.tag = i
            black.state = ms.blackout ? .on : .off
            sub.addItem(black)
        }
        return sub
    }

    /// Les aides a la vision atteignables sans ouvrir la fenetre.
    ///
    /// Une aide qui demande d'ouvrir un panneau de reglages n'est pas une aide :
    /// la loupe et l'identificateur de couleur servent justement dans les moments
    /// ou l'on n'arrive plus a lire l'ecran.
    private func buildVisionSubmenu() -> NSMenu {
        let sub = NSMenu()

        let none = NSMenuItem(title: "Aucune correction", action: #selector(onVisionNone), keyEquivalent: "")
        none.target = self
        none.state = ColorMatrixEffect.isVisionFilter(settings.current.filter) ? .off : .on
        sub.addItem(none)

        let kinds: [ColorFilter] = [.protanopia, .deuteranopia, .tritanopia]
        for (i, k) in kinds.enumerated() {
            let item = NSMenuItem(title: Vision.plainName(k) + "   (" + Profile.filterName(k) + ")",
                                  action: #selector(onVisionPick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = settings.current.filter == k ? .on : .off
            sub.addItem(item)
        }

        sub.addItem(.separator())

        let mag = NSMenuItem(title: "Loupe plein ecran", action: #selector(onToggleMagnifier), keyEquivalent: "")
        mag.target = self
        mag.state = settings.magnifierEnabled ? .on : .off
        sub.addItem(mag)

        let ring = NSMenuItem(title: "Anneau autour du pointeur", action: #selector(onToggleBeacon), keyEquivalent: "")
        ring.target = self
        ring.state = settings.beaconEnabled ? .on : .off
        sub.addItem(ring)

        let readerItem = NSMenuItem(title: "Identifier les couleurs", action: #selector(onToggleReader), keyEquivalent: "")
        readerItem.target = self
        readerItem.state = settings.colorReaderEnabled ? .on : .off
        sub.addItem(readerItem)

        sub.addItem(.separator())

        let more = NSMenuItem(title: "Reglages du daltonisme...", action: #selector(onShowColorBlind), keyEquivalent: "")
        more.target = self
        sub.addItem(more)

        return sub
    }

    // ------------------------------------------------------------------ actions du menu

    @objc private func onPickMode(_ sender: NSMenuItem) {
        var all = Profile.builtInModes()
        all.append(contentsOf: settings.customProfiles)
        guard sender.tag >= 0, sender.tag < all.count else { return }
        applyMode(all[sender.tag])
    }

    @objc private func onPickBrightness(_ sender: NSMenuItem) { setBrightness(Double(sender.tag)) }

    @objc private func onToggleScreen(_ sender: NSMenuItem) {
        guard sender.tag < display.monitors.count else { return }
        let ms = settings.forMonitor(display.monitors[sender.tag])
        ms.enabled.toggle()
        settings.save()
        applyAll()
    }

    @objc private func onToggleBlackout(_ sender: NSMenuItem) {
        guard sender.tag < display.monitors.count else { return }
        let ms = settings.forMonitor(display.monitors[sender.tag])
        ms.blackout.toggle()
        settings.save()
        applyAll()
    }

    @objc private func onVisionNone() {
        guard ColorMatrixEffect.isVisionFilter(settings.current.filter) else { return }
        lastVisionFilter = settings.current.filter
        settings.current.filter = .none
        settings.save()
        applyAll()
        panel?.syncAll()
    }

    @objc private func onVisionPick(_ sender: NSMenuItem) {
        let kinds: [ColorFilter] = [.protanopia, .deuteranopia, .tritanopia]
        guard sender.tag >= 0, sender.tag < kinds.count else { return }
        settings.current.filter = kinds[sender.tag]
        lastVisionFilter = kinds[sender.tag]
        settings.save()
        applyAll()
        panel?.syncAll()
    }

    @objc private func onToggleAdaptive() { toggleAdaptive() }

    @objc private func onToggleSolar() {
        settings.schedule = settings.schedule == .manual ? .solar : .manual
        settings.save()
        applyAll()
        panel?.syncAll()
    }

    @objc private func onPause(_ sender: NSMenuItem) {
        pauseFor(minutes: sender.tag)
    }

    @objc private func onResume() { resumeEffects() }
    @objc private func onBreakNow() { breaks.triggerBreak() }
    @objc private func onShowPanel() { showPanel() }
    @objc private func onResetEverything() { resetEverything() }
    @objc private func onQuit() { exitCleanly() }
    @objc private func onToggleMagnifier() { toggleMagnifier() }
    @objc private func onToggleBeacon() { toggleBeacon() }
    @objc private func onToggleReader() { toggleColorReader() }

    @objc private func onShowColorBlind() {
        showPanel()
        panel?.selectPage(panel?.colorBlindPageIndex ?? 0)
    }

    @objc private func onInstallUpdate() { promptUpdate() }

    // ------------------------------------------------------------------ actions

    public func applyMode(_ p: Profile) {
        settings.current.copyFrom(p)
        settings.activeModeName = p.name
        settings.save()
        applyAll()
        panel?.syncAll()
    }

    public func setBrightness(_ value: Double) {
        settings.current.brightness = SafetyGuard.clampBrightness(value)
        settings.save()
        applyAll()
    }

    public func nudgeBrightness(_ delta: Double) {
        setBrightness(settings.current.brightness + delta)
    }

    public func nudgeTemperature(_ delta: Int) {
        guard settings.schedule == .manual else { return }
        settings.current.kelvin = max(ColorTemp.minKelvin,
                                      min(ColorTemp.maxKelvin, settings.current.kelvin + delta))
        settings.save()
        applyAll()
    }

    public func nextMode() {
        var all = Profile.builtInModes()
        all.append(contentsOf: settings.customProfiles)
        guard !all.isEmpty else { return }
        let index = all.firstIndex { $0.name == settings.activeModeName } ?? 0
        applyMode(all[(index + 1) % all.count])
    }

    public func toggleAdaptive() {
        settings.adaptiveEnabled.toggle()
        settings.save()
        syncEnginesFromSettings()
        applyAll()
        panel?.syncAll()
    }

    public func pauseFor(minutes: Int) {
        if minutes < 0 {
            pauseUntil = Date.distantFuture
            display.suspend("en pause")
        } else {
            let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
            pauseUntil = until
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            display.suspend("en pause jusqu'a " + formatter.string(from: until))
        }
        updateIcon()
        panel?.refreshReadouts()
    }

    public func resumeEffects() {
        pauseUntil = nil
        display.resume()
        updateIcon()
        panel?.refreshReadouts()
    }

    public func togglePause() {
        if display.suspended { resumeEffects() } else { pauseFor(minutes: -1) }
    }

    private func checkPauseExpiry() {
        guard let until = pauseUntil, until != .distantFuture else { return }
        if Date() >= until { resumeEffects() }
    }

    public func resetEverything() {
        pauseUntil = nil
        settings.current = Profile()
        settings.activeModeName = "Normal"
        settings.schedule = .manual
        settings.adaptiveEnabled = false
        for ms in settings.monitors { ms.blackout = false; ms.enabled = true }
        display.resume()
        display.restoreAll()
        settings.save()
        syncEnginesFromSettings()
        applyAll()
        panel?.syncAll()
    }

    /// Applique l'etat courant apres avoir laisse les automatismes s'exprimer.
    public func applyAll() {
        applyFullscreenPolicy()

        if !display.suspended {
            let sched = Scheduler.evaluate(settings, Date())
            if settings.schedule != .manual {
                settings.current.kelvin = sched.kelvin
                // L'adaptation au contenu, plus reactive, garde la main sur la luminosite.
                if sched.brightnessApplies && !settings.adaptiveEnabled {
                    settings.current.brightness = SafetyGuard.clampBrightness(sched.brightness)
                }
            }
        }

        display.apply()
        updateIcon()
        panel?.refreshReadouts()
    }

    private func syncEnginesFromSettings() {
        adaptive.minBrightness = settings.adaptiveMin
        adaptive.maxBrightness = settings.adaptiveMax
        adaptive.reactivity = settings.adaptiveReactivity
        adaptive.intervalMs = settings.adaptiveIntervalMs

        if settings.adaptiveEnabled && !adaptive.isRunning { adaptive.start() }
        else if !settings.adaptiveEnabled && adaptive.isRunning { adaptive.stop() }

        breaks.enabled = settings.breaksEnabled
        breaks.intervalMinutes = max(1, settings.breakIntervalMinutes)
        breaks.durationSeconds = max(5, settings.breakDurationSeconds)
        breaks.dimDuringBreak = settings.breakDim
        breaks.playSound = settings.breakSound
        breaks.blinkReminders = settings.blinkReminders
        breaks.blinkIntervalMinutes = max(1, settings.blinkIntervalMinutes)

        syncVisionAids()
    }

    /// Met les aides a la vision en accord avec les reglages.
    ///
    /// Chaque aide est isolee : une loupe refusee par le systeme ne doit pas
    /// empecher l'anneau de s'afficher, et une erreur sur l'une ne doit jamais
    /// laisser les autres dans un etat indetermine.
    public func syncVisionAids() {
        beacon.size = settings.beaconSize
        beacon.color = settings.beaconColor
        beacon.opacity = settings.beaconOpacity
        beacon.setVisible(settings.beaconEnabled)

        if settings.colorReaderEnabled { reader.show() } else { reader.hide() }

        if settings.magnifierEnabled {
            // Un refus du systeme est enregistre dans les reglages : sans cela
            // l'interrupteur resterait allume devant un ecran inchange.
            if !ScreenMagnifier.setZoom(settings.magnifierZoom) { settings.magnifierEnabled = false }
        } else {
            ScreenMagnifier.stop()
        }
    }

    // ------------------------------------------------------------------ aides a la vision

    /// Allume ou eteint la correction daltonisme, en gardant le type choisi.
    public func toggleVisionCorrection() {
        if ColorMatrixEffect.isVisionFilter(settings.current.filter) {
            lastVisionFilter = settings.current.filter
            settings.current.filter = .none
        } else {
            // Premiere utilisation sans reglage prealable : la deuteranomalie est
            // de loin la forme la plus repandue, c'est le point de depart le moins
            // mauvais - et la page Daltonisme permet d'en changer en un clic.
            settings.current.filter = lastVisionFilter != .none ? lastVisionFilter : .deuteranopia
        }
        settings.save()
        applyAll()
        panel?.syncAll()
    }

    public func toggleColorReader() {
        settings.colorReaderEnabled.toggle()
        settings.save()
        syncVisionAids()
        panel?.refreshReadouts()
    }

    public func toggleMagnifier() {
        settings.magnifierEnabled.toggle()
        syncVisionAids()
        settings.save()
        panel?.refreshReadouts()
    }

    public func toggleBeacon() {
        settings.beaconEnabled.toggle()
        settings.save()
        syncVisionAids()
        panel?.refreshReadouts()
    }

    @discardableResult
    public func copyColorUnderCursor() -> String {
        reader.copyColorUnderCursor()
    }

    // ------------------------------------------------------------------ automatismes

    private func applyAdaptive(_ suggested: Double) {
        guard settings.adaptiveEnabled, !display.suspended else { return }
        guard abs(settings.current.brightness - suggested) >= 0.4 else { return }
        settings.current.brightness = SafetyGuard.clampBrightness(suggested)
        display.apply()
        updateIcon()
    }

    private func onForegroundChanged(_ process: String) {
        guard settings.appRulesEnabled, !process.isEmpty else { return }
        if process == (Bundle.main.bundleIdentifier ?? "").lowercased() { return }

        guard let match = settings.appRules.first(where: { $0.processName == process }) else {
            if !appliedRule.isEmpty {
                appliedRule = ""
                if display.suspended && display.suspendReason.hasPrefix("regle") { display.resume() }
                applyAll()
            }
            return
        }

        appliedRule = process

        if match.disable {
            display.suspend("regle pour " + process)
            updateIcon()
            return
        }

        if display.suspended && display.suspendReason.hasPrefix("regle") { display.resume() }

        var all = Profile.builtInModes()
        all.append(contentsOf: settings.customProfiles)
        if let p = all.first(where: { $0.name == match.profileName }) { applyMode(p) }
    }

    private static let fullscreenReason = "application en plein ecran"

    /// Traduit le reglage de plein ecran en actions sur les etages concernes.
    ///
    /// Idempotente, et rejouee a chaque application des reglages : entrer en plein
    /// ecran et changer le reglage sont deux chemins vers le meme etat, et aucun ne
    /// doit laisser trainer la decision de l'autre.
    ///
    /// Une suspension posee pour une autre raison - pause manuelle, pause oculaire,
    /// regle d'application - n'est jamais reecrite : elle est plus explicite que
    /// celle-ci, et sa raison sert a savoir qui devra la lever.
    private func applyFullscreenPolicy() {
        let full = watcher.isFullscreen
        let suspendAll = full && settings.onFullscreen == .everything
        let holdOverlay = full && settings.onFullscreen == .overlayOnly

        if suspendAll {
            if !display.suspended || display.suspendReason == TrayApp.fullscreenReason {
                display.suspend(TrayApp.fullscreenReason)
            }
        } else if display.suspendReason == TrayApp.fullscreenReason {
            display.resume()
        }

        if holdOverlay { display.holdOverlay(TrayApp.fullscreenReason) }
        else if display.overlayHoldReason == TrayApp.fullscreenReason { display.releaseOverlay() }
    }

    private func onBreakState(_ inBreak: Bool) {
        if inBreak { display.suspend("pause en cours") }
        else if display.suspendReason == "pause en cours" { display.resume() }
    }

    private func onSlowTick() {
        if settings.schedule != .manual { applyAll() }
        else { display.reapplyIfNeeded() }

        panel?.refreshReadouts()
        maybeCheckForUpdates()
    }

    /// Applique un ordre depose par un second lancement en ligne de commande.
    ///
    /// Rien n'est consomme tant qu'une boite modale est ouverte : ouvrir une
    /// fenetre par-dessus une question en attente fait disparaitre la question
    /// sans reponse, et l'appelant croit alors qu'on lui en a donne une.
    private func checkPendingCommand() {
        guard NSApp.modalWindow == nil else { return }
        let cmd = CommandLineDriver.consumePending()
        guard !cmd.isEmpty else { return }
        let parts = CommandLineDriver.splitArgs(cmd)

        for a in parts {
            switch a.lowercased() {
            case "--pause": pauseFor(minutes: -1); return
            case "--resume": resumeEffects(); return
            case "--break": breaks.triggerBreak(); return
            case "--show": showPanel(); return
            default: break
            }
        }

        if CommandLineDriver.apply(to: settings, parts) {
            settings.save()
            syncEnginesFromSettings()
            applyAll()
            panel?.syncAll()
        }
    }

    // ------------------------------------------------------------------ raccourcis

    public func rebindHotkeys() {
        hotkeys.unregister()
        guard settings.hotkeysEnabled else { return }
        hotkeys.onAction = { [weak self] action in self?.run(action) }
        hotkeys.register(settings.hotkeys)
    }

    public func run(_ action: String) {
        switch action {
        case "brightness.up": nudgeBrightness(5)
        case "brightness.down": nudgeBrightness(-5)
        case "temp.warmer": nudgeTemperature(-200)
        case "temp.cooler": nudgeTemperature(200)
        case "reset": resetEverything()
        case "pause.toggle": togglePause()
        case "mode.next": nextMode()
        case "adaptive.toggle": toggleAdaptive()
        case "break.now": breaks.triggerBreak()
        case "panel.show": showPanel()
        case "vision.toggle": toggleVisionCorrection()
        case "color.reader": toggleColorReader()
        case "color.copy": copyColorUnderCursor()
        case "magnifier.toggle": toggleMagnifier()
        case "beacon.toggle": toggleBeacon()
        default: break
        }
    }

    // ------------------------------------------------------------------ fenetre

    public func showPanel() {
        if panel == nil {
            let p = ControlPanel(settings, display, { [weak self] in self?.applyAll() })
            p.togglePause = { [weak self] in self?.togglePause() }
            p.autoPage.engine = adaptive
            p.appsPage.watcher = watcher
            p.comfortPage.reminder = breaks
            p.hotkeysPage.rebind = { [weak self] in self?.rebindHotkeys() }
            p.visionPage.aidsChanged = { [weak self] in self?.syncVisionAids() }
            p.colorBlindPage.aidsChanged = { [weak self] in self?.syncVisionAids() }
            p.colorBlindPage.copyColorUnderCursor = { [weak self] in self?.copyColorUnderCursor() ?? "" }
            panel = p
        }
        panel?.show()
    }

    /// Les raccourcis clavier de la fenetre, interceptes avant AppKit.
    public func handlePanelKey(_ event: NSEvent) -> Bool {
        guard let panel = panel, panel.window.isKeyWindow else { return false }
        return panel.handleKey(event)
    }

    // ------------------------------------------------------------------ evenements systeme

    private func hookSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter

        workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                              object: nil, queue: .main) { [weak self] _ in
            // Au reveil, macOS a remis la table de couleurs a l'identite : il faut
            // la reposer.
            self?.applyAll()
        }

        workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                              object: nil, queue: .main) { [weak self] _ in
            self?.applyAll()
        }

        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                              object: nil, queue: .main) { [weak self] _ in
            self?.applyAll()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.display.refreshMonitors()
            ScreenFilter.shared.displaysChanged()
            self.applyAll()
            self.panel?.syncAll()
        }

        // Batterie : sur un portable, le boost au-dessus de 100 % pousse le
        // retroeclairage au maximum et vide l'accumulateur.
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self, self.settings.disableOnBattery else { return }
            if TrayApp.onBattery() && self.settings.current.brightness > 100 {
                self.settings.current.brightness = 100
                self.applyAll()
            }
        }
    }

    static func onBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
            if let state = info[kIOPSPowerSourceStateKey] as? String {
                return state == kIOPSBatteryPowerValue
            }
        }
        return false
    }

    private func onPanic() {
        pauseUntil = nil
        settings.current = Profile()
        settings.activeModeName = "Normal"
        settings.schedule = .manual
        settings.adaptiveEnabled = false
        for ms in settings.monitors { ms.blackout = false; ms.enabled = true }

        // La loupe fait partie de ce dont il faut pouvoir sortir : un bureau
        // agrandi huit fois est aussi difficile a piloter qu'un bureau noir.
        // L'anneau et l'etiquette, eux, ne genent pas et sont laisses en place.
        settings.magnifierEnabled = false

        settings.save()
        syncEnginesFromSettings()
        updateIcon()
        panel?.syncAll()
    }

    // ------------------------------------------------------------------ mises a jour

    private var availableUpdate: UpdateInfo?
    private let startedAt = Date()
    private var lastUpdateAttempt = Date.distantPast
    private var updateBusy = false

    /// Verification quotidienne. Attend une minute apres le demarrage : a
    /// l'ouverture de session, le reseau n'est souvent pas encore la, et
    /// l'application a mieux a faire que de se renseigner sur elle-meme.
    private func maybeCheckForUpdates() {
        guard settings.checkUpdates, !updateBusy else { return }
        let now = Date()
        guard now.timeIntervalSince(startedAt) >= 60 else { return }
        guard now.timeIntervalSince(settings.lastUpdateCheck) >= 24 * 3600 else { return }
        guard now.timeIntervalSince(lastUpdateAttempt) >= 3600 else { return }
        checkForUpdates(manual: false)
    }

    private func checkForUpdates(manual: Bool) {
        guard !updateBusy else { return }
        updateBusy = true
        lastUpdateAttempt = Date()
        Updater.lastStatus = "Verification en cours..."

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var info: UpdateInfo?
            var failure: String?
            do { info = try Updater.fetch() } catch { failure = error.localizedDescription }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateBusy = false

                if let failure = failure {
                    Updater.lastStatus = "Derniere verification impossible : pas de reponse de GitHub."
                    if manual {
                        Alerts.warn("GitHub n'a pas pu etre joint.",
                                    failure + "\n\nVous pouvez verifier a la main : " + Updater.releasesPage)
                    }
                    self.panel?.syncAll()
                    return
                }

                guard let info = info else { return }
                self.settings.lastUpdateCheck = Date()
                self.settings.save()

                if Updater.isNewer(info.version, Installer.currentVersion) {
                    self.availableUpdate = info
                    Updater.lastStatus = "Version \(info.shortVersion) disponible."
                    if manual { self.promptUpdate() }
                    else {
                        Notice.show("OpusScreen \(info.shortVersion) est disponible",
                                    "Ouvrez le menu d'OpusScreen pour l'installer. Vos reglages sont conserves.")
                    }
                } else {
                    self.availableUpdate = nil
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "fr_FR")
                    formatter.dateFormat = "d MMMM 'a' HH:mm"
                    Updater.lastStatus = "A jour. Verifie le " + formatter.string(from: Date()) + "."
                    if manual {
                        Alerts.info("Vous avez la derniere version d'OpusScreen.",
                                    "Version " + Installer.currentVersionShort + ".")
                    }
                }
                self.panel?.syncAll()
            }
        }
    }

    /// Rien ne s'installe sans accord : l'utilisateur est peut-etre au milieu d'une
    /// presentation, et l'application va redemarrer.
    private func promptUpdate() {
        guard let info = availableUpdate, !updateBusy else { return }

        let yes = Alerts.confirm(
            "OpusScreen \(info.shortVersion) est disponible.",
            "Vous avez la version \(Installer.currentVersionShort).\n\n"
          + "L'installer maintenant ? OpusScreen redemarrera en quelques secondes, "
          + "avec tous vos reglages.\n\nNouveautes : "
          + (info.pageUrl.isEmpty ? Updater.releasesPage : info.pageUrl),
            yes: "Installer", no: "Plus tard")
        guard yes else { return }

        updateBusy = true
        Notice.show("Mise a jour d'OpusScreen", "Telechargement de la version \(info.shortVersion)...")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var failure: String?
            do {
                let archive = try Updater.download(info)
                let app = try Updater.unpack(archive)
                DispatchQueue.main.async {
                    do {
                        try Updater.apply(app)
                        self?.exitCleanly()
                    } catch {
                        self?.updateBusy = false
                        Alerts.warn("La mise a jour n'a pas pu se faire.",
                                    error.localizedDescription
                                  + "\n\nOpusScreen continue avec la version actuelle. "
                                  + "Vous pouvez telecharger la nouvelle a la main : "
                                  + Updater.releasesPage)
                    }
                }
                return
            } catch {
                failure = error.localizedDescription
            }

            DispatchQueue.main.async {
                self?.updateBusy = false
                Alerts.warn("La mise a jour n'a pas pu se faire.",
                            (failure ?? "") + "\n\nOpusScreen continue avec la version actuelle.")
            }
        }
    }

    // ------------------------------------------------------------------ sortie

    public func exitCleanly() {
        slowTick?.invalidate()
        fastTick?.invalidate()

        hotkeys.unregister()
        PanicKey.shared.stop()
        adaptive.dispose()
        breaks.dispose()
        ScreenMagnifier.stop()
        reader.dispose()
        beacon.dispose()
        display.restoreAll()
        display.dispose()

        HardwareBacklight.stop()
        SafetyGuard.clearDirtyFlag()

        NSStatusBar.system.removeStatusItem(statusItem)
        NSApp.terminate(nil)
    }
}

/// Les avis passagers.
///
/// Les notifications du systeme demandent une autorisation, et une application
/// qui la reclame au premier lancement pour annoncer sa propre mise a jour se
/// fait refuser - a juste titre. Un petit bandeau suffit, et il s'efface seul.
public enum Notice {
    public static func show(_ title: String, _ detail: String) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 88),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = WindowLevels.notice
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = NoticeView(frame: NSRect(x: 0, y: 0, width: 360, height: 88))
        view.title = title
        view.detail = detail
        panel.contentView = view

        if let screen = NSScreen.main {
            let work = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: work.maxX - 384, y: work.maxY - 112))
        }
        panel.orderFrontRegardless()

        Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in
            panel.orderOut(nil)
            panel.close()
        }
    }

    final class NoticeView: FlippedView {
        var title = ""
        var detail = ""

        override func draw(_ dirtyRect: NSRect) {
            Draw.fill(bounds, radius: 10, Theme.card)
            Draw.stroke(bounds, radius: 10, Theme.border)
            Draw.text(title, in: NSRect(x: 16, y: 12, width: bounds.width - 32, height: 20),
                      font: Theme.bodyBold, color: Theme.fg)
            Draw.text(detail, in: NSRect(x: 16, y: 36, width: bounds.width - 32, height: 44),
                      font: Theme.small, color: Theme.dim, wrap: true)
        }
    }
}
