import Foundation

/// Ce que l'on demande a un filtre de deficience chromatique.
///
/// Les deux usages n'ont rien a voir et sont pourtant servis par les memes
/// matrices : la personne daltonienne veut ECARTER les couleurs qu'elle confond,
/// le concepteur d'interface veut VOIR ce qu'elle percoit. Un seul reglage pour
/// les deux serait ambigu ; deux modes explicites ne le sont pas.
public enum FilterMode: Int {
    case correction = 0   // aide : les couleurs confondues sont ecartees
    case simulation = 1   // demonstration : on affiche la vision deficiente
}

/// Quatrieme etage du pipeline : une matrice de couleur appliquee a tout l'affichage.
///
/// Pourquoi cet etage existe : une table de couleurs traite chaque canal SEPAREMENT.
/// Elle peut assombrir le bleu, mais elle ne peut pas calculer une valeur de rouge
/// qui depend du vert. Or c'est exactement ce qu'exigent la saturation, l'inversion,
/// le sepia et les filtres pour daltoniens.
///
/// Windows offrait `MagSetFullscreenColorEffect`, une matrice 5x5 posee par le
/// compositeur. macOS n'a pas d'equivalent : ses filtres de couleur d'accessibilite
/// ne prennent que cinq reglages figes, sans matrice libre. L'etage est donc
/// reconstruit - capture de l'affichage par ScreenCaptureKit, matrice appliquee par
/// un nuanceur Metal, resultat repose par-dessus l'ecran. C'est plus de travail,
/// c'est la seule facon d'obtenir une matrice quelconque, et cela offre au passage
/// ce que Windows n'avait pas : un filtre REGLABLE ECRAN PAR ECRAN.
///
/// L'algebre ci-dessous est celle de la version Windows, a la virgule pres : c'est
/// elle qui est verifiee par les tests, et elle ne depend d'aucun systeme.
public enum ColorMatrixEffect {

    /// Faux quand l'etage ne peut pas fonctionner - autorisation d'enregistrement
    /// de l'ecran refusee, machine sans Metal. L'interface le dit alors, plutot que
    /// de laisser un interrupteur sans effet.
    public static var available: Bool { ScreenFilter.shared.available }

    public static var isActive: Bool { ScreenFilter.shared.matrixActive }

    /// Ce qui manque pour que l'etage fonctionne, en une phrase. Vide s'il fonctionne.
    public static var unavailableReason: String { ScreenFilter.shared.unavailableReason }

    // ------------------------------------------------------------------ application

    /// Applique saturation et filtre simple.
    @discardableResult
    public static func apply(_ saturationPercent: Double, _ filter: ColorFilter) -> Bool {
        apply(saturationPercent, filter, 100, 100, .correction)
    }

    /// Applique l'etage complet, globalement.
    ///
    ///   severityPercent : gravite de la deficience, 0 = vision normale,
    ///                     100 = dichromatie complete. Entre les deux se trouvent
    ///                     les ANOMALIES (protanomalie, deuteranomalie...), de loin
    ///                     les plus repandues.
    ///   strengthPercent : intensite de la correction, sans effet en simulation.
    @discardableResult
    public static func apply(_ saturationPercent: Double, _ filter: ColorFilter,
                             _ severityPercent: Double, _ strengthPercent: Double,
                             _ mode: FilterMode) -> Bool {
        if isNeutralRequest(saturationPercent, filter, severityPercent, strengthPercent, mode) {
            reset()
            return true
        }
        let m = buildMatrix(saturationPercent, filter, severityPercent, strengthPercent, mode)
        return ScreenFilter.shared.setMatrixEverywhere(m)
    }

    /// Vrai si le reglage demande ne modifie rien : inutile d'armer l'etage.
    public static func isNeutralRequest(_ saturationPercent: Double, _ filter: ColorFilter,
                                        _ severityPercent: Double, _ strengthPercent: Double,
                                        _ mode: FilterMode) -> Bool {
        if abs(saturationPercent - 100) >= 0.5 { return false }
        if filter == .none { return true }

        if isVisionFilter(filter) {
            if severityPercent < 0.5 { return true }
            if mode == .correction && strengthPercent < 0.5 { return true }
        }
        return false
    }

