import Foundation
import CoreGraphics

/// Repartition d'une consigne de luminosite entre les trois etages disponibles.
/// C'est ici qu'est encode le choix de conception « hybride intelligent ».
public struct BrightnessPlan {
    public var gammaExponent: Double = 1.0   // g : out = in^(1/g). g > 1 eclaircit sans ecreter.
    public var linearGain: Double = 1.0      // multiplicateur final. > 1 ecrete les hautes lumieres.
    public var overlayTransmission: Double = 1.0  // 1.0 = aucun voile ; 0.15 = laisse passer 15 %
    public var hardwareTarget: Int = -1      // retroeclairage vise, ou -1 pour ne pas y toucher
    public var clips: Bool = false           // vrai si des hautes lumieres seront ecretees

    public init() {}

    public var overlayAlpha: UInt8 {
        var a = (1.0 - overlayTransmission) * 255.0
        if a < 0 { a = 0 }
        if a > 250 { a = 250 }   // garde-fou : jamais un voile totalement opaque
        return UInt8(a.rounded())
    }
}

public final class GammaApplyResult {
    public var success = false          // la table a ete acceptee par le systeme
    public var clamped = false          // le systeme l'a rabotee
    public var effectiveScale: Double = 1  // 1.0 = appliquee telle quelle ; < 1 = repli
    public init() {}
}

/// Construit et applique la table de couleurs du GPU. C'est la technique de f.lux
/// (`SetDeviceGammaRamp` sur Windows, `CGSetDisplayTransferByTable` ici), etendue
/// au-dela de 100 % de luminosite.
public enum GammaEngine {
    public static let minBrightness = 5.0
    public static let maxBrightness = 150.0

    /// En dessous de ce seuil, la gamma seule devient sale (bandes de couleur,
    /// perte de nuances) : le voile facon PangoBright prend alors le relais.
    private static let gammaFloor = 35.0

    // ------------------------------------------------------------------ le plan

    /// Traduit une consigne 5-150 % en reglages concrets pour les trois etages.
    ///
    ///   B <= 35 %   : gamma au plancher + voile qui absorbe le reste
    ///   35 - 100 %  : gain lineaire descendant, aucun voile
    ///   100 - 135 % : courbe gamma pure -> AUCUN ecretage, aucune perte
    ///   135 - 150 % : on ajoute un peu de gain lineaire, quelques blancs ecretes
    ///   > 100 %     : le retroeclairage physique est pousse au maximum
    public static func plan(_ brightness: Double, allowOverlay: Bool, allowHardware: Bool) -> BrightnessPlan {
        var b = brightness
        if b < minBrightness { b = minBrightness }
        if b > maxBrightness { b = maxBrightness }

        var p = BrightnessPlan()
        let ratio = b / 100.0

        if b > 100.0 {
            // --- etage 1 : de vrais photons en plus, quand le materiel le permet
            if allowHardware { p.hardwareTarget = 100 }

            // --- etage 2 : courbe gamma. 0 reste 0, 1 reste 1 : zero perte.
            p.gammaExponent = 1.0 + (ratio - 1.0) * 1.6

            // --- etage 3 : gain lineaire, uniquement dans le dernier tiers
            let linearStart = 1.35
            if ratio > linearStart {
                p.linearGain = 1.0 + (ratio - linearStart) * 0.8
                p.clips = true
            }
        } else if b >= gammaFloor {
            // Assombrissement propre par la table : invisible aux captures d'ecran,
            // et il traverse le plein ecran sans dommage.
            p.linearGain = ratio
        } else {
            // Sous le plancher : la table reste a 35 %, le voile absorbe le reste.
            p.linearGain = gammaFloor / 100.0
            let remaining = b / gammaFloor   // 0.14 a 1.0
            if allowOverlay {
                p.overlayTransmission = remaining
            } else {
                // Sans voile autorise, on descend au maximum de ce que la table permet.
                p.linearGain = ratio
            }
        }

        return p
    }

    // ------------------------------------------------------------------ la table

    /// Fabrique la table : luminosite et temperature fusionnees en une seule passe.
    public static func buildRamp(_ plan: BrightnessPlan, kelvin: Int) -> Native.RampTable {
        var p = Profile()
        p.kelvin = kelvin
        return buildRamp(plan, p)
    }

