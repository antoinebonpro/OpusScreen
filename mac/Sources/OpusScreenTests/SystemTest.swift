// Le harnais maison remplace XCTest : voir Harness.swift.
import Foundation
import AppKit
@testable import OpusScreenKit

/// Ce qui touche au systeme, et ce qui l'entoure : horloge solaire,
/// planification, mise a jour, ligne de commande, theme, icone.
final class SystemTest: XCTestCase {

    override func setUp() {
        super.setUp()
        DisplayController.dryRun = true
        Settings.dataFolderOverride = NSTemporaryDirectory() + "opusscreen-tests-system"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: Settings.dataFolderOverride ?? "")
        Settings.dataFolderOverride = nil
        super.tearDown()
    }

    // ------------------------------------------------------------------ temperature

    @objc func testNeutralAt6500() {
        let m = ColorTemp.multipliers(6500)
        XCTAssertEqual(m[0], 1.0, accuracy: 1e-9)
        XCTAssertEqual(m[1], 1.0, accuracy: 1e-9)
        XCTAssertEqual(m[2], 1.0, accuracy: 1e-9)
    }

    @objc func testWarmerRemovesBlueFirst() {
        let warm = ColorTemp.multipliers(2000)
        XCTAssertEqual(warm[0], 1.0, accuracy: 1e-9, "le rouge reste au maximum")
        XCTAssertLessThan(warm[2], warm[1])
        XCTAssertLessThan(warm[1], warm[0])
    }

    @objc func testMultipliersAreMonotonic() {
        var previousBlue = 0.0
        for k in stride(from: ColorTemp.minKelvin, through: ColorTemp.maxKelvin, by: 100) {
            let blue = ColorTemp.multipliers(k)[2]
            XCTAssertGreaterThanOrEqual(blue + 1e-9, previousBlue, "a \(k) K")
            previousBlue = blue
        }
    }

    @objc func testMultipliersAreClamped() {
        XCTAssertEqual(ColorTemp.multipliers(-500), ColorTemp.multipliers(ColorTemp.minKelvin))
        XCTAssertEqual(ColorTemp.multipliers(99999), ColorTemp.multipliers(ColorTemp.maxKelvin))
    }

    @objc func testFluxPresetsArePresent() {
        let names = Preset.builtIn().map { $0.name }
        XCTAssertTrue(names.contains("Couleurs recommandees"))
        XCTAssertTrue(names.contains("f.lux classique"))
        XCTAssertTrue(names.contains("Aucun"))

        let none = Scheduler.findPreset("Aucun")
        XCTAssertEqual(none.day, 6500)
        XCTAssertEqual(none.night, 6500)
        XCTAssertEqual(none.late, 6500)
    }

    // ------------------------------------------------------------------ soleil

    @objc func testSunTimesAreSaneInParis() {
        let components = DateComponents(year: 2026, month: 6, day: 21, hour: 12)
        let date = Calendar.current.date(from: components)!
        guard let times = SolarClock.sunTimes(date, 48.8566, 2.3522) else {
            XCTFail("le soleil se leve a Paris au solstice d'ete")
            return
        }
        XCTAssertGreaterThan(times.sunset, times.sunrise)
        XCTAssertLessThan(times.sunrise, 8.0)
        XCTAssertGreaterThan(times.sunset, 19.0)
    }

    @objc func testPolarNightIsReportedRatherThanInvented() {
        let components = DateComponents(year: 2026, month: 12, day: 21, hour: 12)
        let date = Calendar.current.date(from: components)!
        XCTAssertNil(SolarClock.sunTimes(date, 80.0, 0.0),
                     "au-dela du cercle polaire, il faut dire que le soleil ne se leve pas")
    }

    @objc func testFormatHour() {
        XCTAssertEqual(SolarClock.formatHour(13.5), "13:30")
        XCTAssertEqual(SolarClock.formatHour(0), "00:00")
        XCTAssertEqual(SolarClock.formatHour(25.25), "01:15", "au-dela de minuit, on reboucle")
    }

    @objc func testWrappedIntervalCrossesMidnight() {
        XCTAssertTrue(SolarClock.isBetweenWrapped(1.0, 23.0, 7.0))
        XCTAssertTrue(SolarClock.isBetweenWrapped(23.5, 23.0, 7.0))
        XCTAssertFalse(SolarClock.isBetweenWrapped(12.0, 23.0, 7.0))
    }

    // ------------------------------------------------------------------ planification

    @objc func testManualScheduleChangesNothing() {
        let s = Settings()
        s.schedule = .manual
        s.current.kelvin = 4200
        let r = Scheduler.evaluate(s, Date())
        XCTAssertEqual(r.kelvin, 4200)
        XCTAssertFalse(r.brightnessApplies)
    }

    @objc func testFixedHoursUseTheGivenTimes() {
        let s = Settings()
        s.schedule = .fixedHours
        s.fixedDayHour = 8
        s.fixedNightHour = 19
        s.presetName = "f.lux classique"

        let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 13))!
        let r = Scheduler.evaluate(s, noon)
        XCTAssertEqual(r.kelvin, 6500, "en pleine journee, la teinte du jour")
        XCTAssertEqual(r.phase, .day)
    }

    @objc func testNightIsWarmerThanDay() {
        let s = Settings()
        s.schedule = .fixedHours
        s.fixedDayHour = 8
        s.fixedNightHour = 19
        s.bedtimeHour = 23
        s.presetName = "Couleurs recommandees"

        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 13))!
        let night = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 21))!

        XCTAssertGreaterThan(Scheduler.evaluate(s, day).kelvin,
                             Scheduler.evaluate(s, night).kelvin)
    }

    @objc func testScheduleCanDriveBrightness() {
        let s = Settings()
        s.schedule = .fixedHours
        s.scheduleAffectsBrightness = true
        s.dayBrightness = 110
        s.nightBrightness = 60
        s.fixedDayHour = 8
        s.fixedNightHour = 19

        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 13))!
        let r = Scheduler.evaluate(s, day)
        XCTAssertTrue(r.brightnessApplies)
        XCTAssertEqual(r.brightness, 110, accuracy: 0.01)
    }

    @objc func testScheduleDescriptionMentionsTheTimes() {
        let s = Settings()
        s.schedule = .fixedHours
        let r = Scheduler.evaluate(s, Date())
        XCTAssertTrue(Scheduler.describe(s, r).contains("Jour"))

        s.schedule = .manual
        XCTAssertTrue(Scheduler.describe(s, r).contains("manuel"))
    }

    // ------------------------------------------------------------------ adaptation au contenu

    @objc func testAdaptiveInvertsTheContent() {
        let engine = ContentAdaptive()
        engine.minBrightness = 40
        engine.maxBrightness = 110

        let onWhite = engine.targetFor(1.0)
        let onBlack = engine.targetFor(0.0)

        XCTAssertEqual(onWhite, 40, accuracy: 0.01, "une page blanche fait baisser l'ecran")
        XCTAssertEqual(onBlack, 110, accuracy: 0.01, "une scene sombre le fait remonter")
        XCTAssertGreaterThan(engine.targetFor(0.25), engine.targetFor(0.75))
    }

    @objc func testAdaptiveStaysWithinSafeBounds() {
        let engine = ContentAdaptive()
        engine.minBrightness = -100
        engine.maxBrightness = 9999
        XCTAssertLessThanOrEqual(engine.targetFor(0), GammaEngine.maxBrightness)
        XCTAssertGreaterThanOrEqual(engine.targetFor(1), GammaEngine.minBrightness)
    }

    // ------------------------------------------------------------------ mise a jour

    @objc func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer([1, 1, 0], [1, 0, 9]))
        XCTAssertTrue(Updater.isNewer([2, 0], [1, 9, 9]))
        XCTAssertFalse(Updater.isNewer([1, 0, 0], [1, 0, 0]))
        XCTAssertFalse(Updater.isNewer([1, 0], [1, 0, 1]))
        XCTAssertTrue(Updater.isNewer([1, 0, 1], [1, 0]))
    }

    @objc func testTagParsing() {
        XCTAssertEqual(Updater.parseVersion("v3.4.0"), [3, 4, 0])
        XCTAssertEqual(Updater.parseVersion("3.4.0"), [3, 4, 0])
        XCTAssertEqual(Updater.parseVersion("v1.2"), [1, 2])
        // L'etiquette de la ligne macOS, qui vit dans le meme depot que celle de
        // Windows et ne suit pas la meme numerotation.
        XCTAssertEqual(Updater.parseVersion("mac-v1.0.0"), [1, 0, 0])
        XCTAssertEqual(Updater.parseVersion("sans-chiffre"), [0])
    }

    /// Le depot porte les deux versions. La plus recente publication est celle de
    /// Windows ; celle qui nous concerne est la plus recente qui porte un paquet
    /// macOS. Se tromper de ligne annoncerait chaque jour une erreur de reseau qui
    /// n'en est pas une.
    @objc func testReleaseListPicksTheMacOne() {
        let json = """
        [
          {"tag_name": "v3.4.0", "assets": [
             {"name": "OpusScreen.exe", "browser_download_url": "https://example.invalid/win", "size": 1}]},
          {"tag_name": "mac-v1.0.0", "assets": [
             {"name": "OpusScreen-mac.zip", "browser_download_url": "https://example.invalid/mac",
              "size": 99, "digest": "sha256:beef"}]},
          {"tag_name": "v3.3.1", "assets": [
             {"name": "OpusScreen.exe", "browser_download_url": "https://example.invalid/old", "size": 1}]}
        ]
        """
        guard let info = Updater.parseList(Data(json.utf8)) else {
            XCTFail("la publication macOS aurait du etre trouvee")
            return
        }
        XCTAssertEqual(info.version, [1, 0, 0])
        XCTAssertEqual(info.downloadUrl, "https://example.invalid/mac")
        XCTAssertEqual(info.sha256, "beef")
    }

    @objc func testReleaseListWithoutAnyMacPackage() {
        let json = """
        [{"tag_name": "v3.4.0", "assets": [
            {"name": "OpusScreen.exe", "browser_download_url": "https://example.invalid/win", "size": 1}]}]
        """
        XCTAssertNil(Updater.parseList(Data(json.utf8)),
                     "aucun paquet macOS : il n'y a rien a proposer")
    }

    @objc func testReleaseParsing() {
        let json = """
        {
          "tag_name": "v2.0.0",
          "name": "OpusScreen 2.0.0",
          "html_url": "https://example.invalid/release",
          "assets": [
            {"name": "OpusScreen.exe", "browser_download_url": "https://example.invalid/win", "size": 1},
            {"name": "OpusScreen-mac.zip", "browser_download_url": "https://example.invalid/mac",
             "size": 4242, "digest": "sha256:abc123"}
          ]
        }
        """
        guard let info = Updater.parse(Data(json.utf8)) else {
            XCTFail("la publication aurait du etre lue")
            return
        }
        XCTAssertEqual(info.version, [2, 0, 0])
        XCTAssertEqual(info.downloadUrl, "https://example.invalid/mac",
                       "c'est le paquet macOS qu'il faut prendre, pas celui de Windows")
        XCTAssertEqual(info.size, 4242)
        XCTAssertEqual(info.sha256, "abc123")
    }

    @objc func testReleaseWithoutMacAssetIsRejected() {
        let json = """
        {"tag_name": "v2.0.0", "assets": [
          {"name": "OpusScreen.exe", "browser_download_url": "https://example.invalid/win", "size": 1}]}
        """
        XCTAssertNil(Updater.parse(Data(json.utf8)),
                     "une publication sans paquet macOS ne doit rien proposer")
    }

    // ------------------------------------------------------------------ ligne de commande

    @objc func testModeNameWithSpacesIsMatched() {
        let s = Settings()
        // Sans guillemets : les mots se recollent, et la correspondance la plus
        // longue gagne.
        CommandLineDriver.apply(to: s, ["--mode", "Nuit", "profonde"])
        XCTAssertEqual(s.activeModeName, "Nuit profonde")
        XCTAssertEqual(s.current.brightness, 35, accuracy: 0.01)
    }

    @objc func testModeNameStopsAtTheNextOption() {
        let s = Settings()
        CommandLineDriver.apply(to: s, ["--mode", "Lecture", "--brightness", "120"])
        XCTAssertEqual(s.activeModeName, "Lecture")
        XCTAssertEqual(s.current.brightness, 120, accuracy: 0.01)
    }

    @objc func testVisionAcceptsPlainAndClinicalNames() {
        XCTAssertEqual(CommandLineDriver.parseVision("vert"), .deuteranopia)
        XCTAssertEqual(CommandLineDriver.parseVision("deuteranopia"), .deuteranopia)
        XCTAssertEqual(CommandLineDriver.parseVision("rouge"), .protanopia)
        XCTAssertEqual(CommandLineDriver.parseVision("bleu"), .tritanopia)
        XCTAssertEqual(CommandLineDriver.parseVision("aucune"), ColorFilter.none)
        XCTAssertNil(CommandLineDriver.parseVision("mauve"))
    }

    @objc func testQuotedArgumentsSurviveTheRoundTrip() {
        let parts = CommandLineDriver.splitArgs("--mode \"Nuit profonde\" --brightness 42")
        XCTAssertEqual(parts, ["--mode", "Nuit profonde", "--brightness", "42"])
    }

    @objc func testCommandDetection() {
        XCTAssertTrue(CommandLineDriver.hasCommand(["--brightness", "50"]))
        XCTAssertFalse(CommandLineDriver.hasCommand(["--minimized"]))
        XCTAssertTrue(CommandLineDriver.wantsShow(["--show"]))
        XCTAssertTrue(CommandLineDriver.startMinimized(["--minimized"]))
    }

    // ------------------------------------------------------------------ codes de touche

    @objc func testKeyCodeMappingIsBidirectional() {
        for vk: UInt32 in [0x26, 0x28, 0x25, 0x27, 0x41, 0x5A, 0x30, 0x39, 0x70, 0x7B] {
            guard let mac = KeyCodes.macKeyCode(forWindowsVK: vk) else {
                XCTFail("aucune correspondance pour 0x\(String(vk, radix: 16))")
                continue
            }
            XCTAssertEqual(KeyCodes.windowsVK(forMacKeyCode: mac), vk)
        }
    }

    @objc func testEveryDefaultHotkeyCanBeRegistered() {
        // Un raccourci par defaut sans correspondance macOS serait un raccourci
        // documente qui ne fonctionne pas.
        for h in Settings.defaultHotkeys() {
            XCTAssertNotNil(KeyCodes.macKeyCode(forWindowsVK: h.key),
                            "le raccourci \(h.action) n'est pas traduisible")
        }
    }

    // ------------------------------------------------------------------ theme

    /// Le contraste est verifie, pas devine. Une application dont l'argument
    /// principal est l'accessibilite ne peut pas se permettre du texte a 3:1.
    @objc func testThemeContrastRatios() {
        let pairs: [(String, NSColor, NSColor, Double)] = [
            ("texte sur carte", Theme.fg, Theme.card, 4.5),
            ("texte attenue sur carte", Theme.dim, Theme.card, 4.5),
            ("texte discret sur carte", Theme.faint, Theme.card, 4.5),
            ("texte sur fond", Theme.fg, Theme.bg, 4.5),
            ("accent sur carte", Theme.accent, Theme.card, 4.5),
            ("accent sur fond", Theme.accent, Theme.bg, 4.5),
            ("boost sur carte", Theme.boost, Theme.card, 4.5),
            ("bon sur creux", Theme.good, Theme.sunken, 4.5),
            ("danger sur creux", Theme.danger, Theme.sunken, 4.5),
            // Un trait qui identifie un composant : 3:1 suffit.
            ("trait fort sur carte", Theme.borderStrong, Theme.card, 3.0),
            ("focus sur carte", Theme.focus, Theme.card, 3.0),
        ]

        for (name, front, back, minimum) in pairs {
            let ratio = Theme.contrastRatio(front, back)
            XCTAssertGreaterThanOrEqual(ratio, minimum,
                String(format: "%@ : %.2f:1, il en faut %.1f", name, ratio, minimum))
        }
    }

    // ------------------------------------------------------------------ icone

    @objc func testTrayGlyphDrawsAtEverySize() {
        for size in [16.0, 18.0, 22.0, 32.0] as [CGFloat] {
            let image = TrayGlyph.draw(size: size, profile: Profile(), suspended: false, adaptive: false)
            XCTAssertEqual(image.size.width, size)
            XCTAssertEqual(image.size.height, size)
        }
    }

    @objc func testTrayGlyphStateColourFollowsTheSettings() {
        var warm = Profile()
        warm.kelvin = 2000
        let warmColour = TrayGlyph.stateColor(warm)
        let neutralColour = TrayGlyph.stateColor(Profile())

        XCTAssertLessThan(warmColour.b, neutralColour.b, "le soir, la pupille perd son bleu")

        var dim = Profile()
        dim.brightness = 20
        XCTAssertLessThan(TrayGlyph.stateColor(dim).luminance, neutralColour.luminance)
    }

    // ------------------------------------------------------------------ modes livres

    @objc func testBuiltInModesAreAllValid() {
        for var mode in Profile.builtInModes() {
            let before = mode
            mode.clampAll()
            XCTAssertEqual(mode.brightness, before.brightness, accuracy: 0.01,
                           "le mode « \(mode.name) » sort des bornes")
            XCTAssertEqual(mode.kelvin, before.kelvin)
            XCTAssertFalse(mode.name.isEmpty)
            XCTAssertFalse(mode.summary().isEmpty)
        }
    }

    @objc func testAccessibilityModesArePresent() {
        let names = Profile.builtInModes().map { $0.name }
        for expected in ["Daltonisme - rouge", "Daltonisme - vert", "Daltonisme - bleu",
                         "Achromatopsie", "Basse vision", "Photophobie", "Sombre partout"] {
            XCTAssertTrue(names.contains(expected), "mode d'accessibilite manquant : \(expected)")
        }
    }

    @objc func testNormalModeIsNeutral() {
        guard let normal = Profile.builtInModes().first(where: { $0.name == "Normal" }) else {
            XCTFail("le mode Normal doit exister")
            return
        }
        XCTAssertTrue(normal.isNeutral(), "le mode Normal doit rendre l'ecran strictement normal")
    }

    // ------------------------------------------------------------------ regles par application

    @objc func testAppRuleRoundTrip() {
        let r = AppRule()
        r.processName = "com.apple.safari"
        r.profileName = "Lecture"
        r.disable = true

        let back = AppRule.deserialize(r.serialize())
        XCTAssertEqual(back.processName, r.processName)
        XCTAssertEqual(back.profileName, r.profileName)
        XCTAssertTrue(back.disable)
    }

    @objc func testKnownAppsUseBundleIdentifiers() {
        for entry in KnownApps.suggestions() {
            XCTAssertTrue(entry.process.contains("."),
                          "« \(entry.process) » ne ressemble pas a un identifiant de paquet")
            XCTAssertEqual(entry.process, entry.process.lowercased())
        }
    }

    // ------------------------------------------------------------------ couleurs

    @objc func testRGBParsingAndSerialising() {
        XCTAssertEqual(RGB.parse("255,168,66"), RGB(255, 168, 66))
        XCTAssertNil(RGB.parse("255,168"))
        XCTAssertNil(RGB.parse("rouge"))
        XCTAssertEqual(RGB(255, 168, 66).serialized, "255,168,66")
        XCTAssertEqual(RGB(255, 168, 66).hex, "#FFA842")
    }

    @objc func testRGBClampsOutOfRangeValues() {
        XCTAssertEqual(RGB(-10, 300, 128), RGB(0, 255, 128))
    }
}
