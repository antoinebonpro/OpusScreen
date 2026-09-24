import Foundation

/// Ce que l'on sait des deficiences visuelles, mis a la portee de l'interface :
/// les intitules, les explications, et les paires de couleurs sur lesquelles se
/// juge reellement l'efficacite d'un filtre.
///
/// Aucun appel systeme ici : uniquement du savoir metier, testable a froid.
///
/// Sources du contenu : nomenclature clinique usuelle des dyschromatopsies,
/// planches de confusion de type Ishihara pour le choix des paires, et
/// recommandations d'accessibilite en basse vision (contraste et luminance).
public enum Vision {

    // ------------------------------------------------------------------ intitules

    /// Nom courant, celui qu'une personne concernee reconnaitra.
    public static func plainName(_ f: ColorFilter) -> String {
        switch f {
        case .protanopia: return "Rouge mal percu"
        case .deuteranopia: return "Vert mal percu"
        case .tritanopia: return "Bleu mal percu"
        default: return "Aucune correction"
        }
    }

    /// Nom clinique, avec la frequence dans la population.
    public static func clinicalName(_ f: ColorFilter) -> String {
        switch f {
        case .protanopia:
            return "Protanopie / protanomalie - environ 1 homme sur 100"
        case .deuteranopia:
            return "Deuteranopie / deuteranomalie - environ 6 hommes sur 100, "
                 + "la forme de loin la plus repandue"
        case .tritanopia:
            return "Tritanopie / tritanomalie - moins de 1 personne sur 1000, "
                 + "sans difference entre les sexes"
        default:
            return ""
        }
    }

    /// Ce que la personne confond concretement, en langage ordinaire.
    public static func confusions(_ f: ColorFilter) -> String {
        switch f {
        case .protanopia:
            return "Le rouge parait sombre, presque noir. Rouge et vert se confondent, "
                 + "mais aussi rouge et brun, rose et gris, violet et bleu."
        case .deuteranopia:
            return "Le vert et le rouge se confondent sans que le rouge s'assombrisse. "
                 + "Vert et brun, rose et gris, turquoise et gris se melangent aussi."
        case .tritanopia:
            return "Bleu et vert se confondent, jaune et rose egalement. "
                 + "Le violet devient indistinguable du rouge."
        default:
            return ""
        }
    }

    /// Gravite en mots. Un pourcentage seul ne dit rien a personne.
    public static func severityWord(_ severity: Double) -> String {
        if severity < 5 { return "vision normale" }
        if severity < 35 { return "anomalie legere" }
        if severity < 70 { return "anomalie moderee" }
        if severity < 95 { return "anomalie severe" }
        return "dichromatie complete"
    }

    // ------------------------------------------------------------------ paires de confusion

    /// Deux couleurs qu'une deficience donnee tend a rendre identiques.
    public struct Pair {
        public let a: RGB
        public let b: RGB
        public let label: String
        public init(_ a: RGB, _ b: RGB, _ label: String) { self.a = a; self.b = b; self.label = label }
    }

    /// Direction de confusion : le deplacement de couleur auquel cette deficience
    /// est le plus aveugle.
    ///
    /// Elle est CALCULEE a partir de la matrice de simulation, et non choisie a la
    /// main. La difference n'est pas theorique : une premiere version listait des
    /// paires « rouge / vert », « rose / gris » ecrites d'apres le sens commun.
    /// Verifiees, elles se revelaient parfaitement distinctes une fois simulees -
    /// elles differaient surtout par la CLARTE, que la deficience ne touche pas.
    /// Le comparateur montrait donc des couleurs que la personne distingue deja,
    /// et concluait a l'inutilite d'une correction qui, elle, fonctionnait.
    ///
    /// La direction cherchee est celle que la simulation ecrase le plus : le
    /// vecteur v qui minimise |v x M|, c'est-a-dire le vecteur propre de M x Mt
    /// associe a la plus petite valeur propre. Il est obtenu par iteration inverse,
    /// qui converge en quelques tours sur une matrice 3x3.
    public static func confusionDirection(_ f: ColorFilter) -> [Double] {
        let kind: ColorFilter = (f == .protanopia || f == .deuteranopia || f == .tritanopia)
            ? f : .deuteranopia

        let m = ColorMatrixEffect.simulationMatrix(kind)

        // A = M x Mt : symetrique definie positive, ses vecteurs propres sont ceux
        // que l'on cherche et ses valeurs propres mesurent l'ecrasement.
        var a = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for i in 0..<3 {
            for j in 0..<3 {
                var s = 0.0
                for k in 0..<3 { s += m[i][k] * m[j][k] }
                a[i][j] = s
            }
        }

        guard let inv = invert3(a) else { return [1, -1, 0] }   // repli : l'axe rouge-vert

        // Iteration inverse : multiplier par A^-1 amplifie la plus PETITE valeur
        // propre de A, donc converge vers la direction la plus ecrasee.
        var v = [0.577, -0.577, 0.577]
        for _ in 0..<60 {
            var w = [Double](repeating: 0, count: 3)
            for i in 0..<3 {
                w[i] = inv[i][0] * v[0] + inv[i][1] * v[1] + inv[i][2] * v[2]
            }
            let norm = (w[0] * w[0] + w[1] * w[1] + w[2] * w[2]).squareRoot()
            if norm < 1e-12 { break }
            v[0] = w[0] / norm; v[1] = w[1] / norm; v[2] = w[2] / norm
        }
        return v
    }