    /// Version complete : ajoute a la passe precedente le contraste, la courbe gamma
    /// choisie par l'utilisateur et la balance manuelle des trois canaux.
    ///
    /// Ordre des operations, du plus structurel au plus cosmetique :
    ///   1. courbe    : forme de la reponse (plan de luminosite x reglage utilisateur)
    ///   2. contraste : etalement autour du gris moyen
    ///   3. gain      : niveau general
    ///   4. couleur   : temperature puis balance manuelle des canaux
    public static func buildRamp(_ plan: BrightnessPlan, _ profile: Profile) -> Native.RampTable {
        let temp = ColorTemp.multipliers(profile.kelvin)
        var ramp = Native.RampTable.allocate()

        // La courbe du plan (boost) et celle choisie par l'utilisateur se composent.
        var gamma = plan.gammaExponent * (profile.gammaCurve / 100.0)
        if gamma < 0.2 { gamma = 0.2 }
        let invGamma = 1.0 / gamma

        let contrast = profile.contrast / 100.0

        let rMul = temp[0] * (profile.redGain / 100.0)
        let gMul = temp[1] * (profile.greenGain / 100.0)
        let bMul = temp[2] * (profile.blueGain / 100.0)

        for i in 0..<Native.RampTable.size {
            var v = Double(i) / 255.0

            if abs(gamma - 1.0) > 1e-9 { v = pow(v, invGamma) }

            // Contraste : etirement autour de 0.5, le gris moyen ne bouge pas.
            if abs(contrast - 1.0) > 1e-9 {
                v = 0.5 + (v - 0.5) * contrast
                if v < 0 { v = 0 } else if v > 1 { v = 1 }
            }

            v *= plan.linearGain

            ramp.red[i] = toRampValue(v * rMul)
            ramp.green[i] = toRampValue(v * gMul)
            ramp.blue[i] = toRampValue(v * bMul)
        }

        return enforceFloor(ramp)
    }

    /// Plancher de securite mesure sur la TABLE PRODUITE, et non sur la consigne.
    ///
    /// La luminosite est bornee a 5 % des son entree, par `SafetyGuard.clampBrightness`.
    /// Mais elle n'est pas seule a assombrir : la temperature et surtout les trois
    /// gains de canaux la MULTIPLIENT ensuite, et ces gains descendent jusqu'a zero.
    /// Les trois a zero donnaient donc un ecran strictement noir a n'importe quelle
    /// luminosite demandee.
    ///
    /// Le critere retenu est la LUMINANCE du blanc, pas chaque canal pris a part :
    /// couper entierement le bleu est un reglage legitime - c'est meme la reduction
    /// de lumiere bleue poussee au bout - et cela laisse encore 93 % de luminance.
    /// Couper les trois n'en laisse aucune.
    ///
    /// Quand le plancher est franchi, la table est remontee PROPORTIONNELLEMENT :
    /// la teinte voulue est conservee, seule son intensite est relevee jusqu'au
    /// minimum lisible. Rien n'est refuse a l'utilisateur, sauf l'ecran noir.
    static func enforceFloor(_ ramp: Native.RampTable) -> Native.RampTable {
        let floor = minBrightness / 100.0   // 0,05
        let last = Native.RampTable.size - 1

        let r = Double(ramp.red[last]) / 65535.0
        let g = Double(ramp.green[last]) / 65535.0
        let b = Double(ramp.blue[last]) / 65535.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

        // Au-dessus du plancher : la table passe telle quelle.
        if luminance >= floor { return ramp }

        // Exactement noire : il n'y a plus aucune proportion a conserver, donc
        // rien a remonter. On rend un gris neutre au niveau du plancher.
        if luminance <= 1e-7 {
            var grey = Native.RampTable.allocate()
            for i in 0..<Native.RampTable.size {
                let v = toRampValue(Double(i) / 255.0 * floor)
                grey.red[i] = v; grey.green[i] = v; grey.blue[i] = v
            }
            return grey
        }

        let lift = floor / luminance
        var raised = Native.RampTable.allocate()
        for i in 0..<Native.RampTable.size {
            raised.red[i] = toRampValue(Double(ramp.red[i]) / 65535.0 * lift)
            raised.green[i] = toRampValue(Double(ramp.green[i]) / 65535.0 * lift)
            raised.blue[i] = toRampValue(Double(ramp.blue[i]) / 65535.0 * lift)
        }
        return raised
    }

