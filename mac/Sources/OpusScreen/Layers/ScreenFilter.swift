import Foundation
import AppKit
import Metal
import QuartzCore
import CoreVideo
import CoreGraphics
import ScreenCaptureKit

/// Niveaux de fenetre de l'application, tous au meme endroit.
///
/// Les quatre surfaces que l'application pose par-dessus le bureau doivent
/// s'empiler dans un ordre precis, et cet ordre est une decision de conception -
/// pas une suite de nombres recopies d'un fichier a l'autre.
public enum WindowLevels {
    private static var shield: Int { Int(CGShieldingWindowLevel()) }

    /// L'image filtree : c'est elle qui remplace le bureau. Tout le reste passe dessus.
    public static var filter: NSWindow.Level { .init(shield - 3) }

    /// Le voile. Pose SUR l'image filtree : assombrir apres avoir corrige les
    /// couleurs, et non l'inverse. Un voile noir est une multiplication, une
    /// correction daltonienne est lineaire : pour les filtres de vision les deux
    /// ordres donnent le meme resultat. Ils ne different que pour l'inversion, ou
    /// assombrir en dernier est le comportement attendu.
    public static var veil: NSWindow.Level { .init(shield - 2) }

    /// Les aides a la vision : anneau du pointeur, etiquette de couleur. Elles
    /// s'adressent a l'oeil, pas a l'image : rien ne doit les recouvrir.
    public static var aid: NSWindow.Level { .init(shield - 1) }

    /// Les rappels de pause et de clignement, au-dessus de tout le reste.
    public static var notice: NSWindow.Level { .init(shield) }
}

/// Le quatrieme etage du pipeline, et la loupe, servis par le meme mecanisme.
///
/// Sur Windows, `MagSetFullscreenColorEffect` et `MagSetFullscreenTransform`
/// vivaient dans la meme bibliotheque et s'appliquaient au meme compositeur : la
/// loupe et la correction du daltonisme se cumulaient sans se gener, ce que la
/// loupe de Windows ne savait pas faire. macOS n'offre ni l'une ni l'autre - ses
/// filtres de couleur d'accessibilite n'acceptent que cinq reglages figes, et sa
/// loupe ignore tout reglage de couleur.
///
/// L'etage est donc reconstruit : ScreenCaptureKit lit l'affichage, un nuanceur
/// Metal applique la matrice 5x5 et l'agrandissement, le resultat est repose dans
/// une fenetre qui couvre l'ecran. Le cumul des deux fonctions est conserve - il
/// est meme ici structurel, puisque c'est la meme passe de calcul.
///
/// Ce que le portage gagne : la matrice est reglable ECRAN PAR ECRAN. Windows
/// n'exposait qu'un effet pour tout le bureau, contrainte que la documentation
/// d'origine signalait comme telle.
///
/// Ce qu'il coute, et qui est dit sans detour :
///   - l'autorisation « Enregistrement de l'ecran » est necessaire ; sans elle
///     l'etage s'annonce indisponible, comme le faisait la version Windows quand
///     `magnification.dll` manquait ;
///   - le pointeur de la souris est dessine par le systeme AU-DESSUS de toutes
///     les fenetres. Il n'est donc pas recolore par la matrice. Sous la loupe, un
///     pointeur agrandi est ajoute a l'image pour que la cible reste visible.
public final class ScreenFilter: NSObject {

    public static let shared = ScreenFilter()

    // ------------------------------------------------------------------ etat

    private var matrices: [CGDirectDisplayID: [Float]] = [:]
    private var zoom: Double = 1.0
    /// Interne plutot que prive : la suite de verification reelle doit pouvoir
    /// constater qu'un ecran a bien recu sa passe de filtrage, et non se
    /// contenter de croire l'indicateur qui dit qu'il aurait du.
    private(set) var nodes: [CGDirectDisplayID: FilterNode] = [:]

    private var device: MTLDevice?
    private var pipeline: MTLRenderPipelineState?
    private var queue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?

    private var metalFailed = false
    private var permissionDenied = false
    private var cursorHidden = false

    /// Vrai quand l'etage peut fonctionner.
    public var available: Bool {
        if metalFailed { return false }
        if DisplayController.dryRun { return true }
        return CGPreflightScreenCaptureAccess()
    }