    /// Filtres pilotes par la gravite : ceux qui modelisent une deficience.
    public static func isVisionFilter(_ f: ColorFilter) -> Bool {
        f == .protanopia || f == .deuteranopia || f == .tritanopia
    }

    /// Remet la matrice identite : l'affichage retrouve ses couleurs exactes.
    public static func reset() {
        ScreenFilter.shared.clearMatrix()
    }

    public static func shutdown() {
        ScreenFilter.shared.shutdown()
    }

    // ------------------------------------------------------------------ algebre
    //
    // Convention reprise telle quelle de l'API Windows : le pixel est un vecteur
    // ligne [R G B A 1] multiplie a GAUCHE de la matrice. Donc
    // out[col] = somme sur row de in[row] * M[row][col]. La cinquieme ligne porte
    // les decalages constants.
    //
    // La conserver, plutot que de passer a la convention colonne plus courante en
    // graphisme, garde les matrices identiques a celles des documents et des tests
    // de la version d'origine - et evite l'erreur de transposition silencieuse, qui
    // rend des couleurs plausibles et fausses.

    public static func identity() -> [Float] {
        var m = [Float](repeating: 0, count: 25)
        for i in 0..<5 { m[i * 5 + i] = 1 }
        return m
    }

    /// Produit de deux matrices 5x5 stockees a plat.
    private static func multiply(_ a: [Float], _ b: [Float]) -> [Float] {
        var r = [Float](repeating: 0, count: 25)
        for i in 0..<5 {
            for j in 0..<5 {
                var sum: Float = 0
                for k in 0..<5 { sum += a[i * 5 + k] * b[k * 5 + j] }
                r[i * 5 + j] = sum
            }
        }
        return r
    }

    /// La matrice complete, saturation et filtre compris.
    ///
    /// Expose publiquement pour une raison precise : l'apercu de la page Couleur
    /// doit passer les couleurs par EXACTEMENT le meme calcul que l'ecran. Une
    /// version reecrite a cote avait fini par diverger - l'apercu ignorait purement
    /// et simplement les filtres pour daltoniens, qui sont pourtant ceux que l'on
    /// a le plus besoin de comparer avant de les appliquer.
    public static func buildMatrix(_ saturationPercent: Double, _ filter: ColorFilter,
                                   _ severityPercent: Double, _ strengthPercent: Double,
                                   _ mode: FilterMode) -> [Float] {
        multiply(saturationMatrix(saturationPercent / 100.0),
                 filterMatrix(filter, severityPercent, strengthPercent, mode))
    }

    // Coefficients de luminance perceptuelle (Rec. 709), les memes que ceux
    // utilises pour convertir en niveaux de gris.
    private static let lr = 0.2126, lg = 0.7152, lb = 0.0722

    /// s = 0 -> niveaux de gris, s = 1 -> inchange, s = 2 -> tres sature.
    private static func saturationMatrix(_ s: Double) -> [Float] {
        var m = identity()
        let inv = 1.0 - s

        m[0] = Float(lr * inv + s); m[1] = Float(lr * inv); m[2] = Float(lr * inv)
        m[5] = Float(lg * inv); m[6] = Float(lg * inv + s); m[7] = Float(lg * inv)
        m[10] = Float(lb * inv); m[11] = Float(lb * inv); m[12] = Float(lb * inv + s)
        return m
    }

    private static func filterMatrix(_ f: ColorFilter, _ severityPercent: Double,
                                     _ strengthPercent: Double, _ mode: FilterMode) -> [Float] {
        switch f {
        case .grayscale:
            return saturationMatrix(0)

        case .invert:
            var m = identity()
            m[0] = -1; m[6] = -1; m[12] = -1
            m[20] = 1; m[21] = 1; m[22] = 1   // decalage : out = 1 - in
            return m

        case .invertKeepHue:
            return invertKeepHue()

        case .sepia:
            var m = identity()
            // colonnes = destination R, G, B
            m[0] = 0.393; m[1] = 0.349; m[2] = 0.272
            m[5] = 0.769; m[6] = 0.686; m[7] = 0.534
            m[10] = 0.189; m[11] = 0.168; m[12] = 0.131
            return m

        case .protanopia, .deuteranopia, .tritanopia:
            return mode == .simulation
                ? expand(simulation(f, severityPercent / 100.0))
                : daltonize(f, severityPercent / 100.0, strengthPercent / 100.0)

        default:
            return identity()
        }
    }

