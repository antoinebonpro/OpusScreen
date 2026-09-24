import Foundation
import AppKit

/// Loupe plein ecran : le bureau entier est agrandi et suit le pointeur.
///
/// Elle partage sa passe de calcul avec la matrice de couleur - c'est le meme
/// nuanceur, sur la meme image capturee. L'agrandissement et la correction du
/// daltonisme se cumulent donc sans se gener, ce que la loupe de macOS ne sait pas
/// faire : celle-ci ignore tout reglage de couleur, et les filtres de couleur du
/// systeme ignorent la loupe.
///
/// La regle de securite vaut ici comme pour la table de couleurs : une
/// transformation plein ecran laissee en place rend la machine difficile a
/// piloter. Elle est donc annulee par le raccourci de secours, a la fermeture, et
/// sur exception.
public enum ScreenMagnifier {
    public static let minZoom = 1.0
    public static let maxZoom = 8.0

    /// Vrai quand la loupe agrandit reellement l'ecran.
    public static var isActive: Bool { ScreenFilter.shared.magnifying }

    /// Faux quand le systeme a refuse : l'interface propose alors la loupe de macOS.
    public static var available: Bool { ScreenFilter.shared.available }

    public static var zoom: Double { ScreenFilter.shared.currentZoom }

    /// Regle le facteur d'agrandissement. 1,0 eteint la loupe.
    /// Retourne faux si le systeme n'accepte pas l'agrandissement plein ecran.
    @discardableResult
    public static func setZoom(_ value: Double) -> Bool {
        var z = value
        if z < minZoom { z = minZoom }
        if z > maxZoom { z = maxZoom }

        if z <= minZoom + 0.001 {
            stop()
            return true
        }
        if !available { return false }
        return ScreenFilter.shared.setZoom(z)
    }

    /// Remet l'ecran a l'echelle 1. Sans effet si la loupe n'est pas active.
    public static func stop() {
        _ = ScreenFilter.shared.setZoom(1.0)
    }

    /// Annulation inconditionnelle, appelable depuis n'importe quel etat.
    /// Utilisee par le filet de securite : elle ne suppose rien de l'etat interne.
    public static func forceReset() {
        ScreenFilter.shared.panicStop()
    }

    // ------------------------------------------------------------------ repli

    /// Ouvre le Zoom d'accessibilite de macOS.
    ///
    /// Repli assume : sur les machines ou l'enregistrement de l'ecran est refuse -
    /// politique d'entreprise, session distante - mieux vaut conduire l'utilisateur
    /// vers l'outil integre que lui laisser un interrupteur qui ne fait rien.
    @discardableResult
    public static func openSystemZoom() -> Bool {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Zoom")!
        return NSWorkspace.shared.open(url)
    }
}