    /// Ce qui manque, en une phrase. Vide si tout va bien.
    public var unavailableReason: String {
        if metalFailed { return "cette machine n'expose pas de peripherique Metal utilisable" }
        if DisplayController.dryRun { return "" }
        if !CGPreflightScreenCaptureAccess() {
            return "l'autorisation « Enregistrement de l'ecran » n'est pas accordee"
        }
        return ""
    }

    /// Vrai quand au moins un ecran porte une matrice non neutre.
    public var matrixActive: Bool { !matrices.isEmpty }

    /// Vrai quand la loupe agrandit reellement.
    public var magnifying: Bool { zoom > 1.001 }

    private override init() { super.init() }

    // ------------------------------------------------------------------ demande d'autorisation

    /// Demande l'autorisation d'enregistrement de l'ecran.
    ///
    /// macOS ne la montre qu'une fois par installation : au refus, la seule voie
    /// est le panneau des Reglages Systeme, et l'interface y conduit plutot que de
    /// laisser un interrupteur sans effet.
    @discardableResult
    public func requestPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    public static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    // ------------------------------------------------------------------ pilotage

    /// Applique la meme matrice a tous les ecrans.
    @discardableResult
    public func setMatrixEverywhere(_ m: [Float]) -> Bool {
        var wanted: [CGDirectDisplayID: [Float]] = [:]
        for id in Native.activeDisplayIDs() { wanted[id] = m }
        return setMatrices(wanted)
    }

    /// Applique une matrice par ecran. Les ecrans absents du dictionnaire
    /// retrouvent leurs couleurs exactes.
    @discardableResult
    public func setMatrices(_ wanted: [CGDirectDisplayID: [Float]]) -> Bool {
        let identity = ColorMatrixEffect.identity()
        var kept: [CGDirectDisplayID: [Float]] = [:]
        for (id, m) in wanted where m != identity { kept[id] = m }

        matrices = kept
        return refresh()
    }

    /// Remet la matrice identite partout : l'affichage retrouve ses couleurs exactes.
    public func clearMatrix() {
        guard !matrices.isEmpty else { return }
        matrices.removeAll()
        _ = refresh()
    }

    /// Regle l'agrandissement. 1,0 eteint la loupe.
    @discardableResult
    public func setZoom(_ value: Double) -> Bool {
        var z = value
        if z < ScreenMagnifier.minZoom { z = ScreenMagnifier.minZoom }
        if z > ScreenMagnifier.maxZoom { z = ScreenMagnifier.maxZoom }
        zoom = z
        return refresh()
    }

    public var currentZoom: Double { zoom }

    /// Arret inconditionnel, appelable depuis le filet de securite.
    /// Elle ne suppose rien de l'etat interne : un bureau agrandi huit fois ne se
    /// pilote pas mieux qu'un bureau noir.
    public func panicStop() {
        matrices.removeAll()
        zoom = 1.0
        teardownAll()
    }

    public func shutdown() {
        panicStop()
        textureCache = nil
        pipeline = nil
        queue = nil
        device = nil
    }

    // ------------------------------------------------------------------ cycle de vie

    /// Ecrans qui ont besoin d'une passe de filtrage en ce moment.
    private func wantedDisplays() -> Set<CGDirectDisplayID> {
        var wanted = Set<CGDirectDisplayID>()
        if magnifying {
            // La loupe agrandit tout l'affichage, comme le faisait la version
            // Windows : un seul ecran agrandi au milieu d'un bureau a deux ecrans
            // deplace le pointeur d'un monde a l'autre sans prevenir.
            for id in Native.activeDisplayIDs() { wanted.insert(id) }
        }
        for id in matrices.keys { wanted.insert(id) }
        return wanted
    }

    @discardableResult
    private func refresh() -> Bool {
        if DisplayController.dryRun { return true }

        let wanted = wantedDisplays()

        // Rien a faire : on demonte tout, et on ne demande aucune autorisation.
        if wanted.isEmpty {
            teardownAll()
            return true
        }

        guard available else { return false }
        guard ensureMetal() else { return false }

        // Ecrans qui n'ont plus besoin de rien.
        for (id, node) in nodes where !wanted.contains(id) {
            node.stop()
            nodes.removeValue(forKey: id)
        }

        let identity = ColorMatrixEffect.identity()
        for id in wanted {
            let node: FilterNode
            if let existing = nodes[id] {
                node = existing
            } else {
                guard let created = FilterNode(displayID: id, owner: self) else { continue }
                nodes[id] = created
                node = created
            }
            node.matrix = matrices[id] ?? identity
            node.zoom = zoom
            node.start()
        }

        updateCursorVisibility()
        return true
    }

