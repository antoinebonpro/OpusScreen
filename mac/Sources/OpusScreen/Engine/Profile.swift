import Foundation

/// Filtres qui melangent les canaux entre eux : impossibles avec une simple table.
public enum ColorFilter: Int, CaseIterable {
    case none = 0
    case grayscale      // niveaux de gris
    case invert         // inversion, le « mode programmation » d'Iris
    case sepia          // lecture prolongee
    case protanopia     // daltonisme : deficience du rouge
    case deuteranopia   // daltonisme : deficience du vert
    case tritanopia     // daltonisme : deficience du bleu
    case invertKeepHue  // inversion de la luminosite, teintes conservees
}

/// Un profil rassemble tout ce qui definit le rendu de l'ecran.
///
/// Les concurrents appellent cela des « modes » (Iris) ou des « presets » (Lunar).
/// Tout en est un ici, y compris l'etat courant : cela evite d'avoir deux
/// representations differentes des memes reglages.
public struct Profile {
    public var name = "Personnalise"

    // --- etage table de couleurs ---
    public var brightness: Double = 100   // 5 - 150
    public var kelvin: Int = 6500         // 1200 - 6500
    public var contrast: Double = 100     // 50 - 150
    public var gammaCurve: Double = 100   // 50 - 200, 100 = neutre
    public var redGain: Double = 100      // 0 - 150, balance manuelle des canaux
    public var greenGain: Double = 100
    public var blueGain: Double = 100

    // --- etage matrice de couleur ---
    public var saturation: Double = 100   // 0 = gris, 100 = normal, 200 = tres sature
    public var filter: ColorFilter = .none

    /// Gravite de la deficience chromatique, 0 a 100.
    ///
    /// 100 = dichromatie complete (le cone manque). En dessous : une ANOMALIE,
    /// c'est-a-dire un cone present mais decale - de tres loin le cas le plus
    /// frequent. Un filtre calibre uniquement sur la dichromatie sur-corrige
    /// donc la majorite des personnes concernees.
    public var visionSeverity: Double = 100

    /// Intensite de la correction daltonienne, 0 a 150. Sans effet en simulation.
    public var filterStrength: Double = 100

    /// Corriger la vision de l'utilisateur, ou montrer celle d'une autre personne.
    public var mode: FilterMode = .correction

    // --- etage voile ---
    public var tint: RGB = .black

    public init() {}

    public func clone() -> Profile { self }

    public mutating func copyFrom(_ o: Profile) {
        brightness = o.brightness; kelvin = o.kelvin; contrast = o.contrast
        gammaCurve = o.gammaCurve; redGain = o.redGain; greenGain = o.greenGain
        blueGain = o.blueGain; saturation = o.saturation; filter = o.filter; tint = o.tint
        visionSeverity = o.visionSeverity; filterStrength = o.filterStrength; mode = o.mode
    }

    /// Recopie ici les SEULS champs qui ont change entre deux etats d'un autre
    /// profil, et dit si quelque chose a bouge.
    ///
    /// Sert a repercuter un reglage general sur un ecran qui tient par ailleurs
    /// ses propres valeurs : bouger la luminosite generale ne doit pas remettre
    /// la temperature que cet ecran gardait a part. Recopier le profil entier
    /// serait plus court d'une ligne, et effacerait ce reglage a chaque passage -
    /// plusieurs fois par minute des que la luminosite adaptative tourne.
    @discardableResult
    public mutating func copyChanged(_ before: Profile, _ after: Profile) -> Bool {
        var any = false
        if Profile.differs(before.brightness, after.brightness) { brightness = after.brightness; any = true }
        if before.kelvin != after.kelvin { kelvin = after.kelvin; any = true }
        if Profile.differs(before.contrast, after.contrast) { contrast = after.contrast; any = true }
        if Profile.differs(before.gammaCurve, after.gammaCurve) { gammaCurve = after.gammaCurve; any = true }
        if Profile.differs(before.redGain, after.redGain) { redGain = after.redGain; any = true }
        if Profile.differs(before.greenGain, after.greenGain) { greenGain = after.greenGain; any = true }
        if Profile.differs(before.blueGain, after.blueGain) { blueGain = after.blueGain; any = true }
        if Profile.differs(before.saturation, after.saturation) { saturation = after.saturation; any = true }
        if before.filter != after.filter { filter = after.filter; any = true }
        if Profile.differs(before.visionSeverity, after.visionSeverity) { visionSeverity = after.visionSeverity; any = true }
        if Profile.differs(before.filterStrength, after.filterStrength) { filterStrength = after.filterStrength; any = true }
        if before.mode != after.mode { mode = after.mode; any = true }
        if before.tint != after.tint { tint = after.tint; any = true }
        return any
    }

    private static func differs(_ a: Double, _ b: Double) -> Bool { abs(a - b) > 0.005 }

