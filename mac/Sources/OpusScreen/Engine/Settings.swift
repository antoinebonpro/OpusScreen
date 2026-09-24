import Foundation

/// Ce qui pilote la temperature quand l'automatisme est actif.
public enum ScheduleMode: Int {
    case manual = 0     // rien d'automatique
    case solar          // lever et coucher du soleil calcules sur place
    case fixedHours     // horaires saisis par l'utilisateur
}

/// Ce qui doit ceder quand une fenetre passe en plein ecran.
///
/// Les quatre etages ne genent pas de la meme facon : le voile est une fenetre
/// posee par-dessus l'ecran, que le plein ecran met mal a l'aise ; la table de
/// couleurs, elle, est appliquee par la carte graphique en sortie et traverse jeux
/// et videos sans dommage. C'est aussi elle qui porte tout le boost au-dela de
/// 100 % - le suspendre revenait a retirer la luminosite au moment ou elle sert
/// le plus.
public enum FullscreenSuspend: Int {
    case never = 0        // rien ne change en plein ecran
    case overlayOnly      // seul le voile est retire ; couleur et boost restent
    case everything       // tous les etages reviennent a la normale
}

/// Reglages propres a un ecran, retrouves par identifiant materiel.
public final class MonitorSettings {
    public var stableId = ""
    public var friendlyName = ""
    public var enabled = true           // faux = cet ecran n'est pas touche
    public var independent = false      // vrai = utilise son propre profil
    public var own = Profile()
    public var brightnessOffset: Double = 0   // decalage applique au profil global, en points
    public var blackout = false         // ecran eteint (equivalent du BlackOut de Lunar)

    /// Vrai = cet ecran ne suit plus du tout les reglages generaux.
    ///
    /// A distinguer du profil independant, qui donne seulement a l'ecran ses
    /// propres valeurs : celles-ci sont rafraichies des qu'un mode est choisi,
    /// parce qu'un mode est une commande pour toute la machine. Le verrou est
    /// l'exception explicite - l'ecran calibre que rien ne doit bouger.
    public var locked = false

    public init() {}

    public func serialize() -> String {
        [
            MonitorSettings.esc(stableId),
            MonitorSettings.esc(friendlyName),
            enabled ? "1" : "0",
            independent ? "1" : "0",
            Profile.num(brightnessOffset),
            blackout ? "1" : "0",
            MonitorSettings.esc(own.serialize()),
            // Champ ajoute apres coup, donc place en DERNIER : un fichier ecrit par
            // une version anterieure se relit tel quel, verrou a faux.
            locked ? "1" : "0",
        ].joined(separator: "~")
    }

    public static func deserialize(_ s: String) -> MonitorSettings {
        let m = MonitorSettings()
        let f = s.components(separatedBy: "~")
        if f.count > 0 { m.stableId = unesc(f[0]) }
        if f.count > 1 { m.friendlyName = unesc(f[1]) }
        if f.count > 2 { m.enabled = f[2] == "1" }
        if f.count > 3 { m.independent = f[3] == "1" }
        if f.count > 4 { m.brightnessOffset = Profile.parseDouble(f[4]) ?? 0 }
        if f.count > 5 { m.blackout = f[5] == "1" }
        if f.count > 6 { m.own = Profile.deserialize(unesc(f[6])) }
        if f.count > 7 { m.locked = f[7] == "1" }
        return m
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "~", with: "%7E").replacingOccurrences(of: "|", with: "%7C")
    }
    private static func unesc(_ s: String) -> String {
        s.replacingOccurrences(of: "%7E", with: "~").replacingOccurrences(of: "%7C", with: "|")
    }
}

/// Un raccourci global reconfigurable.
///
/// Les codes stockes sont ceux de Windows - modificateurs 1/2/4/8 et codes de
/// touche virtuels. Ce n'est pas de l'archeologie : c'est ce qui permet a un
/// fichier de configuration d'aller d'une machine a l'autre sans perdre les
/// raccourcis. La traduction vers les codes Carbon de macOS se fait au moment de
/// poser le raccourci, dans `Hotkeys`.
public final class HotkeyBinding {
    public var action = ""
    public var modifiers: UInt32 = 0
    public var key: UInt32 = 0
    public var enabled = true

