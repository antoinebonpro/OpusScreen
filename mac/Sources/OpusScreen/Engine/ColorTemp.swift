import Foundation

/// Convertit une temperature de couleur (Kelvin) en multiplicateurs RGB.
///
/// C'est la partie « f.lux » du moteur : approximation du rayonnement du corps noir,
/// normalisee pour que 6500 K soit exactement neutre (aucune modification de l'image).
public enum ColorTemp {
    public static let minKelvin = 1200   // bougie tres chaude, comme le « late » de f.lux
    public static let maxKelvin = 6500   // lumiere du jour = neutre

    /// Valeurs brutes de la formule a 6500 K, qui servent de reference de
    /// normalisation.
    ///
    /// Elles sont CALCULEES par la formule elle-meme, et non recopiees arrondies
    /// a quatre decimales comme on les trouve publiees. La difference se mesure :
    /// avec les constantes arrondies, 6500 K rendait 0,99996 sur le bleu au lieu
    /// de 1. Quatre centiemes de millieme ne se voient pas a l'oeil, mais ils se
    /// voient dans la table - deux ou trois niveaux d'ecart sur 65535 - et ils
    /// rendaient fausse la seule promesse que cette classe ait a tenir : a
    /// 6500 K, l'image n'est pas modifiee.
    private static let reference: [Double] = raw(65.0)

    /// Renvoie [r, g, b] dans [0..1]. A 6500 K le resultat est exactement [1, 1, 1].
    public static func multipliers(_ kelvin: Int) -> [Double] {
        var k = kelvin
        if k < minKelvin { k = minKelvin }
        if k > maxKelvin { k = maxKelvin }

        let value = raw(Double(k) / 100.0)
        return [clamp01(value[0] / reference[0]),
                clamp01(value[1] / reference[1]),
                clamp01(value[2] / reference[2])]
    }

    /// L'approximation du rayonnement du corps noir, telle qu'elle est publiee.
    /// `t` est la temperature en centaines de kelvins.
    private static func raw(_ t: Double) -> [Double] {
        let r: Double, g: Double, b: Double

        // --- rouge ---
        if t <= 66.0 { r = 255.0 }
        else { r = 329.698727446 * pow(t - 60.0, -0.1332047592) }

        // --- vert ---
        if t <= 66.0 { g = 99.4708025861 * log(t) - 161.1195681661 }
        else { g = 288.1221695283 * pow(t - 60.0, -0.0755148492) }

        // --- bleu ---
        if t >= 66.0 { b = 255.0 }
        else if t <= 19.0 { b = 0.0 }
        else { b = 138.5177312231 * log(t - 10.0) - 305.0447927307 }

        return [r, g, b]
    }

    private static func clamp01(_ v: Double) -> Double {
        if v < 0.0 { return 0.0 }
        if v > 1.0 { return 1.0 }
        return v
    }

    /// Libelle court pour l'interface, ex. « 3400 K - chaud ».
    public static func describe(_ kelvin: Int) -> String {
        let mood: String
        if kelvin >= 6000 { mood = "lumiere du jour" }
        else if kelvin >= 5000 { mood = "legerement chaud" }
        else if kelvin >= 4000 { mood = "halogene" }
        else if kelvin >= 3000 { mood = "chaud" }
        else if kelvin >= 2200 { mood = "lampe a incandescence" }
        else { mood = "bougie" }
        return "\(kelvin) K - \(mood)"
    }
}

/// Un preset jour / nuit / tard.
/// Les sept premiers sont ceux de f.lux, releves dans son fichier media/preset.json.
public struct Preset {
    public var name: String
    public var description: String
    public var day: Int
    public var night: Int
    public var late: Int

    public init(_ name: String, _ desc: String, _ day: Int, _ night: Int, _ late: Int) {
        self.name = name; self.description = desc
        self.day = day; self.night = night; self.late = late
    }

    public static func builtIn() -> [Preset] {
        [
            Preset("Couleurs recommandees", "Chaud au coucher du soleil, bougie avant de dormir", 6500, 3400, 1900),
            Preset("Reduire la fatigue oculaire", "Moins de fatigue, jour et nuit", 5900, 3600, 2500),
            Preset("f.lux classique", "Chaud au coucher du soleil, et toute la nuit", 6500, 3400, 3400),
            Preset("Travail tardif", "Lumineux apres le coucher du soleil, puis on ralentit", 6500, 6500, 2300),
            Preset("Loin de l'equateur", "Une pointe de coucher de soleil, bougie au coucher", 6500, 5500, 1900),
            Preset("Peinture rupestre", "Lumiere tres chaude en permanence", 2700, 2300, 1500),
            Preset("Fidelite des couleurs", "Ajustements plus faibles, meilleure precision colorimetrique", 6500, 5000, 3400),
            Preset("Aucun", "Pas de changement de temperature", 6500, 6500, 6500),
        ]
    }
}
