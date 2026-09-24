// Le harnais maison remplace XCTest : voir Harness.swift.
import Foundation
@testable import OpusScreenKit

/// Le savoir metier sur les deficiences visuelles.
///
/// La propriete centrale est celle du comparateur : les paires montrees doivent
/// etre REELLEMENT confondues par la vision simulee. Une premiere version listait
/// des paires ecrites d'apres le sens commun ; mesurees, elles se revelaient
/// parfaitement distinctes, et le comparateur concluait a l'inutilite d'une
/// correction qui, elle, fonctionnait.
final class VisionTest: XCTestCase {

    private let filters: [ColorFilter] = [.protanopia, .deuteranopia, .tritanopia]

    // ------------------------------------------------------------------ ecart percu

    @objc func testDeltaEIsZeroForIdenticalColours() {
        XCTAssertEqual(Vision.deltaE(RGB(120, 80, 40), RGB(120, 80, 40)), 0, accuracy: 1e-9)
    }

    @objc func testDeltaEGrowsWithDistance() {
        let base = RGB(128, 128, 128)
        let near = Vision.deltaE(base, RGB(132, 128, 128))
        let far = Vision.deltaE(base, RGB(200, 60, 60))
        XCTAssertLessThan(near, far)
        XCTAssertLessThan(near, Vision.justNoticeable, "quatre niveaux ne se voient pas")
    }

    @objc func testLabOfKnownColours() {
        let white = Vision.toLab(.white)
        XCTAssertEqual(white[0], 100, accuracy: 0.1)
        XCTAssertEqual(white[1], 0, accuracy: 0.1)
        XCTAssertEqual(white[2], 0, accuracy: 0.1)

        let black = Vision.toLab(.black)
        XCTAssertEqual(black[0], 0, accuracy: 0.1)
    }

    // ------------------------------------------------------------------ direction de confusion

