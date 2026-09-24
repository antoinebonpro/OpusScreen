import Foundation

/// Une planche du test : un chiffre cache dans un semis de pastilles.
public final class VisionPlate {
    /// Deficience visee. `.none` = planche de controle, lisible par tout le monde.
    public var axis: ColorFilter = .none

    /// Gravite a partir de laquelle cette planche devient illisible.
    public var level: Double = 100

    public var digit = 0
    public var choices: [Int] = []
    public var background = RGB.black
    public var figure = RGB.white

    /// Graine du semis : la meme planche se redessine a l'identique.
    public var seed: UInt64 = 0

    public init() {}
}

/// Generateur pseudo-aleatoire a graine, reproductible.
///
/// `Int.random` s'appuie sur la source du systeme : deux appels avec la meme
/// graine ne rendraient pas la meme planche, et une planche qui se redessine
/// differemment a chaque rafraichissement de fenetre est inutilisable. Ce
/// generateur est celui de la famille xorshift, court et parfaitement determine.
public struct SeededRandom {
    private var state: UInt64

    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Entier dans [0, bound).
    public mutating func nextInt(_ bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        return Int(next() % UInt64(bound))
    }

    /// Flottant dans [0, 1).
    public mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }
}

/// Le test guide : ce qui se calcule, sans rien d'affichable.
///
/// Deux temps, et deux raisons.
///
/// Les PLANCHES trouvent le type. Chacune cache un chiffre dont la couleur ne
/// differe du fond que le long de la direction de confusion d'une deficience
/// precise : cette vision-la ne lit rien, les deux autres lisent sans peine. Le
/// choix des couleurs n'est pas decide a la main - il est cherche, puis verifie
/// par le calcul de l'ecart percu apres simulation.
///
/// L'ESCALIER mesure la gravite. On montre deux couleurs sur cette direction, en
/// resserrant l'ecart a chaque reponse juste et en l'elargissant a chaque erreur :
/// la suite converge vers le plus petit ecart que la personne distingue encore.
/// De ce seuil on remonte a la gravite, puisque l'on sait calculer le seuil que
/// produirait chaque gravite.
///
/// Classer quelqu'un dans une case - « deuteranope » - serait plus simple et
/// faux : l'immense majorite des personnes concernees ont une ANOMALIE partielle,
/// et une correction calibree sur la dichromatie les gene au lieu de les aider.
public enum VisionExam {
    public static let justNoticeable = Vision.justNoticeable

    /// Les trois deficiences testees.
    public static let axes: [ColorFilter] = [.protanopia, .deuteranopia, .tritanopia]

    private static let anchor: [Double] = [0.52, 0.50, 0.48]

    // ------------------------------------------------------------------ couleurs

    private static func kind(_ f: ColorFilter) -> ColorFilter {
        (f == .protanopia || f == .deuteranopia || f == .tritanopia) ? f : .deuteranopia
    }

    /// Les deux couleurs d'un essai, ecartees de `separation` (0 a 1) le long de
    /// la direction de confusion. 1 = l'ecart maximal que l'ecran permet ici.
    public static func pairAt(_ axis: ColorFilter, _ separation: Double) -> (RGB, RGB) {
        let k = kind(axis)
        let d = Vision.confusionDirection(k)
        let t = max(0, min(1, separation)) * Vision.maxSpread(anchor, d)
        return (Vision.rgb(anchor, d, -t / 2), Vision.rgb(anchor, d, +t / 2))
    }

    /// Ecart que percoit reellement une vision de cette gravite.
    public static func perceivedDelta(_ axis: ColorFilter, _ severity: Double, _ a: RGB, _ b: RGB) -> Double {
        let sim = ColorMatrixEffect.buildMatrix(100, kind(axis), severity, 100, .simulation)
        return Vision.deltaE(ColorMatrixEffect.transform(sim, a), ColorMatrixEffect.transform(sim, b))
    }

