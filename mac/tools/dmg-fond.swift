#!/usr/bin/env swift
//
// Le fond de la fenetre du disque d'installation, TRACE.
//
// Un fond de DMG est une image, et une image se fabrique d'ordinaire dans un
// editeur - ce qui la rend impossible a modifier sans cet editeur, et impossible
// a verifier. Celle-ci se redessine d'une commande, comme le reste.
//
//   swift tools/dmg-fond.swift <sortie.png> <echelle>
//
// Elle est claire, et ce n'est pas un choix d'esthetique. Le Finder ecrit le nom
// des icones dans la couleur du THEME du systeme, pas dans celle du fond : noir
// en theme clair, blanc en theme sombre. Aucune image ne peut convenir aux deux.
// Le theme clair est le plus repandu, et c'est celui du Finder par defaut ; un
// fond clair sert donc le plus grand nombre. Tout ce qui doit rester lisible est
// en outre ecrit AILLEURS que sous les icones, la ou le Finder n'ecrit rien.
//
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let echelle = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: dmg-fond.swift <sortie.png> <echelle>\n".utf8))
    exit(2)
}
let sortie = args[1]
let L = 640.0, H = 400.0                       // la fenetre, en points
let s = CGFloat(echelle)

guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(L * echelle), pixelsHigh: Int(H * echelle),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }

let ctx = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.cgContext.scaleBy(x: s, y: s)
ctx.cgContext.setShouldAntialias(true)
ctx.imageInterpolation = .high

func c(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255,
            alpha: CGFloat(a))
}

// Repere ecrit comme on lit : origine en HAUT a gauche, comme le Finder place
// ses icones. Sans cela, chaque coordonnee de ce fichier devrait etre traduite
// de tete au moment de la comparer a celles du script qui pose les icones.
func y(_ depuisLeHaut: Double) -> CGFloat { CGFloat(H - depuisLeHaut) }

// ------------------------------------------------------------------ le fond

// Un seul degrade vertical, en trois arrets : blanc en haut, une pointe de
// turquoise au milieu - a hauteur des icones -, gris tres pale en bas.
//
// La couleur a d'abord ete posee en lueur RONDE au centre. Un degrade radial
// s'arrete net au bord de sa forme : on voyait le disque. Un degre qui traverse
// toute l'image n'a pas de bord, donc rien a trahir.
NSGradient(colors: [c(252, 253, 253), c(228, 244, 242), c(233, 240, 239)],
           atLocations: [0, 0.52, 1], colorSpace: .sRGB)!
    .draw(in: NSRect(x: 0, y: 0, width: L, height: H), angle: -90)

// ------------------------------------------------------------------ le texte

func ecrire(_ texte: String, _ taille: CGFloat, _ poids: NSFont.Weight,
            _ couleur: NSColor, centreEn cx: Double, hautA hy: Double, interligne: CGFloat = 0) {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    p.lineSpacing = interligne
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: taille, weight: poids),
        .foregroundColor: couleur,
        .paragraphStyle: p,
    ]
    let a = NSAttributedString(string: texte, attributes: attrs)
    let boite = a.boundingRect(with: NSSize(width: 560, height: 200),
                               options: [.usesLineFragmentOrigin, .usesFontLeading])
    a.draw(with: NSRect(x: CGFloat(cx) - 280, y: y(hy) - boite.height,
                        width: 560, height: boite.height),
           options: [.usesLineFragmentOrigin, .usesFontLeading])
}

ecrire("Glissez OpusScreen dans Applications", 20, .semibold, c(17, 38, 42),
       centreEn: L / 2, hautA: 52)
ecrire("Puis, la toute première fois : clic droit sur l’application → Ouvrir.",
       13, .regular, c(92, 116, 118), centreEn: L / 2, hautA: 84)

// ------------------------------------------------------------------ la fleche

// Elle part du bord de l'icone de gauche et s'arrete au bord de celle de droite :
// une fleche qui passe SOUS une icone ne designe plus rien.
let axe = y(196)
let depart: CGFloat = 258, arrivee: CGFloat = 382
let epaisseur: CGFloat = 9
let pointe: CGFloat = 26

let fleche = NSBezierPath()
fleche.move(to: NSPoint(x: depart, y: axe - epaisseur / 2))
fleche.line(to: NSPoint(x: arrivee - pointe, y: axe - epaisseur / 2))
fleche.line(to: NSPoint(x: arrivee - pointe, y: axe - pointe / 2 - 3))
fleche.line(to: NSPoint(x: arrivee, y: axe))
fleche.line(to: NSPoint(x: arrivee - pointe, y: axe + pointe / 2 + 3))
fleche.line(to: NSPoint(x: arrivee - pointe, y: axe + epaisseur / 2))
fleche.line(to: NSPoint(x: depart, y: axe + epaisseur / 2))
fleche.close()
c(23, 190, 177).setFill()
fleche.fill()

// ------------------------------------------------------------------ la signature

ecrire("OpusScreen — luminosité, couleur et accessibilité visuelle",
       11, .regular, c(139, 161, 162), centreEn: L / 2, hautA: 372)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: sortie))
print("  \(sortie)  \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