    private static func invert3(_ m: [[Double]]) -> [[Double]]? {
        let det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        if abs(det) < 1e-12 { return nil }

        var r = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        r[0][0] = (m[1][1] * m[2][2] - m[1][2] * m[2][1]) / det
        r[0][1] = (m[0][2] * m[2][1] - m[0][1] * m[2][2]) / det
        r[0][2] = (m[0][1] * m[1][2] - m[0][2] * m[1][1]) / det
        r[1][0] = (m[1][2] * m[2][0] - m[1][0] * m[2][2]) / det
        r[1][1] = (m[0][0] * m[2][2] - m[0][2] * m[2][0]) / det
        r[1][2] = (m[0][2] * m[1][0] - m[0][0] * m[1][2]) / det
        r[2][0] = (m[1][0] * m[2][1] - m[1][1] * m[2][0]) / det
        r[2][1] = (m[0][1] * m[2][0] - m[0][0] * m[2][1]) / det
        r[2][2] = (m[0][0] * m[1][1] - m[0][1] * m[1][0]) / det
        return r
    }

    /// Couleurs de depart des paires : des tons moyens, assez ecartes en teinte
    /// pour que le comparateur ne montre pas quatre fois la meme chose. La clarte
    /// reste au milieu de la plage, seul endroit ou l'on peut s'ecarter loin dans
    /// les deux sens sans sortir des couleurs affichables.
    private static let anchors: [[Double]] = [
        [0.50, 0.50, 0.50],
        [0.60, 0.46, 0.42],
        [0.44, 0.54, 0.46],
        [0.48, 0.46, 0.60],
    ]

    /// Les paires servent a repondre a la seule question qui vaille devant un
    /// filtre : « est-ce que je vois maintenant une difference la ou je n'en
    /// voyais pas ? » Un nuancier ordinaire ne repond pas a cette question,
    /// parce qu'il ne met pas cote a cote les couleurs qui se confondent.
    public static func confusionPairs(_ f: ColorFilter) -> [Pair] {
        confusionPairs(f, 100)
    }

    /// Version tenant compte de la gravite reglee.
    ///
    /// Le parametre n'est pas un raffinement : les paires doivent etre confondues
    /// PAR CETTE PERSONNE. Construites a gravite maximale puis montrees a quelqu'un
    /// regle sur une anomalie moderee, elles ressortaient parfaitement distinctes -
    /// le comparateur affichait « distinctes » des la colonne de gauche et donnait
    /// l'impression que la correction ne servait a rien.
    public static func confusionPairs(_ f: ColorFilter, _ severityPercent: Double) -> [Pair] {
        var pairs: [Pair] = []
        let d = confusionDirection(f)

        let kind: ColorFilter = (f == .protanopia || f == .deuteranopia || f == .tritanopia)
            ? f : .deuteranopia
        let sim = ColorMatrixEffect.buildMatrix(100, kind, severityPercent, 100, .simulation)

        for anchor in anchors {
            let t = confusedSpread(anchor, d, sim)

            let a = rgb(anchor, d, -t / 2)
            let b = rgb(anchor, d, +t / 2)

            // Seul cas ou l'ancrage n'apprend rien : les deux couleurs tombent sur
            // la meme valeur affichable. Le seuil porte donc sur le resultat et non
            // sur l'ecart theorique - un ecart de trois niveaux sur 255 suffit a
            // produire deux pastilles distinctes une fois la correction appliquee.
            if a == b { continue }

            // Quand l'ecart tenable est faible, les deux couleurs tombent sous le
            // meme nom. « gris / gris » ne dit rien : on annonce alors la nuance.
            let na = nameOf(a), nb = nameOf(b)
            pairs.append(Pair(a, b, na == nb ? na + ", deux nuances" : na + " / " + nb))
        }

        // Toujours au moins une paire a montrer, meme si la geometrie se derobe.
        if pairs.isEmpty {
            pairs.append(Pair(RGB(214, 62, 62), RGB(88, 158, 62), "rouge / vert"))
        }

        return pairs
    }