    public init() {}
    public init(_ action: String, _ mods: UInt32, _ key: UInt32) {
        self.action = action; self.modifiers = mods; self.key = key
    }

    public static let modAlt: UInt32 = 0x1      // Option sur macOS
    public static let modControl: UInt32 = 0x2  // Control
    public static let modShift: UInt32 = 0x4    // Maj
    public static let modWin: UInt32 = 0x8      // Commande sur macOS

    public func serialize() -> String {
        "\(action)>\(modifiers)>\(key)>\(enabled ? "1" : "0")"
    }

    public static func deserialize(_ s: String) -> HotkeyBinding {
        let h = HotkeyBinding()
        let f = s.components(separatedBy: ">")
        if f.count > 0 { h.action = f[0] }
        if f.count > 1 { h.modifiers = UInt32(f[1]) ?? 0 }
        if f.count > 2 { h.key = UInt32(f[2]) ?? 0 }
        if f.count > 3 { h.enabled = f[3] == "1" }
        return h
    }

    /// Le raccourci tel qu'un utilisateur de Mac le lit : les symboles du clavier,
    /// dans l'ordre ou Apple les affiche.
    public func describe() -> String {
        var parts: [String] = []
        if (modifiers & HotkeyBinding.modControl) != 0 { parts.append("⌃") }
        if (modifiers & HotkeyBinding.modAlt) != 0 { parts.append("⌥") }
        if (modifiers & HotkeyBinding.modShift) != 0 { parts.append("⇧") }
        if (modifiers & HotkeyBinding.modWin) != 0 { parts.append("⌘") }
        parts.append(HotkeyBinding.keyName(key))
        return parts.joined()
    }

    public static func keyName(_ vk: UInt32) -> String {
        switch vk {
        case 0x26: return "↑"
        case 0x28: return "↓"
        case 0x25: return "←"
        case 0x27: return "→"
        case 0x20: return "Espace"
        case 0x2D: return "Inser"
        case 0x2E: return "⌦"
        case 0x21: return "⇞"
        case 0x22: return "⇟"
        case 0x24: return "↖"
        case 0x23: return "↘"
        case 0x1B: return "⎋"
        case 0x0D: return "↩"
        default:
            if vk >= 0x30 && vk <= 0x39 { return String(UnicodeScalar(vk)!) }
            if vk >= 0x41 && vk <= 0x5A { return String(UnicodeScalar(vk)!) }
            if vk >= 0x70 && vk <= 0x7B { return "F\(vk - 0x6F)" }
            return String(format: "0x%02X", vk)
        }
    }
}

/// Tous les reglages persistants, en texte clef=valeur.
///
/// Le format est rigoureusement celui de la version Windows. Un fichier exporte
/// depuis un PC s'importe ici tel quel, et inversement : quelqu'un qui change de
/// machine - ou qui travaille sur les deux - ne recommence pas ses reglages. C'est
/// aussi un fichier qui se lit, se sauvegarde et se supprime a la main.
public final class Settings {

    /// Dossier de remplacement, pour les tests : ils modifient tout, et ne doivent
    /// jamais ecrire dans la configuration reelle de l'utilisateur.
    public static var dataFolderOverride: String?

    public static var dataFolder: String {
        if let o = dataFolderOverride, !o.isEmpty { return o }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("OpusScreen").path
    }

    private static var filePath: String {
        (dataFolder as NSString).appendingPathComponent("settings.ini")
    }

    /// Vrai si aucun fichier de reglages n'existait au chargement.
    /// Sert a ouvrir la fenetre au tout premier lancement : demarrer discretement
    /// est le bon comportement ensuite, mais la premiere fois cela donne
    /// l'impression que rien ne s'est passe.
    public private(set) var isFirstRun = false

    // ---------------- etat visuel courant ----------------
    public var current = Profile()
    public var activeModeName = "Normal"
    public var customProfiles: [Profile] = []

    /// Reglages de daltonisme enregistres par l'utilisateur, nommes par lui.
    public var visionPresets: [VisionPreset] = []

    /// Resume du dernier test guide, affiche dans l'onglet Daltonisme.
    public var lastExamSummary = ""

