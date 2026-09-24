// Le harnais maison remplace XCTest : voir Harness.swift.
import Foundation
@testable import OpusScreenKit

/// La persistance, et la compatibilite avec le fichier de la version Windows.
///
/// Le format n'est pas un detail d'implementation : c'est ce qui permet a
/// quelqu'un qui travaille sur les deux systemes de ne regler ses quatre-vingts
/// curseurs qu'une fois. Un champ renomme casse cette promesse en silence.
final class SettingsTest: XCTestCase {

    override func setUp() {
        super.setUp()
        DisplayController.dryRun = true
        Settings.dataFolderOverride = NSTemporaryDirectory() + "opusscreen-tests-settings"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: Settings.dataFolderOverride ?? "")
        Settings.dataFolderOverride = nil
        super.tearDown()
    }

    // ------------------------------------------------------------------ profils

    @objc func testProfileRoundTrip() {
        var p = Profile()
        p.name = "Mon mode"
        p.brightness = 123.5
        p.kelvin = 3400
        p.contrast = 112
        p.gammaCurve = 90
        p.redGain = 95
        p.greenGain = 100
        p.blueGain = 60
        p.saturation = 140
        p.filter = .tritanopia
        p.visionSeverity = 65
        p.filterStrength = 80
        p.mode = .simulation
        p.tint = RGB(255, 168, 66)

        let back = Profile.deserialize(p.serialize())

        XCTAssertEqual(back.name, p.name)
        XCTAssertEqual(back.brightness, p.brightness, accuracy: 0.01)
        XCTAssertEqual(back.kelvin, p.kelvin)
        XCTAssertEqual(back.contrast, p.contrast, accuracy: 0.01)
        XCTAssertEqual(back.gammaCurve, p.gammaCurve, accuracy: 0.01)
        XCTAssertEqual(back.blueGain, p.blueGain, accuracy: 0.01)
        XCTAssertEqual(back.saturation, p.saturation, accuracy: 0.01)
        XCTAssertEqual(back.filter, p.filter)
        XCTAssertEqual(back.visionSeverity, p.visionSeverity, accuracy: 0.01)
        XCTAssertEqual(back.filterStrength, p.filterStrength, accuracy: 0.01)
        XCTAssertEqual(back.mode, p.mode)
        XCTAssertEqual(back.tint, p.tint)
    }

    @objc func testProfileNameMayContainSeparators() {
        var p = Profile()
        p.name = "Nuit ; profonde | speciale"
        let back = Profile.deserialize(p.serialize())
        XCTAssertEqual(back.name, p.name)
    }

    /// Un fichier ecrit par une version anterieure a 3.0 n'a pas les trois
    /// derniers champs. Il doit se relire tel quel, avec les valeurs par defaut.
    @objc func testOldProfileFormatStillReads() {
        let old = "Lecture;85;4200;95;100;100;100;100;92;0;0,0,0"
        let p = Profile.deserialize(old)
        XCTAssertEqual(p.name, "Lecture")
        XCTAssertEqual(p.brightness, 85, accuracy: 0.01)
        XCTAssertEqual(p.kelvin, 4200)
        XCTAssertEqual(p.visionSeverity, 100, "valeur par defaut")
        XCTAssertEqual(p.filterStrength, 100)
        XCTAssertEqual(p.mode, .correction)
    }

    @objc func testNumbersUseNoLocalSeparator() {
        // Un fichier ecrit en France doit se relire aux Etats-Unis, et
        // reciproquement : la virgule decimale rendrait le champ illisible.
        XCTAssertFalse(Profile.num(123.5).contains(","))
        XCTAssertEqual(Profile.num(100), "100")
        XCTAssertEqual(Profile.num(123.5), "123.5")
    }

    // ------------------------------------------------------------------ configuration complete

    @objc func testFullSettingsRoundTrip() {
        let s = Settings()
        s.current.brightness = 130
        s.current.kelvin = 3000
        s.activeModeName = "Film"
        s.schedule = .solar
        s.presetName = "f.lux classique"
        s.latitude = 45.7640
        s.longitude = 4.8357
        s.bedtimeHour = 23.5
        s.adaptiveEnabled = true
        s.adaptiveMin = 35
        s.beaconEnabled = true
        s.beaconColor = RGB(10, 200, 90)
        s.magnifierZoom = 3.5
        s.breaksEnabled = true
        s.onFullscreen = .everything
        s.matrixPerScreen = true
        s.showInDock = true

        var custom = Profile()
        custom.name = "Perso"
        custom.brightness = 55
        s.customProfiles.append(custom)

        let preset = VisionPreset()
        preset.name = "Mon ecran de jour"
        preset.filter = .protanopia
        preset.severity = 55
        s.visionPresets.append(preset)

        let rule = AppRule()
        rule.processName = "com.apple.safari"
        rule.profileName = "Lecture"
        s.appRules.append(rule)

        let back = Settings.fromText(s.export())

        XCTAssertEqual(back.current.brightness, 130, accuracy: 0.01)
        XCTAssertEqual(back.current.kelvin, 3000)
        XCTAssertEqual(back.activeModeName, "Film")
        XCTAssertEqual(back.schedule, .solar)
        XCTAssertEqual(back.presetName, "f.lux classique")
        XCTAssertEqual(back.latitude, 45.7640, accuracy: 0.001)
        XCTAssertEqual(back.bedtimeHour, 23.5, accuracy: 0.01)
        XCTAssertTrue(back.adaptiveEnabled)
        XCTAssertEqual(back.adaptiveMin, 35, accuracy: 0.01)
        XCTAssertTrue(back.beaconEnabled)
        XCTAssertEqual(back.beaconColor, RGB(10, 200, 90))
        XCTAssertEqual(back.magnifierZoom, 3.5, accuracy: 0.01)
        XCTAssertTrue(back.breaksEnabled)
        XCTAssertEqual(back.onFullscreen, .everything)
        XCTAssertTrue(back.matrixPerScreen)
        XCTAssertTrue(back.showInDock)
        XCTAssertEqual(back.customProfiles.count, 1)
        XCTAssertEqual(back.customProfiles.first?.name, "Perso")
        XCTAssertEqual(back.visionPresets.count, 1)
        XCTAssertEqual(back.visionPresets.first?.severity, 55)
        XCTAssertEqual(back.appRules.count, 1)
        XCTAssertEqual(back.appRules.first?.processName, "com.apple.safari")
    }

    /// La clef du demarrage automatique s'appelle `startWithWindows` dans le
    /// fichier, des deux cotes. C'est volontaire : un fichier venu d'un PC doit
    /// garder ce reglage.
    @objc func testWindowsStartupKeyIsUnderstood() {
        let text = "startWithWindows=1\n"
        XCTAssertTrue(Settings.fromText(text).startWithSystem)
    }

    @objc func testMonitorSettingsRoundTrip() {
        let m = MonitorSettings()
        m.stableId = "v00000610-m0000A02F-s00000000"
        m.friendlyName = "DELL U2412M"
        m.enabled = false
        m.independent = true
        m.brightnessOffset = -12.5
        m.blackout = true
        m.locked = true
        m.own.brightness = 42

        let back = MonitorSettings.deserialize(m.serialize())
        XCTAssertEqual(back.stableId, m.stableId)
        XCTAssertEqual(back.friendlyName, m.friendlyName)
        XCTAssertFalse(back.enabled)
        XCTAssertTrue(back.independent)
        XCTAssertEqual(back.brightnessOffset, -12.5, accuracy: 0.01)
        XCTAssertTrue(back.blackout)
        XCTAssertTrue(back.locked)
        XCTAssertEqual(back.own.brightness, 42, accuracy: 0.01)
    }

    /// Un fichier ecrit avant l'apparition du verrou n'a pas ce champ : il doit
    /// se relire tel quel, verrou a faux.
    @objc func testMonitorSettingsWithoutLockField() {
        let old = "abc~Mon ecran~1~0~0~0~Personnalise;100;6500;100;100;100;100;100;100;0;0,0,0"
        let m = MonitorSettings.deserialize(old)
        XCTAssertFalse(m.locked)
        XCTAssertTrue(m.enabled)
    }

    // ------------------------------------------------------------------ raccourcis

    @objc func testDefaultHotkeysCoverEveryAction() {
        let actions = Set(Settings.defaultHotkeys().map { $0.action })
        for expected in ["brightness.up", "brightness.down", "temp.warmer", "temp.cooler",
                         "reset", "pause.toggle", "mode.next", "adaptive.toggle", "break.now",
                         "panel.show", "vision.toggle", "color.reader", "color.copy",
                         "magnifier.toggle", "beacon.toggle"] {
            XCTAssertTrue(actions.contains(expected), "action manquante : \(expected)")
        }
    }

    @objc func testEveryActionHasALabel() {
        for h in Settings.defaultHotkeys() {
            XCTAssertNotEqual(Settings.actionLabel(h.action), h.action,
                              "l'action \(h.action) n'a pas d'intitule lisible")
        }
    }

    @objc func testHotkeyRoundTrip() {
        let h = HotkeyBinding("mode.next", HotkeyBinding.modControl | HotkeyBinding.modAlt, 0x4D)
        let back = HotkeyBinding.deserialize(h.serialize())
        XCTAssertEqual(back.action, "mode.next")
        XCTAssertEqual(back.modifiers, h.modifiers)
        XCTAssertEqual(back.key, 0x4D)
        XCTAssertTrue(back.enabled)
    }

    /// Une action ajoutee apres coup doit apparaitre chez les gens qui ont deja
    /// un fichier : sinon la nouvelle fonction reste invisible au clavier pour
    /// tous ceux qui utilisent l'application depuis longtemps.
    @objc func testMissingHotkeysAreMerged() {
        let partial = "hotkey=brightness.up>3>38>1\n"
        let s = Settings.fromText(partial)
        let actions = Set(s.hotkeys.map { $0.action })
        XCTAssertTrue(actions.contains("magnifier.toggle"))
        XCTAssertTrue(actions.contains("beacon.toggle"))
        XCTAssertEqual(s.hotkeys.filter { $0.action == "brightness.up" }.count, 1,
                       "l'action deja presente ne doit pas etre dupliquee")
    }

    @objc func testHotkeyDescriptionUsesMacSymbols() {
        let h = HotkeyBinding("x", HotkeyBinding.modControl | HotkeyBinding.modAlt, 0x26)
        XCTAssertEqual(h.describe(), "⌃⌥↑")
    }

    // ------------------------------------------------------------------ ecrans qui suivent

    /// Un ecran en profil independant ignorait en silence tout ce qui se decidait
    /// dans la page Ecran : choisir un mode ne changeait RIEN chez lui.
    @objc func testGeneralChangesReachIndependentScreens() {
        let s = Settings()
        let m = MonitorInfo()
        m.stableId = "ecran-1"
        let ms = s.forMonitor(m)
        ms.independent = true
        ms.own.brightness = 100
        ms.own.kelvin = 6500

        s.markGeneralAsPushed()
        s.current.brightness = 60
        XCTAssertTrue(s.syncFollowingScreens())
        XCTAssertEqual(ms.own.brightness, 60, accuracy: 0.01)
        XCTAssertEqual(ms.own.kelvin, 6500, "un champ inchange ne doit pas etre ecrase")
    }

    @objc func testLockedScreensNeverFollow() {
        let s = Settings()
        let m = MonitorInfo()
        m.stableId = "ecran-calibre"
        let ms = s.forMonitor(m)
        ms.locked = true
        ms.own.brightness = 100

        s.markGeneralAsPushed()
        s.current.brightness = 40
        s.syncFollowingScreens()
        XCTAssertEqual(ms.own.brightness, 100, "un ecran verrouille ne bouge jamais")
    }

    @objc func testLockBeatsLinking() {
        let s = Settings()
        s.linkMonitors = true
        let m = MonitorInfo()
        m.stableId = "ecran-calibre"
        let ms = s.forMonitor(m)
        ms.locked = true
        ms.own.brightness = 77

        s.current.brightness = 120
        XCTAssertEqual(s.effectiveFor(m).brightness, 77, accuracy: 0.01)
    }

    @objc func testOffsetAppliesOnlyToFollowingScreens() {
        let s = Settings()
        let m = MonitorInfo()
        m.stableId = "ecran-2"
        let ms = s.forMonitor(m)
        ms.brightnessOffset = -20

        s.current.brightness = 100
        XCTAssertEqual(s.effectiveFor(m).brightness, 80, accuracy: 0.01)

        // Meme un decalage enorme ne peut pas franchir la borne basse.
        ms.brightnessOffset = -500
        XCTAssertEqual(s.effectiveFor(m).brightness, GammaEngine.minBrightness, accuracy: 0.01)
    }

    @objc func testScreensNotFollowingIsExplained() {
        let s = Settings()
        let m = MonitorInfo()
        m.stableId = "ecran-3"
        m.friendlyName = "Studio Display"
        m.index = 0
        s.forMonitor(m).blackout = true

        let reasons = s.screensNotFollowing([m])
        XCTAssertEqual(reasons.count, 1)
        XCTAssertTrue(reasons[0].contains("eteint"))
    }

    // ------------------------------------------------------------------ disque

    @objc func testSaveAndLoad() {
        let s = Settings()
        s.current.brightness = 66
        s.activeModeName = "Soiree"
        s.save()

        let back = Settings.load()
        XCTAssertEqual(back.current.brightness, 66, accuracy: 0.01)
        XCTAssertEqual(back.activeModeName, "Soiree")
        XCTAssertFalse(back.isFirstRun)
    }

    @objc func testFirstRunIsDetected() {
        try? FileManager.default.removeItem(atPath: Settings.dataFolder)
        XCTAssertTrue(Settings.load().isFirstRun)
    }

    @objc func testUnreadableFileFallsBackToDefaults() {
        try? FileManager.default.createDirectory(atPath: Settings.dataFolder,
                                                 withIntermediateDirectories: true)
        let path = (Settings.dataFolder as NSString).appendingPathComponent("settings.ini")
        try? "ceci n'est pas une configuration\n@@@@\n".write(toFile: path, atomically: true, encoding: .utf8)

        let s = Settings.load()
        XCTAssertEqual(s.current.brightness, 100, "les valeurs par defaut doivent tenir")
        XCTAssertFalse(s.hotkeys.isEmpty)
    }
}