    /// Le plus grand ecart qui reste INDISTINGUABLE une fois simule.
    ///
    /// Prendre simplement l'ecart maximal que la gamme autorise ne convient pas :
    /// les modeles de simulation ecrasent l'axe de confusion sans l'annuler tout a
    /// fait, si bien que deux couleurs tres eloignees finissent par se distinguer
    /// meme apres simulation. Le comparateur affichait alors « distinctes » dans la
    /// colonne « aujourd'hui » - c'est-a-dire l'inverse de ce qu'il doit montrer.
    ///
    /// On cherche donc par dichotomie le plus grand ecart dont la difference percue
    /// reste sous le seuil de perception. Les couleurs obtenues sont, par mesure et
    /// non par affirmation, celles que la personne ne peut pas separer.
    private static func confusedSpread(_ anchor: [Double], _ d: [Double], _ sim: [Float]) -> Double {
        let maxT = maxSpread(anchor, d)
        if maxT < 0.05 { return 0 }

        // Meme au maximum la paire reste confondue : autant la montrer bien ecartee.
        if simulatedDelta(anchor, d, maxT, sim) <= justNoticeable { return maxT }

        var lo = 0.0, hi = maxT
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if simulatedDelta(anchor, d, mid, sim) <= justNoticeable { lo = mid } else { hi = mid }
        }
        return lo
    }

    private static func simulatedDelta(_ anchor: [Double], _ d: [Double], _ t: Double, _ sim: [Float]) -> Double {
        let a = ColorMatrixEffect.transform(sim, rgb(anchor, d, -t / 2))
        let b = ColorMatrixEffect.transform(sim, rgb(anchor, d, +t / 2))
        return deltaE(a, b)
    }

    /// Plus grand ecart tenable de part et d'autre de l'ancrage sans sortir des
    /// couleurs affichables. Les bornes s'arretent avant 0 et 1 : une couleur
    /// ecretee cesse d'etre sur la direction de confusion, et la paire ne serait
    /// alors plus confondue pour de mauvaises raisons.
    static func maxSpread(_ anchor: [Double], _ d: [Double]) -> Double {
        let lo = 0.06, hi = 0.94
        var t = 2.0
        for i in 0..<3 {
            if abs(d[i]) < 1e-6 { continue }
            let roomLow = (anchor[i] - lo) / abs(d[i])
            let roomHigh = (hi - anchor[i]) / abs(d[i])
            t = min(t, 2.0 * min(roomLow, roomHigh))
        }
        return t
    }

    static func rgb(_ anchor: [Double], _ d: [Double], _ t: Double) -> RGB {
        RGB(component(anchor[0] + d[0] * t),
            component(anchor[1] + d[1] * t),
            component(anchor[2] + d[2] * t))
    }

    static func component(_ v: Double) -> Int {
        let i = Int((v * 255).rounded())
        return i < 0 ? 0 : (i > 255 ? 255 : i)
    }

    /// Ecart percu entre deux couleurs, en Delta E CIE76.
    ///
    /// Sert a chiffrer ce que l'oeil constate : un filtre est utile si l'ecart
    /// entre les deux couleurs d'une paire AUGMENTE une fois le filtre passe.
    /// En dessous de 2,3 - le seuil de perception habituellement retenu - deux
    /// couleurs sont considerees comme identiques.
    public static let justNoticeable = 2.3

    public static func deltaE(_ a: RGB, _ b: RGB) -> Double {
        let la = toLab(a), lb = toLab(b)
        let dl = la[0] - lb[0], da = la[1] - lb[1], db = la[2] - lb[2]
        return (dl * dl + da * da + db * db).squareRoot()
    }

    /// sRGB -> CIE L*a*b*, illuminant D65. Etape obligee pour parler d'ecart percu.
    public static func toLab(_ c: RGB) -> [Double] {
        let r = linear(Double(c.r) / 255.0)
        let g = linear(Double(c.g) / 255.0)
        let b = linear(Double(c.b) / 255.0)

        // sRGB -> XYZ (D65)
        var x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
        var y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
        var z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041

        // Normalisation par le blanc de reference D65
        x /= 0.95047; y /= 1.00000; z /= 1.08883

        let fx = pivot(x), fy = pivot(y), fz = pivot(z)
        return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
    }

    private static func linear(_ s: Double) -> Double {
        s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }

    private static func pivot(_ t: Double) -> Double {
        t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0)
    }

    // ------------------------------------------------------------------ nom des couleurs

    private struct Named {
        let name: String
        let color: RGB
        let lab: [Double]
        init(_ name: String, _ r: Int, _ g: Int, _ b: Int) {
            self.name = name
            self.color = RGB(r, g, b)
            self.lab = Vision.toLab(self.color)
        }
    }

    /// Repertoire de reference pour nommer une couleur.
    ///
    /// Volontairement court et ordinaire : l'interet de l'outil est d'entendre
    /// « vert olive », pas « chartreuse foncee ». Une liste de 140 noms rendrait
    /// la reponse precise et inutilisable.
    private static let palette: [Named] = [
        Named("noir",            0,   0,   0),
        Named("gris tres fonce", 48,  48,  48),
        Named("gris fonce",      90,  90,  90),
        Named("gris",           128, 128, 128),
        Named("gris clair",     190, 190, 190),
        Named("blanc",          255, 255, 255),

        Named("rouge",          220,  20,  30),
        Named("rouge fonce",    130,  20,  25),
        Named("bordeaux",       110,  30,  50),
        Named("rose",           244, 150, 175),
        Named("rose vif",       236,  70, 140),
        Named("saumon",         242, 140, 120),
        Named("corail",         240, 110,  80),

        Named("orange",         246, 140,  30),
        Named("orange fonce",   200,  95,  20),
        Named("brun",           130,  90,  55),
        Named("brun clair",     176, 138,  96),
        Named("beige",          226, 208, 176),
        Named("ocre",           192, 150,  60),

        Named("jaune",          248, 220,  50),
        Named("jaune pale",     246, 238, 160),
        Named("moutarde",       200, 168,  40),
        Named("vert olive",     128, 140,  50),
        Named("vert citron",    160, 210,  60),

        Named("vert",            50, 160,  70),
        Named("vert fonce",      25,  95,  50),
        Named("vert clair",     140, 210, 140),
        Named("turquoise",       40, 180, 170),
        Named("cyan",            60, 210, 230),

        Named("bleu ciel",      120, 180, 240),
        Named("bleu",            40, 100, 210),
        Named("bleu fonce",      25,  50, 130),
        Named("bleu marine",     22,  36,  80),
        Named("indigo",          80,  70, 180),

        Named("violet",         140,  80, 190),
        Named("violet fonce",    90,  45, 130),
        Named("mauve",          190, 150, 215),
        Named("magenta",        215,  60, 190),
        Named("prune",          130,  60, 110),
    ]

    /// Nom francais de la couleur la plus proche, au sens de l'ecart percu.
    ///
    /// La comparaison a lieu en L*a*b* et non en RVB : en RVB, deux couleurs
    /// separees par la meme distance numerique peuvent etre l'une identique et
    /// l'autre franchement differente pour l'oeil. C'est precisement l'erreur
    /// que ne peut pas se permettre un outil dont le seul role est de dire
    /// a quelqu'un ce qu'il ne voit pas.
    public static func nameOf(_ c: RGB) -> String {
        let lab = toLab(c)
        var best = Double.greatestFiniteMagnitude
        var name = "couleur"

        for n in palette {
            let dl = lab[0] - n.lab[0], da = lab[1] - n.lab[1], db = lab[2] - n.lab[2]
            let d = dl * dl + da * da + db * db
            if d < best { best = d; name = n.name }
        }
        return name
    }

    /// Nom complet, avec la nuance quand la couleur est nettement plus claire ou sombre.
    public static func describeColor(_ c: RGB) -> String {
        let name = nameOf(c)
        let l = toLab(c)[0]

        // Les noms qui portent deja une nuance de clarte ne se cumulent pas.
        let alreadyQualified = name.contains("clair") || name.contains("fonce")
                            || name.contains("pale") || name == "noir" || name == "blanc"

        if !alreadyQualified {
            if l < 25 { return name + " tres fonce" }
            if l > 88 { return name + " tres clair" }
        }
        return name
    }
}
