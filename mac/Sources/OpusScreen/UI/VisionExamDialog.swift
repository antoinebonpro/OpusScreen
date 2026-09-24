import Foundation
import AppKit

/// La fenetre du test guide.
///
/// Elle ne calcule rien : tout ce qui decide vit dans `VisionExam`. Ici on montre,
/// on recolte des reponses, et on rend le resultat. Cette separation n'est pas de
/// la coquetterie - c'est ce qui permet de verifier la mesure par le calcul, sans
/// cliquer, et de faire passer le test a un observateur simule dont on connait la
/// vision.
///
/// Pendant toute la duree du test, les effets de l'application sont SUSPENDUS :
/// mesurer une vision a travers une correction deja posee reviendrait a mesurer la
/// correction. Ils sont retablis a la fermeture, quelle qu'en soit la facon.
public final class VisionExamDialog: NSObject {

    public enum Step { case intro, plates, pairs, result }

    private let settings: Settings
    private let display: DisplayController?
    private let wasSuspended: Bool

    private let plates: [VisionPlate]
    private var read: [Bool] = []
    private var plateIndex = 0

    private var stair: VisionExam.Staircase?
    private var pair: (RGB, RGB) = (.black, .white)

    // Mesure des trois axes, quand les planches n'ont rien trouve.
    private var screening = false
    private var pending: [ColorFilter] = []
    private var measured: [ColorFilter: Double] = [:]

    private var step: Step = .intro

    // Resultat
    public private(set) var foundFilter: ColorFilter = .none
    public private(set) var foundSeverity: Double = 100
    public private(set) var confidence = 0
    public private(set) var applied = false

    // Interface
    private let window: NSWindow
    private let root = FlippedView()
    private let titleLabel = LabelView("")
    private let textLabel = LabelView("")
    private let progressLabel = LabelView("")
    private let plateView = PlateView()
    private let pairView = PairView()
    private let answers = FlippedView()
    private var choiceButtons: [DarkButton] = []
    private let nextButton = DarkButton("Commencer")
    private let quitButton = DarkButton("Arreter")

    private var restored = false

    public convenience init(_ s: Settings, _ d: DisplayController?) {
        self.init(s, d, seed: UInt64(Date().timeIntervalSince1970 * 1000))
    }

    public init(_ s: Settings, _ d: DisplayController?, seed: UInt64) {
        self.settings = s
        self.display = d
        self.plates = VisionExam.plates(seed: seed)
        self.wasSuspended = d?.suspended ?? false

        let size = NSSize(width: 700, height: 640)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        super.init()

        if let d = d, !wasSuspended { d.suspend("test de vision en cours") }

        window.title = "Test de vision des couleurs"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.card
        window.isReleasedWhenClosed = false
        window.contentView = root

        buildUi()
        show(.intro)
    }

    public var currentStep: Step { step }
    public var currentPlate: VisionPlate? { plateIndex < plates.count ? plates[plateIndex] : nil }
    public var staircase: VisionExam.Staircase? { stair }

    // ------------------------------------------------------------------ construction

    private func buildUi() {
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.card.cgColor

        titleLabel.font = Theme.title
        titleLabel.color = Theme.fg
        titleLabel.frame = NSRect(x: 28, y: 22, width: 644, height: 28)
        root.addSubview(titleLabel)

        textLabel.font = Theme.body
        textLabel.color = Theme.dim
        textLabel.wraps = true
        textLabel.frame = NSRect(x: 28, y: 54, width: 644, height: 120)
        root.addSubview(textLabel)

        plateView.frame = NSRect(x: 160, y: 182, width: 380, height: 290)
        plateView.isHidden = true
        root.addSubview(plateView)

        pairView.frame = NSRect(x: 130, y: 204, width: 440, height: 230)
        pairView.isHidden = true
        root.addSubview(pairView)

        answers.frame = NSRect(x: 28, y: 490, width: 644, height: 60)
        root.addSubview(answers)

        progressLabel.font = Theme.small
        progressLabel.color = Theme.faint
        progressLabel.frame = NSRect(x: 28, y: 600, width: 400, height: 20)
        root.addSubview(progressLabel)

        quitButton.frame = NSRect(x: 560, y: 592, width: 112, height: Theme.minTarget)
        quitButton.onClick = { [weak self] in self?.close() }
        root.addSubview(quitButton)

        nextButton.frame = NSRect(x: 436, y: 592, width: 118, height: Theme.minTarget)
        nextButton.onClick = { [weak self] in self?.begin() }
        root.addSubview(nextButton)
    }

