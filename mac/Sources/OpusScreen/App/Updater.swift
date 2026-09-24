import Foundation
import AppKit
import CryptoKit

/// Ce que GitHub dit de la derniere version publiee.
public struct UpdateInfo {
    public var version: [Int] = [0, 0, 0]
    public var tag = ""
    public var title = ""
    public var downloadUrl = ""
    public var size: Int64 = 0
    public var sha256 = ""
    public var pageUrl = ""

    public var shortVersion: String { version.map(String.init).joined(separator: ".") }
}

/// La verification quotidienne, et l'installation controlee.
///
/// C'est la seule connexion de l'application : elle demande a GitHub le numero de
/// la derniere version publiee, et rien d'autre n'est envoye. Le fichier
/// telecharge est verifie - taille, empreinte SHA-256 publiee par GitHub, numero
/// de version lu dans le paquet - AVANT de remplacer quoi que ce soit.
public enum Updater {

    /// La LISTE des publications, et non « la derniere ».
    ///
    /// Les deux versions vivent dans le meme depot et ne suivent pas la meme
    /// numerotation : la version Windows en est a sa 3.4, celle-ci commence a 1.0.
    /// Demander « la derniere publication » rendrait donc la derniere publication
    /// WINDOWS, ou l'on ne trouverait aucun paquet macOS - et l'application
    /// annoncerait chaque jour une erreur de reseau qui n'en est pas une.
    ///
    /// On parcourt donc les publications de la plus recente a la plus ancienne, et
    /// l'on retient la premiere qui porte un paquet macOS. Les deux lignes de
    /// produit avancent alors chacune a son rythme, dans le meme depot, sans se
    /// marcher dessus.
    public static let apiUrl = "https://api.github.com/repos/antoinebonpro/OpusScreen/releases?per_page=30"
    public static let releasesPage = "https://github.com/antoinebonpro/OpusScreen/releases"

    /// Le nom de l'archive publiee pour macOS.
    ///
    /// Distinct de celui de la version Windows : les deux paquets vivent dans la
    /// meme publication GitHub, et prendre le mauvais donnerait un fichier qui ne
    /// s'ouvre pas.
    private static let assetName = "OpusScreen-mac.zip"

    /// Emis quand l'interface demande une verification immediate.
    public static var checkRequested: (() -> Void)?

    public static func requestCheck() { checkRequested?() }

    public static var lastStatus = ""

    // ------------------------------------------------------------------ lecture

    public static func parse(_ data: Data) -> UpdateInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var info = UpdateInfo()
        info.tag = (root["tag_name"] as? String) ?? ""
        info.title = (root["name"] as? String) ?? ""
        info.pageUrl = (root["html_url"] as? String) ?? ""
        info.version = parseVersion(info.tag)

        guard let assets = root["assets"] as? [[String: Any]] else { return nil }
        for asset in assets {
            guard let name = asset["name"] as? String, name == assetName else { continue }
            info.downloadUrl = (asset["browser_download_url"] as? String) ?? ""
            info.size = (asset["size"] as? NSNumber)?.int64Value ?? 0
            // GitHub publie l'empreinte sous la forme « sha256:abcdef... »
            if let digest = asset["digest"] as? String, digest.hasPrefix("sha256:") {
                info.sha256 = String(digest.dropFirst("sha256:".count))
            }
            break
        }

