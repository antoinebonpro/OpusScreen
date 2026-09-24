import Foundation
import AppKit
import CoreGraphics
@testable import OpusScreenKit

/// Le lanceur de tests.
///
/// Il refuse d'annoncer un succes si une suite n'a rien execute : une suite
/// silencieuse est le pire des resultats, parce qu'elle ressemble a un succes.
/// C'etait deja la regle du script de la version Windows.

// Les sept suites ordinaires ne doivent jamais toucher a l'ecran de la machine
// qui les execute. La huitieme - la verification reelle - leve elle-meme ce mode
// a blanc, et rend tout ce qu'elle emprunte.
DisplayController.dryRun = true
SystemVolume.dryRun = true

let live = Swift.CommandLine.arguments.contains("--live")

if Swift.CommandLine.arguments.contains("--probe") { Probe.run(); Probe.measure(); exit(0) }
if Swift.CommandLine.arguments.contains("--gamma") { Probe.gamma(); exit(0) }
if Swift.CommandLine.arguments.contains("--update-check") { Probe.updateCheck(); exit(0) }

// Pose une table sombre puis meurt sans rien rendre. Sert a un seul test, qui
// constate ce que macOS fait d'une table dont le proprietaire disparait - la
// difference la plus importante avec Windows, et celle sur laquelle repose tout
// le raisonnement de securite.
if Swift.CommandLine.arguments.contains("--pose-et-meurs") {
    var ramp = Native.RampTable.allocate()
    for i in 0..<Native.RampTable.size {
        let v = UInt16(Double(i) / 255.0 * 65535.0 * 0.3)
        ramp.red[i] = v; ramp.green[i] = v; ramp.blue[i] = v
    }
    Native.setGammaRamp(CGMainDisplayID(), ramp)
    exit(0)
}
if Swift.CommandLine.arguments.contains("--render") {
    Probe.render(into: NSTemporaryDirectory() + "opusscreen-pages")
    exit(0)
}

print("")
print("OpusScreen - verification")
print("")

let suites: [(String, XCTestCase.Type)] = [
    ("moteur de luminosite", EngineTest.self),
    ("matrice de couleur", MatrixTest.self),
    ("vision et couleurs", VisionTest.self),
    ("test guide", ExamTest.self),
    ("securite", SafetyTest.self),
    ("reglages", SettingsTest.self),
    ("systeme", SystemTest.self),
]

var executed = 0
var empty: [String] = []

for (label, suite) in suites {
    let n = TestRunner.run(suite)
    if n == 0 { empty.append(label) }
    executed += n
}

if live {
    print("")
    print("Verification reelle - l'ecran va changer brievement.")
    print("")
    // AppKit est necessaire : cette suite cree de vraies fenetres.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    let n = TestRunner.run(LiveTest.self)
    if n == 0 { empty.append("verification reelle") }
    executed += n

    // Quoi qu'il soit arrive, l'ecran est rendu.
    SafetyGuard.emergencyRestore()
    Native.restoreAllGamma()
}

print("")
print("\(executed) tests, \(TestReport.assertions) assertions")

if !TestReport.failures.isEmpty {
    print("")
    print("ECHECS :")
    for failure in TestReport.failures { print(failure) }
}

if live && !LiveTest.skipped.isEmpty {
    print("")
    print("NON VERIFIABLE SUR CETTE MACHINE :")
    for s in LiveTest.skipped { print("  · " + s) }
    print("  Ce ne sont pas des echecs : c'est ce que le materiel ou les")
    print("  autorisations de cette machine ne permettent pas de constater.")
}

if !empty.isEmpty {
    print("")
    print("SUITES VIDES : " + empty.joined(separator: ", "))
    print("Une suite qui n'execute rien ressemble a un succes. Ce n'en est pas un.")
}

print("")
if TestReport.failures.isEmpty && empty.isEmpty {
    print("Tout passe.")
    exit(0)
} else {
    print("Verification en echec.")
    exit(1)
}