    /// Affiche et attend. Vrai si le resultat a ete applique.
    @discardableResult
    public func run(over parent: NSWindow?) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        NSApp.runModal(for: window)
        return applied
    }

    private func close() {
        restoreScreen()
        NSApp.stopModal()
        window.orderOut(nil)
    }

    /// Les effets reviennent quoi qu'il arrive : fin du test, croix, Echap, ou
    /// fenetre detruite sans avoir jamais ete montree. Rendre l'ecran est la
    /// seule chose que cette fenetre ne doit jamais oublier.
    private func restoreScreen() {
        guard !restored else { return }
        restored = true
        if let d = display, !wasSuspended { d.resume() }
    }

    deinit { restoreScreen() }

    // ------------------------------------------------------------------ deroulement

    private func show(_ newStep: Step) {
        step = newStep
        plateView.isHidden = newStep != .plates
        pairView.isHidden = newStep != .pairs
        clearAnswers()

        switch newStep {
        case .intro:
            titleLabel.text = "Trouver votre reglage, en deux minutes"
            textLabel.text = "Deux series de questions.\n\n"
                + "1. Des planches ou se cache un chiffre : vous dites lequel, ou qu'il n'y en a aucun.\n"
                + "2. Deux couleurs cote a cote : vous dites si elles vous paraissent identiques.\n\n"
                + "Ne devinez pas : « aucun chiffre » et « identiques » sont des reponses utiles. "
                + "Pendant le test, la correction en cours est retiree - c'est votre oeil que l'on "
                + "mesure, pas votre ecran deja corrige."
            nextButton.title = "Commencer"
            nextButton.isHidden = false
            progressLabel.text = ""

        case .plates:
            titleLabel.text = "Quel chiffre voyez-vous ?"
            textLabel.text = "Regardez l'ensemble du disque. Si aucun chiffre ne se detache, c'est une "
                + "reponse comme une autre - souvent la plus instructive."
            nextButton.isHidden = true
            showPlate()

        case .pairs:
            titleLabel.text = "Ces deux couleurs sont-elles identiques ?"
            textLabel.text = "Parfois elles le sont presque, parfois pas du tout : il n'y a pas de piege. "
                + "Repondez d'apres ce que vous voyez, sans chercher a bien faire."
            nextButton.isHidden = true
            showPair()

        case .result:
            showResult()
        }
    }

    private func clearAnswers() {
        for v in answers.subviews { v.removeFromSuperview() }
        choiceButtons.removeAll()
    }

    private func addAnswer(_ text: String, _ index: Int, _ count: Int, _ action: @escaping () -> Void) {
        let gap = Theme.spaceSm
        let w = (answers.bounds.width - gap * CGFloat(count - 1)) / CGFloat(count)
        let b = DarkButton(text, action: action)
        b.font = Theme.bodyBold
        b.frame = NSRect(x: CGFloat(index) * (w + gap), y: 0, width: w, height: 52)
        answers.addSubview(b)
        choiceButtons.append(b)
    }

    /// Passe de l'accueil a la premiere planche. Public : les tests s'en servent.
    public func begin() {
        if step == .intro { show(.plates) }
    }

    // ---------------- planches ----------------

    private func showPlate() {
        let p = plates[plateIndex]
        plateView.show(p)
        progressLabel.text = "Planche \(plateIndex + 1) sur \(plates.count)"

        let n = p.choices.count + 1
        for (i, digit) in p.choices.enumerated() {
            addAnswer(String(digit), i, n) { [weak self] in self?.answerPlate(digit) }
        }
        addAnswer("Aucun chiffre", p.choices.count, n) { [weak self] in self?.answerPlate(-1) }
    }

    /// Repond a la planche courante. -1 = aucun chiffre vu.
    public func answerPlate(_ digit: Int) {
        guard step == .plates else { return }
        read.append(digit == plates[plateIndex].digit)
        plateIndex += 1

        if plateIndex < plates.count { clearAnswers(); showPlate(); return }

        let outcome = VisionExam.typeFromPlates(plates, read)
        foundFilter = outcome.filter
        confidence = outcome.confidence

        // Rouge et vert se confondent aussi entre eux : leurs axes sont voisins, et
        // une planche cachee a l'un l'est souvent presque a l'autre. Quand les
        // planches ne tranchent pas nettement, on ne tire pas a pile ou face - on
        // mesure les axes a egalite, et le profil des trois mesures designe la vision.
        let misses = VisionExam.misses(plates, read)
        var top = 0, second = 0
        for (_, value) in misses {
            if value > top { second = top; top = value }
            else if value > second { second = value }
        }

        if foundFilter == .none || top - second <= 1 {
            screening = true
            pending = VisionExam.axes
            measured.removeAll()
            nextScreeningAxis()
        } else {
            screening = false
            stair = VisionExam.Staircase(foundFilter)
        }
        show(.pairs)
    }

    // ---------------- comparaisons ----------------

    private func showPair() {
        guard let stair = stair else { return }
        pair = VisionExam.pairAt(stair.axis, stair.separation)

        // L'ordre change a chaque essai : sinon la meme couleur reste a gauche et
        // l'on finit par repondre d'apres la position plutot que d'apres la couleur.
        let swapped = (stair.trials % 2) == 1
        pairView.show(swapped ? pair.1 : pair.0, swapped ? pair.0 : pair.1)

        progressLabel.text = "Comparaison \(stair.trials + 1) - \(Int((stair.progress * 100).rounded())) %"

        addAnswer("Identiques", 0, 2) { [weak self] in self?.answerPair(false) }
        addAnswer("Differentes", 1, 2) { [weak self] in self?.answerPair(true) }
    }

    /// Repond a la comparaison : vrai si les deux couleurs paraissent differentes.
    public func answerPair(_ distinguished: Bool) {
        guard step == .pairs, let stair = stair else { return }
        stair.answer(distinguished)

        if !stair.done { clearAnswers(); showPair(); return }

        if !screening {
            foundSeverity = VisionExam.severityFromThreshold(stair.axis, stair.threshold)
            show(.result)
            return
        }

        measured[stair.axis] = stair.threshold
        if !pending.isEmpty { nextScreeningAxis(); clearAnswers(); showPair(); return }

        finishScreening()
    }

    /// Mesure courte de l'axe suivant, quand les planches n'ont rien trouve.
    private func nextScreeningAxis() {
        let axis = pending.removeFirst()
        stair = VisionExam.Staircase(axis, 5, 12)
    }

    /// Conclusion de la mesure sur les trois axes : l'axe le plus mauvais, et
    /// seulement s'il l'est nettement plus que les autres. Un ecart faible entre
    /// les trois, c'est une vision normale - l'annoncer daltonienne serait un faux
    /// diagnostic tire du bruit de mesure.
    private func finishScreening() {
        let fit = VisionExam.fit(measured)

        if fit.severity < 20 || fit.quality < 0.3 {
            foundFilter = .none
            foundSeverity = 0
            confidence = 0
        } else {
            foundFilter = fit.axis
            foundSeverity = fit.severity
            // Mesure courte : la confiance plafonne, meme quand tout concorde.
            confidence = Int(min(75, fit.quality * 100).rounded())
        }
        show(.result)
    }

    // ---------------- resultat ----------------

    private func showResult() {
        progressLabel.text = ""
        nextButton.isHidden = true

        if foundFilter == .none {
            titleLabel.text = "Aucune deficience detectee"
            textLabel.text = "Vous avez lu toutes les planches : rien n'indique de confusion des "
                + "couleurs, et aucune correction n'est necessaire.\n\n"
                + "Si vous savez par ailleurs etre daltonien, c'est que les planches sont passees "
                + "a cote - la luminosite ou le profil de couleur de l'ecran peuvent fausser le "
                + "test. Le reglage a la main reste possible dans l'onglet Daltonisme."
            addAnswer("Recommencer", 0, 2) { [weak self] in self?.restart() }
            addAnswer("Fermer", 1, 2) { [weak self] in self?.close() }
            return
        }

        titleLabel.text = "Resultat : " + Vision.plainName(foundFilter).lowercased()
        var text = String(format: "%@\n\nGravite mesuree : %.0f %% - %@.\nConfiance du depistage : %d %%.\n\n"
                        + "La gravite compte autant que le type : une correction calibree sur une "
                        + "deficience complete rend l'ecran criard a qui n'en a qu'une partie.",
                          Vision.clinicalName(foundFilter), foundSeverity,
                          Vision.severityWord(foundSeverity), confidence)

        if (foundFilter == .protanopia || foundFilter == .deuteranopia) && confidence < 60 {
            text += "\n\nRouge ou vert : les deux se ressemblent beaucoup a ce degre, et les "
                  + "separer demande un appareil de cabinet. Si la correction proposee vous "
                  + "parait fausse, essayez l'autre depuis l'onglet Daltonisme."
        }

        if confidence < 50 {
            text += "\n\nConfiance faible : mieux vaut refaire le test au calme que de se fier a ceci."
        }
        textLabel.text = text

        addAnswer("Appliquer", 0, 3) { [weak self] in self?.apply(); self?.close() }
        addAnswer("Appliquer et enregistrer...", 1, 3) { [weak self] in self?.applyAndSave() }
        addAnswer("Recommencer", 2, 3) { [weak self] in self?.restart() }
    }

    private func restart() {
        read.removeAll()
        plateIndex = 0
        stair = nil
        screening = false
        pending.removeAll()
        measured.removeAll()
        foundFilter = .none
        foundSeverity = 100
        confidence = 0
        show(.plates)
    }

    /// Pose le resultat dans les reglages. L'appelant l'applique ensuite a l'ecran.
    public func apply() {
        guard foundFilter != .none else { return }
        settings.current.filter = foundFilter
        settings.current.visionSeverity = foundSeverity
        settings.current.mode = .correction

        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        settings.lastExamSummary = String(format: "%@ - %@, gravite %.0f %%",
                                          formatter.string(from: Date()),
                                          Vision.plainName(foundFilter).lowercased(),
                                          foundSeverity)
        applied = true
    }

    /// Applique, puis enregistre sous un nom choisi. Public : les tests s'en servent.
    public func saveAs(_ name: String) {
        apply()
        guard !name.isEmpty else { return }
        let preset = VisionPreset.fromProfile(name, settings.current)
        settings.visionPresets.removeAll { $0.name == preset.name }
        settings.visionPresets.append(preset)
    }

    private func applyAndSave() {
        if let name = PromptDialog.ask("Enregistrer ce reglage", "Nom du reglage :",
                                       Vision.plainName(foundFilter), window: window) {
            saveAs(name)
        } else {
            apply()
        }
        close()
    }
}

