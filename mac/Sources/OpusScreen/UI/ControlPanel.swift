import Foundation
import AppKit

/// Fenetre de reglages.
///
/// Onze pages plutot qu'un long formulaire : avec quatre-vingts reglages, tout
/// montrer d'un coup rendrait l'application inutilisable pour le geste quotidien,
/// qui se resume a bouger un curseur. La deuxieme page porte ce geste ; les dix
/// autres attendent qu'on aille les chercher.
///
/// Cette classe n'assemble que la coquille : chaque page connait son domaine et
/// rien d'autre.
public final class ControlPanel: NSObject, NSWindowDelegate {

    public let window: NSWindow
    private let settings: Settings
    private let display: DisplayController
    private let push: () -> Void

    private let root = FlippedView()
    private let nav = SideNav()
    private let content = FlippedView()
    private let titleLabel = LabelView("")
    private let subtitleLabel = LabelView("")
    private let statusLabel = LabelView("")
    private let pauseButton = DarkButton("Suspendre")

    private var pages: [SettingsPage] = []

    public private(set) var welcomePage: PageWelcome!
    public private(set) var displayPage: PageDisplay!
    public private(set) var colorPage: PageColor!
    public private(set) var colorBlindPage: PageColorBlind!
    public private(set) var visionPage: PageVision!
    public private(set) var autoPage: PageAuto!
    public private(set) var appsPage: PageApps!
    public private(set) var screensPage: PageScreens!
    public private(set) var comfortPage: PageComfort!
    public private(set) var hotkeysPage: PageHotkeys!
    public private(set) var advancedPage: PageAdvanced!

    /// Rang de l'onglet Daltonisme, ouvert depuis le menu de la barre des menus.
    ///
    /// Calcule depuis la liste, et non ecrit a la main : une constante avait
    /// ouvert la page voisine le jour ou un onglet s'etait glisse avant elle.
    public var colorBlindPageIndex: Int { pages.firstIndex(where: { $0 === colorBlindPage }) ?? 0 }
    public var visionPageIndex: Int { pages.firstIndex(where: { $0 === visionPage }) ?? 0 }

    /// Declenche la suspension ou la reprise depuis le bouton du pied de page.
    public var togglePause: (() -> Void)?

    private static var navWidth: CGFloat { Theme.px(196) }
    private static var headerHeight: CGFloat { Theme.px(66) }
    private static var footerHeight: CGFloat { Theme.px(52) }

    public init(_ settings: Settings, _ display: DisplayController, _ push: @escaping () -> Void) {
        self.settings = settings
        self.display = display
        self.push = push

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Theme.px(830), height: Theme.px(680)),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()

        window.title = "OpusScreen"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.bg
        window.minSize = NSSize(width: Theme.px(760), height: Theme.px(560))
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = root

        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.bg.cgColor