    // ------------------------------------------------------------------ inversion douce

    /// Inversion de la LUMINOSITE, teintes conservees.
    ///
    /// L'inversion classique retourne aussi les teintes : le rouge devient cyan,
    /// une photo devient un negatif. C'est ce qui rend le « mode programmation »
    /// inutilisable des qu'une image est a l'ecran. Ici on inverse le clair et le
    /// sombre en laissant la teinte ou elle etait, ce qu'iOS appelle « inversion
    /// intelligente ».
    ///
    ///     inverser puis tourner la teinte d'un demi-tour se resume a
    ///         sortie = entree + (1 - 2 x luminance) x blanc
    ///
    /// Le blanc devient noir, le noir devient blanc, et un rouge sombre devient un
    /// rouge clair au lieu d'un cyan. Les hautes lumieres saturees sortent de la
    /// plage affichable et sont ecretees : c'est le prix de la conservation des
    /// teintes, et c'est le meme compromis que fait iOS.
    private static func invertKeepHue() -> [Float] {
        var m = identity()
        let lum = [lr, lg, lb]
        for i in 0..<3 {
            for j in 0..<3 {
                m[i * 5 + j] = Float((i == j ? 1.0 : 0.0) - 2.0 * lum[i])
            }
        }
        m[20] = 1; m[21] = 1; m[22] = 1   // le +1 constant
        return m
    }

    // ------------------------------------------------------------------ daltonisme

    /// Matrices de simulation a pleine gravite, en convention entree -> sortie.
    ///
    /// Ce sont les matrices classiques de la litterature (Vienot, Brettel, reprises
    /// par Fidaner) : elles ecrasent fortement l'axe de confusion propre a chaque
    /// deficience, de sorte que deux couleurs separees le long de cet axe ressortent
    /// quasi identiques.
    public static func simulationMatrix(_ f: ColorFilter) -> [[Double]] {
        fullSimulation(f)
    }

    private static func fullSimulation(_ f: ColorFilter) -> [[Double]] {
        switch f {
        case .protanopia:
            return [[0.567, 0.558, 0.000],
                    [0.433, 0.442, 0.242],
                    [0.000, 0.000, 0.758]]
        case .deuteranopia:
            return [[0.625, 0.700, 0.000],
                    [0.375, 0.300, 0.300],
                    [0.000, 0.000, 0.700]]
        default: // tritanopie
            return [[0.950, 0.000, 0.000],
                    [0.050, 0.433, 0.475],
                    [0.000, 0.567, 0.525]]
        }
    }

    /// Simulation a gravite reglable.
    ///
    /// La dichromatie - l'absence totale d'un type de cone - est le cas rare.
    /// Le cas frequent est l'ANOMALIE : le cone existe mais sa sensibilite est
    /// decalee, et la confusion n'est que partielle. On interpole donc entre
    /// l'identite (vision normale) et la dichromatie complete.
    ///
    /// C'est une approximation, et elle est assumee comme telle : le modele exact
    /// demanderait de decaler le pic d'absorption du cone dans l'espace LMS, ce qui
    /// n'est pas representable par une interpolation lineaire. Mais elle conserve
    /// la propriete qui compte - l'axe de confusion reste le meme, seule son
    /// amplitude change - et c'est ce que fait aussi le reglage d'intensite des
    /// filtres de couleur de macOS.
    private static func simulation(_ f: ColorFilter, _ severityRaw: Double) -> [[Double]] {
        var severity = severityRaw
        if severity < 0 { severity = 0 }
        if severity > 1 { severity = 1 }

        let full = fullSimulation(f)
        var sim = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for i in 0..<3 {
            for j in 0..<3 {
                sim[i][j] = (1.0 - severity) * (i == j ? 1.0 : 0.0) + severity * full[i][j]
            }
        }
        return sim
    }

