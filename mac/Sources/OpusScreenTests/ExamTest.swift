// Le harnais maison remplace XCTest : voir Harness.swift.
import Foundation
@testable import OpusScreenKit

/// Le test guide de vision des couleurs.
///
/// Le point de cette suite : faire passer le test a des observateurs SIMULES
/// dont on connait exactement la vision, et verifier que la mesure les retrouve.
/// C'est possible parce que tout ce qui decide vit dans `VisionExam`, sans
/// dependre d'un clic - la separation entre le calcul et la fenetre n'est pas
/// de la coquetterie, elle est ce qui rend le test verifiable.
final class ExamTest: XCTestCase {

    private let axes: [ColorFilter] = [.protanopia, .deuteranopia, .tritanopia]

    // ------------------------------------------------------------------ paires d'essai

    @objc func testPairSeparationGrowsWithTheRequest() {
        for axis in axes {
            var previous = 0.0
            for separation in stride(from: 0.1, through: 1.0, by: 0.1) {
                let p = VisionExam.pairAt(axis, separation)
                let delta = Vision.deltaE(p.0, p.1)
                XCTAssertGreaterThanOrEqual(delta + 0.5, previous, "\(axis) a \(separation)")
                previous = delta
            }
            XCTAssertGreaterThan(previous, 10, "l'ecart maximal doit etre franc (\(axis))")
        }
    }

    @objc func testZeroSeparationGivesTheSameColourTwice() {
        for axis in axes {
            let p = VisionExam.pairAt(axis, 0)
            XCTAssertEqual(p.0, p.1)
        }
    }

    // ------------------------------------------------------------------ seuil et gravite

    @objc func testThresholdGrowsWithSeverity() {
        for axis in axes {
            var previous = 0.0
            for severity in stride(from: 0.0, through: 100.0, by: 20.0) {
                let t = VisionExam.separationThreshold(axis, severity)
                XCTAssertGreaterThanOrEqual(t + 1e-6, previous,
                    "le seuil doit croitre avec la gravite (\(axis) a \(severity))")
                previous = t
            }
        }
    }

    /// L'aller-retour : d'une gravite on calcule un seuil, du seuil on doit
    /// retrouver la gravite. C'est ce qui permet a l'escalier de conclure.
    ///
    /// La plage testee commence a 50 %, et ce n'est pas une facilite : sous une
    /// vingtaine de pour cent, le seuil varie si peu que l'inversion cesse
    /// d'etre bien conditionnee - deux gravites tres differentes produisent le
    /// meme seuil a un millieme pres. C'est precisement pourquoi le test guide
    /// refuse d'annoncer une deficience sous 20 % plutot que de nommer un
    /// chiffre qu'il ne mesure pas.
    @objc func testSeverityFromThresholdIsTheInverse() {
        for axis in axes {
            for severity in [50.0, 70.0, 90.0] {
                let threshold = VisionExam.separationThreshold(axis, severity)
                let back = VisionExam.severityFromThreshold(axis, threshold)
                XCTAssertEqual(back, severity, accuracy: 15,
                               "\(axis) : gravite \(severity) -> seuil \(threshold) -> \(back)")
            }
        }
    }

    // ------------------------------------------------------------------ escalier

    /// Un observateur simule : il repond « differentes » quand l'ecart percu par
    /// SA vision depasse le seuil de perception. Exactement ce que ferait une
    /// personne parfaitement attentive.
    private func simulatedObserver(axis: ColorFilter, severity: Double,
                                   pairAxis: ColorFilter, separation: Double) -> Bool {
        let p = VisionExam.pairAt(pairAxis, separation)
        return VisionExam.perceivedDelta(axis, severity, p.0, p.1) >= VisionExam.justNoticeable
    }

    @objc func testStaircaseConvergesOnASimulatedObserver() {
        for axis in axes {
            for severity in [40.0, 70.0, 100.0] {
                let stair = VisionExam.Staircase(axis)
                var guard_ = 0
                while !stair.done && guard_ < 200 {
                    stair.answer(simulatedObserver(axis: axis, severity: severity,
                                                   pairAxis: axis, separation: stair.separation))
                    guard_ += 1
                }
                XCTAssertTrue(stair.done, "l'escalier doit conclure (\(axis), \(severity))")

                let measured = VisionExam.severityFromThreshold(axis, stair.threshold)
                XCTAssertEqual(measured, severity, accuracy: 25,
                               "\(axis) : gravite reelle \(severity), mesuree \(measured)")
            }
        }
    }