    // ---------------- automatisme horaire ----------------
    public var schedule: ScheduleMode = .manual
    public var presetName = "Couleurs recommandees"
    public var latitude: Double = 48.8566
    public var longitude: Double = 2.3522
    public var bedtimeHour: Double = 23.0
    public var wakeHour: Double = 7.0
    public var fixedDayHour: Double = 8.0
    public var fixedNightHour: Double = 19.0
    public var transitionMinutes: Int = 60
    /// Fait aussi varier la luminosite avec l'heure, pas seulement la couleur.
    public var scheduleAffectsBrightness = false
    public var dayBrightness: Double = 100
    public var nightBrightness: Double = 70

    // ---------------- luminosite adaptative au contenu ----------------
    public var adaptiveEnabled = false
    public var adaptiveMin: Double = 40
    public var adaptiveMax: Double = 110
    public var adaptiveReactivity: Double = 3
    public var adaptiveIntervalMs: Int = 1200

    // ---------------- ecrans ----------------
    public var monitors: [MonitorSettings] = []
    public var linkMonitors = true

    /// Ecran dont les reglages de couleur pilotent la matrice, quand elle est
    /// partagee. Vide = ecran principal.
    ///
    /// Sur Windows, l'API n'exposait qu'un seul effet pour tout le bureau et ce
    /// choix etait une contrainte. Ici la matrice est reconstruite ecran par ecran :
    /// le reglage reste, mais il ne sert qu'aux personnes qui PREFERENT un filtre
    /// unique - et il est explique comme tel dans la page Ecrans.
    public var matrixSourceId = ""

    /// Vrai = un seul filtre pour tous les ecrans, celui de l'ecran de reference.
    /// Faux = chaque ecran applique le sien. Le defaut suit les ecrans lies.
    public var matrixPerScreen = false

    // ---------------- aides a la vision ----------------
    /// Etiquette qui nomme la couleur sous le pointeur.
    public var colorReaderEnabled = false

    /// Anneau de reperage autour du pointeur.
    public var beaconEnabled = false
    public var beaconSize: Int = 72
    public var beaconOpacity: Int = 70
    public var beaconColor = RGB(255, 168, 66)

    /// Loupe plein ecran. Le facteur est conserve meme eteinte.
    public var magnifierEnabled = false
    public var magnifierZoom: Double = 2.0

    /// Rappel de clignement, contre la secheresse oculaire.
    public var blinkReminders = false
    public var blinkIntervalMinutes: Int = 5

    // ---------------- regles par application ----------------
    public var appRulesEnabled = false
    public var appRules: [AppRule] = []
    public var onFullscreen: FullscreenSuspend = .overlayOnly
    public var disableOnBattery = false

    // ---------------- pauses oculaires ----------------
    public var breaksEnabled = false
    public var breakIntervalMinutes: Int = 20
    public var breakDurationSeconds: Int = 20
    public var breakDim = false
    public var breakSound = true

    // ---------------- etages autorises ----------------
    public var useHardwareBacklight = true
    public var useOverlay = true
    public var useColorMatrix = true
    public var smoothTransitions = true
    public var transitionSpeedMs: Int = 400

    // ---------------- systeme ----------------
    public var startWithSystem = false
    public var startMinimized = true
    public var hotkeysEnabled = true
    public var trayWheelControl = true
    public var skipDarkConfirm = false
    public var ignoreConflicts = false
    public var warnedAboutClamp = false
    public var showTrayPercentage = true

    /// Icone visible dans le Dock, en plus de la barre des menus.
    ///
    /// Faux par defaut : l'application n'a pas de fenetre permanente, et une icone
    /// de Dock qui ne mene nulle part encombre pour rien. Certaines personnes
    /// preferent pourtant l'avoir - notamment pour la lancer au clavier.
    public var showInDock = false

    // ---------------- mises a jour ----------------
    /// Demande une fois par jour a GitHub le numero de la derniere version. Active
    /// par defaut : c'est ce qui garantit qu'on ne reste pas sur une version
    /// corrigee depuis longtemps sans le savoir.
    public var checkUpdates = true
    /// Derniere verification reussie, en temps universel.
    public var lastUpdateCheck = Date.distantPast