        return info.downloadUrl.isEmpty ? nil : info
    }

    /// Le numero contenu dans une etiquette, quel que soit ce qui le precede.
    ///
    /// « v3.4.0 », « mac-v1.0.0 », « 1.2 » rendent tous ce qu'il faut : on part du
    /// premier chiffre. Une etiquette est un nom que l'on choisit, pas un format.
    public static func parseVersion(_ tag: String) -> [Int] {
        guard let start = tag.firstIndex(where: { $0.isNumber }) else { return [0] }
        let cleaned = tag[start...]
        let parts = cleaned.split(separator: ".").compactMap { Int($0.prefix(while: { $0.isNumber })) }
        return parts.isEmpty ? [0] : parts
    }

    /// La publication la plus recente qui porte un paquet macOS.
    public static func parseList(_ data: Data) -> UpdateInfo? {
        guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        // GitHub rend les publications de la plus recente a la plus ancienne.
        for release in releases {
            if (release["draft"] as? Bool) == true { continue }
            guard let data = try? JSONSerialization.data(withJSONObject: release) else { continue }
            if let info = parse(data) { return info }
        }
        return nil
    }

    /// Vrai si `candidate` est plus recente que `current`.
    public static func isNewer(_ candidate: [Int], _ current: [Int]) -> Bool {
        let n = max(candidate.count, current.count)
        for i in 0..<n {
            let a = i < candidate.count ? candidate[i] : 0
            let b = i < current.count ? current[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Interroge GitHub. Synchrone : l'appelant la lance sur un fil a lui.
    public static func fetch() throws -> UpdateInfo {
        guard let url = URL(string: apiUrl) else { throw UpdaterError.badUrl }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub refuse les requetes sans identification d'agent.
        request.setValue("OpusScreen/" + Installer.currentVersionShort, forHTTPHeaderField: "User-Agent")

        let (data, response) = try synchronousData(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdaterError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let info = parseList(data) else { throw UpdaterError.noAsset }
        return info
    }

    // ------------------------------------------------------------------ telechargement

    public static func download(_ info: UpdateInfo) throws -> URL {
        guard let url = URL(string: info.downloadUrl) else { throw UpdaterError.badUrl }
        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        request.setValue("OpusScreen/" + Installer.currentVersionShort, forHTTPHeaderField: "User-Agent")

        let (data, response) = try synchronousData(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdaterError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        // Verification AVANT d'ecrire quoi que ce soit d'utilisable.
        if info.size > 0 && Int64(data.count) != info.size { throw UpdaterError.sizeMismatch }
        if !info.sha256.isEmpty {
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if digest.lowercased() != info.sha256.lowercased() { throw UpdaterError.digestMismatch }
        }

        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OpusScreenUpdate", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let archive = folder.appendingPathComponent(assetName)
        try data.write(to: archive)
        return archive
    }

    /// Deballe l'archive et rend le paquet qu'elle contient.
    public static func unpack(_ archive: URL) throws -> URL {
        let folder = archive.deletingLastPathComponent().appendingPathComponent("unpacked", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // `ditto` conserve les attributs etendus et la signature du paquet ;
        // `unzip` ne le fait pas toujours, et un paquet dont la signature a saute
        // ne se lance plus.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", archive.path, folder.path]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw UpdaterError.unpackFailed }

        let contents = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdaterError.unpackFailed
        }
        return app
    }

    /// Remplace le paquet en place, puis relance.
    ///
    /// La version du paquet telecharge est relue avant l'echange : une archive
    /// correcte mais contenant une version PLUS ANCIENNE ferait regresser
    /// l'application sans que rien ne le dise.
    public static func apply(_ newApp: URL) throws {
        let plist = newApp.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist),
              let version = info["CFBundleShortVersionString"] as? String,
              isNewer(parseVersion(version), Installer.currentVersion) else {
            throw UpdaterError.notNewer
        }

        let current = URL(fileURLWithPath: Bundle.main.bundlePath)
        let fm = FileManager.default

        // L'echange se fait par `replaceItemAt`, qui est atomique : a aucun
        // instant il n'existe d'etat ou l'application a disparu.
        _ = try fm.replaceItemAt(current, withItemAt: newApp)

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = ["--updated"]
        NSWorkspace.shared.openApplication(at: current, configuration: config) { _, _ in }
    }

    public static func wasJustUpdated(_ args: [String]) -> Bool {
        args.contains { $0.lowercased() == "--updated" }
    }

    // ------------------------------------------------------------------ utilitaires

    /// Requete synchrone. L'appelant tourne deja sur un fil a lui ; introduire
    /// une chaine asynchrone ici compliquerait la lecture sans rien apporter.
    private static func synchronousData(for request: URLRequest) throws -> (Data, URLResponse) {
        var result: Result<(Data, URLResponse), Error>?
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { result = .failure(error) }
            else if let data = data, let response = response { result = .success((data, response)) }
            else { result = .failure(UpdaterError.empty) }
            semaphore.signal()
        }.resume()

        semaphore.wait()
        switch result {
        case .success(let pair): return pair
        case .failure(let error): throw error
        case .none: throw UpdaterError.empty
        }
    }

    public enum UpdaterError: LocalizedError {
        case badUrl, empty, noAsset, sizeMismatch, digestMismatch, unpackFailed, notNewer
        case http(Int)

        public var errorDescription: String? {
            switch self {
            case .badUrl: return "adresse invalide"
            case .empty: return "aucune reponse"
            case .noAsset: return "aucun paquet macOS dans cette publication"
            case .sizeMismatch: return "la taille du fichier ne correspond pas a celle annoncee"
            case .digestMismatch: return "l'empreinte du fichier ne correspond pas a celle publiee"
            case .unpackFailed: return "l'archive n'a pas pu etre ouverte"
            case .notNewer: return "l'archive ne contient pas une version plus recente"
            case .http(let code): return "GitHub a repondu \(code)"
            }
        }
    }
}
