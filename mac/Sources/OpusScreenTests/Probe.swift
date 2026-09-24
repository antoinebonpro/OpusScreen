import Foundation
import AppKit
@testable import OpusScreenKit

/// Sonde de mise au point.
///
/// Elle ne verifie rien : elle MONTRE. Deux usages, tous deux nes d'un besoin
/// concret pendant le portage.
///
///   `--probe` liste ce que le moteur rend pour quelques couleurs, quand il faut
///   choisir un exemple juste plutot que plausible.
///
///   `--render` dessine les onze pages de reglages dans des fichiers PNG. Une
///   interface entierement peinte a la main ne se verifie pas en lisant le code :
///   il faut la regarder. Et la regarder hors ecran, sans autorisation de
///   capture, permet de le faire depuis un terminal - y compris sur une machine
///   de construction qui n'a pas d'ecran du tout.
enum Probe {

    static func run() {
        print("-- noms de couleurs --")
        for c in [RGB(20, 8, 4), RGB(30, 40, 38), RGB(12, 30, 60), RGB(70, 20, 90),
                  RGB(245, 250, 200), RGB(250, 240, 245), RGB(200, 250, 250)] {
            print(c.hex, "->", Vision.nameOf(c), "/", Vision.describeColor(c),
                  String(format: "L=%.1f", Vision.toLab(c)[0]))
        }
    }

    /// Ce que GitHub repond vraiment, aujourd'hui, a la question posee par
    /// l'application.
    ///
    /// Les tests verifient la LECTURE d'une reponse ecrite a la main. Ils ne
    /// peuvent pas dire si la publication existe, si le nom du paquet est le bon,
    /// ni si la ligne macOS a ete separee de celle de Windows comme prevu. Cette
    /// sonde pose la question au vrai serveur, et montre la reponse. Elle ne
    /// telecharge rien et n'installe rien.
    static func updateCheck() {
        print("-- interrogation de GitHub --")
        print("   ", Updater.apiUrl)
        do {
            let info = try Updater.fetch()
            print("    publication : \(info.tag)  (\(info.title))")
            print("    version lue : \(info.shortVersion)")
            print("    paquet      : \(info.downloadUrl)")
            print("    taille      : \(info.size) o")
            print("    empreinte   : \(info.sha256)")
            let mienne = Installer.currentVersion.map(String.init).joined(separator: ".")
            print("    installee   : \(mienne)")
            print(Updater.isNewer(info.version, Installer.currentVersion)
                  ? "    => une version plus recente est proposee"
                  : "    => rien de plus recent : aucune proposition")
        } catch {
            print("    echec : \(error.localizedDescription)")
        }
    }

    /// Dessine chaque page dans un PNG. Rend le dossier utilise.
    static func render(into folder: String) {
        // AppKit exige une application, meme pour peindre hors ecran. Celle-ci
        // n'apparait nulle part : ni Dock, ni barre des menus, ni fenetre.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        DisplayController.dryRun = true
        Settings.dataFolderOverride = NSTemporaryDirectory() + "opusscreen-render"

        let settings = Settings.load()
        // Un etat qui montre quelque chose : sans cela les pages s'affichent
        // toutes au neutre et l'on ne verifie que des zeros.
        settings.current.brightness = 128
        settings.current.kelvin = 3400
        settings.current.filter = .deuteranopia
        settings.current.visionSeverity = 65
        settings.adaptiveEnabled = true
        settings.breaksEnabled = true
        settings.beaconEnabled = true

        let display = DisplayController(settings)
        let panel = ControlPanel(settings, display, {})

        let window = panel.window
        let tall = Swift.CommandLine.arguments.contains("--tall")
        window.setContentSize(NSSize(width: 900, height: tall ? 1900 : 720))

        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)

        let pages = ["01-decouvrir", "02-ecran", "03-couleur", "04-daltonisme", "05-vision",
                     "06-automatisme", "07-applications", "08-ecrans", "09-confort",
                     "10-raccourcis", "11-avance"]

        for (index, name) in pages.enumerated() {
            panel.selectPage(index)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()

            guard let root = window.contentView,
                  let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { continue }
            root.cacheDisplay(in: root.bounds, to: rep)

            if Swift.CommandLine.arguments.contains("--frames") && index == 3 {
                dumpLabels(root, depth: 0)
            }

            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let path = (folder as NSString).appendingPathComponent("\(name).png")
            try? data.write(to: URL(fileURLWithPath: path))
            print("  \(name).png  \(Int(root.bounds.width))x\(Int(root.bounds.height))")
        }

        try? FileManager.default.removeItem(atPath: Settings.dataFolderOverride ?? "")
        print("Rendu dans \(folder)")
    }
}

extension Probe {
    /// Le point blanc de chaque ecran, tel qu'il est POSE en ce moment.
    ///
    /// Sert au test de bout en bout, qui pilote la vraie application depuis un
    /// terminal : sans cette lecture, il faudrait croire l'application sur
    /// parole quand elle dit avoir assombri l'ecran.
    static func gamma() {
        for id in Native.activeDisplayIDs() {
            guard let ramp = Native.getGammaRamp(id) else {
                print("\(id) illisible")
                continue
            }
            let last = Native.RampTable.size - 1
            print(String(format: "%u %.4f %.4f %.4f", id,
                         Double(ramp.red[last]) / 65535.0,
                         Double(ramp.green[last]) / 65535.0,
                         Double(ramp.blue[last]) / 65535.0))
        }
    }

    /// Affiche la boite reservee a chaque etiquette, et celle qu'il lui
    /// faudrait. L'ecart entre les deux, c'est du texte tranche.
    static func dumpLabels(_ view: NSView, depth: Int) {
        if let label = view as? LabelView, label.wraps, label.text.count > 80 {
            let needed = Draw.height(of: label.text, font: label.font, width: label.frame.width)
            print(String(format: "    boite %.0f x %.0f | il en faudrait %.0f | %@...",
                         label.frame.width, label.frame.height, needed,
                         String(label.text.prefix(40))))
        }
        for sub in view.subviews { dumpLabels(sub, depth: depth + 1) }
    }

    /// Mesure d'un texte long : la hauteur annoncee correspond-elle a ce qui est
    /// reellement dessine ?
    static func measure() {
        let text = "Des planches ou se cache un chiffre trouvent le TYPE, puis des comparaisons de "
                 + "couleurs mesurent la GRAVITE en resserrant l'ecart jusqu'a votre limite. Le reglage "
                 + "obtenu vaut mieux qu'un reglage devine : une correction calibree sur une deficience "
                 + "complete rend l'ecran criard a qui n'en a qu'une partie. Pendant le test, la "
                 + "correction en cours est retiree, puis retablie a la sortie."

        for width in [638.0, 700.0] as [CGFloat] {
            let h = Draw.height(of: text, font: Theme.small, width: width)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            let a = NSAttributedString(string: text, attributes: [.font: Theme.small, .paragraphStyle: style])
            let box = a.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading])
            let lineHeight = Theme.small.ascender - Theme.small.descender + Theme.small.leading
            print(String(format: "largeur %.0f : Draw.height=%.1f  boundingRect=%.1f  ligne=%.1f  -> %.1f lignes",
                         width, h, box.height, lineHeight, box.height / lineHeight))
        }
    }
}
