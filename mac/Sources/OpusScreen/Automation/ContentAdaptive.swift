import Foundation
import CoreGraphics

/// Luminosite qui suit le contenu affiche : une page blanche fait baisser l'ecran,
/// une video sombre le fait remonter. C'est le principe de Gammy, absent aussi bien
/// de f.lux que de PangoBright.
///
/// Deux details qui font que cela fonctionne sans osciller :
///
///   - La mesure est prise sur la memoire d'image, donc AVANT que la table de
///     couleurs ne soit appliquee en sortie. Notre propre effet n'entre pas dans
///     la mesure, ce qui interdit toute boucle de retroaction.
///   - Le voile et l'image filtree sont retires de la capture - toutes nos
///     fenetres declarent `sharingType = .none`. Sans cela le voile se
///     mesurerait lui-meme. Cet indicateur a un second merite : ces surfaces
///     disparaissent aussi des captures d'ecran de l'utilisateur, ce que
///     PangoBright ne faisait pas.
public final class ContentAdaptive {

    // Resolution d'analyse : suffisante pour juger d'une ambiance, negligeable a calculer.
    private static let sampleW = 48
    private static let sampleH = 27

    private let queue = DispatchQueue(label: "opusscreen.adaptive", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var smoothed: Double = -1

    /// Bornes entre lesquelles l'automatisme a le droit de se deplacer.
    public var minBrightness: Double = 40
    public var maxBrightness: Double = 110

    /// 1 = tres lent et stable, 10 = tres reactif. Au-dela de 6 l'ecran respire.
    public var reactivity: Double = 3

    /// Intervalle de mesure en millisecondes.
    public var intervalMs: Int = 1200

    /// Appele avec la luminosite suggeree. Toujours emis hors du fil de l'interface.
    public var suggestedBrightness: ((Double) -> Void)?

    public private(set) var lastMeasuredLuminance: Double = 0

    public private(set) var isRunning = false

    public init() {}

    public func start() {
        guard timer == nil else { return }
        isRunning = true
        smoothed = -1

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.2,
                   repeating: .milliseconds(max(200, intervalMs)))
        t.setEventHandler { [weak self] in self?.step() }
        timer = t
        t.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
        smoothed = -1
    }

    /// Reprogramme la cadence sans perdre le lissage en cours.
    public func reschedule() {
        guard isRunning else { return }
        timer?.schedule(deadline: .now() + .milliseconds(max(200, intervalMs)),
                        repeating: .milliseconds(max(200, intervalMs)))
    }

    private func step() {
        guard let lum = measureScreenLuminance() else { return }
        lastMeasuredLuminance = lum

        let target = targetFor(lum)

        // Lissage exponentiel : la reactivite pilote la constante de temps.
        if smoothed < 0 { smoothed = target }
        let alpha = max(0.02, min(0.5, reactivity / 20.0))
        smoothed += (target - smoothed) * alpha

        suggestedBrightness?(smoothed)
    }

    /// Ecran clair -> on baisse, ecran sombre -> on monte. La racine carree evite
    /// que les scenes tres sombres ne fassent bondir la luminosite d'un coup.
    func targetFor(_ luminance: Double) -> Double {
        let t = max(0, min(1, luminance)).squareRoot()
        let b = maxBrightness - (maxBrightness - minBrightness) * t
        return SafetyGuard.clampBrightness(b)
    }

    /// Luminance perceptuelle moyenne de l'affichage, entre 0 et 1. nil si echec.
    ///
    /// La mesure porte sur l'ecran PRINCIPAL et non sur l'union de tous les
    /// ecrans : capturer un bureau de trois dalles pour en tirer un seul nombre
    /// coute trois fois plus cher pour une reponse qui melange des contenus sans
    /// rapport - un film sur un ecran et un traitement de texte sur l'autre
    /// donneraient une moyenne qui ne decrit ni l'un ni l'autre.
    func measureScreenLuminance() -> Double? {
        let display = CGMainDisplayID()
        guard let image = CGDisplayCreateImage(display) else { return nil }
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }

        let rowBytes = image.bytesPerRow
        let pixelBytes = image.bitsPerPixel / 8
        guard pixelBytes >= 3, image.width > 0, image.height > 0 else { return nil }

        let stepX = max(1, image.width / ContentAdaptive.sampleW)
        let stepY = max(1, image.height / ContentAdaptive.sampleH)

        var sum = 0.0
        var count = 0
        var y = 0
        while y < image.height {
            var x = 0
            while x < image.width {
                let offset = y * rowBytes + x * pixelBytes
                let b0 = Double(bytes[offset])
                let b1 = Double(bytes[offset + 1])
                let b2 = Double(bytes[offset + 2])
                // Ordre des octets BGRA sur toutes les machines visees ; les
                // coefficients de luminance sont ceux de Rec. 709.
                sum += (0.2126 * b2 + 0.7152 * b1 + 0.0722 * b0) / 255.0
                count += 1
                x += stepX
            }
            y += stepY
        }
        return count > 0 ? sum / Double(count) : nil
    }

    public func dispose() { stop() }
}