    /// Filtre d'assistance pour daltoniens, et non simulation de leur vision.
    ///
    /// Principe : on simule ce que la personne ne distingue pas, on mesure l'ecart
    /// avec l'image d'origine, et on reinjecte cet ecart sur les canaux qu'elle
    /// percoit encore. Deux couleurs autrefois confondues redeviennent distinctes.
    ///
    ///     erreur   = pixel x (I - Simulation)
    ///     resultat = pixel + intensite x erreur x Redistribution
    ///     donc  M  = I + intensite x (I - Simulation) x Redistribution
    ///
    /// L'ordre des deux produits n'est pas interchangeable : la redistribution
    /// s'applique A l'erreur, pas l'inverse. Le produit est calcule ici plutot
    /// qu'ecrit a la main pre-multiplie, pour que la formule reste verifiable.
    ///
    /// Propriete a preserver : comme la simulation laisse les gris intacts, chaque
    /// colonne de (I - Simulation) est de somme nulle. Un gris produit donc une
    /// erreur nulle et ressort inchange - le filtre ne teinte jamais l'interface.
    private static func daltonize(_ f: ColorFilter, _ severity: Double, _ strengthRaw: Double) -> [Float] {
        var strength = strengthRaw
        if strength < 0 { strength = 0 }
        if strength > 1.5 { strength = 1.5 }

        let sim = simulation(f, severity)

        // Ou reverser l'erreur de chaque canal. Le canal deficient cede son erreur
        // aux deux autres ; les canaux sains conservent la leur (diagonale a 1).
        let shift: [[Double]]
        if f == .tritanopia {
            shift = [[1.0, 0.0, 0.0],     // erreur du rouge -> rouge
                     [0.0, 1.0, 0.0],     // erreur du vert  -> vert
                     [0.7, 0.7, 0.0]]     // erreur du bleu  -> rouge et vert
        } else {
            shift = [[0.0, 0.7, 0.7],     // erreur du rouge -> vert et bleu
                     [0.0, 1.0, 0.0],
                     [0.0, 0.0, 1.0]]
        }

        // D = I - sim
        var d = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for i in 0..<3 {
            for j in 0..<3 { d[i][j] = ((i == j) ? 1.0 : 0.0) - sim[i][j] }
        }

        // M3 = I + intensite x D x shift
        var m3 = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for i in 0..<3 {
            for j in 0..<3 {
                var acc = 0.0
                for k in 0..<3 { acc += d[i][k] * shift[k][j] }
                m3[i][j] = ((i == j) ? 1.0 : 0.0) + strength * acc
            }
        }

        return expand(m3)
    }

    /// Passe d'une matrice couleur 3x3 a la matrice 5x5 du pipeline.
    private static func expand(_ m3: [[Double]]) -> [Float] {
        var m = identity()
        for i in 0..<3 {
            for j in 0..<3 { m[i * 5 + j] = Float(m3[i][j]) }
        }
        return m
    }

    // ------------------------------------------------------------------ usage hors ecran

    /// Passe une couleur dans une matrice 5x5, exactement comme le fait le nuanceur.
    /// Sert aux apercus et aux tests : une seule implementation de la regle, donc
    /// aucune divergence possible entre ce qui est montre et ce qui est applique.
    public static func transform(_ m: [Float], _ r: inout Double, _ g: inout Double, _ b: inout Double) {
        let inp: [Double] = [r, g, b, 1, 1]
        var or_ = 0.0, og = 0.0, ob = 0.0
        for i in 0..<5 {
            or_ += inp[i] * Double(m[i * 5 + 0])
            og += inp[i] * Double(m[i * 5 + 1])
            ob += inp[i] * Double(m[i * 5 + 2])
        }
        r = or_ < 0 ? 0 : (or_ > 1 ? 1 : or_)
        g = og < 0 ? 0 : (og > 1 ? 1 : og)
        b = ob < 0 ? 0 : (ob > 1 ? 1 : ob)
    }

    /// Version couleur, pour les apercus.
    public static func transform(_ m: [Float], _ c: RGB) -> RGB {
        var r = Double(c.r) / 255.0, g = Double(c.g) / 255.0, b = Double(c.b) / 255.0
        transform(m, &r, &g, &b)
        return RGB(Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
