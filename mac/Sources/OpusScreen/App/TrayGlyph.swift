import Foundation
import AppKit

/// L'icone de la barre des menus, dessinee a la demande.
///
/// Elle etait un disque plein dont la COULEUR disait l'etat de l'ecran. L'idee
/// etait juste - un regard suffisait a savoir ce que l'application faisait - mais
/// elle avait un defaut qu'aucun reglage ne corrigeait : au reglage par defaut,
/// 100 % et 6500 K, cette couleur est blanche. L'utilisateur voyait donc un point
/// blanc anonyme au milieu de vingt autres icones, et ne retrouvait pas son
/// application. Une icone qui ne se reconnait pas est une application perdue.
///
/// La forme reprend donc celle du logo - un oeil - et la couleur d'etat se
/// deplace du disque entier vers la PUPILLE. On ne perd rien : la teinte du soir,
/// la pastille de l'adaptation et la pause restent lisibles, mais a l'interieur
/// d'une silhouette qui, elle, ne change jamais.
///
/// Le dessin est TRACE a chaque taille plutot que reduit depuis le logo en pleine
/// resolution : c'est la seule facon d'obtenir une icone nette a dix-huit points.
public enum TrayGlyph {

    /// Turquoise du logo. Il tient le contraste aussi bien sur une barre claire
    /// que sombre - et sur macOS la barre des menus change de fond avec le fond
    /// d'ecran, pas seulement avec le theme.
    private static let ink = RGB(23, 190, 177)

    /// Gris neutre des effets suspendus : plus aucune couleur d'ecran annoncee.
    private static let inkOff = RGB(150, 156, 172)

    /// Dessine l'icone pour un etat donne.
    ///
    /// Fonction pure : elle ne lit aucun reglage global et ne touche a rien.
    /// C'est ce qui permet de la verifier par un test, ce qui serait impossible
    /// si elle vivait au milieu de la classe de la barre des menus.
    public static func draw(size: CGFloat, profile: Profile, suspended: Bool,
                            adaptive: Bool) -> NSImage {
        let side = max(8, size)
        let image = NSImage(size: NSSize(width: side, height: side))

        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        ctx.setShouldAntialias(true)

        let u = side / 32.0                            // tout est trace en unites de 32
        let stroke = max(1.4, 2.6 * u)
        let outline = suspended ? inkOff : ink

        // Le halo du boost, sous l'oeil : au-dela de 100 %, l'application ajoute
        // vraiment de la lumiere, et cela se voit sur l'icone.
        if !suspended && profile.brightness > 100 {
            let vivid = stateColor(profile)
            ctx.setFillColor(CGColor(srgbRed: CGFloat(vivid.r) / 255, green: CGFloat(vivid.g) / 255,
                                     blue: CGFloat(vivid.b) / 255, alpha: 0.24))
            ctx.fillEllipse(in: CGRect(x: 0.5 * u, y: 4 * u, width: 31 * u, height: 24 * u))
        }

        ctx.addPath(almond(u))
        ctx.setStrokeColor(outline.cgColor)
        ctx.setLineWidth(stroke)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        if suspended {
            // Deux barres, le signe universel de la pause. Elles prennent la place
            // de la pupille : l'oeil est la, il ne regarde plus.
            ctx.setFillColor(inkOff.cgColor)
            ctx.fill(CGRect(x: 13 * u, y: 12 * u, width: 2.6 * u, height: 8 * u))
            ctx.fill(CGRect(x: 17.4 * u, y: 12 * u, width: 2.6 * u, height: 8 * u))
        } else {
            // La pupille porte l'etat : sa couleur est celle que l'ecran rend.
            let pupil = CGRect(x: 11 * u, y: 11 * u, width: 10 * u, height: 10 * u)
            ctx.setFillColor(stateColor(profile).cgColor)
            ctx.fillEllipse(in: pupil)

            // Un cerne sombre separe une pupille tres claire d'une barre des menus
            // claire, ce qui arrive des que le fond d'ecran est pale.
            ctx.setStrokeColor(CGColor(srgbRed: 12 / 255, green: 32 / 255, blue: 38 / 255, alpha: 0.59))
            ctx.setLineWidth(max(1, 1.4 * u))
            ctx.strokeEllipse(in: pupil)
        }

        if adaptive {
            // La luminosite adaptative agit toute seule : le dire evite de chercher
            // pourquoi l'ecran bouge sans qu'on y touche.
            let badge = CGRect(x: 22 * u, y: 22 * u, width: 9 * u, height: 9 * u)
            ctx.setFillColor(RGB(86, 200, 130).cgColor)
            ctx.fillEllipse(in: badge)
            ctx.setStrokeColor(CGColor(srgbRed: 12 / 255, green: 32 / 255, blue: 38 / 255, alpha: 0.67))
            ctx.setLineWidth(max(1, 1.2 * u))
            ctx.strokeEllipse(in: badge)
        }

        return image
    }