    private func teardownAll() {
        for (_, node) in nodes { node.stop() }
        nodes.removeAll()
        updateCursorVisibility()
    }

    /// Sous la loupe, le pointeur du systeme reste a sa taille normale : il est
    /// dessine au-dessus de toutes les fenetres, la notre comprise. On demande
    /// donc a le masquer, et l'image filtree en dessine un a la bonne echelle.
    /// Si le systeme refuse de le masquer - c'est son droit, l'application n'est
    /// pas au premier plan - les deux coexistent, ce qui reste utilisable.
    private func updateCursorVisibility() {
        let shouldHide = magnifying && !nodes.isEmpty
        if shouldHide && !cursorHidden {
            CGDisplayHideCursor(CGMainDisplayID())
            cursorHidden = true
        } else if !shouldHide && cursorHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            cursorHidden = false
        }
    }

    /// A appeler quand la configuration des ecrans change.
    public func displaysChanged() {
        for (id, node) in nodes where !Native.activeDisplayIDs().contains(id) {
            node.stop()
            nodes.removeValue(forKey: id)
        }
        _ = refresh()
    }

    // ------------------------------------------------------------------ Metal

    /// Interne pour la meme raison : compiler le nuanceur est la seule chose
    /// qui puisse echouer silencieusement sur une machine donnee, et c'est donc
    /// la premiere a verifier.
    @discardableResult
    func ensureMetal() -> Bool {
        if metalFailed { return false }
        if pipeline != nil { return true }

        guard let dev = MTLCreateSystemDefaultDevice() else { metalFailed = true; return false }
        device = dev
        queue = dev.makeCommandQueue()

        // Le nuanceur est compile a l'execution plutot que livre precompile :
        // le compilateur `metal` n'est present qu'avec Xcode, et cette
        // application se construit avec les seuls outils en ligne de commande.
        guard let library = try? dev.makeLibrary(source: ScreenFilter.shaderSource, options: nil) else {
            metalFailed = true
            return false
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "opus_vertex")
        desc.fragmentFunction = library.makeFunction(name: "opus_fragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let state = try? dev.makeRenderPipelineState(descriptor: desc) else {
            metalFailed = true
            return false
        }
        pipeline = state

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &cache)
        textureCache = cache

        return true
    }

    fileprivate var metalDevice: MTLDevice? { device }
    fileprivate var metalQueue: MTLCommandQueue? { queue }
    fileprivate var metalPipeline: MTLRenderPipelineState? { pipeline }
    fileprivate var metalCache: CVMetalTextureCache? { textureCache }

    /// Le nuanceur.
    ///
    /// La matrice est appliquee sur les valeurs TELLES QU'ELLES SONT ENCODEES,
    /// sans passer par le lineaire. Ce n'est pas un oubli : c'est ce que faisait
    /// le compositeur de Windows, c'est ce que fait `ColorMatrixEffect.transform`
    /// qui sert aux apercus et aux tests, et c'est la seule facon que l'apercu de
    /// la page Couleur montre exactement ce que l'ecran affichera. Linearise, le
    /// meme filtre daltonien rendrait des couleurs differentes de celles annoncees
    /// par le comparateur.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float3x3 mix;       // contribution de r, g, b a la sortie
        float3   offset;    // decalages constants de la cinquieme ligne
        float2   uvScale;   // agrandissement
        float2   uvOffset;  // coin superieur gauche de la zone montree
        float2   cursor;    // pointeur, en coordonnees de texture
        float    cursorSize;// 0 = aucun pointeur dessine
        float    pad;
    };

    struct VOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VOut opus_vertex(uint vid [[vertex_id]],
                            constant Uniforms &u [[buffer(0)]]) {
        // Un grand triangle qui deborde de l'ecran : moins de sommets qu'un
        // rectangle, et aucun risque de couture au milieu.
        float2 corner = float2((vid << 1) & 2, vid & 2);
        VOut out;
        out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
        float2 uv = float2(corner.x, 1.0 - corner.y);
        out.uv = u.uvOffset + uv * u.uvScale;
        return out;
    }

    fragment float4 opus_fragment(VOut in [[stage_in]],
                                  texture2d<float> src [[texture(0)]],
                                  constant Uniforms &u [[buffer(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float4 c = src.sample(s, in.uv);

        float3 outRgb = u.mix * c.rgb + u.offset;
        outRgb = clamp(outRgb, 0.0, 1.0);

        // Pointeur agrandi : un chevron simple, trace a la main. Il n'apparait
        // que sous la loupe, ou le pointeur du systeme reste minuscule.
        if (u.cursorSize > 0.0) {
            float2 d = (in.uv - u.cursor) / u.uvScale;
            float2 p = d / u.cursorSize;
            if (p.x >= 0.0 && p.y >= 0.0 && p.y <= 1.0 && p.x <= 0.72) {
                float edge = p.y * 0.72;
                float inner = p.y * 0.52;
                if (p.x <= edge) {
                    float3 ink = (p.x > inner && p.y > 0.12) ? float3(0.0) : float3(1.0);
                    outRgb = mix(outRgb, ink, 0.95);
                }
            }
        }

        return float4(outRgb, 1.0);
    }
    """
}

/// Ce qu'une passe de filtrage doit savoir, en un bloc aligne pour le nuanceur.
struct FilterUniforms {
    var mix: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1))
    var offset: SIMD3<Float> = .zero
    var uvScale: SIMD2<Float> = SIMD2(1, 1)
    var uvOffset: SIMD2<Float> = .zero
    var cursor: SIMD2<Float> = .zero
    var cursorSize: Float = 0
    var pad: Float = 0
}

/// Un ecran filtre : sa capture, sa fenetre, sa passe de rendu.
final class FilterNode: NSObject, SCStreamOutput, SCStreamDelegate {

    let displayID: CGDirectDisplayID
    private weak var owner: ScreenFilter?

    var matrix: [Float] = ColorMatrixEffect.identity()
    var zoom: Double = 1.0

    private var window: NSPanel?
    private var layer: CAMetalLayer?
    private var stream: SCStream?
    private var running = false
    private let sampleQueue = DispatchQueue(label: "opusscreen.filter.samples", qos: .userInteractive)

    init?(displayID: CGDirectDisplayID, owner: ScreenFilter) {
        self.displayID = displayID
        self.owner = owner
        super.init()
        guard buildWindow() else { return nil }
    }

    // ------------------------------------------------------------------ fenetre

    private func buildWindow() -> Bool {
        guard let device = owner?.metalDevice else { return false }

        let bounds = Native.quartzToAppKit(CGDisplayBounds(displayID))
        let panel = NSPanel(contentRect: bounds,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = WindowLevels.filter
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        // Invisible aux captures d'ecran, donc invisible a NOTRE PROPRE capture :
        // sans cela le filtre se filmerait lui-meme et l'image partirait en
        // boucle au bout de quelques images. C'est la meme precaution que
        // `WDA_EXCLUDEFROMCAPTURE` sur Windows, et elle rend au passage les
        // captures de l'utilisateur propres.
        panel.sharingType = .none

        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: bounds.size))
        view.wantsLayer = true

        let metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }?.backingScaleFactor ?? 2
        metalLayer.drawableSize = CGSize(width: CGFloat(CGDisplayPixelsWide(displayID)),
                                         height: CGFloat(CGDisplayPixelsHigh(displayID)))
        // Les valeurs traversent sans retouche : ce que le nuanceur ecrit est ce
        // que la dalle recoit. Une conversion de profil ici fausserait la matrice.
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)

        view.layer = metalLayer
        panel.contentView = view

        window = panel
        layer = metalLayer
        SafetyGuard.registerOverlay(panel)
        return true
    }

    // ------------------------------------------------------------------ capture

    func start() {
        guard !running else { return }
        running = true

        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self = self, self.running else { return }
            guard let content = content, error == nil,
                  let display = content.displays.first(where: { $0.displayID == self.displayID })
            else {
                DispatchQueue.main.async { self.running = false }
                return
            }

            // Aucune exclusion explicite : nos propres fenetres de filtrage, de
            // voile, d'anneau et d'etiquette declarent toutes `sharingType = .none`
            // et sont donc deja absentes de la capture. La fenetre de reglages,
            // elle, est bien capturee - il serait incoherent qu'une correction
            // daltonienne s'applique a tout l'ecran sauf a la fenetre qui la regle.
            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.width = CGDisplayPixelsWide(self.displayID)
            config.height = CGDisplayPixelsHigh(self.displayID)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            config.queueDepth = 3
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.showsCursor = false
            config.scalesToFit = false

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            do {
                try stream.addStreamOutput(self, type: .screen,
                                           sampleHandlerQueue: self.sampleQueue)
                stream.startCapture { err in
                    if err != nil {
                        DispatchQueue.main.async { self.running = false }
                        return
                    }
                    DispatchQueue.main.async {
                        self.window?.orderFrontRegardless()
                    }
                }
                self.stream = stream
            } catch {
                DispatchQueue.main.async { self.running = false }
            }
        }
    }

    func stop() {
        running = false
        stream?.stopCapture { _ in }
        stream = nil
        if let w = window {
            SafetyGuard.unregisterOverlay(w)
            w.orderOut(nil)
            w.close()
        }
        window = nil
        layer = nil
    }

    // ------------------------------------------------------------------ rendu

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, running else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        render(pixelBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.running else { return }
            // La capture s'est arretee toute seule - changement de resolution,
            // verrouillage de session. On la relance, sinon l'ecran resterait fige
            // sur la derniere image recue, ce qui est bien pire qu'aucun filtre.
            self.running = false
            self.stream = nil
            self.start()
        }
    }

    private func render(_ pixelBuffer: CVPixelBuffer) {
        guard let owner = owner,
              let cache = owner.metalCache,
              let pipeline = owner.metalPipeline,
              let queue = owner.metalQueue,
              let layer = layer else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture)
        guard status == kCVReturnSuccess,
              let cvTexture = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else { return }

        guard let drawable = layer.nextDrawable() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        guard let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        var uniforms = buildUniforms()

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FilterUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FilterUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        buffer.present(drawable)
        buffer.commit()
    }

    /// Traduit la matrice 5x5 et l'agrandissement en ce que le nuanceur attend.
    ///
    /// La convention de la matrice est celle de la version Windows - le pixel est
    /// un vecteur LIGNE. Metal multiplie une matrice par un vecteur COLONNE : les
    /// colonnes du `float3x3` sont donc les lignes de la matrice d'origine. C'est
    /// exactement le genre de detail qui, mal traite, rend des couleurs plausibles
    /// et fausses - d'ou la transposition explicite, et le test qui la verifie.
    private func buildUniforms() -> FilterUniforms {
        var u = FilterUniforms()

        u.mix = (SIMD3(matrix[0], matrix[1], matrix[2]),
                 SIMD3(matrix[5], matrix[6], matrix[7]),
                 SIMD3(matrix[10], matrix[11], matrix[12]))

        // Cinquieme ligne (constantes) et quatrieme (alpha, toujours 1 ici).
        u.offset = SIMD3(matrix[20] + matrix[15],
                         matrix[21] + matrix[16],
                         matrix[22] + matrix[17])

        let bounds = CGDisplayBounds(displayID)
        if zoom > 1.001 {
            let visible = 1.0 / zoom
            let cursor = Native.cursorPosition()

            // Le pointeur est ramene dans CET ecran : sur un bureau a deux
            // ecrans, la zone montree ne doit jamais deborder de sa dalle.
            let cx = min(max(cursor.x, bounds.minX), bounds.maxX)
            let cy = min(max(cursor.y, bounds.minY), bounds.maxY)
            let relX = bounds.width > 0 ? (cx - bounds.minX) / bounds.width : 0.5
            let relY = bounds.height > 0 ? (cy - bounds.minY) / bounds.height : 0.5

            var ox = relX - visible / 2
            var oy = relY - visible / 2
            ox = min(max(ox, 0), 1 - visible)
            oy = min(max(oy, 0), 1 - visible)

            u.uvScale = SIMD2(Float(visible), Float(visible))
            u.uvOffset = SIMD2(Float(ox), Float(oy))

            // Pointeur dessine : sa taille est donnee en fraction de texture, pour
            // qu'il garde la meme taille apparente quel que soit l'agrandissement.
            let cursorHeightPixels = 26.0 * zoom
            u.cursor = SIMD2(Float(relX), Float(relY))
            u.cursorSize = Float(cursorHeightPixels / max(1, bounds.height))
        } else {
            u.uvScale = SIMD2(1, 1)
            u.uvOffset = SIMD2(0, 0)
            u.cursorSize = 0
        }

        return u
    }
}
