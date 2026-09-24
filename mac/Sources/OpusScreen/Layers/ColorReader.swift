import Foundation
import AppKit
import CoreGraphics

/// Identificateur de couleur : dit a voix d'ecrit ce que le pointeur survole.
///
/// C'est l'outil que reclament en premier les personnes daltoniennes, et celui
/// qu'aucun des concurrents ne propose. Un filtre ecarte les couleurs les unes
/// des autres ; il ne repond pas a la question posee cent fois par jour :
/// « ce fil, ce graphique, ce bouton - il est de quelle couleur ? »
///
/// La lecture se fait sur la memoire d'image AVANT la table de couleurs et avant
/// la matrice : les deux s'appliquent a la sortie video, pas au dessin. La couleur
/// annoncee est donc celle que l'application a reellement dessinee, et non celle
/// deformee par les reglages en cours - c'est la seule reponse qui ait une valeur.
public final class ColorReader {

    /// Taille du carre echantillonne autour du pointeur, en pixels d'ecran.
    static let gridPixels = 9

    private var window: ReaderWindow?
    private var tick: Timer?
    private var autoHide: Timer?

    public init() {}

    public var isVisible: Bool { window?.isVisible ?? false }

    public func toggle() { isVisible ? hide() : show() }

    public func show() {
        if window == nil { window = ReaderWindow() }
        update()
        window?.orderFrontRegardless()
        if tick == nil {
            tick = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                self?.update()
            }
            RunLoop.main.add(tick!, forMode: .common)
        }
    }

    public func hide() {
        tick?.invalidate(); tick = nil
        autoHide?.invalidate(); autoHide = nil
        window?.orderOut(nil)
    }

    private func update() {
        guard let window = window else { return }
        let p = Native.cursorPosition()
        window.follow(cursor: p, grid: ColorReader.sample(around: p, size: ColorReader.gridPixels))
    }

    /// Copie la couleur sous le pointeur dans le presse-papiers, et montre
    /// brievement la lecture pour que le geste ne soit pas silencieux.
    @discardableResult
    public func copyColorUnderCursor() -> String {
        let p = Native.cursorPosition()
        let c = ColorReader.pixel(at: p)
        let hex = c.hex

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)

        if !isVisible {
            show()
            // La lecture reste affichee assez longtemps pour etre lue, puis
            // disparait : l'outil rend service sans rien laisser trainer.
            autoHide?.invalidate()
            autoHide = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
        return hex + "  " + Vision.describeColor(c)
    }

    // ------------------------------------------------------------------ lecture d'ecran

    /// La couleur d'un point de l'ecran, en coordonnees Quartz.
    public static func pixel(at point: CGPoint) -> RGB {
        let grid = sample(around: point, size: 1)
        return grid[0][0]
    }

    /// Carre de pixels centre sur le pointeur, pour la grille agrandie.
    ///
    /// Une seule capture pour tout le carre : lire pixel par pixel demandait une
    /// capture par pixel, soit quatre-vingt-une captures par image affichee.
    static func sample(around center: CGPoint, size: Int) -> [[RGB]] {
        var grid = [[RGB]](repeating: [RGB](repeating: RGB(24, 24, 24), count: size), count: size)

        let half = size / 2
        let rect = CGRect(x: center.x - CGFloat(half), y: center.y - CGFloat(half),
                          width: CGFloat(size), height: CGFloat(size))

        guard let display = MonitorEnum.all().first(where: { $0.bounds.cgRect.contains(center) })
                ?? MonitorEnum.all().first else { return grid }

        guard let image = CGDisplayCreateImage(display.displayID,
                                               rect: rect.offsetBy(dx: -CGFloat(display.bounds.left),
                                                                   dy: -CGFloat(display.bounds.top)))
        else { return grid }

        // L'image rendue est en pixels physiques : sur une dalle Retina, neuf
        // points font dix-huit pixels. On echantillonne donc au centre de chaque
        // point plutot que de supposer une correspondance un pour un.
        let scaleX = Double(image.width) / Double(size)
        let scaleY = Double(image.height) / Double(size)

        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return grid }
        let rowBytes = image.bytesPerRow
        let pixelBytes = image.bitsPerPixel / 8
        guard pixelBytes >= 3 else { return grid }

        // L'ordre des octets depend du format rendu par le systeme ; on le lit
        // plutot que de le supposer.
        let info = image.bitmapInfo
        let littleEndian = info.contains(.byteOrder32Little)

        for y in 0..<size {
            for x in 0..<size {
                let px = min(image.width - 1, Int((Double(x) + 0.5) * scaleX))
                let py = min(image.height - 1, Int((Double(y) + 0.5) * scaleY))
                let offset = py * rowBytes + px * pixelBytes
                let b0 = Int(bytes[offset])
                let b1 = Int(bytes[offset + 1])
                let b2 = Int(bytes[offset + 2])
                grid[x][y] = littleEndian ? RGB(b2, b1, b0) : RGB(b0, b1, b2)
            }
        }
        return grid
    }

    public func dispose() {
        tick?.invalidate(); tick = nil
        autoHide?.invalidate(); autoHide = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    // ------------------------------------------------------------------ la fenetre

    /// Etiquette qui suit le pointeur. Elle ne prend jamais le focus et laisse
    /// passer les clics : lire une couleur ne doit pas empecher de travailler
    /// dessus au meme moment.
    final class ReaderWindow: NSPanel {
        private let view = ReaderView()

        private static let cellSize: CGFloat = 13
        private static var gridSide: CGFloat { cellSize * CGFloat(ColorReader.gridPixels) }
        private static let panelWidth: CGFloat = 214

        init() {
            let size = NSSize(width: ReaderWindow.gridSide + ReaderWindow.panelWidth + 24,
                              height: ReaderWindow.gridSide + 16)
            super.init(contentRect: NSRect(origin: .zero, size: size),
                       styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered,
                       defer: false)

            level = WindowLevels.aid
            isOpaque = false
            backgroundColor = .clear
            hasShadow = true
            ignoresMouseEvents = true
            hidesOnDeactivate = false
            isMovable = false
            alphaValue = 248.0 / 255.0

            // Sans cette exclusion, la fenetre finirait par se lire elle-meme des
            // qu'elle passe sous la zone echantillonnee - et annoncerait sa propre
            // couleur de fond.
            sharingType = .none

            collectionBehavior = [.canJoinAllSpaces, .stationary,
                                  .fullScreenAuxiliary, .ignoresCycle]

            view.frame = NSRect(origin: .zero, size: size)
            contentView = view
        }

        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }

        /// Se place a cote du pointeur, en basculant de cote quand le bord de
        /// l'ecran approche : une etiquette a moitie sortie ne se lit pas.
        func follow(cursor: CGPoint, grid: [[RGB]]) {
            view.grid = grid
            view.center = grid[ColorReader.gridPixels / 2][ColorReader.gridPixels / 2]
            view.needsDisplay = true

            let appKitCursor = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(appKitCursor) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

            var x = appKitCursor.x + 26
            var y = appKitCursor.y - frame.height - 26

            if x + frame.width > visible.maxX { x = appKitCursor.x - frame.width - 26 }
            if y < visible.minY { y = appKitCursor.y + 26 }
            if x < visible.minX { x = visible.minX }
            if y + frame.height > visible.maxY { y = visible.maxY - frame.height }

            setFrameOrigin(NSPoint(x: x, y: y))
        }

        final class ReaderView: NSView {
            var grid: [[RGB]] = []
            var center = RGB.black

            override var isFlipped: Bool { true }

            override func draw(_ dirtyRect: NSRect) {
                guard let ctx = NSGraphicsContext.current?.cgContext else { return }

                ctx.setFillColor(Theme.bg.cgColor)
                ctx.fill(bounds)
                ctx.setStrokeColor(Theme.borderStrong.cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))

                drawGrid(ctx, x: 8, y: 8)
                drawReadout(ctx, x: ReaderWindow.gridSide + 18, y: 8)
            }

            /// Grille agrandie : chaque carre est un pixel reel de l'ecran.
            private func drawGrid(_ ctx: CGContext, x ox: CGFloat, y oy: CGFloat) {
                guard grid.count == ColorReader.gridPixels else { return }
                let cell = ReaderWindow.cellSize
                let side = ReaderWindow.gridSide

                for y in 0..<ColorReader.gridPixels {
                    for x in 0..<ColorReader.gridPixels {
                        ctx.setFillColor(grid[x][y].cgColor)
                        ctx.fill(CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell,
                                        width: cell, height: cell))
                    }
                }

                ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.27))
                ctx.setLineWidth(1)
                for i in 0...ColorReader.gridPixels {
                    let p = CGFloat(i) * cell
                    ctx.move(to: CGPoint(x: ox + p, y: oy)); ctx.addLine(to: CGPoint(x: ox + p, y: oy + side))
                    ctx.move(to: CGPoint(x: ox, y: oy + p)); ctx.addLine(to: CGPoint(x: ox + side, y: oy + p))
                }
                ctx.strokePath()

                // Le pixel effectivement mesure, cercle de blanc puis de noir : le
                // repere reste visible quel que soit le fond qu'il entoure.
                let c = CGFloat(ColorReader.gridPixels / 2)
                let target = CGRect(x: ox + c * cell, y: oy + c * cell, width: cell, height: cell)
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(target.insetBy(dx: -1.5, dy: -1.5))
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(2)
                ctx.stroke(target)

                ctx.setStrokeColor(Theme.border.cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(CGRect(x: ox, y: oy, width: side, height: side))
            }

            private func drawReadout(_ ctx: CGContext, x ox: CGFloat, y oy: CGFloat) {
                let swatch = CGRect(x: ox, y: oy, width: 44, height: 44)
                ctx.setFillColor(center.cgColor)
                ctx.fill(swatch)
                ctx.setStrokeColor(Theme.borderStrong.cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(swatch)

                let name = Vision.describeColor(center)
                let hex = center.hex
                let rgbText = "R \(center.r)   V \(center.g)   B \(center.b)"

                Draw.text(name.capitalizedFirst, in: NSRect(x: ox + 54, y: oy - 2, width: ReaderWindow.panelWidth - 62, height: 20),
                          font: Theme.heading, color: Theme.fg)
                Draw.text(hex, in: NSRect(x: ox + 54, y: oy + 20, width: ReaderWindow.panelWidth - 62, height: 16),
                          font: Theme.mono, color: Theme.accent)
                Draw.text(rgbText, in: NSRect(x: ox + 54, y: oy + 36, width: ReaderWindow.panelWidth - 62, height: 16),
                          font: Theme.mono, color: Theme.dim)
                Draw.text("⌃⌥⇧C : copier   -   ⌃⌥C : fermer",
                          in: NSRect(x: ox, y: oy + ReaderWindow.gridSide - 20,
                                     width: ReaderWindow.panelWidth, height: 16),
                          font: Theme.small, color: Theme.faint)
            }
        }
    }
}

extension String {
    /// Premiere lettre en capitale, sans toucher au reste - `capitalized`
    /// majusculerait chaque mot et transformerait « vert olive » en « Vert Olive ».
    public var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