    /// Le plus petit ecart qu'une vision de cette gravite distingue encore.
    ///
    /// Au-dela de 1, l'ecart maximal de l'ecran ne suffit plus : la valeur se
    /// prolonge alors au-dela pour rester croissante avec la gravite, sans quoi
    /// toutes les gravites severes rendraient le meme seuil et la mesure ne
    /// pourrait plus les distinguer.
    public static func separationThreshold(_ axis: ColorFilter, _ severity: Double) -> Double {
        let full = pairAt(axis, 1.0)
        let atFull = perceivedDelta(axis, severity, full.0, full.1)
        if atFull < justNoticeable {
            return 1.0 + (justNoticeable - atFull) / justNoticeable
        }

        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            let p = pairAt(axis, mid)
            if perceivedDelta(axis, severity, p.0, p.1) >= justNoticeable { hi = mid } else { lo = mid }
        }
        return hi
    }

    /// Gravite qui produirait ce seuil : l'operation inverse de la precedente,
    /// par dichotomie, puisque le seuil croit avec la gravite.
    public static func severityFromThreshold(_ axis: ColorFilter, _ threshold: Double) -> Double {
        var lo = 0.0, hi = 100.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if separationThreshold(axis, mid) < threshold { lo = mid } else { hi = mid }
        }
        return ((lo + hi) / 2).rounded()
    }

    /// Seuil conventionnel de qui ne distingue rien, meme a l'ecart maximal.
    public static func ceilingThreshold(_ axis: ColorFilter) -> Double {
        separationThreshold(axis, 100)
    }

    /// Seuil qu'un observateur donne obtiendrait sur les couleurs d'un AUTRE axe.
    ///
    /// C'est la piece qui manquait pour distinguer le rouge du vert. Leurs axes de
    /// confusion sont voisins : mesurer « le rouge est mauvais » ne dit pas si la
    /// personne est protanope ou deuteranope, car les deux echouent un peu partout.
    /// Ce qui les separe, c'est le PROFIL des trois mesures.
    public static func predictedThreshold(_ pairAxis: ColorFilter, _ observerAxis: ColorFilter,
                                          _ severity: Double) -> Double {
        let full = pairAt(pairAxis, 1.0)
        let atFull = perceivedDelta(observerAxis, severity, full.0, full.1)
        if atFull < justNoticeable {
            return 1.0 + (justNoticeable - atFull) / justNoticeable
        }

        var lo = 0.0, hi = 1.0
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            let p = pairAt(pairAxis, mid)
            if perceivedDelta(observerAxis, severity, p.0, p.1) >= justNoticeable { hi = mid } else { lo = mid }
        }
        return hi
    }

    /// La vision qui explique le mieux les seuils mesures sur plusieurs axes.
    ///
    /// On essaie chaque deficience a chaque gravite, on predit les seuils qu'elle
    /// donnerait, et l'on garde celle dont les predictions collent le mieux aux
    /// mesures. Comparer betement « quel axe est le plus mauvais » se trompait de
    /// type une fois sur deux entre le rouge et le vert, parce que le plus mauvais
    /// axe d'un deuteranope n'est pas toujours le sien.
    ///
    /// `quality` vaut 1 pour un accord parfait et tend vers 0 quand rien ne colle.
    public static func fit(_ measured: [ColorFilter: Double])
        -> (axis: ColorFilter, severity: Double, quality: Double) {

        guard !measured.isEmpty else { return (.none, 0, 0) }

        // Hypothese de reference : une vision normale. Une deficience ne sera
        // annoncee que si elle explique NETTEMENT mieux les mesures - sans cette
        // comparaison, le moindre bruit de mesure se voyait promu en diagnostic.
        var normalError = 0.0
        for (axis, value) in measured {
            let predicted = predictedThreshold(axis, axes[0], 0)
            let d = log(max(1e-3, value)) - log(max(1e-3, predicted))
            normalError += d * d
        }

        var bestError = Double.greatestFiniteMagnitude
        var secondBest = Double.greatestFiniteMagnitude
        var foundAxis: ColorFilter = .none
        var foundSeverity = 0.0

        for candidate in axes {
            var bestForAxis = Double.greatestFiniteMagnitude
            var bestSeverity = 0.0
            var s = 0.0
            while s <= 100.0001 {
                var error = 0.0
                for (axis, value) in measured {
                    let predicted = predictedThreshold(axis, candidate, s)
                    let d = log(max(1e-3, value)) - log(max(1e-3, predicted))
                    error += d * d
                }
                if error < bestForAxis { bestForAxis = error; bestSeverity = s }
                s += 2.5
            }

            if bestForAxis < bestError {
                secondBest = bestError
                bestError = bestForAxis
                foundAxis = candidate
                foundSeverity = bestSeverity
            } else if bestForAxis < secondBest {
                secondBest = bestForAxis
            }
        }

        // Qualite : combien la deficience explique mieux les mesures qu'une vision
        // normale, tempere par l'ecart avec la deuxieme hypothese. Deux
        // explications aussi bonnes signifient que la mesure ne tranche pas entre
        // elles, et il faut le dire plutot que de choisir au hasard.
        let gainPart = normalError <= 1e-9 ? 0 : max(0, min(1, 1.0 - bestError / normalError))
        let gapPart = secondBest == Double.greatestFiniteMagnitude
            ? 1.0
            : min(1.0, (secondBest - bestError) / max(0.05, bestError + 0.05))
        let quality = gainPart * (0.45 + 0.55 * gapPart)
        return (foundAxis, foundSeverity.rounded(), quality)
    }

    // ------------------------------------------------------------------ escalier

    /// Escalier adaptatif : l'ecart se resserre apres une reponse juste, s'elargit
    /// apres une erreur. Le pas diminue a chaque retournement, et le seuil retenu
    /// est la moyenne geometrique des derniers retournements.
    ///
    /// C'est la methode des mesures de seuil en psychophysique. Elle vaut mieux
    /// qu'une liste fixe d'ecarts : elle passe l'essentiel de ses essais autour de
    /// la limite de la personne, la ou l'information se trouve, au lieu de
    /// gaspiller des ecrans sur des ecarts evidents ou impossibles.
    public final class Staircase {
        private let axisValue: ColorFilter
        private var reversals: [Double] = []
        private var sep = 1.0
        private var factor = 1.7
        private var lastCorrect = false
        private var hasLast = false
        private var trialCount = 0
        private var ceilingMisses = 0
        private var thresholdValue = Double.nan

        public static let maxTrialsDefault = 22

        private let wantedReversals: Int
        private let maxTrials: Int

        public convenience init(_ axis: ColorFilter) {
            self.init(axis, 8, Staircase.maxTrialsDefault)
        }

        /// Version courte, pour comparer plusieurs axes : moins de retournements,
        /// donc un seuil moins fin, mais trois mesures tiennent alors dans le temps
        /// d'une seule. La precision se rattrape ensuite sur l'axe retenu.
        public init(_ axis: ColorFilter, _ wantedReversals: Int, _ maxTrials: Int) {
            self.axisValue = axis
            self.wantedReversals = wantedReversals
            self.maxTrials = maxTrials
        }

        public var axis: ColorFilter { axisValue }
        public var separation: Double { sep }
        public var trials: Int { trialCount }
        public var done: Bool { !thresholdValue.isNaN }
        public var threshold: Double { thresholdValue }

        /// Avancement affichable, de 0 a 1.
        public var progress: Double {
            let byTrials = Double(trialCount) / Double(maxTrials)
            let byReversals = Double(reversals.count) / Double(wantedReversals)
            return min(1, max(byTrials, byReversals))
        }

        public func answer(_ distinguished: Bool) {
            if done { return }
            trialCount += 1

            if !distinguished && sep >= 0.999 {
                // Meme au maximum, les deux couleurs restent identiques pour cette
                // personne : il n'y a pas de seuil a mesurer, la deficience est
                // complete sur cet axe.
                ceilingMisses += 1
                if ceilingMisses >= 2 {
                    thresholdValue = VisionExam.ceilingThreshold(axisValue)
                    return
                }
            }

            if hasLast && distinguished != lastCorrect {
                reversals.append(sep)
                factor = max(1.08, factor.squareRoot())
            }
            lastCorrect = distinguished
            hasLast = true

            sep = distinguished ? sep / factor : min(1.0, sep * factor)
            if sep < 0.004 { sep = 0.004 }

            if reversals.count >= wantedReversals || trialCount >= maxTrials { finish() }
        }

        private func finish() {
            if reversals.isEmpty { thresholdValue = sep; return }

            let take = min(max(3, wantedReversals - 2), reversals.count)
            var sum = 0.0
            for i in (reversals.count - take)..<reversals.count {
                sum += log(max(1e-4, reversals[i]))
            }
            thresholdValue = exp(sum / Double(take))
        }
    }

    // ------------------------------------------------------------------ planches

    private static let digitPool = [2, 3, 5, 6, 8, 9]

    /// Ancrages candidats. Une planche n'est bonne que si, autour de cet ancrage,
    /// on trouve un ecart qui disparait pour la deficience visee tout en restant
    /// franc pour les deux autres - sinon la planche accuserait le mauvais axe.
    private static func candidates() -> [[Double]] {
        var list: [[Double]] = []
        let levels = [0.38, 0.46, 0.54, 0.62]
        let tints = [-0.10, -0.05, 0.0, 0.05, 0.10]
        for l in levels {
            for a in tints {
                for b in tints { list.append([l + a, l, l + b]) }
            }
        }
        return list
    }

    private static func hiddenSpread(_ anchor: [Double], _ d: [Double],
                                     _ target: ColorFilter, _ level: Double) -> Double {
        let sim = ColorMatrixEffect.buildMatrix(100, target, level, 100, .simulation)
        let maxT = Vision.maxSpread(anchor, d)
        if maxT < 0.05 { return 0 }

        if simDelta(anchor, d, maxT, sim) <= justNoticeable * 0.8 { return maxT }

        var lo = 0.0, hi = maxT
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if simDelta(anchor, d, mid, sim) <= justNoticeable * 0.8 { lo = mid } else { hi = mid }
        }
        return lo
    }

    private static func simDelta(_ anchor: [Double], _ d: [Double], _ t: Double, _ sim: [Float]) -> Double {
        Vision.deltaE(ColorMatrixEffect.transform(sim, Vision.rgb(anchor, d, -t / 2)),
                      ColorMatrixEffect.transform(sim, Vision.rgb(anchor, d, +t / 2)))
    }

    /// Deux niveaux seulement, et c'est une limite physique, pas un choix.
    ///
    /// Verifie a l'image : en dessous d'un ecart d'environ 9 Delta E, le chiffre
    /// n'est plus lisible par PERSONNE une fois disperse en pastilles. Une planche
    /// plus subtile n'aurait donc pas depiste les anomalies legeres, elle aurait
    /// piege tout le monde.
    ///
    /// Cacher un chiffre a une anomalie LEGERE demanderait un ecart de couleur si
    /// faible qu'une vision normale ne le verrait pas non plus : la planche ne
    /// separerait plus rien. Les anomalies legeres ne se depistent donc pas par
    /// des planches - elles se MESURENT, et c'est le role de l'escalier, que la
    /// fenetre lance sur les trois axes quand les planches ne trouvent rien.
    private static let levels: [Double] = [100]
    private static let minNormal: [Double] = [14]

    /// Deux planches par deficience : une erreur d'inattention ne suffit pas a accuser.
    private static let platesPerAxis = 2

    public static func plates(seed: UInt64) -> [VisionPlate] {
        var rnd = SeededRandom(seed: seed)
        var plates: [VisionPlate] = []
        var recentDigits: [Int] = []

        for target in axes {
            let d = Vision.confusionDirection(target)

            for lvl in 0..<levels.count {
                let level = levels[lvl]
                var found: [VisionPlate] = []
                var scores: [Double] = []

                for anchor in candidates() {
                    let t = hiddenSpread(anchor, d, target, level)
                    if t < 0.03 { continue }

                    let a = Vision.rgb(anchor, d, -t / 2)
                    let b = Vision.rgb(anchor, d, +t / 2)
                    let normal = Vision.deltaE(a, b)
                    if normal < minNormal[lvl] { continue }   // invisible aussi pour une vision normale

                    // Une planche doit accuser UNE deficience : si les deux autres
                    // ne la lisent pas non plus, elle ne distingue rien.
                    var worstOther = Double.greatestFiniteMagnitude
                    for other in axes where other != target {
                        worstOther = min(worstOther, perceivedDelta(other, level, a, b))
                    }
                    if worstOther < 2.0 { continue }

                    let candidate = make(target, a, b, &rnd, &recentDigits)
                    candidate.level = level
                    found.append(candidate)
                    scores.append(worstOther)
                }

                // Les ancrages qui separent le mieux les trois visions.
                var picks = 0
                while picks < platesPerAxis && !found.isEmpty {
                    var best = 0
                    for i in 1..<scores.count where scores[i] > scores[best] { best = i }
                    plates.append(found[best])
                    found.remove(at: best)
                    scores.remove(at: best)
                    picks += 1
                }
            }
        }

        // Planches de controle : le chiffre ne differe que par la CLARTE, qu'aucune
        // deficience chromatique ne touche. Les rater, c'est avoir repondu au
        // hasard - et le resultat doit alors le dire.
        plates.append(make(.none, gray(0.34), gray(0.68), &rnd, &recentDigits))
        plates.append(make(.none, gray(0.72), gray(0.40), &rnd, &recentDigits))

        return plates
    }

    private static func gray(_ v: Double) -> RGB {
        RGB(white: Vision.component(v))
    }

    private static func make(_ axis: ColorFilter, _ figure: RGB, _ background: RGB,
                             _ rnd: inout SeededRandom, _ recentDigits: inout [Int]) -> VisionPlate {
        let p = VisionPlate()
        p.axis = axis
        p.figure = figure
        p.background = background
        p.seed = rnd.next()

        // Un chiffre different d'une planche a l'autre : repeter le meme invite a
        // repondre de memoire plutot qu'a regarder.
        for _ in 0..<12 {
            p.digit = digitPool[rnd.nextInt(digitPool.count)]
            if !recentDigits.contains(p.digit) { break }
        }
        recentDigits.append(p.digit)
        if recentDigits.count > 3 { recentDigits.removeFirst() }

        var choices = [p.digit]
        while choices.count < 4 {
            let c = digitPool[rnd.nextInt(digitPool.count)]
            if !choices.contains(c) { choices.append(c) }
        }
        // Melange, sinon la bonne reponse serait toujours le premier bouton.
        var i = choices.count - 1
        while i > 0 {
            let j = rnd.nextInt(i + 1)
            choices.swapAt(i, j)
            i -= 1
        }
        p.choices = choices
        return p
    }

    /// Planches ratees par axe. La fenetre s'en sert pour savoir si les planches
    /// tranchent ou si deux axes restent a egalite - auquel cas elle mesure plutot
    /// que de trancher a pile ou face.
    public static func misses(_ plates: [VisionPlate], _ read: [Bool]) -> [ColorFilter: Int] {
        var missed: [ColorFilter: Int] = [:]
        for f in axes { missed[f] = 0 }
        guard plates.count == read.count else { return missed }

        for i in 0..<plates.count where plates[i].axis != .none && !read[i] {
            missed[plates[i].axis, default: 0] += 1
        }
        return missed
    }

    /// Planches de controle ratees : au-dela de zero, le test n'est pas fiable.
    public static func controlsMissed(_ plates: [VisionPlate], _ read: [Bool]) -> Int {
        guard plates.count == read.count else { return 0 }
        var n = 0
        for i in 0..<plates.count where plates[i].axis == .none && !read[i] { n += 1 }
        return n
    }

    /// Conclusion des planches : la deficience dont les planches ont ete ratees.
    ///
    /// `confidence` va de 0 a 100. Il retombe quand les planches d'un autre axe
    /// sont ratees aussi, et s'effondre quand une planche de controle l'est : le
    /// test dit alors qu'il ne sait pas, plutot que d'annoncer un diagnostic tire
    /// de reponses au hasard.
    public static func typeFromPlates(_ plates: [VisionPlate], _ read: [Bool])
        -> (filter: ColorFilter, confidence: Int) {

        guard plates.count == read.count else { return (.none, 0) }

        let missed = misses(plates, read)
        var total: [ColorFilter: Int] = [:]
        for f in axes { total[f] = 0 }
        for p in plates where p.axis != .none { total[p.axis, default: 0] += 1 }
        let controls = controlsMissed(plates, read)

        var best: ColorFilter = .none
        var bestMissed = 0
        for f in axes where (missed[f] ?? 0) > bestMissed {
            bestMissed = missed[f] ?? 0
            best = f
        }

        if best == .none || bestMissed == 0 { return (.none, 0) }

        var others = 0
        for f in axes where f != best { others += missed[f] ?? 0 }

        let share = Double(bestMissed) / Double(max(1, total[best] ?? 1))
        let score = 100 * share - 25 * Double(others) - 60 * Double(controls)
        return (best, Int(max(0, min(100, score)).rounded()))
    }
}