    /// Peuple des l'instanciation, et non au chargement : une remise a zero ou un
    /// import partiel laisserait sinon l'utilisateur sans aucun raccourci.
    public var hotkeys: [HotkeyBinding] = Settings.defaultHotkeys()

    /// Vrai des qu'un raccourci a ete lu depuis un fichier.
    private var hotkeysFromFile = false

    /// Vrai des que la cle recente du plein ecran a ete lue.
    private var fullscreenFromFile = false

    public init() {}

    // ------------------------------------------------------------------ ecrans

    public func forMonitor(_ m: MonitorInfo) -> MonitorSettings {
        for ms in monitors where ms.stableId == m.stableId { return ms }

        let created = MonitorSettings()
        created.stableId = m.stableId
        created.friendlyName = m.friendlyName
        monitors.append(created)
        return created
    }

    /// Profil effectif pour un ecran, une fois les reglages propres pris en compte.
    public func effectiveFor(_ m: MonitorInfo) -> Profile {
        let ms = forMonitor(m)

        // Ecrans lies = profil independant ignore. Il etait applique quand meme :
        // un ecran regle a part une fois restait a part pour toujours, meme apres
        // avoir coche « Lier tous les ecrans », et le reglage general ne
        // l'atteignait plus. Le profil reste memorise pour le jour ou l'on delie.
        //
        // Le verrou, lui, passe avant la liaison : il est demande ecran par ecran
        // et pour une raison precise - un ecran calibre - qu'une case cochee
        // ailleurs n'a pas a defaire.
        let independent = ms.locked || (ms.independent && !linkMonitors)
        var p = independent ? ms.own.clone() : current.clone()
        if !independent && abs(ms.brightnessOffset) > 0.01 {
            p.brightness = SafetyGuard.clampBrightness(p.brightness + ms.brightnessOffset)
        }
        return p
    }

    /// Etat general au moment de la derniere repercussion sur les ecrans.
    /// Nul tant qu'aucune n'a eu lieu : le chargement du fichier ne doit rien
    /// repercuter du tout, sinon les profils propres memorises seraient ecrases
    /// par le profil general au premier demarrage venu.
    private var lastGeneral: Profile?

    /// Prend acte de l'etat general courant sans rien repercuter. Appelee apres
    /// un chargement ou un import : ce qui vient du fichier n'est pas un geste
    /// de l'utilisateur.
    public func markGeneralAsPushed() {
        lastGeneral = current.clone()
    }

    /// Repercute sur chaque ecran qui le suit ce qui vient de changer dans le
    /// reglage general.
    ///
    /// Seuls les champs REELLEMENT modifies depuis la derniere fois sont recopies.
    /// C'est ce qui permet aux deux gestes de coexister : descendre la luminosite
    /// generale ne remet pas la temperature qu'on avait reglee a part sur cet
    /// ecran, et la luminosite adaptative - qui ne touche qu'un champ, plusieurs
    /// fois par minute - n'efface plus rien au passage.
    ///
    /// Un ecran verrouille est saute : c'est la seule facon de ne jamais suivre.
    @discardableResult
    public func syncFollowingScreens() -> Bool {
        guard let before = lastGeneral else { markGeneralAsPushed(); return false }

        var touched = false
        for ms in monitors {
            if ms.locked { continue }
            if ms.own.copyChanged(before, current) { touched = true }
        }
        markGeneralAsPushed()
        return touched
    }

    /// Ecrans que le reglage general n'atteint pas, et pourquoi.
    public func screensNotFollowing(_ list: [MonitorInfo]) -> [String] {
        var reasons: [String] = []
        for m in list {
            let ms = forMonitor(m)
            if ms.locked { reasons.append(m.label + " : profil verrouille") }
            else if !ms.enabled { reasons.append(m.label + " : effets desactives") }
            else if ms.blackout { reasons.append(m.label + " : ecran eteint") }
        }
        return reasons
    }

    // ------------------------------------------------------------------ raccourcis

