import Foundation
import AppKit

/// Une vue dont l'origine est en haut a gauche.
///
/// AppKit compte depuis le bas ; toute la mise en page de cette application est
/// pensee de haut en bas, comme on lit. Retourner la vue une fois vaut mieux que
/// soustraire des hauteurs a chaque ligne.
public class FlippedView: NSView {
    public override var isFlipped: Bool { true }
}

/// Base commune a toutes les pages de reglages.
///
/// Chaque page ne s'occupe que de son domaine et empile ses lignes ; le
/// positionnement, le defilement et les marges sont geres ici une bonne fois.
/// C'est ce qui permet d'ajouter un reglage en une ligne sans toucher a la mise
/// en page.
///
/// L'empilement est recalcule a chaque redimensionnement plutot que fige a la
/// construction : les textes explicatifs ne connaissent leur nombre de lignes
/// qu'une fois la largeur reelle connue.
public class SettingsPage: NSView {

    public let settings: Settings
    public let display: DisplayController
    public let push: () -> Void
    public var loading = false

    private let scroll = NSScrollView()
    private let stack = FlippedView()

    private struct Item {
        let view: NSView
        let gap: CGFloat
        let wraps: Bool
    }

    private var items: [Item] = []
    private var lastWidth: CGFloat = -1

    private static var pad: CGFloat { Theme.px(24) }

    public init(_ settings: Settings, _ display: DisplayController, _ push: @escaping () -> Void) {
        self.settings = settings
        self.display = display
        self.push = push
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 500))

        wantsLayer = true
        layer?.backgroundColor = Theme.card.cgColor

        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = stack
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    // ------------------------------------------------------------------ empilement

    /// Ajoute un controle a la suite du precedent.
    @discardableResult
    public func add<T: NSView>(_ view: T, _ gapBefore: CGFloat? = nil) -> T {
        items.append(Item(view: view, gap: gapBefore ?? Theme.spaceSm, wraps: false))
        stack.addSubview(view)
        return view
    }

    public func section(_ title: String) {
        add(UiKit.sectionTitle(title), items.isEmpty ? Theme.px(6) : Theme.spaceXl)
        add(UiKit.divider(), Theme.px(2))
    }

    /// Texte explicatif, dont la hauteur suit le nombre de lignes reellement occupees.
    @discardableResult
    public func note(_ text: String) -> LabelView {
        let l = UiKit.caption(text)
        items.append(Item(view: l, gap: Theme.spaceXs, wraps: true))
        stack.addSubview(l)
        return l
    }

    public var contentWidth: CGFloat {
        max(Theme.px(160), bounds.width - SettingsPage.pad * 2 - Theme.px(18))
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        scroll.frame = bounds
        if bounds.width != lastWidth { relayout() }
    }

    public override func layout() {
        super.layout()
        scroll.frame = bounds
        if bounds.width != lastWidth { relayout() }
    }

    /// Repositionne toute la pile. Peu couteux : quelques dizaines de controles.
    public func relayout() {
        let w = contentWidth
        guard w > Theme.px(160) else { return }
        lastWidth = bounds.width

        var y = Theme.px(14)
        for item in items {
            if item.view.isHidden { continue }

            // Le texte mesure est celui que l'etiquette porte MAINTENANT, et non
            // celui qu'on lui avait donne a la construction : plusieurs pages
            // remplacent le leur par l'etat reel du systeme, et leur boite
            // resterait calculee sur la chaine vide du depart.
            var height = item.view.frame.height
            if let label = item.view as? LabelView, item.wraps || label.wraps {
                height = label.fittingHeight(for: w)
            } else if let toggle = item.view as? ToggleRow {
                height = toggle.fittingHeight(for: w)
            }

            y += item.gap
            item.view.frame = NSRect(x: SettingsPage.pad, y: y, width: w, height: height)
            item.view.needsLayout = true
            item.view.layoutSubtreeIfNeeded()
            y += height
        }

        y += Theme.px(24)
        stack.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(y, bounds.height))
    }

    // ------------------------------------------------------------------ contrat

    /// Recharge l'affichage a partir des reglages. Appelee a chaque ouverture.
    public func sync() {}

    /// Recharge, puis redispose la pile.
    ///
    /// L'ordre compte : `sync` pose des textes dont on ne connait la longueur
    /// qu'a cet instant - l'etat du systeme, un resume, un compte. Sans la
    /// redisposition qui suit, ces textes attendaient le prochain
    /// redimensionnement de la fenetre pour obtenir leur place, c'est-a-dire
    /// souvent jamais.
    public func syncAndLayout() {
        sync()
        lastWidth = -1
        relayout()
    }

    /// Titre affiche en en-tete de la fenetre quand la page est active.
    public var pageTitle: String { "" }

    /// Sous-titre explicatif.
    public var pageSubtitle: String { "" }

    public func commit() {
        guard !loading else { return }
        push()
        settings.save()
    }

    public func commitNoSave() {
        guard !loading else { return }
        push()
    }

    /// La fenetre qui contient cette page, pour les boites de dialogue.
    public var hostWindow: NSWindow? { window }
}