    @objc func testStaircaseStopsEarlyOnTotalDeficiency() {
        // Quelqu'un qui ne distingue rien, meme a l'ecart maximal : il n'y a pas
        // de seuil a mesurer, et l'escalier doit le reconnaitre au lieu de
        // continuer vingt-deux essais pour rien.
        let stair = VisionExam.Staircase(.deuteranopia)
        var count = 0
        while !stair.done && count < 50 {
            stair.answer(false)
            count += 1
        }
        XCTAssertTrue(stair.done)
        XCTAssertLessThan(count, 6, "deux refus au maximum suffisent a conclure")
    }

    @objc func testStaircaseProgressReachesOne() {
        let stair = VisionExam.Staircase(.protanopia, 4, 10)
        var alternate = true
        while !stair.done {
            stair.answer(alternate)
            alternate.toggle()
        }
        XCTAssertEqual(stair.progress, 1.0, accuracy: 0.001)
    }

    // ------------------------------------------------------------------ planches

    @objc func testPlatesAreReproducibleForAGivenSeed() {
        let a = VisionExam.plates(seed: 12345)
        let b = VisionExam.plates(seed: 12345)
        XCTAssertEqual(a.count, b.count)
        for i in 0..<a.count {
            XCTAssertEqual(a[i].digit, b[i].digit)
            XCTAssertEqual(a[i].figure, b[i].figure)
            XCTAssertEqual(a[i].background, b[i].background)
            XCTAssertEqual(a[i].seed, b[i].seed)
        }
    }

    @objc func testPlatesCoverEveryAxisAndIncludeControls() {
        let plates = VisionExam.plates(seed: 7)
        for axis in axes {
            XCTAssertGreaterThanOrEqual(plates.filter { $0.axis == axis }.count, 1,
                                        "aucune planche pour \(axis)")
        }
        XCTAssertGreaterThanOrEqual(plates.filter { $0.axis == .none }.count, 2,
                                    "il faut des planches de controle")
    }

    @objc func testPlatesAreReadableByNormalVision() {
        for plate in VisionExam.plates(seed: 21) {
            let delta = Vision.deltaE(plate.figure, plate.background)
            XCTAssertGreaterThan(delta, 9,
                "une planche illisible par tout le monde ne depiste rien (chiffre \(plate.digit))")
        }
    }

    @objc func testPlateChoicesContainTheAnswer() {
        for plate in VisionExam.plates(seed: 33) {
            XCTAssertTrue(plate.choices.contains(plate.digit))
            XCTAssertEqual(Set(plate.choices).count, plate.choices.count,
                           "les propositions ne doivent pas se repeter")
        }
    }

    @objc func testTargetedPlatesHideTheDigitFromTheirAxisOnly() {
        for plate in VisionExam.plates(seed: 55) where plate.axis != .none {
            let hidden = VisionExam.perceivedDelta(plate.axis, plate.level,
                                                   plate.figure, plate.background)
            XCTAssertLessThan(hidden, VisionExam.justNoticeable,
                              "la planche doit s'effacer pour \(plate.axis)")

            for other in axes where other != plate.axis {
                let visible = VisionExam.perceivedDelta(other, plate.level,
                                                        plate.figure, plate.background)
                XCTAssertGreaterThanOrEqual(visible, 2.0,
                    "une planche qui s'efface pour tout le monde n'accuse personne")
            }
        }
    }

    @objc func testControlPlatesAreReadableByEveryone() {
        for plate in VisionExam.plates(seed: 99) where plate.axis == .none {
            for axis in axes {
                let delta = VisionExam.perceivedDelta(axis, 100, plate.figure, plate.background)
                XCTAssertGreaterThan(delta, VisionExam.justNoticeable,
                    "une planche de controle doit se lire avec n'importe quelle vision")
            }
        }
    }

    // ------------------------------------------------------------------ conclusion

    @objc func testTypeFromPlatesAccusesTheRightAxis() {
        let plates = VisionExam.plates(seed: 4242)
        // Un observateur qui rate exactement les planches de la deuteranopie.
        let read = plates.map { $0.axis != .deuteranopia }
        let outcome = VisionExam.typeFromPlates(plates, read)
        XCTAssertEqual(outcome.filter, .deuteranopia)
        XCTAssertGreaterThan(outcome.confidence, 50)
    }

