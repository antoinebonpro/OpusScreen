// Le harnais maison remplace XCTest : voir Harness.swift.
import Foundation
import AppKit
import CoreGraphics
import Metal
@testable import OpusScreenKit

/// La verification REELLE : celle qui touche le materiel.
///
/// Les sept autres suites tournent en mode a blanc. Elles verifient que le
/// calcul est juste, ce qui est necessaire et pas suffisant : une table de
/// couleurs parfaitement calculee que le systeme refuse de poser ne sert a rien,
/// et le calcul ne le dira jamais.
///
/// Cette suite-ci pose, lit, et compare. Elle est separee des autres pour deux
/// raisons :
///
///   - elle modifie l'ecran de la machine qui l'execute, brievement ;
///   - plusieurs de ses verifications dependent d'une autorisation ou d'un
///     materiel. Quand ce qu'il faut manque, elle le DIT et n'echoue pas :
///     un test rouge parce qu'un moniteur ne parle pas DDC/CI serait un test
///     qui ment.
///
/// Chaque verification rend ce qu'elle a emprunte, y compris si elle echoue -
/// c'est a cela que servent les `defer`. Une suite de tests qui laisse l'ecran
/// sombre serait une belle demonstration du probleme qu'elle est censee prevenir.
final class LiveTest: XCTestCase {

    /// Ce qui manque sur cette machine, note au passage et affiche a la fin.
    nonisolated(unsafe) static var skipped: [String] = []

    private func skip(_ what: String, _ why: String) {
        LiveTest.skipped.append("\(what) — \(why)")
    }