        buildUi()
        syncAll()
    }

    // ------------------------------------------------------------------ construction

    private func buildUi() {
        // ---------------- en-tete ----------------
        titleLabel.font = Theme.title
        titleLabel.color = Theme.fg
        root.addSubview(titleLabel)

        subtitleLabel.font = Theme.small
        subtitleLabel.color = Theme.dim
        root.addSubview(subtitleLabel)

        statusLabel.font = Theme.small
        statusLabel.color = Theme.dim
        statusLabel.align = .right
        statusLabel.wraps = true
        root.addSubview(statusLabel)

        // ---------------- navigation ----------------
        // Le nom du produit vit dans la colonne de navigation, pas dans l'en-tete :
        // l'en-tete est ancre a droite du menu et son espace revient au titre de page.
        root.addSubview(nav)

        let brand = LabelView("OpusScreen")
        brand.font = Theme.title
        brand.color = Theme.accent
        brand.frame = NSRect(x: Theme.px(58), y: Theme.px(16),
                             width: ControlPanel.navWidth - Theme.px(64), height: Theme.px(22))
        nav.addSubview(brand)

        let version = LabelView("version " + Installer.currentVersionShort)
        version.font = Theme.small
        version.color = Theme.faint
        version.frame = NSRect(x: Theme.px(59), y: Theme.px(38),
                               width: ControlPanel.navWidth - Theme.px(64), height: Theme.px(16))
        nav.addSubview(version)

        // La place du logo est reservee tout de suite ; l'image arrive quand elle
        // arrive. Attendre une lecture de fichier pour construire une fenetre,
        // c'est accepter que la fenetre n'apparaisse jamais si le systeme decide
        // de poser une question a l'utilisateur d'abord.
        let mark = NSImageView(frame: NSRect(x: Theme.px(14), y: Theme.px(16),
                                             width: Theme.px(38), height: Theme.px(32)))
        mark.imageScaling = .scaleProportionallyUpOrDown
        nav.addSubview(mark)
        AppIcon.withLogo { [weak mark] image in mark?.image = image }

        nav.topOffset = Theme.px(66)
        nav.onSelect = { [weak self] index in self?.showPage(index) }

        // ---------------- pied ----------------
        pauseButton.onClick = { [weak self] in self?.togglePause?() }
        root.addSubview(pauseButton)

        let reset = DarkButton("Tout reinitialiser") { [weak self] in self?.onReset() }
        root.addSubview(reset)
        resetButton = reset

        panicNote.font = Theme.small
        panicNote.color = Theme.faint
        panicNote.align = .right
        panicNote.text = "Secours : ⌃⌥⇧R retablit un ecran normal, meme si l'application ne repond plus."
        root.addSubview(panicNote)

        // ---------------- contenu ----------------
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.card.cgColor
        root.addSubview(content)

        // ---------------- pages ----------------
        welcomePage = PageWelcome(settings, display, push)
        displayPage = PageDisplay(settings, display, push)
        colorPage = PageColor(settings, display, push)
        colorBlindPage = PageColorBlind(settings, display, push)
        visionPage = PageVision(settings, display, push)
        autoPage = PageAuto(settings, display, push)
        appsPage = PageApps(settings, display, push)
        screensPage = PageScreens(settings, display, push)
        comfortPage = PageComfort(settings, display, push)
        hotkeysPage = PageHotkeys(settings, display, push)
        advancedPage = PageAdvanced(settings, display, push)

        addPage(welcomePage, "Decouvrir", .compass)
        addPage(displayPage, "Ecran", .sun)
        addPage(colorPage, "Couleur", .palette)
        addPage(colorBlindPage, "Daltonisme", .colorblind)
        addPage(visionPage, "Vision", .vision)
        addPage(autoPage, "Automatisme", .clock)
        addPage(appsPage, "Applications", .apps)
        addPage(screensPage, "Ecrans", .screens)
        addPage(comfortPage, "Confort", .eye)
        addPage(hotkeysPage, "Raccourcis", .keyboard)
        addPage(advancedPage, "Avance", .sliders)

        layoutChrome()

        // Le tout premier lancement s'ouvre sur la page qui explique ou
        // l'application se range - sans quoi elle se referme dans la barre des
        // menus et parait avoir disparu. Les lancements suivants ouvrent l'ecran
        // de tous les jours : une explication deja lue qui revient chaque fois
        // devient une porte a pousser.
        let first = settings.isFirstRun ? 0 : 1
        nav.setSelectionSilent(first)
        showPage(first)
    }

    private var resetButton: DarkButton?
    private let panicNote = LabelView("")

    private func addPage(_ page: SettingsPage, _ label: String, _ glyph: NavGlyph) {
        page.isHidden = true
        content.addSubview(page)
        pages.append(page)
        nav.addTab(label, glyph)
    }

    private func showPage(_ index: Int) {
        guard index >= 0, index < pages.count else { return }
        for (i, p) in pages.enumerated() { p.isHidden = (i != index) }
        pages[index].frame = content.bounds
        pages[index].syncAndLayout()
        titleLabel.text = pages[index].pageTitle
        subtitleLabel.text = pages[index].pageSubtitle
        updateStatus()
    }

    public func selectPage(_ index: Int) {
        nav.select(index)
    }

    // ------------------------------------------------------------------ mise en page

    private func layoutChrome() {
        let w = root.bounds.width
        let h = root.bounds.height
        guard w > 0, h > 0 else { return }

        let header = ControlPanel.headerHeight
        let footer = ControlPanel.footerHeight
        let navW = ControlPanel.navWidth

        nav.frame = NSRect(x: 0, y: 0, width: navW, height: h)

        let statusWidth = Theme.px(300)
        let left = navW + Theme.px(24)
        let statusX = max(left + Theme.px(160), w - statusWidth - Theme.px(20))

        titleLabel.frame = NSRect(x: left, y: Theme.px(14),
                                  width: max(Theme.px(140), statusX - left - Theme.spaceLg),
                                  height: Theme.px(22))
        subtitleLabel.frame = NSRect(x: left, y: Theme.px(36),
                                     width: max(Theme.px(140), statusX - left - Theme.spaceLg),
                                     height: Theme.px(18))
        statusLabel.frame = NSRect(x: statusX, y: Theme.px(14), width: statusWidth, height: Theme.px(40))

        content.frame = NSRect(x: navW, y: header, width: w - navW, height: h - header - footer)
        for p in pages where !p.isHidden {
            p.frame = content.bounds
            p.relayout()
        }

        pauseButton.frame = NSRect(x: navW + Theme.px(20), y: h - footer + Theme.px(8),
                                   width: Theme.px(116), height: Theme.minTarget)
        resetButton?.frame = NSRect(x: navW + Theme.px(144), y: h - footer + Theme.px(8),
                                    width: Theme.px(140), height: Theme.minTarget)
        panicNote.frame = NSRect(x: navW + Theme.px(292), y: h - footer + Theme.px(8),
                                 width: max(Theme.px(80), w - navW - Theme.px(312)),
                                 height: Theme.minTarget)
    }

    public func windowDidResize(_ notification: Notification) {
        layoutChrome()
    }

    // ------------------------------------------------------------------ synchronisation

    /// Recharge toutes les pages depuis les reglages.
    public func syncAll() {
        for p in pages { p.syncAndLayout() }
        updateStatus()
    }

    /// Recharge seulement la page visible : appelee a chaque changement de valeur.
    public func refreshReadouts() {
        for p in pages where !p.isHidden { p.syncAndLayout() }
        updateStatus()
    }

    private func updateStatus() {
        var bits: [String] = []

        if display.suspended {
            bits.append("SUSPENDU - " + display.suspendReason)
            statusLabel.color = Theme.boost
        } else {
            bits.append("\(Int(settings.current.brightness.rounded())) % - \(settings.current.kelvin) K")
            statusLabel.color = Theme.dim
        }

        // Signale en premier ce qui empeche les reglages de tenir : c'est la cause
        // la plus frequente d'un « ca ne marche pas » attribue a tort a l'application.
        if AutoBrightness.isAnyAutoActive() {
            bits.append("luminosite automatique active - voir Avance")
            statusLabel.color = Theme.boost
        } else if display.gammaClamped {
            bits.append("table de couleurs rabotee - voir Avance")
        } else if display.clipping {
            bits.append("hautes lumieres ecretees au-dela de 135 %")
        }
        if display.colorMatrixFailed { bits.append("matrice de couleur indisponible") }

        statusLabel.text = bits.joined(separator: "\n")
        pauseButton.title = display.suspended ? "Reprendre" : "Suspendre"
    }

    // ------------------------------------------------------------------ evenements

    private func onReset() {
        settings.current = Profile()
        settings.activeModeName = "Normal"
        settings.schedule = .manual
        settings.adaptiveEnabled = false
        for ms in settings.monitors {
            ms.blackout = false
            ms.enabled = true
            ms.brightnessOffset = 0
        }
        display.restoreAll()
        push()
        settings.save()
        syncAll()
    }

    public func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        layoutChrome()
        syncAll()
    }

    /// La croix range la fenetre ; on ne quitte que par le menu de la barre des menus.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        window.orderOut(nil)
        return false
    }

    /// ⌘1 a ⌘9 puis ⌘0 : acces direct aux pages, sans quitter le clavier.
    /// Le zero sert la dixieme, comme sur la rangee de chiffres du clavier.
    public func handleKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers {
            if let digit = Int(chars), digit >= 1, digit <= 9 {
                nav.select(digit - 1)
                return true
            }
            if chars == "0" { nav.select(9); return true }
        }
        if event.keyCode == 53 {   // echappement
            window.orderOut(nil)
            return true
        }
        return false
    }
}
