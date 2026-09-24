import Foundation
import AppKit

/// Les quelques gestes de dessin que toute l'interface repete.
///
/// L'application dessine ses controles a la main - curseurs, interrupteurs,
/// listes, icones. Sans ce fichier, chacun redefinirait sa facon de poser du
/// texte, et la moindre correction de mise en page serait a faire vingt fois.
public enum Draw {

    public enum Align { case left, center, right }

    /// Pose du texte dans un rectangle, centre verticalement, avec points de
    /// suspension si la place manque.
    public static func text(_ string: String, in rect: NSRect, font: NSFont, color: NSColor,
                            align: Align = .left, wrap: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = align.nsAlignment
        style.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]

        let attributed = NSAttributedString(string: string, attributes: attributes)

        if wrap {
            // Les MEMES options qu'a la mesure, et ce n'est pas un detail : sans
            // `usesFontLeading`, le dessin compte une interligne differente de
            // celle qui a servi a calculer la boite. L'ecart vaut une fraction de
            // point par ligne - assez, sur un paragraphe de quatre lignes, pour
            // que la derniere ne tienne plus et disparaisse. Et comme rien ne
            // tronque plus, une boite mal calculee se verrait au lieu de se
            // cacher derriere des points de suspension.
            attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            return
        }

        // Centre vertical : un texte pose au bord haut d'une ligne de 36 points
        // flotte visiblement au-dessus du curseur qu'il etiquette.
        let height = attributed.size().height
        let y = rect.minY + (rect.height - height) / 2
        attributed.draw(with: NSRect(x: rect.minX, y: y, width: rect.width, height: height),
                        options: [.usesLineFragmentOrigin])
    }

    /// Hauteur qu'il faut reserver a un texte pour qu'il tienne en entier.
    ///
    /// Mesuree avec le MEME moteur que celui qui le dessinera. Mesurer autrement
    /// se paie en texte tranche : les deux ne coupent pas les lignes au meme
    /// endroit.
    public static func height(of string: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font, .paragraphStyle: style,
        ])
        let bounds = attributed.boundingRect(
            with: NSSize(width: max(60, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(bounds.height) + 2
    }

    public static func width(of string: String, font: NSFont) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        return ceil(NSAttributedString(string: string, attributes: [.font: font]).size().width)
    }

    /// Rectangle plein.
    public static func fill(_ rect: NSRect, _ color: NSColor) {
        color.setFill()
        rect.fill()
    }

    /// Rectangle a coins arrondis.
    public static func fill(_ rect: NSRect, radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    public static func stroke(_ rect: NSRect, _ color: NSColor, width: CGFloat = 1) {
        color.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: width / 2, dy: width / 2))
        path.lineWidth = width
        path.stroke()
    }

    public static func stroke(_ rect: NSRect, radius: CGFloat, _ color: NSColor, width: CGFloat = 1) {
        color.setStroke()
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2),
                                xRadius: radius, yRadius: radius)
        path.lineWidth = width
        path.stroke()
    }

    /// Anneau de focus, dessine autour d'un controle atteint au clavier.
    ///
    /// Il est indispensable et il est verifie : un controle dessine a la main ne
    /// recoit aucun halo du systeme, et sans lui le parcours au clavier avance a
    /// l'aveugle - dans une application dont l'accessibilite est l'argument.
    public static func focusRing(_ rect: NSRect, radius: CGFloat = 4) {
        stroke(rect.insetBy(dx: -2, dy: -2), radius: radius + 2, Theme.focus, width: 2)
    }
}

extension Draw.Align {
    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}
