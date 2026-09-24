// swift-tools-version:5.9
import PackageDescription

// OpusScreen pour macOS.
//
// Deux cibles plutot qu'une : tout le savoir vit dans OpusScreenKit, et
// l'executable ne porte que son point d'entree. C'est ce qui permet aux tests
// d'importer le moteur sans lancer d'application, exactement comme la version
// Windows compile ses suites de tests contre les memes fichiers source.
let package = Package(
    name: "OpusScreen",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "OpusScreenKit",
            path: "Sources/OpusScreen",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "OpusScreenApp",
            dependencies: ["OpusScreenKit"],
            path: "Sources/Launcher"
        ),
        // Les tests sont un EXECUTABLE, pas une cible de test.
        //
        // XCTest n'est pas livre avec les outils en ligne de commande d'Apple :
        // il faudrait Xcode. Or cette application se construit et se verifie
        // avec les seuls outils du systeme, comme la version Windows le faisait
        // avec le compilateur livre par le .NET Framework. Le harnais tient en
        // un fichier et porte les memes noms que XCTest, de sorte que les
        // fichiers de test se compilent tels quels contre le vrai cadre le jour
        // ou Xcode est present.
        .executableTarget(
            name: "OpusScreenTests",
            dependencies: ["OpusScreenKit"],
            path: "Sources/OpusScreenTests"
        ),
    ]
)