    private static func toRampValue(_ v: Double) -> UInt16 {
        var scaled = v * 65535.0
        if scaled < 0 { scaled = 0 }
        if scaled > 65535 { scaled = 65535 }
        return UInt16(scaled.rounded())
    }

    /// Melange une table avec l'identite. t = 0 -> identite, t = 1 -> table complete.
    public static func blend(_ ramp: Native.RampTable, _ t: Double) -> Native.RampTable {
        if t >= 1.0 { return ramp }
        let f = max(0.0, t)
        let id = Native.RampTable.identity()
        var out = Native.RampTable.allocate()
        for i in 0..<Native.RampTable.size {
            out.red[i] = UInt16(Double(id.red[i]) + (Double(ramp.red[i]) - Double(id.red[i])) * f)
            out.green[i] = UInt16(Double(id.green[i]) + (Double(ramp.green[i]) - Double(id.green[i])) * f)
            out.blue[i] = UInt16(Double(id.blue[i]) + (Double(ramp.blue[i]) - Double(id.blue[i])) * f)
        }
        return out
    }

    // ------------------------------------------------------------------ acces au systeme

    /// Vrai si cet ecran accepte qu'on lui pose une table.
    ///
    /// macOS l'accepte sur toute dalle pilotee par le processeur graphique. Le test
    /// consiste a relire : une session distante ou un ecran virtuel peut refuser
    /// sans le dire.
    public static func supportsGamma(_ m: MonitorInfo?) -> Bool {
        guard let m = m else { return false }
        if DisplayController.dryRun { return true }
        return CGDisplayGammaTableCapacity(m.displayID) >= 2
    }

    /// Lit la table actuellement en place, pour pouvoir la remettre plus tard.
    public static func capture(_ m: MonitorInfo?) -> Native.RampTable {
        guard let m = m else { return .identity() }
        return Native.getGammaRamp(m.displayID) ?? .identity()
    }

    /// Applique la table.
    ///
    /// La version Windows devait redescendre par paliers quand GDI refusait une
    /// courbe trop marquee. macOS n'impose pas cette limite : le repli progressif
    /// est conserve pour les cas ou le systeme refuse quand meme - session
    /// distante, ecran virtuel - plutot que d'echouer en silence.
    @discardableResult
    public static func apply(_ m: MonitorInfo?, _ ramp: Native.RampTable) -> GammaApplyResult {
        let res = GammaApplyResult()
        guard let m = m else { return res }
        if DisplayController.dryRun { res.success = true; return res }

        let steps: [Double] = [1.0, 0.85, 0.7, 0.55, 0.4, 0.25, 0.1]
        for t in steps {
            let attempt = t >= 1.0 ? ramp : blend(ramp, t)
            if Native.setGammaRamp(m.displayID, attempt) {
                res.success = true
                res.effectiveScale = t
                res.clamped = differsFromWritten(m.displayID, attempt) || t < 1.0
                return res
            }
        }
        return res
    }

    /// Relit la table et la compare a celle qu'on vient d'ecrire. Un ecart notable
    /// signifie que le systeme l'a rabotee.
    private static func differsFromWritten(_ id: CGDirectDisplayID, _ written: Native.RampTable) -> Bool {
        guard let back = Native.getGammaRamp(id) else { return false }
        var maxDiff = 0
        for i in 0..<Native.RampTable.size {
            maxDiff = max(maxDiff, abs(Int(back.red[i]) - Int(written.red[i])))
            maxDiff = max(maxDiff, abs(Int(back.green[i]) - Int(written.green[i])))
            maxDiff = max(maxDiff, abs(Int(back.blue[i]) - Int(written.blue[i])))
        }
        return maxDiff > 2048   // ~3 % de l'echelle : au-dela ce n'est plus un arrondi
    }

    /// Remet la table identite : l'ecran redevient strictement normal.
    @discardableResult
    public static func resetToIdentity(_ m: MonitorInfo?) -> Bool {
        if DisplayController.dryRun { return true }
        guard let m = m else {
            Native.restoreAllGamma()
            return true
        }
        Native.restoreGamma(m.displayID)
        return true
    }
}