    public static func defaultHotkeys() -> [HotkeyBinding] {
        let CTRL = HotkeyBinding.modControl
        let ALT = HotkeyBinding.modAlt
        let SHIFT = HotkeyBinding.modShift

        var l: [HotkeyBinding] = []
        l.append(HotkeyBinding("brightness.up", CTRL | ALT, 0x26))       // fleche haut
        l.append(HotkeyBinding("brightness.down", CTRL | ALT, 0x28))     // fleche bas
        l.append(HotkeyBinding("temp.warmer", CTRL | ALT, 0x25))         // fleche gauche
        l.append(HotkeyBinding("temp.cooler", CTRL | ALT, 0x27))         // fleche droite
        l.append(HotkeyBinding("reset", CTRL | ALT | SHIFT, 0x52))       // R
        l.append(HotkeyBinding("pause.toggle", CTRL | ALT, 0x50))        // P
        l.append(HotkeyBinding("mode.next", CTRL | ALT, 0x4D))           // M
        l.append(HotkeyBinding("adaptive.toggle", CTRL | ALT, 0x41))     // A
        l.append(HotkeyBinding("break.now", CTRL | ALT, 0x42))           // B
        l.append(HotkeyBinding("panel.show", CTRL | ALT, 0x4C))          // L
        // --- accessibilite ---
        l.append(HotkeyBinding("vision.toggle", CTRL | ALT, 0x44))       // D, daltonisme
        l.append(HotkeyBinding("color.reader", CTRL | ALT, 0x43))        // C, couleur
        l.append(HotkeyBinding("color.copy", CTRL | ALT | SHIFT, 0x43))  // C
        l.append(HotkeyBinding("magnifier.toggle", CTRL | ALT, 0x5A))    // Z, zoom
        l.append(HotkeyBinding("beacon.toggle", CTRL | ALT, 0x48))       // H, halo
        return l
    }

    /// Ajoute les actions apparues apres l'ecriture du fichier de reglages.
    ///
    /// Sans cela, une nouvelle fonction pilotable au clavier resterait invisible
    /// pour tous ceux qui utilisent deja l'application : leur fichier ne contient
    /// que les actions de l'epoque, et il REMPLACE les valeurs par defaut au lieu
    /// de s'y ajouter. Une combinaison deja prise n'est jamais volee - l'action
    /// est alors ajoutee desactivee, prete a etre reglee dans la page Raccourcis.
    private func mergeMissingHotkeys() {
        for def in Settings.defaultHotkeys() {
            if hotkeys.contains(where: { $0.action == def.action }) { continue }

            let taken = hotkeys.contains { $0.enabled && $0.key == def.key && $0.modifiers == def.modifiers }
            let added = HotkeyBinding(def.action, def.modifiers, def.key)
            added.enabled = !taken
            hotkeys.append(added)
        }
    }

    public static func actionLabel(_ action: String) -> String {
        switch action {
        case "brightness.up": return "Luminosite +"
        case "brightness.down": return "Luminosite -"
        case "temp.warmer": return "Couleur plus chaude"
        case "temp.cooler": return "Couleur plus froide"
        case "reset": return "Tout reinitialiser (secours)"
        case "pause.toggle": return "Suspendre / reprendre"
        case "mode.next": return "Mode suivant"
        case "adaptive.toggle": return "Adaptatif on / off"
        case "break.now": return "Pause pour les yeux"
        case "panel.show": return "Ouvrir les reglages"
        case "vision.toggle": return "Correction daltonisme on / off"
        case "color.reader": return "Identifier la couleur (etiquette)"
        case "color.copy": return "Copier la couleur sous le pointeur"
        case "magnifier.toggle": return "Loupe plein ecran on / off"
        case "beacon.toggle": return "Anneau autour du pointeur"
        default: return action
        }
    }

    // ------------------------------------------------------------------ E/S

    public static func load() -> Settings {
        let s = Settings()
        s.isFirstRun = !FileManager.default.fileExists(atPath: filePath)

        if let text = try? String(contentsOfFile: filePath, encoding: .utf8) {
            s.applyText(text)
        }

        if s.hotkeys.isEmpty { s.hotkeys = defaultHotkeys() }
        s.mergeMissingHotkeys()
        s.current.clampAll()
        // Ce qui sort du fichier est un etat deja etabli, pas un geste : il ne doit
        // rien repercuter sur les profils propres des ecrans.
        s.markGeneralAsPushed()
        return s
    }

