import Foundation
import CoreAudio
import AudioToolbox

/// Le volume de sortie, et ce qu'on peut honnetement en faire.
///
/// La version Windows avait ici sa fonction la plus utile et la plus mal comprise :
/// « tout remettre au maximum ». Sous Windows, chaque application memorise son
/// propre curseur dans le mixeur du systeme ; un curseur baisse une fois par
/// megarde le reste pour toujours, et le mixeur est un panneau que peu de gens
/// savent ou trouver. Une video trop faible venait de la bien plus souvent que du
/// volume general.
///
/// **macOS n'a pas de mixeur par application.** Il n'existe aucun volume propre a
/// Safari ou a VLC au niveau du systeme : il n'y a qu'un volume de sortie, et
/// celui que chaque lecteur gere lui-meme, dans sa propre fenetre. Il n'y a donc
/// rien a « recuperer » ici, et pretendre le contraire serait inventer une
/// fonction. Ce qui reste est vrai et utile : le volume general, le silence, et
/// le plafond materiel exprime en decibels.
public enum SystemVolume {

    /// Pour les tests : rien n'est envoye au materiel de la machine qui les execute.
    public static var dryRun = false

    // ------------------------------------------------------------------ peripherique

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)
        guard status == noErr, device != 0 else { return nil }
        return device
    }

    public static var available: Bool { defaultOutputDevice() != nil }

    /// Nom du peripherique de sortie, pour que l'interface dise de quoi elle parle.
    public static var deviceName: String {
        guard let device = defaultOutputDevice() else { return "" }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, ptr)
        }
        return status == noErr ? (name as String) : ""
    }

    // ------------------------------------------------------------------ volume

    private static var mainVolumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    /// Volume general, de 0 a 100. -1 quand il n'y a rien a lire.
    public static func getMaster() -> Double {
        guard let device = defaultOutputDevice() else { return -1 }
        var address = mainVolumeAddress
        guard AudioObjectHasProperty(device, &address) else { return -1 }

        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return -1 }
        return Double(value) * 100.0
    }

    @discardableResult
    public static func setMaster(_ percent: Double) -> Bool {
        if dryRun { return true }
        guard let device = defaultOutputDevice() else { return false }
        var address = mainVolumeAddress
        guard AudioObjectHasProperty(device, &address) else { return false }

        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return false }

        var value = Float32(max(0, min(100, percent)) / 100.0)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    // ------------------------------------------------------------------ silence

    public static var isMuted: Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return false }

        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    @discardableResult
    public static func setMuted(_ muted: Bool) -> Bool {
        if dryRun { return true }
        guard let device = defaultOutputDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return false }

        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    // ------------------------------------------------------------------ plafond

    /// Plafond du materiel, en decibels. Zero decibel est le maximum de la sortie :
    /// c'est la meme limite que le voile qui ne peut retirer de la lumiere sans
    /// jamais en ajouter.
    public static var ceilingDb: Double {
        guard let device = defaultOutputDevice() else { return 0 }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeRangeDecibels,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1)
        guard AudioObjectHasProperty(device, &address) else { return 0 }

        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &range) == noErr else { return 0 }
        return Double(range.mMaximum)
    }

    // ------------------------------------------------------------------ « tout au maximum »

    public struct RaiseResult {
        public var masterRaised = false
        public var wasUnmuted = false
        public var masterBefore: Double = 0
        public var masterAfter: Double = 0

        /// Vrai quand il n'y avait rien a recuperer. Le cas le plus frequent, et
        /// celui qu'il ne faut surtout pas maquiller en succes : annoncer
        /// « c'est fait » quand rien n'a bouge envoie chercher un probleme la
        /// ou il n'y en a pas.
        public var nothingToDo: Bool { !masterRaised && !wasUnmuted }
    }

    @discardableResult
    public static func raiseEverything() -> RaiseResult {
        var r = RaiseResult()
        r.masterBefore = getMaster()

        if isMuted {
            setMuted(false)
            r.wasUnmuted = true
        }

        if r.masterBefore >= 0 && r.masterBefore < 99.5 {
            if setMaster(100) {
                r.masterRaised = true
            }
        }
        r.masterAfter = getMaster()
        return r
    }

    /// Ce que macOS permet, et ce qu'il ne permet pas. Affiche tel quel dans la
    /// page Confort : c'est une explication, pas un message d'erreur.
    public static let platformNote =
        "macOS n'a pas de mixeur par application : il n'existe pas de volume propre a "
      + "chaque logiciel au niveau du systeme, contrairement a Windows. Il n'y a donc rien "
      + "a recuperer ici - seulement le volume de sortie, ci-dessus, et le silence. "
      + "Si une video reste faible alors que le volume general est au maximum, le curseur "
      + "a baisser est dans le lecteur lui-meme.\n\n"
      + "Aller AU-DELA de 100 % est impossible depuis une application ordinaire : la sortie "
      + "declare sa plage en decibels et son maximum vaut 0 dB. C'est la meme limite que le "
      + "voile de PangoBright sur la luminosite - un attenuateur retire du signal, il n'en "
      + "ajoute pas. La luminosite a pu depasser 100 % parce qu'un autre etage existait, la "
      + "table de couleurs de la carte graphique. Le son n'a pas d'equivalent : amplifier "
      + "demanderait de s'inserer dans le flux audio, donc un pilote a installer. Le lecteur "
      + "video, lui, peut le faire sur son propre son - VLC monte a 200 %."
}
