import Foundation
import AppKit
import CoreGraphics

/// Surveille l'application au premier plan.
///
/// Deux usages, tous deux reserves aux versions payantes de la concurrence :
///
///   - Profils par application (Lunar Pro) : Photoshop en couleurs fideles,
///     le lecteur video en mode film, le terminal en mode nuit - sans rien toucher.
///   - Suspension automatique en jeu ou en video plein ecran, pour ne pas fausser
///     les couleurs ni laisser un voile par-dessus une partie.
public final class AppWatcher {
    private var lastProcess = ""
    private var lastFullscreen = false

    /// Identifiant de l'application active, en minuscules.
    ///
    /// Sur Windows c'etait le nom de l'executable. Sur macOS, l'identifiant de
    /// paquet - `com.apple.safari` - est le seul nom qui ne change ni avec la
    /// langue, ni avec le nom que l'utilisateur a donne a l'application dans le
    /// Finder. Le nom lisible est conserve a cote, pour l'affichage.
    public private(set) var currentProcess = ""
    public private(set) var currentName = ""

    public private(set) var isFullscreen = false

    /// Emis quand l'application au premier plan change.
    public var foregroundChanged: ((String) -> Void)?

    /// Emis quand on entre ou sort d'un plein ecran.
    public var fullscreenChanged: ((Bool) -> Void)?

    public init() {}

    /// A appeler periodiquement, typiquement chaque seconde.
    public func poll() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let proc = (app.bundleIdentifier ?? app.localizedName ?? "").lowercased()
        currentName = app.localizedName ?? proc
        if proc != lastProcess {
            lastProcess = proc
            currentProcess = proc
            foregroundChanged?(proc)
        }

        let full = AppWatcher.isFrontWindowFullscreen(app)
        if full != lastFullscreen {
            lastFullscreen = full
            isFullscreen = full
            fullscreenChanged?(full)
        }
    }

    /// Une fenetre est consideree plein ecran si elle couvre exactement un ecran
    /// entier. Le bureau, le Dock et la barre des menus sont exclus : ils
    /// remplissent l'ecran en permanence sans etre des jeux.
    ///
    /// La liste des fenetres suffit, et ne demande aucune autorisation
    /// particuliere tant qu'on ne lit que la geometrie - les titres, eux, en
    /// demanderaient une, et ils ne servent a rien ici.
    static func isFrontWindowFullscreen(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        if app.bundleIdentifier == "com.apple.finder" { return false }

        guard let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let screens = MonitorEnum.all().map { $0.bounds.cgRect }

        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }

            for s in screens where rect.minX <= s.minX + 1 && rect.minY <= s.minY + 1
                                && rect.maxX >= s.maxX - 1 && rect.maxY >= s.maxY - 1 {
                return true
            }
        }
        return false
    }
}

/// Association « application -> profil », telle que la propose Lunar Pro.
public final class AppRule {
    public var processName = ""   // identifiant de paquet, en minuscules
    public var profileName = ""
    public var disable = false    // vrai = suspendre tout effet pour cette application

    public init() {}

    public func serialize() -> String {
        "\(processName)>\(profileName)>\(disable ? "1" : "0")"
    }

    public static func deserialize(_ s: String) -> AppRule {
        let r = AppRule()
        let f = s.components(separatedBy: ">")
        if f.count >= 1 { r.processName = f[0].trimmingCharacters(in: .whitespaces).lowercased() }
        if f.count >= 2 { r.profileName = f[1].trimmingCharacters(in: .whitespaces) }
        if f.count >= 3 { r.disable = f[2] == "1" }
        return r
    }

    public func describe() -> String {
        processName + "  ->  " + (disable ? "aucun effet" : profileName)
    }
}

/// Applications courantes proposees pour creer une regle sans taper le nom.
///
/// La liste n'est plus celle de Windows : elle nomme les logiciels que l'on
/// trouve sur un Mac, avec leur identifiant de paquet reel. Proposer
/// « windowsterminal » a quelqu'un sur macOS aurait ete du portage au sens
/// litteral, et sans usage.
public enum KnownApps {
    public struct Entry {
        public let process: String
        public let label: String
        public let suggested: String
        public init(_ p: String, _ l: String, _ s: String) {
            process = p; label = l; suggested = s
        }
    }

    public static func suggestions() -> [Entry] {
        [
            Entry("com.adobe.photoshop", "Adobe Photoshop", "Normal"),
            Entry("com.adobe.illustrator", "Adobe Illustrator", "Normal"),
            Entry("com.adobe.aftereffects", "After Effects", "Normal"),
            Entry("com.adobe.lightroom", "Lightroom", "Normal"),
            Entry("com.blackmagic-design.davinciresolve", "DaVinci Resolve", "Normal"),
            Entry("com.apple.finalcut", "Final Cut Pro", "Normal"),
            Entry("com.apple.photos", "Photos", "Normal"),
            Entry("org.videolan.vlc", "VLC", "Film"),
            Entry("com.colliderli.iina", "IINA", "Film"),
            Entry("com.apple.tv", "Apple TV", "Film"),
            Entry("com.microsoft.vscode", "Visual Studio Code", "Lecture"),
            Entry("com.apple.dt.xcode", "Xcode", "Lecture"),
            Entry("com.apple.terminal", "Terminal", "Lecture"),
            Entry("com.googlecode.iterm2", "iTerm2", "Lecture"),
            Entry("com.apple.preview", "Aperçu", "Papier"),
            Entry("com.apple.pages", "Pages", "Papier"),
            Entry("com.microsoft.word", "Microsoft Word", "Papier"),
            Entry("com.valvesoftware.steam", "Steam", "Jeu"),
            Entry("us.zoom.xos", "Zoom", "Visioconference"),
            Entry("com.microsoft.teams2", "Microsoft Teams", "Visioconference"),
            Entry("com.apple.facetime", "FaceTime", "Visioconference"),
        ]
    }
}
