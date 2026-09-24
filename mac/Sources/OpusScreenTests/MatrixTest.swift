// Le harnais maison remplace XCTest : voir Harness.swift.
import Foundation
@testable import OpusScreenKit

/// La matrice 5x5 : saturation, inversions, sepia, et surtout les filtres pour
/// daltoniens.
///
/// Deux proprietes comptent plus que les autres, et ce sont les seules qui, si
/// elles cassent, rendent l'application nuisible plutot qu'inutile :
///
///   - un gris doit rester gris. Un filtre qui teinte l'interface se fait
///     desactiver dans la minute ;
///   - a gravite nulle ou intensite nulle, la matrice doit etre EXACTEMENT
///     l'identite. Descendre un curseur a zero doit rendre l'ecran d'origine,
///     pas « presque » l'ecran d'origine.
final class MatrixTest: XCTestCase {

    private let visionFilters: [ColorFilter] = [.protanopia, .deuteranopia, .tritanopia]

    private func through(_ m: [Float], _ c: RGB) -> RGB {
        ColorMatrixEffect.transform(m, c)
    }

    // ------------------------------------------------------------------ gris neutres

    @objc func testCorrectionLeavesGreyUntouched() {
        for f in visionFilters {
            let m = ColorMatrixEffect.buildMatrix(100, f, 100, 100, .correction)
            for level in [0, 64, 128, 191, 255] {
                let out = through(m, RGB(white: level))
                XCTAssertEqual(out.r, level, accuracy: 1, "\(f) a \(level)")
                XCTAssertEqual(out.g, level, accuracy: 1, "\(f) a \(level)")
                XCTAssertEqual(out.b, level, accuracy: 1, "\(f) a \(level)")
            }
        }
    }

    @objc func testSimulationLeavesGreyUntouched() {
        for f in visionFilters {
            let m = ColorMatrixEffect.buildMatrix(100, f, 100, 100, .simulation)
            let out = through(m, RGB(white: 128))
            XCTAssertEqual(out.r, 128, accuracy: 1)
            XCTAssertEqual(out.g, 128, accuracy: 1)
            XCTAssertEqual(out.b, 128, accuracy: 1)
        }
    }

    // ------------------------------------------------------------------ retour exact a l'identite

    @objc func testZeroSeverityIsExactlyIdentity() {
        let identity = ColorMatrixEffect.identity()
        for f in visionFilters {
            let m = ColorMatrixEffect.buildMatrix(100, f, 0, 100, .correction)
            XCTAssertEqual(m, identity, "gravite 0 doit rendre l'identite exacte pour \(f)")
        }
    }

    @objc func testZeroStrengthIsExactlyIdentity() {
        let identity = ColorMatrixEffect.identity()
        for f in visionFilters {
            let m = ColorMatrixEffect.buildMatrix(100, f, 100, 0, .correction)
            XCTAssertEqual(m, identity, "intensite 0 doit rendre l'identite exacte pour \(f)")
        }
    }

    @objc func testNeutralRequestIsRecognised() {
        XCTAssertTrue(ColorMatrixEffect.isNeutralRequest(100, .none, 100, 100, .correction))
        XCTAssertTrue(ColorMatrixEffect.isNeutralRequest(100, .deuteranopia, 0, 100, .correction))
        XCTAssertTrue(ColorMatrixEffect.isNeutralRequest(100, .deuteranopia, 100, 0, .correction))
        XCTAssertFalse(ColorMatrixEffect.isNeutralRequest(100, .deuteranopia, 100, 100, .correction))
        XCTAssertFalse(ColorMatrixEffect.isNeutralRequest(120, .none, 100, 100, .correction))
        XCTAssertFalse(ColorMatrixEffect.isNeutralRequest(100, .sepia, 100, 100, .correction))
    }

    // ------------------------------------------------------------------ ce que le filtre doit faire

    @objc func testCorrectionSeparatesRedAndGreen() {
        let m = ColorMatrixEffect.buildMatrix(100, .deuteranopia, 100, 100, .correction)
        let red = through(m, RGB(200, 60, 60))
        let green = through(m, RGB(60, 160, 60))
        XCTAssertNotEqual(red, green)
        XCTAssertGreaterThan(Vision.deltaE(red, green), 20,
                             "apres correction, rouge et vert doivent rester franchement distincts")
    }

    @objc func testSimulationCrushesTheConfusionAxis() {
        for f in visionFilters {
            let sim = ColorMatrixEffect.buildMatrix(100, f, 100, 100, .simulation)
            let d = Vision.confusionDirection(f)
            let anchor = [0.5, 0.5, 0.5]

            let a = Vision.rgb(anchor, d, -0.12)
            let b = Vision.rgb(anchor, d, +0.12)

            let before = Vision.deltaE(a, b)
            let after = Vision.deltaE(through(sim, a), through(sim, b))

            XCTAssertGreaterThan(before, after,
                                 "la simulation doit reduire l'ecart sur l'axe de confusion (\(f))")
        }
    }