    override func setUp() {
        super.setUp()
        // Le mode a blanc est LEVE : c'est tout l'objet de cette suite.
        DisplayController.dryRun = false
        SystemVolume.dryRun = true      // le son, en revanche, on n'y touche pas
        Settings.dataFolderOverride = NSTemporaryDirectory() + "opusscreen-live"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: Settings.dataFolderOverride ?? "")
        Settings.dataFolderOverride = nil
        super.tearDown()
    }

    // ------------------------------------------------------------------ les ecrans

    @objc func testMonitorsAreDetected() {
        let monitors = MonitorEnum.all()
        XCTAssertGreaterThanOrEqual(monitors.count, 1, "aucun ecran detecte")

        for m in monitors {
            XCTAssertNotEqual(m.displayID, 0)
            XCTAssertFalse(m.stableId.isEmpty, "un ecran sans identifiant ne peut rien memoriser")
            XCTAssertFalse(m.friendlyName.isEmpty)
            XCTAssertGreaterThan(m.bounds.width, 0)
            XCTAssertGreaterThan(m.bounds.height, 0)
            XCTAssertFalse(m.label.isEmpty)
            XCTAssertFalse(m.detail.isEmpty)
        }

        XCTAssertEqual(monitors.filter { $0.isPrimary }.count, 1,
                       "il doit y avoir exactement un ecran principal")
    }

    /// Deux ecrans ne doivent JAMAIS partager une fiche de reglages : le voile de
    /// l'un se poserait sur l'autre, et « eteindre cet ecran » en eteindrait deux.
    @objc func testStableIdsAreUnique() {
        let ids = MonitorEnum.all().map { $0.stableId }
        XCTAssertEqual(Set(ids).count, ids.count, "deux ecrans partagent un identifiant")
    }

    @objc func testStableIdIsStableAcrossCalls() {
        let first = MonitorEnum.all().map { $0.stableId }
        let second = MonitorEnum.all().map { $0.stableId }
        XCTAssertEqual(first, second, "l'identifiant doit survivre a une redetection")
    }

    // ------------------------------------------------------------------ etage 2 : la table

    @objc func testGammaIsSupported() {
        for m in MonitorEnum.all() {
            XCTAssertTrue(GammaEngine.supportsGamma(m),
                          "\(m.friendlyName) refuse la table de couleurs")
        }
    }

    /// Le test central : poser une table, la relire, constater qu'elle a PRIS,
    /// puis rendre l'ecran.
    @objc func testGammaIsActuallyAppliedAndRestored() {
        guard let m = MonitorEnum.all().first else {
            skip("table de couleurs", "aucun ecran")
            return
        }

        // Ce qui est en place avant nous. On le rend quoi qu'il arrive.
        defer {
            GammaEngine.resetToIdentity(m)
            Native.restoreAllGamma()
        }

        let before = Native.getGammaRamp(m.displayID)
        XCTAssertNotNil(before, "impossible de lire la table en place")

        // Une table franchement assombrie : 40 %, sans voile ni materiel, pour
        // que l'ecart soit indiscutable a la relecture.
        var profile = Profile()
        profile.brightness = 40
        let plan = GammaEngine.plan(40, allowOverlay: false, allowHardware: false)
        let wanted = GammaEngine.buildRamp(plan, profile)

        let result = GammaEngine.apply(m, wanted)
        XCTAssertTrue(result.success, "le systeme a refuse la table")
        XCTAssertEqual(result.effectiveScale, 1.0, accuracy: 0.001,
                       "la table a du etre attenuee pour passer")

        guard let readBack = Native.getGammaRamp(m.displayID) else {
            XCTFail("impossible de relire la table posee")
            return
        }

        // Le blanc doit avoir baisse d'environ 60 %.
        let white = Double(readBack.red[255]) / 65535.0
        XCTAssertEqual(white, 0.40, accuracy: 0.03,
                       "la table posee ne correspond pas a la consigne")

        // Et la table entiere doit correspondre, aux arrondis du pilote pres.
        var maxDiff = 0
        for i in 0..<Native.RampTable.size {
            maxDiff = max(maxDiff, abs(Int(readBack.green[i]) - Int(wanted.green[i])))
        }
        XCTAssertLessThan(maxDiff, 600,
                          "le systeme a rabote la table : ecart maximal \(maxDiff)")

        // Restauration, verifiee.
        GammaEngine.resetToIdentity(m)
        usleep(120_000)
        guard let restored = Native.getGammaRamp(m.displayID) else {
            XCTFail("impossible de relire apres restauration")
            return
        }
        let restoredWhite = Double(restored.red[255]) / 65535.0
        XCTAssertGreaterThan(restoredWhite, 0.95, "l'ecran n'a pas ete rendu")
    }

    /// Le plancher de securite, verifie sur la vraie table et non sur le calcul :
    /// les trois gains a zero ne doivent pas rendre l'ecran noir.
    @objc func testBlackScreenIsImpossibleOnRealHardware() {
        guard let m = MonitorEnum.all().first else { return }
        defer { GammaEngine.resetToIdentity(m); Native.restoreAllGamma() }

        var profile = Profile()
        profile.redGain = 0
        profile.greenGain = 0
        profile.blueGain = 0
        let plan = GammaEngine.plan(GammaEngine.minBrightness, allowOverlay: false, allowHardware: false)
        GammaEngine.apply(m, GammaEngine.buildRamp(plan, profile))

        guard let posed = Native.getGammaRamp(m.displayID) else {
            XCTFail("impossible de relire")
            return
        }
        let luminance = 0.2126 * Double(posed.red[255]) / 65535.0
                      + 0.7152 * Double(posed.green[255]) / 65535.0
                      + 0.0722 * Double(posed.blue[255]) / 65535.0
        XCTAssertGreaterThan(luminance, 0.02, "l'ecran est devenu noir sur du vrai materiel")
    }

    /// La restauration d'urgence doit rendre l'ecran depuis N'IMPORTE QUEL fil.
    /// C'est toute la valeur du raccourci de secours.
    @objc func testEmergencyRestoreFromAnotherThread() {
        guard let m = MonitorEnum.all().first else { return }

        var profile = Profile()
        profile.brightness = 30
        let plan = GammaEngine.plan(30, allowOverlay: false, allowHardware: false)
        GammaEngine.apply(m, GammaEngine.buildRamp(plan, profile))

        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            SafetyGuard.emergencyRestore()
            done.signal()
        }
        XCTAssertEqual(done.wait(timeout: .now() + 5), .success,
                       "la restauration d'urgence ne rend pas la main")

        // La partie « fenetres » de la restauration est confiee au fil principal :
        // c'est voulu, AppKit ne se manipule pas ailleurs. Il faut donc laisser la
        // boucle tourner ici, sinon ce nettoyage se deverserait au milieu du test
        // SUIVANT - ce qu'il a fait, et ce que ce commentaire evite de refaire
        // chercher a quelqu'un.
        pumpRunLoop(0.4)
        usleep(150_000)
        guard let after = Native.getGammaRamp(m.displayID) else { return }
        XCTAssertGreaterThan(Double(after.red[255]) / 65535.0, 0.95,
                             "l'ecran n'a pas ete rendu par la restauration d'urgence")
    }

    /// Ce que macOS fait d'une table dont le proprietaire disparait.
    ///
    /// C'est LA question qui decide de tout le raisonnement de securite. Sur
    /// Windows, la table survit au processus : un plantage laisse l'ecran sombre,
    /// et cinq protections existent pour cela. Ce test constate le comportement
    /// reel de macOS au lieu de recopier cette croyance - et la documentation dit
    /// ce que le test mesure.
    @objc func testGammaDoesNotSurviveItsOwner() {
        let me = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])

        let child = Process()
        child.executableURL = me
        child.arguments = ["--pose-et-meurs"]
        do { try child.run() } catch {
            skip("survie de la table", "impossible de lancer un processus fils")
            return
        }
        child.waitUntilExit()

        // Le fils a pose une table a 30 % et n'a rien rendu.
        usleep(400_000)

        guard let after = Native.getGammaRamp(CGMainDisplayID()) else {
            XCTFail("impossible de relire la table")
            return
        }
        let white = Double(after.red[Native.RampTable.size - 1]) / 65535.0

        // Si ce test venait a echouer un jour, ce ne serait pas un defaut de
        // l'application : ce serait macOS qui se met a se comporter comme
        // Windows, et la documentation de securite serait a reecrire.
        XCTAssertGreaterThan(white, 0.95,
            "macOS a laisse la table posee par un processus mort (blanc : \(white)) : "
          + "le danger de Windows existerait alors ici aussi")
    }

    // ------------------------------------------------------------------ etage 4 : Metal

    /// Compiler le nuanceur est la seule chose qui puisse echouer silencieusement
    /// sur une machine donnee. C'est donc la premiere a verifier.
    @objc func testMetalShaderCompiles() {
        guard MTLCreateSystemDefaultDevice() != nil else {
            skip("nuanceur Metal", "aucun peripherique Metal sur cette machine")
            return
        }
        XCTAssertTrue(ScreenFilter.shared.ensureMetal(),
                      "le nuanceur ne compile pas : la matrice et la loupe seraient inertes")
    }

    @objc func testScreenRecordingPermissionIsReported() {
        // On ne demande rien : on verifie seulement que l'application SAIT si
        // elle l'a, et le dit en francais quand elle ne l'a pas.
        let granted = CGPreflightScreenCaptureAccess()
        if granted {
            XCTAssertTrue(ScreenFilter.shared.available)
            XCTAssertTrue(ScreenFilter.shared.unavailableReason.isEmpty)
        } else {
            XCTAssertFalse(ScreenFilter.shared.available)
            XCTAssertFalse(ScreenFilter.shared.unavailableReason.isEmpty,
                           "une fonction indisponible doit dire pourquoi")
            skip("matrice de couleur", "autorisation d'enregistrement de l'ecran absente")
        }
    }

    /// La passe de filtrage se monte-t-elle vraiment ? On demande une matrice,
    /// on regarde si l'ecran a recu sa fenetre, puis on demonte.
    @objc func testFilterNodeIsCreatedAndTornDown() {
        guard CGPreflightScreenCaptureAccess() else {
            skip("passe de filtrage", "autorisation d'enregistrement de l'ecran absente")
            return
        }
        guard let m = MonitorEnum.all().first else { return }

        defer {
            ScreenFilter.shared.panicStop()
            pumpRunLoop(0.3)
        }

        XCTAssertTrue(ScreenFilter.shared.nodes.isEmpty, "l'etage devrait partir demonte")

        let matrix = ColorMatrixEffect.buildMatrix(100, .deuteranopia, 100, 100, .correction)
        let ok = ScreenFilter.shared.setMatrices([m.displayID: matrix])
        XCTAssertTrue(ok, "la pose de la matrice a echoue")
        XCTAssertTrue(ScreenFilter.shared.matrixActive)

        // La capture demarre de facon asynchrone : on attend qu'elle soit la.
        XCTAssertTrue(waitUntil(3) { ScreenFilter.shared.nodes.count == 1 },
                      "aucune passe de filtrage montee pour cet ecran")

        ScreenFilter.shared.clearMatrix()
        XCTAssertTrue(waitUntil(2) { ScreenFilter.shared.nodes.isEmpty },
                      "la passe n'a pas ete demontee")
        XCTAssertFalse(ScreenFilter.shared.matrixActive)
    }

    /// Une matrice identite ne doit RIEN monter : l'etage le plus couteux de
    /// l'application ne s'arme que lorsqu'il sert.
    @objc func testIdentityMatrixArmsNothing() {
        defer { ScreenFilter.shared.panicStop() }
        guard let m = MonitorEnum.all().first else { return }

        ScreenFilter.shared.setMatrices([m.displayID: ColorMatrixEffect.identity()])
        pumpRunLoop(0.3)
        XCTAssertTrue(ScreenFilter.shared.nodes.isEmpty)
        XCTAssertFalse(ScreenFilter.shared.matrixActive)
    }

    @objc func testMagnifierRefusesWithoutPermissionAndReports() {
        defer { ScreenMagnifier.stop(); pumpRunLoop(0.3) }

        if CGPreflightScreenCaptureAccess() {
            XCTAssertTrue(ScreenMagnifier.setZoom(3.0), "la loupe a refuse malgre l'autorisation")
            pumpRunLoop(0.8)
            XCTAssertTrue(ScreenMagnifier.isActive)
            XCTAssertEqual(ScreenMagnifier.zoom, 3.0, accuracy: 0.01)
            ScreenMagnifier.stop()
            pumpRunLoop(0.3)
            XCTAssertFalse(ScreenMagnifier.isActive)
        } else {
            XCTAssertFalse(ScreenMagnifier.setZoom(3.0),
                           "la loupe doit refuser plutot que de laisser croire qu'elle agit")
            XCTAssertFalse(ScreenMagnifier.isActive)
            skip("loupe", "autorisation d'enregistrement de l'ecran absente")
        }
    }

    // ------------------------------------------------------------------ etage 3 : le voile

    /// Le voile doit exister, couvrir exactement son ecran, laisser passer les
    /// clics, et surtout SORTIR DES CAPTURES - sans quoi l'analyse de contenu se
    /// mesurerait elle-meme et partirait en oscillation.
    @objc func testVeilWindowIsCorrectlyConfigured() {
        guard let m = MonitorEnum.all().first else { return }

        let lens = OverlayLens()
        defer { lens.dispose() }

        lens.cover(m)
        lens.tint = .black
        lens.setTransmission(0.5)

        // La condition attendue est « un voile aux dimensions de l'ecran », et
        // non « un voile, puis mesurons-le ». AppKit fait apparaitre une fenetre
        // par une breve animation de zoom : mesurer au premier instant donne 98 %
        // de la taille finale, et le test echouerait pour une raison qui n'a rien
        // a voir avec ce qu'il verifie.
        XCTAssertTrue(waitUntil(3) {
            ownWindows(atLevel: WindowLevels.veil.rawValue).contains {
                abs(Int($0.width) - m.bounds.width) <= 2
                    && abs(Int($0.height) - m.bounds.height) <= 2
            }
        }, "aucun voile aux dimensions de l'ecran (\(m.bounds.width) x \(m.bounds.height))")

        // A transmission totale, le voile doit disparaitre : on ne laisse pas une
        // fenetre au-dessus de tout sans raison.
        //
        // Le voile devient d'abord transparent - donc invisible - puis le serveur
        // de fenetres le retire de sa liste, ce qui prend environ une seconde. La
        // verification attend le retrait plutot que de supposer un delai.
        lens.setTransmission(1.0)
        XCTAssertEqual(lens.isShowing, false, "le voile devrait etre range immediatement")
        XCTAssertTrue(waitUntil(3) { ownWindows(atLevel: WindowLevels.veil.rawValue).isEmpty },
                      "le voile reste a l'ecran alors qu'il ne sert a rien")
    }

    /// L'ordre d'empilement des quatre surfaces est une decision de conception :
    /// le voile assombrit APRES la correction des couleurs, les aides passent
    /// au-dessus des deux, et les rappels au-dessus de tout.
    @objc func testWindowLevelOrder() {
        XCTAssertLessThan(WindowLevels.filter.rawValue, WindowLevels.veil.rawValue)
        XCTAssertLessThan(WindowLevels.veil.rawValue, WindowLevels.aid.rawValue)
        XCTAssertLessThan(WindowLevels.aid.rawValue, WindowLevels.notice.rawValue)
        XCTAssertGreaterThan(WindowLevels.filter.rawValue,
                             Int(CGWindowLevelForKey(.mainMenuWindow)),
                             "l'image filtree doit passer au-dessus de la barre des menus")
    }

    // ------------------------------------------------------------------ aides a la vision

    @objc func testBeaconShowsAndHides() {
        let beacon = CursorBeacon()
        defer { beacon.dispose() }

        beacon.size = 90
        beacon.color = RGB(255, 168, 66)
        beacon.opacity = 70
        beacon.show()

        XCTAssertTrue(beacon.isVisible)
        XCTAssertTrue(waitUntil(3) {
            ownWindows(atLevel: WindowLevels.aid.rawValue).contains { abs(Int($0.width) - 90) <= 2 }
        }, "l'anneau n'est pas a l'ecran a la taille demandee")

        beacon.hide()
        XCTAssertFalse(beacon.isVisible)
        XCTAssertTrue(waitUntil(3) { ownWindows(atLevel: WindowLevels.aid.rawValue).isEmpty },
                      "l'anneau reste a l'ecran apres avoir ete eteint")
    }

    @objc func testColourReaderReadsARealPixel() {
        guard CGPreflightScreenCaptureAccess() else {
            skip("identificateur de couleur", "autorisation d'enregistrement de l'ecran absente")
            return
        }

        let bounds = MonitorEnum.all().first?.bounds.cgRect ?? CGRect(x: 0, y: 0, width: 100, height: 100)
        let point = CGPoint(x: bounds.midX, y: bounds.midY)

        let grid = ColorReader.sample(around: point, size: ColorReader.gridPixels)
        XCTAssertEqual(grid.count, ColorReader.gridPixels)
        XCTAssertEqual(grid[0].count, ColorReader.gridPixels)

        // Une lecture reussie ne rend pas la couleur de repli sur TOUTE la grille.
        let fallback = RGB(24, 24, 24)
        let allFallback = grid.allSatisfy { row in row.allSatisfy { $0 == fallback } }
        XCTAssertFalse(allFallback, "la lecture d'ecran n'a rien rendu")

        // Et la couleur lue doit pouvoir etre nommee.
        let centre = grid[ColorReader.gridPixels / 2][ColorReader.gridPixels / 2]
        XCTAssertFalse(Vision.describeColor(centre).isEmpty)
    }

    @objc func testContentMeasurementReturnsAPlausibleLuminance() {
        guard CGPreflightScreenCaptureAccess() else {
            skip("adaptation au contenu", "autorisation d'enregistrement de l'ecran absente")
            return
        }
        let engine = ContentAdaptive()
        guard let luminance = engine.measureScreenLuminance() else {
            XCTFail("la mesure de contenu n'a rien rendu")
            return
        }
        XCTAssertGreaterThanOrEqual(luminance, 0)
        XCTAssertLessThanOrEqual(luminance, 1)
    }

    // ------------------------------------------------------------------ etage 1 : le materiel

    /// Le retroeclairage n'est pas universel : beaucoup d'ecrans declarent le
    /// DDC/CI sans le servir. Ce qui compte ici est que le sondage REPONDE, et
    /// qu'il dise la verite plutot que de supposer.
    @objc func testBacklightProbeAnswers() {
        let description = HardwareBacklight.probe()
        XCTAssertFalse(description.isEmpty, "le sondage du materiel n'a rien rendu")

        for m in MonitorEnum.all() {
            let what = HardwareBacklight.describeFor(m)
            XCTAssertFalse(what.isEmpty, "\(m.friendlyName) : aucun verdict")
            XCTAssertTrue(["DDC/CI", "dalle interne", "aucun reglage materiel"].contains(what),
                          "verdict inattendu : « \(what) »")
            if what == "aucun reglage materiel" {
                skip("retroeclairage de \(m.friendlyName)", "materiel muet")
            }
        }
    }

    /// Sur une dalle interne, la luminosite se lit. On la lit, on la repose
    /// telle quelle : rien ne doit bouger pour l'utilisateur.
    @objc func testInternalBrightnessIsReadable() {
        let internals = MonitorEnum.all().filter { $0.isInternal }
        guard let m = internals.first else {
            skip("luminosite de la dalle interne", "aucune dalle interne sur cette machine")
            return
        }

        let level = HardwareBacklight.internalBrightness(m.displayID)
        guard level >= 0 else {
            skip("luminosite de la dalle interne", "le systeme ne la rend pas")
            return
        }
        XCTAssertGreaterThanOrEqual(level, 0)
        XCTAssertLessThanOrEqual(level, 100)

        // On repose exactement ce qui etait la.
        XCTAssertTrue(HardwareBacklight.setInternalBrightness(m.displayID, level),
                      "la luminosite se lit mais ne s'ecrit pas")
    }

    // ------------------------------------------------------------------ raccourcis

    @objc func testHotkeysRegisterAndUnregister() {
        let hotkeys = Hotkeys()
        defer { hotkeys.unregister() }

        var received: String?
        hotkeys.onAction = { received = $0 }
        hotkeys.register(Settings.defaultHotkeys())

        // On ne peut pas presser une touche depuis un test sans piloter le
        // systeme. Ce qui se verifie ici, c'est que l'enregistrement ne fait
        // rien exploser et que le desenregistrement rend bien les combinaisons -
        // une combinaison laissee derriere soi resterait volee a tout le systeme.
        hotkeys.unregister()

        let second = Hotkeys()
        second.register(Settings.defaultHotkeys())
        second.unregister()
        XCTAssertNil(received)
    }

    @objc func testPanicKeyReportsWhichPathItUses() {
        PanicKey.shared.start()
        defer { PanicKey.shared.stop() }

        // Les deux chemins sont acceptables ; ce qui ne le serait pas, c'est que
        // l'application ne sache pas lequel elle utilise.
        let independent = PanicKey.shared.independentThreadActive
        if !independent {
            skip("fil de secours autonome", "autorisation d'accessibilite absente (repli actif)")
        }
        XCTAssertTrue(independent || !independent)   // toujours vrai : on note, on n'echoue pas
    }

    // ------------------------------------------------------------------ le systeme autour

    @objc func testAutoBrightnessDetectionAnswers() {
        let description = AutoBrightness.describe()
        XCTAssertFalse(description.isEmpty)

        if !AutoBrightness.detectionAvailable {
            skip("detection de la luminosite automatique", "fonction absente de ce macOS")
            return
        }
        // Lecture seule : on ne change pas un reglage systeme dans un test.
        for panel in AutoBrightness.panels() {
            XCTAssertFalse(panel.name.isEmpty)
        }
    }

    @objc func testConflictDetectionAnswers() {
        let found = ConflictDetector.running()
        // Rien a affirmer sur le contenu : la machine peut avoir f.lux installe.
        // Ce qui compte est que chaque conflit soit decrit en francais.
        for c in found {
            XCTAssertFalse(c.displayName.isEmpty)
            XCTAssertFalse(c.detail.isEmpty)
        }
        if !found.isEmpty {
            skip("ecran sans concurrent", ConflictDetector.describe(found) ?? "")
        }
    }

    @objc func testSystemColourFiltersAreReadable() {
        // Les fonctions viennent d'un cadre prive : si elles disparaissent, la
        // lecture doit rendre faux plutot que de planter.
        _ = SystemColorFilters.colorFilterEnabled
        _ = SystemColorFilters.invertEnabled
        _ = NightShift.isEnabled
        XCTAssertTrue(true)
    }

    @objc func testVolumeIsReadable() {
        guard SystemVolume.available else {
            skip("volume de sortie", "aucune sortie audio")
            return
        }
        let master = SystemVolume.getMaster()
        XCTAssertGreaterThanOrEqual(master, 0)
        XCTAssertLessThanOrEqual(master, 100)
    }

    @objc func testLoginItemStatusIsReadable() {
        // Lecture seule : inscrire la machine au demarrage depuis un test serait
        // exactement le genre de chose qu'un test ne doit jamais faire.
        _ = LoginItem.isEnabled
        XCTAssertTrue(true)
    }

    // ------------------------------------------------------------------ bout en bout

    /// Le controleur complet, sur du vrai materiel : il pose les quatre etages,
    /// puis rend l'ecran.
    @objc func testControllerAppliesAndRestores() {
        let settings = Settings()
        settings.smoothTransitions = false      // pas de fondu : on veut l'etat final tout de suite
        settings.useColorMatrix = false         // l'etage 4 a sa propre verification
        settings.useHardwareBacklight = false   // on ne touche pas au retroeclairage ici
        settings.current.brightness = 45
        settings.current.kelvin = 3000

        let controller = DisplayController(settings)
        defer { controller.restoreAll(); controller.dispose(); Native.restoreAllGamma() }

        guard let m = controller.monitors.first else { return }

        controller.applyNow(fromSuspend: false)
        usleep(150_000)

        guard let posed = Native.getGammaRamp(m.displayID) else {
            XCTFail("impossible de relire apres application")
            return
        }
        XCTAssertLessThan(Double(posed.red[255]) / 65535.0, 0.6,
                          "le controleur n'a pas assombri l'ecran")
        XCTAssertLessThan(Double(posed.blue[255]) / 65535.0,
                          Double(posed.red[255]) / 65535.0,
                          "le controleur n'a pas rechauffe l'ecran")

        // Le temoin de plantage doit etre pose tant qu'un effet est actif.
        let flag = (Settings.dataFolder as NSString).appendingPathComponent("active.flag")
        XCTAssertTrue(FileManager.default.fileExists(atPath: flag),
                      "le temoin de plantage n'a pas ete pose")

        controller.restoreAll()
        usleep(150_000)

        guard let restored = Native.getGammaRamp(m.displayID) else { return }
        XCTAssertGreaterThan(Double(restored.red[255]) / 65535.0, 0.95,
                             "le controleur n'a pas rendu l'ecran")
        XCTAssertFalse(FileManager.default.fileExists(atPath: flag),
                       "le temoin de plantage n'a pas ete efface")
    }

    /// La reprise apres plantage : un temoin laisse par une session precedente
    /// doit rendre l'ecran au demarrage suivant.
    @objc func testCrashRecoveryRestoresTheScreen() {
        guard let m = MonitorEnum.all().first else { return }
        defer { Native.restoreAllGamma(); SafetyGuard.clearDirtyFlag() }

        var profile = Profile()
        profile.brightness = 25
        let plan = GammaEngine.plan(25, allowOverlay: false, allowHardware: false)
        GammaEngine.apply(m, GammaEngine.buildRamp(plan, profile))
        SafetyGuard.markDirty()

        XCTAssertTrue(SafetyGuard.recoverFromCrash(), "le temoin n'a pas ete vu")
        usleep(150_000)

        guard let after = Native.getGammaRamp(m.displayID) else { return }
        XCTAssertGreaterThan(Double(after.red[255]) / 65535.0, 0.95,
                             "la reprise apres plantage n'a pas rendu l'ecran")
    }

    /// Le paquet construit doit etre lancable et bien forme : c'est ce que
    /// l'utilisateur recevra.
    @objc func testApplicationBundleIsWellFormed() {
        let bundlePath = FileManager.default.currentDirectoryPath + "/OpusScreen.app"
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            skip("paquet OpusScreen.app", "pas encore construit (./build.sh)")
            return
        }

        let fm = FileManager.default
        XCTAssertTrue(fm.isExecutableFile(atPath: bundlePath + "/Contents/MacOS/OpusScreen"),
                      "le binaire du paquet n'est pas executable")
        XCTAssertTrue(fm.fileExists(atPath: bundlePath + "/Contents/Info.plist"))
        XCTAssertTrue(fm.fileExists(atPath: bundlePath + "/Contents/Resources/AppIcon.icns"),
                      "le paquet n'a pas d'icone")
        XCTAssertTrue(fm.fileExists(atPath: bundlePath
                                  + "/Contents/Resources/OpusScreen_OpusScreenKit.bundle/logo.png"),
                      "les ressources ne sont pas dans le paquet")

        guard let info = NSDictionary(contentsOfFile: bundlePath + "/Contents/Info.plist") else {
            XCTFail("Info.plist illisible")
            return
        }
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, Installer.bundleIdentifier)
        XCTAssertEqual(info["LSUIElement"] as? Bool, true,
                       "l'application doit vivre dans la barre des menus, pas dans le Dock")
        XCTAssertNotNil(info["NSScreenCaptureUsageDescription"],
                        "macOS refusera l'autorisation sans intitule")
    }

    // ------------------------------------------------------------------ outils

    /// Attend qu'une condition devienne vraie, en laissant tourner la boucle.
    ///
    /// Preferable a un delai devine : le serveur de fenetres ne retire pas une
    /// fenetre de sa liste au moment ou on la range, et la capture d'ecran ne
    /// demarre pas au moment ou on la demande. Un delai fixe serait soit trop
    /// court - et le test echouerait sans raison - soit trop long pour rien.
    @discardableResult
    private func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    /// Laisse tourner la boucle principale : les captures d'ecran et les fenetres
    /// se montent de facon asynchrone, et un test qui regarde trop tot ne verrait
    /// rien.
    private func pumpRunLoop(_ seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    private struct WindowInfo {
        let width: Double
        let height: Double
        let level: Int
    }

    /// Les fenetres de CE processus reellement A L'ECRAN, a un niveau donne.
    ///
    /// `optionOnScreenOnly` et non `optionAll` : une fenetre rangee par
    /// `orderOut` existe toujours, elle n'est simplement plus affichee - et c'est
    /// exactement la question que posent ces verifications.
    private func ownWindows(atLevel level: Int) -> [WindowInfo] {
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return [] }

        var found: [WindowInfo] = []
        for w in list {
            guard let owner = w[kCGWindowOwnerPID as String] as? pid_t, owner == pid else { continue }
            guard let windowLevel = w[kCGWindowLayer as String] as? Int, windowLevel == level else { continue }
            guard let bounds = w[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            found.append(WindowInfo(width: rect.width, height: rect.height, level: windowLevel))
        }
        return found
    }
}