/// Une planche : un semis de pastilles ou le chiffre ne se distingue que par la
/// couleur.
///
/// Les pastilles varient de taille ET de clarte, des deux cotes de la meme facon.
/// Sans cette variation, le chiffre ressortirait par sa regularite - et le test
/// mesurerait la vue, pas la vision des couleurs.
public final class PlateView: NSView {

    private var plate: VisionPlate?

    private struct Dot {
        let x: CGFloat, y: CGFloat, r: CGFloat
        let figure: Bool
        let shade: CGFloat
    }

    private var dots: [Dot] = []

    /// Amplitude de la variation de clarte entre pastilles.
    ///
    /// Elle empeche de lire le chiffre a sa regularite plutot qu'a sa couleur.
    /// Mais sur une planche subtile, l'ecart de couleur du chiffre est lui-meme
    /// faible : une variation trop forte le noierait, et une vision normale ne
    /// verrait plus rien non plus. Elle suit donc la finesse de la planche.
    private var jitter: CGFloat = 0.04

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 290))
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public func show(_ p: VisionPlate) {
        plate = p
        build()
        needsDisplay = true
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        build()
    }

    private func build() {
        dots.removeAll()
        guard let plate = plate, bounds.width > 40, bounds.height > 40 else { return }

        let side = min(bounds.width, bounds.height)
        let cx = bounds.width / 2, cy = bounds.height / 2
        let radius = side / 2 - 2

        // Plus la planche est subtile, plus la variation de clarte doit s'effacer :
        // elle se mesure en pourcentage, l'ecart du chiffre aussi.
        let contrast = Vision.deltaE(plate.figure, plate.background)
        jitter = CGFloat(max(0.008, min(0.04, contrast / 400.0)))

        guard let mask = PlateView.digitMask(plate.digit, Int(side)) else { return }
        let maskWidth = mask.width, maskHeight = mask.height
        guard let data = mask.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return }
        let rowBytes = mask.bytesPerRow
        let pixelBytes = mask.bitsPerPixel / 8

        var rnd = SeededRandom(seed: plate.seed)
        var attempts = 0
        while attempts < 16000 && dots.count < 2600 {
            attempts += 1

            // Des pastilles plus fines que le trait du chiffre : sinon le chiffre
            // se disloque en taches et devient illisible meme pour une vision
            // normale - le test accuserait alors tout le monde.
            let r = 2.0 + CGFloat(rnd.nextDouble()) * (side / 70)
            let angle = rnd.nextDouble() * Double.pi * 2
            let dist = rnd.nextDouble().squareRoot() * Double(radius - r)
            let x = cx + CGFloat(cos(angle) * dist)
            let y = cy + CGFloat(sin(angle) * dist)

            var overlap = false
            for d in dots {
                let dx = d.x - x, dy = d.y - y
                if dx * dx + dy * dy < (d.r + r) * (d.r + r) * 0.95 { overlap = true; break }
            }
            if overlap { continue }

            let mx = Int((x - (cx - side / 2)) * CGFloat(maskWidth) / side)
            let my = Int((y - (cy - side / 2)) * CGFloat(maskHeight) / side)
            var figure = false
            if mx >= 0, my >= 0, mx < maskWidth, my < maskHeight {
                let offset = my * rowBytes + mx * pixelBytes
                figure = bytes[offset] > 128
            }

            dots.append(Dot(x: x, y: y, r: r, figure: figure,
                            shade: CGFloat(rnd.nextDouble() * 2 - 1)))
        }
    }

    /// Le chiffre, blanc sur noir : sert de pochoir pour trier les pastilles.
    private static func digitMask(_ digit: Int, _ side: Int) -> CGImage? {
        let s = max(32, side)
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

        let font = NSFont.systemFont(ofSize: CGFloat(s) * 0.62, weight: .black)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let text = NSAttributedString(string: String(digit), attributes: attributes)
        let size = text.size()

        let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        text.draw(at: NSPoint(x: (CGFloat(s) - size.width) / 2, y: (CGFloat(s) - size.height) / 2))
        NSGraphicsContext.restoreGraphicsState()

        return ctx.makeImage()
    }

    private func shaded(_ c: RGB, _ shade: CGFloat) -> RGB {
        // Applique de la meme facon des deux cotes : la variation ne trahit donc
        // jamais le chiffre, elle empeche seulement de le lire a la regularite.
        let k = 1.0 + Double(shade * jitter)
        return RGB(Int((Double(c.r) * k).rounded()),
                   Int((Double(c.g) * k).rounded()),
                   Int((Double(c.b) * k).rounded()))
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Draw.fill(bounds, Theme.card)
        guard let plate = plate else { return }

        ctx.setShouldAntialias(true)
        for d in dots {
            let c = shaded(d.figure ? plate.figure : plate.background, d.shade)
            ctx.setFillColor(c.cgColor)
            ctx.fillEllipse(in: CGRect(x: d.x - d.r, y: d.y - d.r, width: d.r * 2, height: d.r * 2))
        }
    }

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .image }
    public override func accessibilityLabel() -> String? { "Planche de couleurs" }
    public override func accessibilityValue() -> Any? {
        "Un chiffre est dessine en pastilles d'une couleur voisine du fond."
    }
}

/// Deux couleurs jointives : l'essai de comparaison.
public final class PairView: NSView {

    private var left = RGB(128, 128, 128)
    private var right = RGB(128, 128, 128)

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 440, height: 230))
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public func show(_ a: RGB, _ b: RGB) {
        left = a; right = b
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        Draw.fill(bounds, Theme.card)

        // Jointives, et non separees par du fond : un ecart fin ne se juge qu'au
        // contact. C'est la difference entre un test qui mesure et un test qui
        // fatigue.
        let w = bounds.width / 2
        Draw.fill(NSRect(x: 0, y: 0, width: w, height: bounds.height), left.nsColor)
        Draw.fill(NSRect(x: w, y: 0, width: bounds.width - w, height: bounds.height), right.nsColor)
    }

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .image }
    public override func accessibilityLabel() -> String? { "Deux couleurs a comparer" }
}