    @objc func testConfusionDirectionIsNormalised() {
        for f in filters {
            let d = Vision.confusionDirection(f)
            let norm = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).squareRoot()
            XCTAssertEqual(norm, 1.0, accuracy: 1e-6, "\(f)")
        }
    }

    @objc func testConfusionDirectionIsActuallyCrushed() {
        // Se deplacer le long de cette direction doit passer quasi inapercu une
        // fois la vision simulee ; s'en ecarter doit se voir.
        for f in filters {
            let sim = ColorMatrixEffect.buildMatrix(100, f, 100, 100, .simulation)
            let d = Vision.confusionDirection(f)
            let anchor = [0.5, 0.5, 0.5]

            let along = Vision.deltaE(
                ColorMatrixEffect.transform(sim, Vision.rgb(anchor, d, -0.1)),
                ColorMatrixEffect.transform(sim, Vision.rgb(anchor, d, +0.1)))

            // Une direction perpendiculaire arbitraire, de meme amplitude.
            let other = [d[1], -d[0], 0.0]
            let across = Vision.deltaE(
                ColorMatrixEffect.transform(sim, Vision.rgb(anchor, other, -0.1)),
                ColorMatrixEffect.transform(sim, Vision.rgb(anchor, other, +0.1)))

            XCTAssertLessThan(along, across,
                              "l'axe de confusion doit etre le plus ecrase (\(f))")
        }
    }

    // ------------------------------------------------------------------ les paires

    @objc func testPairsAreGenuinelyConfused() {
        for f in filters {
            let sim = ColorMatrixEffect.buildMatrix(100, f, 100, 100, .simulation)
            for pair in Vision.confusionPairs(f, 100) {
                let delta = Vision.deltaE(ColorMatrixEffect.transform(sim, pair.a),
                                          ColorMatrixEffect.transform(sim, pair.b))
                XCTAssertLessThanOrEqual(delta, Vision.justNoticeable + 0.4,
                    "\(f) : « \(pair.label) » devrait etre confondue, ecart mesure \(delta)")
            }
        }
    }

    @objc func testPairsAreDistinctToNormalVision() {
        for f in filters {
            for pair in Vision.confusionPairs(f, 100) {
                XCTAssertNotEqual(pair.a, pair.b,
                                  "\(f) : une paire dont les deux couleurs sont egales n'apprend rien")
            }
        }
    }

    @objc func testCorrectionIncreasesTheGap() {
        // C'est la promesse de la page Daltonisme : apres correction, l'ecart
        // percu par cette meme vision doit augmenter.
        for f in filters {
            let sim = ColorMatrixEffect.buildMatrix(100, f, 100, 100, .simulation)
            let correction = ColorMatrixEffect.buildMatrix(100, f, 100, 100, .correction)

            var improved = 0
            let pairs = Vision.confusionPairs(f, 100)
            for pair in pairs {
                let before = Vision.deltaE(ColorMatrixEffect.transform(sim, pair.a),
                                           ColorMatrixEffect.transform(sim, pair.b))
                let after = Vision.deltaE(
                    ColorMatrixEffect.transform(sim, ColorMatrixEffect.transform(correction, pair.a)),
                    ColorMatrixEffect.transform(sim, ColorMatrixEffect.transform(correction, pair.b)))
                if after > before { improved += 1 }
            }
            XCTAssertEqual(improved, pairs.count,
                           "\(f) : la correction doit ecarter TOUTES les paires montrees")
        }
    }

    @objc func testPairsFollowTheSeverity() {
        // Des paires baties a pleine gravite puis montrees a quelqu'un regle sur
        // une anomalie moderee ressortaient parfaitement distinctes : le
        // comparateur affichait « distinctes » des la colonne de gauche.
        let f = ColorFilter.deuteranopia
        for severity in [30.0, 60.0, 100.0] {
            let sim = ColorMatrixEffect.buildMatrix(100, f, severity, 100, .simulation)
            for pair in Vision.confusionPairs(f, severity) {
                let delta = Vision.deltaE(ColorMatrixEffect.transform(sim, pair.a),
                                          ColorMatrixEffect.transform(sim, pair.b))
                XCTAssertLessThanOrEqual(delta, Vision.justNoticeable + 0.4,
                    "gravite \(severity) : « \(pair.label) » doit rester confondue")
            }
        }
    }

    @objc func testAtLeastOnePairIsAlwaysShown() {
        for f in filters + [ColorFilter.none] {
            XCTAssertFalse(Vision.confusionPairs(f, 100).isEmpty)
            XCTAssertFalse(Vision.confusionPairs(f, 5).isEmpty)
        }
    }

    // ------------------------------------------------------------------ noms de couleurs

    @objc func testColourNames() {
        XCTAssertEqual(Vision.nameOf(RGB(255, 0, 0)), "rouge")
        XCTAssertEqual(Vision.nameOf(RGB(0, 0, 0)), "noir")
        XCTAssertEqual(Vision.nameOf(RGB(255, 255, 255)), "blanc")
        XCTAssertEqual(Vision.nameOf(RGB(128, 128, 128)), "gris")
        XCTAssertEqual(Vision.nameOf(RGB(40, 100, 210)), "bleu")
    }

    @objc func testDescribeAddsAShadeWhenUseful() {
        // Un bleu marine tres sombre : son nom ne porte pas encore de nuance de
        // clarte, donc la description doit en ajouter une.
        XCTAssertEqual(Vision.nameOf(RGB(12, 30, 60)), "bleu marine")
        XCTAssertTrue(Vision.describeColor(RGB(12, 30, 60)).contains("fonce"))
        // Un nom qui porte deja sa nuance ne se cumule pas.
        XCTAssertEqual(Vision.describeColor(RGB(190, 190, 190)), "gris clair")
    }

    @objc func testSeverityWords() {
        XCTAssertEqual(Vision.severityWord(0), "vision normale")
        XCTAssertEqual(Vision.severityWord(20), "anomalie legere")
        XCTAssertEqual(Vision.severityWord(50), "anomalie moderee")
        XCTAssertEqual(Vision.severityWord(80), "anomalie severe")
        XCTAssertEqual(Vision.severityWord(100), "dichromatie complete")
    }

    @objc func testFilterDisplayNameFollowsSeverity() {
        var p = Profile()
        p.filter = .deuteranopia
        p.visionSeverity = 100
        XCTAssertEqual(p.filterDisplayName(), "deuteranopie")
        p.visionSeverity = 40
        XCTAssertEqual(p.filterDisplayName(), "deuteranomalie",
                       "sous la dichromatie complete, le terme exact est « -omalie »")
    }
}