    public func isNeutral() -> Bool {
        abs(brightness - 100) < 0.01
            && kelvin >= ColorTemp.maxKelvin
            && abs(contrast - 100) < 0.01
            && abs(gammaCurve - 100) < 0.01
            && abs(redGain - 100) < 0.01
            && abs(greenGain - 100) < 0.01
            && abs(blueGain - 100) < 0.01
            && ColorMatrixEffect.isNeutralRequest(saturation, filter, visionSeverity, filterStrength, mode)
    }

    /// La matrice 5x5 que cet etat produit. Une seule source de verite.
    public func buildMatrix() -> [Float] {
        ColorMatrixEffect.buildMatrix(saturation, filter, visionSeverity, filterStrength, mode)
    }

    // ------------------------------------------------------------------ serialisation
    //
    // Le format est CELUI DE LA VERSION WINDOWS, champ pour champ. Ce n'est pas un
    // scrupule d'archiviste : un fichier de configuration exporte depuis un PC
    // s'importe ici tel quel, et inversement. Quelqu'un qui change de machine ne
    // recommence pas ses quatre-vingts reglages.

    public func serialize() -> String {
        var parts: [String] = []
        parts.append(Profile.escape(name))
        parts.append(Profile.num(brightness))
        parts.append(String(kelvin))
        parts.append(Profile.num(contrast))
        parts.append(Profile.num(gammaCurve))
        parts.append(Profile.num(redGain))
        parts.append(Profile.num(greenGain))
        parts.append(Profile.num(blueGain))
        parts.append(Profile.num(saturation))
        parts.append(String(filter.rawValue))
        parts.append(tint.serialized)
        // Champs ajoutes en 3.0 : places APRES la teinte pour qu'un fichier ecrit
        // par une version anterieure continue de se relire tel quel.
        parts.append(Profile.num(visionSeverity))
        parts.append(Profile.num(filterStrength))
        parts.append(String(mode.rawValue))
        return parts.joined(separator: ";")
    }

    public static func deserialize(_ s: String) -> Profile {
        var p = Profile()
        let f = s.components(separatedBy: ";")
        guard f.count >= 11 else { return p }

        p.name = unescape(f[0])
        p.brightness = parseDouble(f[1]) ?? p.brightness
        p.kelvin = Int(f[2]) ?? p.kelvin
        p.contrast = parseDouble(f[3]) ?? p.contrast
        p.gammaCurve = parseDouble(f[4]) ?? p.gammaCurve
        p.redGain = parseDouble(f[5]) ?? p.redGain
        p.greenGain = parseDouble(f[6]) ?? p.greenGain
        p.blueGain = parseDouble(f[7]) ?? p.blueGain
        p.saturation = parseDouble(f[8]) ?? p.saturation
        if let fi = Int(f[9]), let cf = ColorFilter(rawValue: fi) { p.filter = cf }
        if let t = RGB.parse(f[10]) { p.tint = t }

        // Champs 3.0. Absents d'un fichier ancien : les valeurs par defaut
        // reproduisent alors exactement le comportement d'avant.
        if f.count > 11 { p.visionSeverity = parseDouble(f[11]) ?? p.visionSeverity }
        if f.count > 12 { p.filterStrength = parseDouble(f[12]) ?? p.filterStrength }
        if f.count > 13 { p.mode = (Int(f[13]) == 1) ? .simulation : .correction }

        p.clampAll()
        return p
    }

    public mutating func clampAll() {
        brightness = SafetyGuard.clampBrightness(brightness)
        kelvin = Profile.clampInt(kelvin, ColorTemp.minKelvin, ColorTemp.maxKelvin)
        contrast = Profile.clamp(contrast, 50, 150)
        gammaCurve = Profile.clamp(gammaCurve, 50, 200)
        redGain = Profile.clamp(redGain, 0, 150)
        greenGain = Profile.clamp(greenGain, 0, 150)
        blueGain = Profile.clamp(blueGain, 0, 150)
        saturation = Profile.clamp(saturation, 0, 200)
        visionSeverity = Profile.clamp(visionSeverity, 0, 100)
        filterStrength = Profile.clamp(filterStrength, 0, 150)
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        if v.isNaN { return (lo + hi) / 2 }
        return v < lo ? lo : (v > hi ? hi : v)
    }

    static func clampInt(_ v: Int, _ lo: Int, _ hi: Int) -> Int { v < lo ? lo : (v > hi ? hi : v) }

