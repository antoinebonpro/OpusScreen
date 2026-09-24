import Foundation

/// Pilotage en ligne de commande.
///
/// La transmission a l'instance en cours passe par un petit fichier d'ordres
/// plutot que par un canal nomme : c'est lisible, cela survit a un plantage, et
/// cela ne laisse aucun port ni objet systeme derriere soi.
///
/// Sur macOS, un paquet se lance par `open -a OpusScreen --args --brightness 130`,
/// ou directement par son binaire interne. Les deux chemins aboutissent ici.
public enum CommandLineDriver {

    private static var commandPath: String {
        (Settings.dataFolder as NSString).appendingPathComponent("command.txt")
    }

    private static let commands = [
        "--brightness", "--temp", "--mode", "--reset", "--pause", "--resume",
        "--adaptive", "--blackout", "--break", "--show",
        "--vision", "--severity", "--magnifier", "--beacon", "--colors",
    ]

    public static func hasCommand(_ args: [String]) -> Bool {
        args.contains { a in commands.contains { $0.caseInsensitiveCompare(a) == .orderedSame } }
    }

    public static func wantsHelp(_ args: [String]) -> Bool {
        args.contains { $0 == "--help" || $0 == "-h" }
    }

    public static func startMinimized(_ args: [String]) -> Bool {
        args.contains { $0.caseInsensitiveCompare("--minimized") == .orderedSame }
    }

    /// Demande explicite de la fenetre.
    public static func wantsShow(_ args: [String]) -> Bool {
        args.contains { $0.caseInsensitiveCompare("--show") == .orderedSame }
    }

    /// Depose l'ordre pour l'instance en cours.
    @discardableResult
    public static func sendToRunningInstance(_ args: [String]) -> Bool {
        guard !Installer.otherInstances().isEmpty else { return false }
        try? FileManager.default.createDirectory(atPath: Settings.dataFolder,
                                                 withIntermediateDirectories: true)
        try? quote(args).write(toFile: commandPath, atomically: true, encoding: .utf8)
        return true
    }

    /// Recompose une ligne de commande en reprotegeant les arguments contenant des
    /// espaces. Sans cela, `--mode "Nuit profonde"` arrive decoupe en deux mots a
    /// l'instance en cours, et aucun mode ne correspond.
    private static func quote(_ args: [String]) -> String {
        args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }

    /// Lit puis efface l'ordre depose. Chaine vide s'il n'y en a pas.
    public static func consumePending() -> String {
        guard FileManager.default.fileExists(atPath: commandPath) else { return "" }
        let text = (try? String(contentsOfFile: commandPath, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(atPath: commandPath)
        return text
    }

    /// Redecoupe la ligne d'ordre en respectant les guillemets.
    public static func splitArgs(_ line: String) -> [String] {
        var parts: [String] = []
        var inQuotes = false
        var current = ""
        for c in line {
            if c == "\"" { inQuotes.toggle(); continue }
            if c == " " && !inQuotes {
                if !current.isEmpty { parts.append(current); current = "" }
                continue
            }
            current.append(c)
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// Applique un ordre aux reglages. Retourne vrai si quelque chose a change.
    @discardableResult
    public static func apply(to s: Settings, _ args: [String]) -> Bool {
        var changed = false
        var i = 0
        while i < args.count {
            let a = args[i].lowercased()
            let next = i + 1 < args.count ? args[i + 1] : nil

            switch a {
            case "--brightness":
                if let next = next, let v = Double(next) {
                    s.current.brightness = SafetyGuard.clampBrightness(v)
                    changed = true; i += 1
                }

            case "--temp":
                if let next = next, let v = Int(next) {
                    s.current.kelvin = max(ColorTemp.minKelvin, min(ColorTemp.maxKelvin, v))
                    changed = true; i += 1
                }

            case "--mode":
                // Les noms de mode contiennent des espaces. Si l'utilisateur a
                // oublie les guillemets, on recolle les mots suivants et on retient
                // la correspondance la plus longue - « Nuit profonde » marche donc
                // avec ou sans protection.
                let match = matchMode(s, args, from: i + 1)
                if let found = match.profile {
                    s.current.copyFrom(found)
                    s.activeModeName = found.name
                    changed = true
                    i += match.consumed
                } else {
                    i += 1
                }

            case "--reset":
                s.current = Profile()
                s.activeModeName = "Normal"
                s.schedule = .manual
                s.adaptiveEnabled = false
                changed = true

            case "--adaptive":
                if let next = next, next == "on" || next == "off" {
                    s.adaptiveEnabled = (next == "on"); changed = true; i += 1
                } else {
                    s.adaptiveEnabled.toggle(); changed = true
                }

            // --- accessibilite ---
            //
            // Les intitules acceptes sont ceux de la couleur mal percue, pas les
            // termes cliniques : quelqu'un qui ecrit un script se souvient de
            // « vert », pas de « deuteranopie ». Les deux marchent.

            case "--vision":
                if let next = next, let f = parseVision(next) {
                    s.current.filter = f
                    changed = true; i += 1
                }

            case "--severity":
                if let next = next, let v = Double(next) {
                    s.current.visionSeverity = max(0, min(100, v))
                    changed = true; i += 1
                }

            case "--magnifier":
                if let next = next, let zoom = Double(next) {
                    s.magnifierZoom = max(ScreenMagnifier.minZoom, min(ScreenMagnifier.maxZoom, zoom))
                    s.magnifierEnabled = zoom > ScreenMagnifier.minZoom + 0.001
                    changed = true; i += 1
                } else if let next = next, next == "on" || next == "off" {
                    s.magnifierEnabled = (next == "on"); changed = true; i += 1
                } else {
                    s.magnifierEnabled.toggle(); changed = true
                }

            case "--beacon":
                if let next = next, next == "on" || next == "off" {
                    s.beaconEnabled = (next == "on"); changed = true; i += 1
                } else {
                    s.beaconEnabled.toggle(); changed = true
                }

            case "--colors":
                if let next = next, next == "on" || next == "off" {
                    s.colorReaderEnabled = (next == "on"); changed = true; i += 1
                } else {
                    s.colorReaderEnabled.toggle(); changed = true
                }

            default:
                break
            }
            i += 1
        }
        return changed
    }

    /// Reconnait une correction de vision, par la couleur mal percue ou par son
    /// nom clinique. Les deux sont acceptes : l'un se retient, l'autre se cherche.
    static func parseVision(_ word: String) -> ColorFilter? {
        switch word.lowercased() {
        case "none", "aucun", "aucune", "off": return ColorFilter.none
        case "red", "rouge", "protanopie", "protanopia", "protan": return .protanopia
        case "green", "vert", "deuteranopie", "deuteranopia", "deutan": return .deuteranopia
        case "blue", "bleu", "tritanopie", "tritanopia", "tritan": return .tritanopia
        default: return nil
        }
    }

    /// Cherche un mode dont le nom correspond aux arguments a partir de `start`,
    /// en essayant d'abord la plus longue suite de mots.
    private static func matchMode(_ s: Settings, _ args: [String], from start: Int)
        -> (profile: Profile?, consumed: Int) {

        guard start < args.count else { return (nil, 1) }

        var all = Profile.builtInModes()
        all.append(contentsOf: s.customProfiles)

        // Un argument suivant qui commence par -- appartient a la commande d'apres.
        var maxWords = 0
        var k = start
        while k < args.count && !args[k].hasPrefix("--") { maxWords += 1; k += 1 }

        var words = maxWords
        while words >= 1 {
            let candidate = args[start..<(start + words)].joined(separator: " ")
            if let found = all.first(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return (found, words)
            }
            words -= 1
        }
        return (nil, 1)
    }

    public static let helpText = """
    OpusScreen - pilotage en ligne de commande

      open -a OpusScreen --args --brightness 130   luminosite, de 5 a 150
      open -a OpusScreen --args --temp 3400        temperature en kelvins, 1200 a 6500
      open -a OpusScreen --args --mode "Lecture"   applique un mode par son nom
      open -a OpusScreen --args --adaptive on|off  adaptation au contenu affiche

      Accessibilite :
      --vision vert        correction daltonisme : aucune | rouge | vert | bleu
      --severity 70        gravite de la deficience, 0 a 100
      --magnifier 2.5      loupe plein ecran, 1 a 8 (1 = eteinte)
      --beacon on|off      anneau autour du pointeur
      --colors on|off      etiquette qui nomme les couleurs

      --pause              suspend tous les effets
      --resume             reprend
      --break              declenche une pause pour les yeux
      --reset              remet l'ecran a l'etat normal
      --show               ouvre la fenetre de reglages
      --minimized          demarre sans ouvrir la fenetre
      --uninstall          desinstalle OpusScreen

    Si OpusScreen tourne deja, l'ordre lui est transmis et prend effet
    immediatement. Sinon il s'applique au demarrage.

    Le binaire interne du paquet accepte les memes options directement :
      /Applications/OpusScreen.app/Contents/MacOS/OpusScreen --brightness 130
    """
}
