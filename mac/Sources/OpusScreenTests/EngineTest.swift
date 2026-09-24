// Le harnais maison remplace XCTest : voir Harness.swift.
import Foundation
@testable import OpusScreenKit

/// Le moteur de luminosite : le plan a trois etages, et la table qu'il produit.
///
/// Ces valeurs sont celles du tableau de calibration de la documentation. Les
/// verifier par un test plutot que par l'oeil est ce qui permet de modifier la
/// repartition sans casser en silence la promesse « rien n'est ecrete jusqu'a
/// 135 % ».
final class EngineTest: XCTestCase {

    override func setUp() {
        super.setUp()
        DisplayController.dryRun = true
    }

    // ------------------------------------------------------------------ le plan

    @objc func testPlanNeutralAt100() {
        let p = GammaEngine.plan(100, allowOverlay: true, allowHardware: true)
        XCTAssertEqual(p.gammaExponent, 1.0, accuracy: 1e-9)
        XCTAssertEqual(p.linearGain, 1.0, accuracy: 1e-9)
        XCTAssertEqual(p.overlayTransmission, 1.0, accuracy: 1e-9)
        XCTAssertFalse(p.clips)
        XCTAssertEqual(p.hardwareTarget, -1, "a 100 %, le retroeclairage n'a aucune raison de bouger")
    }

    @objc func testPlanDimsLinearlyDownToTheFloor() {
        let p = GammaEngine.plan(50, allowOverlay: true, allowHardware: true)
        XCTAssertEqual(p.linearGain, 0.5, accuracy: 1e-9)
        XCTAssertEqual(p.overlayTransmission, 1.0, accuracy: 1e-9,
                       "au-dessus de 35 %, la table suffit : aucun voile ne doit apparaitre")
    }

    @objc func testVeilTakesOverBelowTheFloor() {
        let p = GammaEngine.plan(10, allowOverlay: true, allowHardware: true)
        XCTAssertEqual(p.linearGain, 0.35, accuracy: 1e-9, "la table reste au plancher")
        XCTAssertEqual(p.overlayTransmission, 10.0 / 35.0, accuracy: 1e-9)
        XCTAssertLessThan(p.overlayAlpha, 251, "le voile n'est jamais totalement opaque")
    }

    @objc func testWithoutVeilTheTableGoesAsLowAsItCan() {
        let p = GammaEngine.plan(10, allowOverlay: false, allowHardware: true)
        XCTAssertEqual(p.linearGain, 0.10, accuracy: 1e-9)
        XCTAssertEqual(p.overlayTransmission, 1.0, accuracy: 1e-9)
    }

    @objc func testNoClippingUpTo135() {
        for brightness in stride(from: 101.0, through: 135.0, by: 1.0) {
            let p = GammaEngine.plan(brightness, allowOverlay: true, allowHardware: true)
            XCTAssertFalse(p.clips, "a \(brightness) %, rien ne doit etre ecrete")
            XCTAssertEqual(p.linearGain, 1.0, accuracy: 1e-9,
                           "jusqu'a 135 %, seule la courbe travaille")
        }
    }

    @objc func testClippingOnlyAppearsAboveTheLastThird() {
        let p = GammaEngine.plan(150, allowOverlay: true, allowHardware: true)
        XCTAssertTrue(p.clips)
        XCTAssertGreaterThan(p.linearGain, 1.0)
        XCTAssertEqual(p.hardwareTarget, 100, "au-dela de 100 %, le retroeclairage est pousse au maximum")
    }

    // ------------------------------------------------------------------ calibration

    /// Luminance au gris moyen, mesuree sur la table produite.
    private func midGrey(_ brightness: Double) -> Double {
        let plan = GammaEngine.plan(brightness, allowOverlay: true, allowHardware: true)
        let ramp = GammaEngine.buildRamp(plan, kelvin: ColorTemp.maxKelvin)
        // Entree 0,5 = index 128 sur 255.
        return Double(ramp.green[128]) / 65535.0
    }