    /// Nombre ecrit sans separateur local : le fichier doit se relire a l'identique
    /// en France comme aux Etats-Unis.
    static func num(_ v: Double) -> String {
        let rounded = (v * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.2f", rounded)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    static func parseDouble(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces))
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: ";", with: "%3B").replacingOccurrences(of: "|", with: "%7C")
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "%3B", with: ";").replacingOccurrences(of: "%7C", with: "|")
    }

    // ------------------------------------------------------------------ modes livres

    /// Les modes prets a l'emploi, inspires de ceux d'Iris (Health, Sleep, Reading,
    /// Programming, Movie, Sunglasses...) et de FaceLight chez Lunar.
    ///
    /// Les quatre derniers ne visent pas le confort mais l'accessibilite : ils
    /// existent parce que le reglage juste pour une deficience donnee n'est pas
    /// devinable, et qu'obliger quelqu'un a le reconstruire curseur par curseur
    /// revient a ne pas le proposer.
    public static func builtInModes() -> [Profile] {
        var list: [Profile] = []

        list.append(make("Normal", 100, 6500, 100, 100, 100, .none))
        list.append(make("Confort", 90, 5000, 100, 100, 100, .none))
        list.append(make("Lecture", 85, 4200, 95, 100, 92, .none))
        list.append(make("Soiree", 70, 3400, 100, 100, 100, .none))
        list.append(make("Nuit profonde", 35, 2000, 95, 100, 88, .none))
        list.append(make("Bougie", 20, 1500, 90, 100, 85, .none))
        list.append(make("Film", 115, 6000, 112, 100, 118, .none))
        list.append(make("Jeu", 125, 6500, 110, 100, 115, .none))
        list.append(make("Plein soleil", 150, 6500, 115, 100, 110, .none))
        list.append(make("Visioconference", 140, 5800, 100, 100, 105, .none))
        list.append(make("Programmation", 100, 5500, 100, 100, 100, .invert))
        list.append(make("Papier", 95, 4000, 100, 100, 60, .sepia))
        list.append(make("Monochrome", 100, 6500, 105, 100, 0, .grayscale))

        // --- accessibilite ---

        // Daltonisme : la saturation est poussee legerement, parce que la
        // correction ecarte les teintes et qu'un peu plus de saturation rend
        // cet ecart plus lisible sans denaturer le reste.
        list.append(make("Daltonisme - rouge", 100, 6500, 105, 100, 115, .protanopia))
        list.append(make("Daltonisme - vert", 100, 6500, 105, 100, 115, .deuteranopia))
        list.append(make("Daltonisme - bleu", 100, 6500, 105, 100, 115, .tritanopia))

        // Achromatopsie : absence totale de vision des couleurs, presque toujours
        // accompagnee d'une photophobie severe. La couleur ne sert plus a rien,
        // la lumiere fait mal : on retire l'une et on baisse l'autre, en montant
        // le contraste pour compenser la perte de reperes.
        list.append(make("Achromatopsie", 45, 4500, 125, 100, 0, .grayscale))

        // Malvoyance : contraste au maximum utile, luminosite au-dessus de la
        // normale. C'est la combinaison recommandee en basse vision quand la
        // sensibilite au contraste est atteinte (DMLA, cataracte).
        list.append(make("Basse vision", 130, 6500, 140, 115, 110, .none))

        // Photophobie / migraine ophtalmique : lumiere reduite et bleu ecarte,
        // sans passer par un noir illisible.
        list.append(make("Photophobie", 30, 2400, 95, 110, 90, .none))

        // Inversion douce : le fond blanc des documents et des pages web devient
        // sombre sans que les photos virent au negatif.
        list.append(make("Sombre partout", 100, 5200, 100, 100, 100, .invertKeepHue))

        return list
    }

    private static func make(_ name: String, _ bright: Double, _ kelvin: Int, _ contrast: Double,
                             _ gamma: Double, _ sat: Double, _ filter: ColorFilter) -> Profile {
        var p = Profile()
        p.name = name
        p.brightness = bright
        p.kelvin = kelvin
        p.contrast = contrast
        p.gammaCurve = gamma
        p.saturation = sat
        p.filter = filter
        return p
    }

    /// Description courte pour l'interface, generee a partir des valeurs.
    public func summary() -> String {
        var bits: [String] = []
        bits.append("\(Int(brightness.rounded())) %")
        if kelvin < ColorTemp.maxKelvin { bits.append("\(kelvin) K") }
        if abs(contrast - 100) > 0.5 { bits.append("contraste \(Int(contrast))") }
        if abs(saturation - 100) > 0.5 { bits.append("saturation \(Int(saturation))") }
        if filter != .none { bits.append(Profile.filterName(filter)) }
        return bits.joined(separator: " - ")
    }

    public static func filterName(_ f: ColorFilter) -> String {
        switch f {
        case .grayscale: return "niveaux de gris"
        case .invert: return "inverse"
        case .invertKeepHue: return "inverse, teintes conservees"
        case .sepia: return "sepia"
        case .protanopia: return "protanopie"
        case .deuteranopia: return "deuteranopie"
        case .tritanopia: return "tritanopie"
        default: return "aucun"
        }
    }

    /// Nom du filtre tenant compte de la gravite : en dessous de la dichromatie
    /// complete, le terme medical n'est plus « -opie » mais « -omalie ». Afficher
    /// « protanopie » a quelqu'un qui regle 40 % de gravite serait faux.
    public func filterDisplayName() -> String {
        if !ColorMatrixEffect.isVisionFilter(filter) { return Profile.filterName(filter) }
        if visionSeverity >= 95 { return Profile.filterName(filter) }

        switch filter {
        case .protanopia: return "protanomalie"
        case .deuteranopia: return "deuteranomalie"
        default: return "tritanomalie"
        }
    }
}