/// Un reglage de vision enregistre : ce que le test a trouve, ou ce que la
/// personne a ajuste elle-meme, sous un nom qu'elle a choisi.
///
/// Volontairement limite aux quatre valeurs qui decrivent la correction. Y mettre
/// un profil complet - luminosite, temperature, gains - reviendrait a changer tout
/// l'ecran en rappelant un reglage de daltonisme, ce que personne n'attend.
public final class VisionPreset {
    public var name = ""
    public var filter: ColorFilter = .deuteranopia
    public var severity: Double = 100
    public var strength: Double = 100
    public var mode: FilterMode = .correction

    public init() {}

    public static func fromProfile(_ name: String, _ p: Profile) -> VisionPreset {
        let v = VisionPreset()
        v.name = name
        v.filter = p.filter
        v.severity = p.visionSeverity
        v.strength = p.filterStrength
        v.mode = p.mode
        return v
    }

    public func applyTo(_ p: inout Profile) {
        p.filter = filter
        p.visionSeverity = severity
        p.filterStrength = strength
        p.mode = mode
    }

    /// Resume affichable : ce que ce reglage fait, en une ligne.
    public func describe() -> String {
        if !ColorMatrixEffect.isVisionFilter(filter) { return "aucune correction" }
        let prefix = mode == .simulation ? "simulation " : ""
        return prefix + Vision.plainName(filter).lowercased()
             + String(format: ", gravite %.0f %%, intensite %.0f %%", severity, strength)
    }

    public func serialize() -> String {
        [
            VisionPreset.esc(name),
            String(filter.rawValue),
            Profile.num(severity),
            Profile.num(strength),
            mode == .simulation ? "1" : "0",
        ].joined(separator: "~")
    }

    public static func deserialize(_ s: String) -> VisionPreset {
        let v = VisionPreset()
        let f = s.components(separatedBy: "~")
        if f.count > 0 { v.name = unesc(f[0]) }
        if f.count > 1, let raw = Int(f[1]), let cf = ColorFilter(rawValue: raw) { v.filter = cf }
        if f.count > 2 { v.severity = Profile.parseDouble(f[2]) ?? 100 }
        if f.count > 3 { v.strength = Profile.parseDouble(f[3]) ?? 100 }
        if f.count > 4 { v.mode = f[4] == "1" ? .simulation : .correction }
        return v
    }

    // Le nom est libre : il peut contenir les caracteres qui servent de separateurs.
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "~", with: "\\t")
         .replacingOccurrences(of: "|", with: "\\p")
         .replacingOccurrences(of: "\n", with: " ")
    }

    private static func unesc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\p", with: "|")
         .replacingOccurrences(of: "\\t", with: "~")
         .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