    private func applyText(_ text: String) {
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "="), eq != line.startIndex else { continue }
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            applyPair(key, val)
        }
    }

    private func applyPair(_ key: String, _ val: String) {
        func d(_ fallback: Double) -> Double { Profile.parseDouble(val) ?? fallback }
        func i(_ fallback: Int) -> Int { Int(val) ?? fallback }
        let on = (val == "1")

        switch key {
        case "current": current = Profile.deserialize(val)
        case "activeMode": activeModeName = val
        case "customProfile": customProfiles.append(Profile.deserialize(val))
        case "visionPreset": visionPresets.append(VisionPreset.deserialize(val))
        case "lastExam": lastExamSummary = val

        case "schedule": schedule = ScheduleMode(rawValue: i(0)) ?? .manual
        case "preset": presetName = val
        case "latitude": latitude = d(latitude)
        case "longitude": longitude = d(longitude)
        case "bedtime": bedtimeHour = d(bedtimeHour)
        case "wake": wakeHour = d(wakeHour)
        case "fixedDay": fixedDayHour = d(fixedDayHour)
        case "fixedNight": fixedNightHour = d(fixedNightHour)
        case "transitionMin": transitionMinutes = i(transitionMinutes)
        case "schedBright": scheduleAffectsBrightness = on
        case "dayBright": dayBrightness = d(dayBrightness)
        case "nightBright": nightBrightness = d(nightBrightness)

        case "adaptive": adaptiveEnabled = on
        case "adaptiveMin": adaptiveMin = d(adaptiveMin)
        case "adaptiveMax": adaptiveMax = d(adaptiveMax)
        case "adaptiveReact": adaptiveReactivity = d(adaptiveReactivity)
        case "adaptiveInterval": adaptiveIntervalMs = i(adaptiveIntervalMs)

        case "monitor": monitors.append(MonitorSettings.deserialize(val))
        case "linkMonitors": linkMonitors = on
        case "matrixSource": matrixSourceId = val
        case "matrixPerScreen": matrixPerScreen = on

        case "colorReader": colorReaderEnabled = on
        case "beacon": beaconEnabled = on
        case "beaconSize": beaconSize = i(beaconSize)
        case "beaconOpacity": beaconOpacity = i(beaconOpacity)
        case "beaconColor": beaconColor = RGB.parse(val) ?? beaconColor
        case "magnifier": magnifierEnabled = on
        case "magnifierZoom": magnifierZoom = d(magnifierZoom)
        case "blink": blinkReminders = on
        case "blinkInterval": blinkIntervalMinutes = i(blinkIntervalMinutes)

        case "appRules": appRulesEnabled = on
        case "appRule": appRules.append(AppRule.deserialize(val))
        case "onFullscreen":
            onFullscreen = FullscreenSuspend(rawValue: i(1)) ?? .overlayOnly
            fullscreenFromFile = true
        case "disableFullscreen":
            // Reglage des versions 2.1 et anterieures, ou le choix se limitait a
            // « tout suspendre » ou « ne rien faire ».
            if !fullscreenFromFile { onFullscreen = on ? .overlayOnly : .never }
        case "disableBattery": disableOnBattery = on

        case "breaks": breaksEnabled = on
        case "breakInterval": breakIntervalMinutes = i(breakIntervalMinutes)
        case "breakDuration": breakDurationSeconds = i(breakDurationSeconds)
        case "breakDim": breakDim = on
        case "breakSound": breakSound = on

        case "hardwareBacklight": useHardwareBacklight = on
        case "useOverlay": useOverlay = on
        case "useColorMatrix": useColorMatrix = on
        case "smooth": smoothTransitions = on
        case "transitionSpeed": transitionSpeedMs = i(transitionSpeedMs)

        // Le fichier Windows ecrit `startWithWindows`. La clef est conservee telle
        // quelle pour que le meme fichier serve des deux cotes ; seul l'intitule
        // affiche change.
        case "startWithWindows", "startWithSystem": startWithSystem = on
        case "startMinimized": startMinimized = on
        case "hotkeysEnabled": hotkeysEnabled = on
        case "trayWheel": trayWheelControl = on
        case "skipDarkConfirm": skipDarkConfirm = on
        case "ignoreConflicts": ignoreConflicts = on
        case "warnedAboutClamp": warnedAboutClamp = on
        case "trayPercent": showTrayPercentage = on
        case "showInDock": showInDock = on
        case "checkUpdates": checkUpdates = on
        case "lastUpdateCheck":
            // Ecrit en « ticks » .NET par la version Windows : 100 nanosecondes
            // depuis l'an 1. La conversion garde les deux fichiers interoperables.
            if let ticks = Int64(val), ticks > 0 {
                let seconds = Double(ticks) / 10_000_000.0
                lastUpdateCheck = Date(timeIntervalSince1970: seconds - 62_135_596_800.0)
            }
        case "hotkey":
            // Le premier raccourci lu remplace les valeurs par defaut plutot
            // que de s'y ajouter, sinon chaque action serait liee deux fois.
            if !hotkeysFromFile { hotkeys.removeAll(); hotkeysFromFile = true }
            hotkeys.append(HotkeyBinding.deserialize(val))

        default: break
        }
    }

    public func save() {
        try? FileManager.default.createDirectory(atPath: Settings.dataFolder,
                                                 withIntermediateDirectories: true)
        try? export().write(toFile: Settings.filePath, atomically: true, encoding: .utf8)
    }

    /// Serialise toute la configuration. Sert aussi a l'export de fichier.
    public func export() -> String {
        var sb = ""
        func line(_ s: String) { sb += s + "\n" }
        func b(_ v: Bool) -> String { v ? "1" : "0" }

        line("# OpusScreen - configuration")
        line("# Supprimer ce fichier remet tous les reglages par defaut.")
        line("")
        line("current=" + current.serialize())
        line("activeMode=" + activeModeName)
        for p in customProfiles { line("customProfile=" + p.serialize()) }
        for v in visionPresets { line("visionPreset=" + v.serialize()) }
        if !lastExamSummary.isEmpty { line("lastExam=" + lastExamSummary) }
        line("")
        line("schedule=\(schedule.rawValue)")
        line("preset=" + presetName)
        line("latitude=" + String(format: "%.4f", latitude))
        line("longitude=" + String(format: "%.4f", longitude))
        line("bedtime=" + Profile.num(bedtimeHour))
        line("wake=" + Profile.num(wakeHour))
        line("fixedDay=" + Profile.num(fixedDayHour))
        line("fixedNight=" + Profile.num(fixedNightHour))
        line("transitionMin=\(transitionMinutes)")
        line("schedBright=" + b(scheduleAffectsBrightness))
        line("dayBright=" + Profile.num(dayBrightness))
        line("nightBright=" + Profile.num(nightBrightness))
        line("")
        line("adaptive=" + b(adaptiveEnabled))
        line("adaptiveMin=" + Profile.num(adaptiveMin))
        line("adaptiveMax=" + Profile.num(adaptiveMax))
        line("adaptiveReact=" + Profile.num(adaptiveReactivity))
        line("adaptiveInterval=\(adaptiveIntervalMs)")
        line("")
        for m in monitors { line("monitor=" + m.serialize()) }
        line("linkMonitors=" + b(linkMonitors))
        line("matrixSource=" + matrixSourceId)
        line("matrixPerScreen=" + b(matrixPerScreen))
        line("")
        line("colorReader=" + b(colorReaderEnabled))
        line("beacon=" + b(beaconEnabled))
        line("beaconSize=\(beaconSize)")
        line("beaconOpacity=\(beaconOpacity)")
        line("beaconColor=" + beaconColor.serialized)
        line("magnifier=" + b(magnifierEnabled))
        line("magnifierZoom=" + Profile.num(magnifierZoom))
        line("blink=" + b(blinkReminders))
        line("blinkInterval=\(blinkIntervalMinutes)")
        line("")
        line("appRules=" + b(appRulesEnabled))
        for r in appRules { line("appRule=" + r.serialize()) }
        line("onFullscreen=\(onFullscreen.rawValue)")
        line("disableBattery=" + b(disableOnBattery))
        line("")
        line("breaks=" + b(breaksEnabled))
        line("breakInterval=\(breakIntervalMinutes)")
        line("breakDuration=\(breakDurationSeconds)")
        line("breakDim=" + b(breakDim))
        line("breakSound=" + b(breakSound))
        line("")
        line("hardwareBacklight=" + b(useHardwareBacklight))
        line("useOverlay=" + b(useOverlay))
        line("useColorMatrix=" + b(useColorMatrix))
        line("smooth=" + b(smoothTransitions))
        line("transitionSpeed=\(transitionSpeedMs)")
        line("")
        line("startWithWindows=" + b(startWithSystem))
        line("startMinimized=" + b(startMinimized))
        line("hotkeysEnabled=" + b(hotkeysEnabled))
        line("trayWheel=" + b(trayWheelControl))
        line("skipDarkConfirm=" + b(skipDarkConfirm))
        line("ignoreConflicts=" + b(ignoreConflicts))
        line("warnedAboutClamp=" + b(warnedAboutClamp))
        line("trayPercent=" + b(showTrayPercentage))
        line("showInDock=" + b(showInDock))
        line("checkUpdates=" + b(checkUpdates))
        let ticks = Int64((lastUpdateCheck.timeIntervalSince1970 + 62_135_596_800.0) * 10_000_000.0)
        line("lastUpdateCheck=\(max(0, ticks))")
        for h in hotkeys { line("hotkey=" + h.serialize()) }
        return sb
    }

    /// Recharge depuis un texte exporte. Utilise par l'import de configuration.
    public static func fromText(_ text: String) -> Settings {
        let s = Settings()
        s.monitors.removeAll()
        s.customProfiles.removeAll()
        s.visionPresets.removeAll()
        s.appRules.removeAll()
        s.applyText(text)
        if s.hotkeys.isEmpty { s.hotkeys = defaultHotkeys() }
        s.mergeMissingHotkeys()
        s.current.clampAll()
        s.markGeneralAsPushed()
        return s
    }

    /// Recopie le contenu d'une configuration importee dans l'instance vivante.
    public func copyFrom(_ src: Settings) {
        current = src.current
        activeModeName = src.activeModeName
        customProfiles = src.customProfiles
        visionPresets = src.visionPresets
        schedule = src.schedule
        presetName = src.presetName
        latitude = src.latitude; longitude = src.longitude
        bedtimeHour = src.bedtimeHour; wakeHour = src.wakeHour
        fixedDayHour = src.fixedDayHour; fixedNightHour = src.fixedNightHour
        transitionMinutes = src.transitionMinutes
        scheduleAffectsBrightness = src.scheduleAffectsBrightness
        dayBrightness = src.dayBrightness; nightBrightness = src.nightBrightness
        adaptiveEnabled = src.adaptiveEnabled
        adaptiveMin = src.adaptiveMin; adaptiveMax = src.adaptiveMax
        adaptiveReactivity = src.adaptiveReactivity; adaptiveIntervalMs = src.adaptiveIntervalMs
        monitors = src.monitors; linkMonitors = src.linkMonitors
        matrixSourceId = src.matrixSourceId; matrixPerScreen = src.matrixPerScreen
        colorReaderEnabled = src.colorReaderEnabled
        beaconEnabled = src.beaconEnabled; beaconSize = src.beaconSize
        beaconOpacity = src.beaconOpacity; beaconColor = src.beaconColor
        magnifierEnabled = src.magnifierEnabled; magnifierZoom = src.magnifierZoom
        blinkReminders = src.blinkReminders; blinkIntervalMinutes = src.blinkIntervalMinutes
        appRulesEnabled = src.appRulesEnabled; appRules = src.appRules
        onFullscreen = src.onFullscreen; disableOnBattery = src.disableOnBattery
        breaksEnabled = src.breaksEnabled; breakIntervalMinutes = src.breakIntervalMinutes
        breakDurationSeconds = src.breakDurationSeconds; breakDim = src.breakDim
        breakSound = src.breakSound
        useHardwareBacklight = src.useHardwareBacklight; useOverlay = src.useOverlay
        useColorMatrix = src.useColorMatrix; smoothTransitions = src.smoothTransitions
        transitionSpeedMs = src.transitionSpeedMs
        trayWheelControl = src.trayWheelControl; showTrayPercentage = src.showTrayPercentage
        showInDock = src.showInDock
        hotkeys = src.hotkeys
        markGeneralAsPushed()
    }
}