    @objc func testCalibrationTable() {
        // Les valeurs du tableau de docs/ARCHITECTURE.md. La tolerance couvre
        // l'arrondi sur 16 bits, pas une derive du modele.
        XCTAssertEqual(midGrey(50), 0.250, accuracy: 0.004)
        XCTAssertEqual(midGrey(100), 0.500, accuracy: 0.004)
        XCTAssertEqual(midGrey(125), 0.610, accuracy: 0.012)
        XCTAssertEqual(midGrey(135), 0.641, accuracy: 0.012)
        XCTAssertEqual(midGrey(150), 0.762, accuracy: 0.015)
    }

    @objc func testMidGreyGrowsWithBrightness() {
        var previous = 0.0
        for b in stride(from: 40.0, through: 150.0, by: 5.0) {
            let value = midGrey(b)
            XCTAssertGreaterThan(value, previous,
                                 "la luminance doit croitre avec la consigne, ratee a \(b) %")
            previous = value
        }
    }

    @objc func testBoostGainsAtLeastFiftyPercentAtMaximum() {
        let gain = midGrey(150) / midGrey(100)
        XCTAssertGreaterThan(gain, 1.50, "a 150 %, les tons moyens doivent gagner au moins 50 %")
    }

    // ------------------------------------------------------------------ la table

    @objc func testIdentityRampIsIdentity() {
        let id = Native.RampTable.identity()
        XCTAssertEqual(id.red[0], 0)
        XCTAssertEqual(id.red[255], 65535)
        XCTAssertEqual(id.green[128], UInt16((128.0 / 255.0 * 65535.0).rounded()))
    }

    @objc func testRampIsMonotonic() {
        var p = Profile()
        p.brightness = 130
        p.contrast = 120
        p.kelvin = 3400
        let plan = GammaEngine.plan(p.brightness, allowOverlay: true, allowHardware: true)
        let ramp = GammaEngine.buildRamp(plan, p)

        for i in 1..<Native.RampTable.size {
            XCTAssertGreaterThanOrEqual(ramp.red[i], ramp.red[i - 1])
            XCTAssertGreaterThanOrEqual(ramp.green[i], ramp.green[i - 1])
            XCTAssertGreaterThanOrEqual(ramp.blue[i], ramp.blue[i - 1])
        }
    }

    @objc func testTemperatureOnlyRemovesBlue() {
        var warm = Profile()
        warm.kelvin = 2000
        let plan = GammaEngine.plan(100, allowOverlay: true, allowHardware: true)
        let ramp = GammaEngine.buildRamp(plan, warm)

        XCTAssertEqual(ramp.red[255], 65535, "le rouge reste intact quand on rechauffe")
        XCTAssertLessThan(ramp.blue[255], ramp.red[255], "le bleu, lui, descend")
        XCTAssertLessThan(ramp.green[255], ramp.red[255])
    }

    @objc func testNeutralTemperatureChangesNothing() {
        let plan = GammaEngine.plan(100, allowOverlay: true, allowHardware: true)
        let ramp = GammaEngine.buildRamp(plan, kelvin: 6500)
        let id = Native.RampTable.identity()
        for i in 0..<Native.RampTable.size {
            XCTAssertEqual(Int(ramp.red[i]), Int(id.red[i]), accuracy: 1)
            XCTAssertEqual(Int(ramp.green[i]), Int(id.green[i]), accuracy: 1)
            XCTAssertEqual(Int(ramp.blue[i]), Int(id.blue[i]), accuracy: 1)
        }
    }

    @objc func testBlendReachesBothEnds() {
        var p = Profile()
        p.brightness = 20
        let plan = GammaEngine.plan(p.brightness, allowOverlay: false, allowHardware: false)
        let ramp = GammaEngine.buildRamp(plan, p)

        let none = GammaEngine.blend(ramp, 0)
        XCTAssertEqual(none.red[255], Native.RampTable.identity().red[255], accuracy: 2)

        let full = GammaEngine.blend(ramp, 1)
        XCTAssertEqual(full.red[255], ramp.red[255])
    }
}