    /// La silhouette en amande : deux courbes qui se rejoignent en pointe a gauche
    /// et a droite. C'est ce pincement lateral qui distingue l'oeil d'un disque, et
    /// il doit atteindre le bord - a dix-huit points, deux points de marge
    /// suffisent a transformer l'amande en rond.
    private static func almond(_ u: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let left = CGPoint(x: 1.5 * u, y: 16 * u)
        let right = CGPoint(x: 30.5 * u, y: 16 * u)

        path.move(to: left)
        path.addCurve(to: right,
                      control1: CGPoint(x: 9 * u, y: 4.5 * u),
                      control2: CGPoint(x: 23 * u, y: 4.5 * u))
        path.addCurve(to: left,
                      control1: CGPoint(x: 23 * u, y: 27.5 * u),
                      control2: CGPoint(x: 9 * u, y: 27.5 * u))
        path.closeSubpath()
        return path
    }

    /// La couleur que rend l'ecran avec ce profil : la temperature donne la
    /// teinte, la luminosite donne le niveau.
    public static func stateColor(_ p: Profile) -> RGB {
        let mult = ColorTemp.multipliers(p.kelvin)
        let b = p.brightness / 150.0
        let level = 58.0 + 195.0 * min(1.0, b * 1.15)
        return RGB(Int((level * mult[0]).rounded()),
                   Int((level * mult[1]).rounded()),
                   Int((level * mult[2]).rounded()))
    }
}

/// Le logo de l'application, embarque dans le paquet.
///
/// Il est charge HORS DU FIL PRINCIPAL, et ce n'est pas une optimisation.
///
/// Lire une ressource de son propre paquet passe par le systeme de fichiers. Si
/// l'application vit dans un dossier protege - le Bureau, Telechargements,
/// Documents - macOS y voit un acces a proteger et demande son accord a
/// l'utilisateur. La lecture BLOQUE alors jusqu'a la reponse. Faite sur le fil
/// principal pendant le lancement, elle fige l'application entiere : aucune
/// fenetre, aucune icone, rien qui explique l'attente.
///
/// Le logo arrive donc quand il arrive, et l'interface se construit sans
/// l'attendre.
public enum AppIcon {

    private static let lock = NSLock()
    private static var cached: NSImage?
    private static var loading = false
    private static var waiting: [(NSImage?) -> Void] = []

    /// Le logo s'il est deja la, sans jamais attendre.
    public static var logo: NSImage? {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    /// Demande le logo. Le bloc est appele sur le fil principal, tout de suite
    /// s'il est deja charge, plus tard sinon.
    public static func withLogo(_ completion: @escaping (NSImage?) -> Void) {
        lock.lock()
        if let image = cached {
            lock.unlock()
            DispatchQueue.main.async { completion(image) }
            return
        }
        waiting.append(completion)
        let shouldStart = !loading
        loading = true
        lock.unlock()

        guard shouldStart else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            var image: NSImage?
            if let url = Bundle.module.url(forResource: "logo", withExtension: "png") {
                image = NSImage(contentsOf: url)
            }

            lock.lock()
            cached = image
            loading = false
            let blocks = waiting
            waiting.removeAll()
            lock.unlock()

            DispatchQueue.main.async { for block in blocks { block(image) } }
        }
    }

    /// L'icone du paquet, derivee du logo.
    ///
    /// Elle est recadree au centre : le logo en pleine largeur devient illisible
    /// des qu'il descend sous soixante-quatre points, et le Dock comme le Finder
    /// l'affichent bien plus petit que cela.
    public static func appIcon(size: CGFloat) -> NSImage? {
        guard let logo = logo else { return nil }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()

        let source = logo.size
        let side = min(source.width, source.height)
        let crop = NSRect(x: (source.width - side) / 2, y: (source.height - side) / 2,
                          width: side, height: side)
        logo.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                  from: crop, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        return image
    }
}