    @objc func testAllPlatesReadMeansNoDeficiency() {
        let plates = VisionExam.plates(seed: 4242)
        let outcome = VisionExam.typeFromPlates(plates, plates.map { _ in true })
        XCTAssertEqual(outcome.filter, .none)
    }

    @objc func testFailedControlsCollapseConfidence() {
        let plates = VisionExam.plates(seed: 4242)
        // Rate les planches de la deuteranopie ET les controles : des reponses au
        // hasard. Le test doit dire qu'il ne sait pas.
        let read = plates.map { $0.axis != .deuteranopia && $0.axis != ColorFilter.none }
        let outcome = VisionExam.typeFromPlates(plates, read)
        XCTAssertLessThan(outcome.confidence, 50,
                          "un controle rate doit effondrer la confiance")
    }

    /// Rouge et vert sont voisins : leurs axes de confusion se ressemblent, et
    /// les separer demande un appareil de cabinet - ce que la fenetre de
    /// resultat dit d'ailleurs a l'utilisateur quand la confiance est faible. Le
    /// test verifie donc ce qui est reellement promis : la FAMILLE est toujours
    /// juste, et le type exact l'est a pleine gravite.
    @objc func testFitFindsTheRightVision() {
        for axis in axes {
            for severity in [60.0, 100.0] {
                var measured: [ColorFilter: Double] = [:]
                for pairAxis in axes {
                    measured[pairAxis] = VisionExam.predictedThreshold(pairAxis, axis, severity)
                }
                let fit = VisionExam.fit(measured)

                if severity >= 100 || axis == .tritanopia {
                    XCTAssertEqual(fit.axis, axis,
                                   "profil de \(axis) a \(severity) attribue a \(fit.axis)")
                } else {
                    let redGreen: Set<ColorFilter> = [.protanopia, .deuteranopia]
                    XCTAssertTrue(redGreen.contains(fit.axis),
                                  "profil de \(axis) a \(severity) attribue a \(fit.axis)")
                }
                XCTAssertEqual(fit.severity, severity, accuracy: 15)
                XCTAssertGreaterThan(fit.quality, 0.3)
            }
        }
    }

    @objc func testFitOnNormalVisionFindsNothingConvincing() {
        var measured: [ColorFilter: Double] = [:]
        for pairAxis in axes {
            measured[pairAxis] = VisionExam.predictedThreshold(pairAxis, .deuteranopia, 0)
        }
        let fit = VisionExam.fit(measured)
        XCTAssertTrue(fit.severity < 20 || fit.quality < 0.3,
                      "une vision normale ne doit pas etre declaree daltonienne")
    }

    // ------------------------------------------------------------------ reglages enregistres

    @objc func testVisionPresetRoundTrip() {
        let v = VisionPreset()
        v.name = "Mon ecran ~ de | jour"
        v.filter = .tritanopia
        v.severity = 62.5
        v.strength = 88
        v.mode = .simulation

        let back = VisionPreset.deserialize(v.serialize())
        XCTAssertEqual(back.name, v.name, "le nom est libre, separateurs compris")
        XCTAssertEqual(back.filter, v.filter)
        XCTAssertEqual(back.severity, v.severity, accuracy: 0.01)
        XCTAssertEqual(back.strength, v.strength, accuracy: 0.01)
        XCTAssertEqual(back.mode, v.mode)
    }

    /// Un reglage de vision ne retient QUE la correction. Le rappeler ne doit
    /// toucher ni la luminosite ni la temperature - ce serait une mauvaise
    /// surprise pour un reglage nomme « lecture ».
    @objc func testVisionPresetTouchesOnlyTheCorrection() {
        var p = Profile()
        p.brightness = 42
        p.kelvin = 2400

        let v = VisionPreset()
        v.filter = .protanopia
        v.severity = 50
        v.applyTo(&p)

        XCTAssertEqual(p.filter, .protanopia)
        XCTAssertEqual(p.visionSeverity, 50, accuracy: 0.01)
        XCTAssertEqual(p.brightness, 42, accuracy: 0.01)
        XCTAssertEqual(p.kelvin, 2400)
    }

    // ------------------------------------------------------------------ generateur

    @objc func testSeededRandomIsDeterministic() {
        var a = SeededRandom(seed: 999)
        var b = SeededRandom(seed: 999)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
    }

    @objc func testSeededRandomStaysInRange() {
        var r = SeededRandom(seed: 1)
        for _ in 0..<1000 {
            let v = r.nextDouble()
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThan(v, 1)
            XCTAssertLessThan(r.nextInt(6), 6)
        }
    }
}