    // ------------------------------------------------------------------ les autres filtres

    @objc func testGrayscaleRemovesAllColour() {
        let m = ColorMatrixEffect.buildMatrix(100, .grayscale, 100, 100, .correction)
        let out = through(m, RGB(220, 60, 60))
        XCTAssertEqual(out.r, out.g, accuracy: 1)
        XCTAssertEqual(out.g, out.b, accuracy: 1)
    }

    @objc func testInvertIsAnInvert() {
        let m = ColorMatrixEffect.buildMatrix(100, .invert, 100, 100, .correction)
        XCTAssertEqual(through(m, RGB.black), RGB.white)
        XCTAssertEqual(through(m, RGB.white), RGB.black)
    }

    @objc func testInvertKeepHuePreservesHue() {
        let m = ColorMatrixEffect.buildMatrix(100, .invertKeepHue, 100, 100, .correction)

        // Le blanc devient noir et le noir devient blanc, comme une inversion
        // ordinaire.
        XCTAssertEqual(through(m, RGB.white).luminance, 0, accuracy: 0.02)
        XCTAssertEqual(through(m, RGB.black).luminance, 1, accuracy: 0.02)

        // Mais un rouge sombre devient un rouge CLAIR, pas un cyan : c'est toute
        // la difference, et c'est ce qui rend le mode utilisable avec des photos.
        let darkRed = RGB(120, 20, 20)
        let out = through(m, darkRed)
        XCTAssertGreaterThan(out.luminance, darkRed.luminance, "la clarte doit s'inverser")
        XCTAssertGreaterThan(out.r, out.g, "la teinte rouge doit survivre")
        XCTAssertGreaterThan(out.r, out.b)
    }

    @objc func testSaturationExtremes() {
        let grey = ColorMatrixEffect.buildMatrix(0, .none, 100, 100, .correction)
        let out = through(grey, RGB(220, 60, 60))
        XCTAssertEqual(out.r, out.g, accuracy: 1)

        let untouched = ColorMatrixEffect.buildMatrix(100, .none, 100, 100, .correction)
        XCTAssertEqual(untouched, ColorMatrixEffect.identity())
    }

    // ------------------------------------------------------------------ gravite

    @objc func testSeverityIsMonotonic() {
        // Plus la gravite monte, plus la correction s'ecarte de l'identite.
        var previous = 0.0
        for severity in stride(from: 0.0, through: 100.0, by: 10.0) {
            let m = ColorMatrixEffect.buildMatrix(100, .deuteranopia, severity, 100, .correction)
            let out = through(m, RGB(160, 120, 90))
            let distance = Vision.deltaE(out, RGB(160, 120, 90))
            XCTAssertGreaterThanOrEqual(distance + 0.01, previous,
                                        "l'effet doit croitre avec la gravite, ratee a \(severity)")
            previous = distance
        }
        XCTAssertGreaterThan(previous, 1.0, "a pleine gravite, la correction doit se voir")
    }

    // ------------------------------------------------------------------ conversion pour le nuanceur

    /// La matrice part vers Metal en colonnes : un vecteur LIGNE d'un cote, un
    /// vecteur COLONNE de l'autre. Une transposition oubliee rend des couleurs
    /// plausibles et fausses - c'est exactement le genre d'erreur qu'aucun regard
    /// ne rattrape.
    @objc func testShaderConversionMatchesTheReferenceTransform() {
        let m = ColorMatrixEffect.buildMatrix(120, .deuteranopia, 70, 90, .correction)

        let columns = [
            [m[0], m[1], m[2]],
            [m[5], m[6], m[7]],
            [m[10], m[11], m[12]],
        ]
        let offset = [m[20] + m[15], m[21] + m[16], m[22] + m[17]]

        for sample in [RGB(200, 60, 60), RGB(60, 160, 200), RGB(128, 128, 128), RGB(30, 200, 90)] {
            let reference = ColorMatrixEffect.transform(m, sample)

            // Ce que fera le nuanceur : mix * rgb + offset.
            let r = Double(sample.r) / 255, g = Double(sample.g) / 255, b = Double(sample.b) / 255
            var out = [0.0, 0.0, 0.0]
            for j in 0..<3 {
                out[j] = Double(columns[0][j]) * r + Double(columns[1][j]) * g
                       + Double(columns[2][j]) * b + Double(offset[j])
                out[j] = min(max(out[j], 0), 1)
            }
            let shader = RGB(Int((out[0] * 255).rounded()),
                             Int((out[1] * 255).rounded()),
                             Int((out[2] * 255).rounded()))

            XCTAssertEqual(shader.r, reference.r, accuracy: 1)
            XCTAssertEqual(shader.g, reference.g, accuracy: 1)
            XCTAssertEqual(shader.b, reference.b, accuracy: 1)
        }
    }
}
