// Le harnais maison remplace XCTest : voir Harness.swift.
import Foundation
@testable import OpusScreenKit

/// Les protections anti-ecran-noir.
///
/// C'est la suite la plus importante du projet. Une table de couleurs modifiee
/// survit a la mort du processus qui l'a ecrite : si l'application disparait alors
/// que l'ecran est a 5 %, l'ecran RESTE a 5 %. Tout ce qui suit verifie qu'aucun
/// chemin - reglage, import, ligne de commande, plantage - ne peut mener a un
/// ecran dont on ne sort pas.
final class SafetyTest: XCTestCase {

    override func setUp() {
        super.setUp()
        DisplayController.dryRun = true
        SystemVolume.dryRun = true
        Settings.dataFolderOverride = NSTemporaryDirectory() + "opusscreen-tests-safety"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: Settings.dataFolderOverride ?? "")
        Settings.dataFolderOverride = nil
        super.tearDown()
    }

    // ------------------------------------------------------------------ bornes dures

    @objc func testBrightnessIsAlwaysClamped() {
        XCTAssertEqual(SafetyGuard.clampBrightness(-50), GammaEngine.minBrightness)
        XCTAssertEqual(SafetyGuard.clampBrightness(0), GammaEngine.minBrightness)
        XCTAssertEqual(SafetyGuard.clampBrightness(1000), GammaEngine.maxBrightness)
        XCTAssertEqual(SafetyGuard.clampBrightness(Double.nan), 100)
        XCTAssertEqual(SafetyGuard.clampBrightness(75), 75)
    }

    @objc func testProfileClampsEverything() {
        var p = Profile()
        p.brightness = -10
        p.kelvin = 99999
        p.contrast = 1000
        p.gammaCurve = -5
        p.redGain = -1
        p.saturation = 5000
        p.visionSeverity = 200
        p.filterStrength = -3
        p.clampAll()

        XCTAssertEqual(p.brightness, GammaEngine.minBrightness)
        XCTAssertEqual(p.kelvin, ColorTemp.maxKelvin)
        XCTAssertEqual(p.contrast, 150)
        XCTAssertEqual(p.gammaCurve, 50)
        XCTAssertEqual(p.redGain, 0)
        XCTAssertEqual(p.saturation, 200)
        XCTAssertEqual(p.visionSeverity, 100)
        XCTAssertEqual(p.filterStrength, 0)
    }

    // ------------------------------------------------------------------ le plancher de la table

    /// Le piege que la borne sur la consigne ne voyait pas : la luminosite est
    /// bien bornee a 5 %, mais les trois gains de canaux la MULTIPLIENT ensuite,
    /// et ils descendent jusqu'a zero. Les trois a zero donnaient un ecran
    /// strictement noir a n'importe quelle luminosite demandee.
    @objc func testAllChannelsAtZeroStillLeavesAReadableScreen() {
        var p = Profile()
        p.brightness = 100
        p.redGain = 0
        p.greenGain = 0
        p.blueGain = 0

        let plan = GammaEngine.plan(p.brightness, allowOverlay: false, allowHardware: false)
        let ramp = GammaEngine.buildRamp(plan, p)

        let white = Double(ramp.red[255]) / 65535.0 * 0.2126
                  + Double(ramp.green[255]) / 65535.0 * 0.7152
                  + Double(ramp.blue[255]) / 65535.0 * 0.0722

        XCTAssertGreaterThanOrEqual(white, GammaEngine.minBrightness / 100.0 - 1e-6,
                                    "l'ecran ne doit jamais devenir strictement noir")
    }

    @objc func testCuttingBlueEntirelyIsAllowed() {
        // Couper le bleu est un reglage legitime - c'est la reduction de lumiere
        // bleue poussee au bout - et il laisse 93 % de luminance. Le plancher ne
        // doit donc PAS s'en meler.
        var p = Profile()
        p.blueGain = 0

        let plan = GammaEngine.plan(100, allowOverlay: false, allowHardware: false)
        let ramp = GammaEngine.buildRamp(plan, p)

        XCTAssertEqual(ramp.blue[255], 0, "le bleu demande a zero doit rester a zero")
        XCTAssertEqual(ramp.red[255], 65535, accuracy: 2, "le rouge ne doit pas etre touche")
    }

    @objc func testFloorRaisesProportionallyAndKeepsTheHue() {
        var ramp = Native.RampTable.allocate()
        // Une table tres sombre, mais teintee : rouge deux fois le vert.
        for i in 0..<Native.RampTable.size {
            ramp.red[i] = UInt16(Double(i) / 255.0 * 65535.0 * 0.02)
            ramp.green[i] = UInt16(Double(i) / 255.0 * 65535.0 * 0.01)
            ramp.blue[i] = 0
        }

        let raised = GammaEngine.enforceFloor(ramp)
        let r = Double(raised.red[255]) / 65535.0
        let g = Double(raised.green[255]) / 65535.0
        let luminance = 0.2126 * r + 0.7152 * g

        // La tolerance couvre l'arrondi sur 16 bits - un niveau vaut 1,5 x 10^-5 -
        // et non une derive du plancher : ce qui est verifie, c'est qu'on ne
        // tombe pas dans le noir, pas qu'on atteigne 0,0500000.
        XCTAssertGreaterThanOrEqual(luminance, 0.05 - 1e-4)
        XCTAssertEqual(r / g, 2.0, accuracy: 0.05, "la teinte voulue doit etre conservee")
    }

    @objc func testCompletelyBlackRampBecomesNeutralGrey() {
        var ramp = Native.RampTable.allocate()
        for i in 0..<Native.RampTable.size {
            ramp.red[i] = 0; ramp.green[i] = 0; ramp.blue[i] = 0
        }
        let fixed = GammaEngine.enforceFloor(ramp)
        XCTAssertEqual(fixed.red[255], fixed.green[255])
        XCTAssertEqual(fixed.green[255], fixed.blue[255])
        XCTAssertGreaterThan(fixed.red[255], 0)
    }

    // ------------------------------------------------------------------ voile

    @objc func testVeilIsNeverFullyOpaque() {
        for brightness in stride(from: 5.0, through: 34.0, by: 1.0) {
            let p = GammaEngine.plan(brightness, allowOverlay: true, allowHardware: false)
            XCTAssertLessThanOrEqual(p.overlayAlpha, 250)
        }
    }

    // ------------------------------------------------------------------ temoin de plantage

    @objc func testDirtyFlagRoundTrip() {
        SafetyGuard.clearDirtyFlag()
        SafetyGuard.markDirty()

        let flag = (Settings.dataFolder as NSString).appendingPathComponent("active.flag")
        XCTAssertTrue(FileManager.default.fileExists(atPath: flag))

        SafetyGuard.clearDirtyFlag()
        XCTAssertFalse(FileManager.default.fileExists(atPath: flag))
    }

    // ------------------------------------------------------------------ la ligne de commande

    @objc func testCommandLineCannotEscapeTheBounds() {
        let s = Settings()
        CommandLineDriver.apply(to: s, ["--brightness", "9999"])
        XCTAssertEqual(s.current.brightness, GammaEngine.maxBrightness)

        CommandLineDriver.apply(to: s, ["--brightness", "-40"])
        XCTAssertEqual(s.current.brightness, GammaEngine.minBrightness)

        CommandLineDriver.apply(to: s, ["--temp", "100000"])
        XCTAssertEqual(s.current.kelvin, ColorTemp.maxKelvin)

        CommandLineDriver.apply(to: s, ["--severity", "500"])
        XCTAssertEqual(s.current.visionSeverity, 100)

        CommandLineDriver.apply(to: s, ["--magnifier", "99"])
        XCTAssertEqual(s.magnifierZoom, ScreenMagnifier.maxZoom)
    }

    @objc func testResetReturnsToNeutral() {
        let s = Settings()
        s.current.brightness = 12
        s.current.kelvin = 1500
        s.adaptiveEnabled = true
        s.schedule = .solar

        CommandLineDriver.apply(to: s, ["--reset"])

        XCTAssertTrue(s.current.isNeutral())
        XCTAssertFalse(s.adaptiveEnabled)
        XCTAssertEqual(s.schedule, .manual)
    }

    /// Un profil neutre doit vraiment etre neutre : c'est lui qui est pose quand
    /// on suspend, et c'est donc lui qui rend l'ecran.
    @objc func testNeutralProfileIsNeutral() {
        XCTAssertTrue(Profile().isNeutral())

        var p = Profile()
        p.brightness = 99.99
        XCTAssertFalse(p.isNeutral())
    }

    @objc func testSuspendedControllerResolvesToNeutral() {
        let s = Settings()
        s.current.brightness = 15
        s.current.kelvin = 2000

        let controller = DisplayController(s)
        controller.suspend("test")
        XCTAssertTrue(controller.suspended)
        XCTAssertTrue(controller.describeCurrentPlan().hasPrefix("suspendu"))

        controller.resume()
        XCTAssertFalse(controller.suspended)
    }
}
