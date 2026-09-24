import Foundation
import AppKit

/// Confort visuel : pauses regulieres, clignement, son et temps d'ecran.
public final class PageComfort: SettingsPage {

    private var enabled: ToggleRow!
    private var interval: SliderRow!
    private var duration: SliderRow!
    private var dim: ToggleRow!
    private var sound: ToggleRow!
    private var blink: ToggleRow!
    private var blinkInterval: SliderRow!
    private var volume: SliderRow!
    private var volumeNote: LabelView!
    private var stats: LabelView!
    private var raiseButton: DarkButton!

    public var reminder: BreakReminder?

    public override var pageTitle: String { "Confort" }
    public override var pageSubtitle: String { "Pauses oculaires et temps d'ecran" }

    public override init(_ s: Settings, _ d: DisplayController, _ push: @escaping () -> Void) {
        super.init(s, d, push)

        section("Pauses pour les yeux")

        enabled = ToggleRow("Rappeler de faire une pause",
                            "Regle 20-20-20 : toutes les 20 minutes, regarder a 6 metres pendant 20 secondes.")
        enabled.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.breaksEnabled = self.enabled.isChecked
            self.pushToReminder()
            self.updateStates()
            self.commit()
        }
        add(enabled, Theme.spaceSm)

        interval = SliderRow("Intervalle", 5, 90, "min")
        interval.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.breakIntervalMinutes = Int(self.interval.value)
            self.pushToReminder()
            self.commitNoSave()
        }
        interval.onCommit = { [weak self] in self?.commit() }
        add(interval, Theme.spaceSm)

        duration = SliderRow("Duree de la pause", 5, 300, "s")
        duration.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.breakDurationSeconds = Int(self.duration.value)
            self.pushToReminder()
            self.commitNoSave()
        }
        duration.onCommit = { [weak self] in self?.commit() }
        add(duration, Theme.spaceSm)

        dim = ToggleRow("Assombrir pendant la pause",
                        "Rend le rappel difficile a ignorer sans bloquer le travail en cours.")
        dim.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.breakDim = self.dim.isChecked
            self.pushToReminder()
            self.commit()
        }
        add(dim, Theme.spaceSm)

        sound = ToggleRow("Signal sonore", nil)
        sound.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.breakSound = self.sound.isChecked
            self.pushToReminder()
            self.commit()
        }
        add(sound, Theme.spaceSm)

        let now = DarkButton("Faire une pause maintenant") { [weak self] in
            self?.reminder?.triggerBreak()
        }
        now.frame.size.height = Theme.minTarget
        add(now, Theme.spaceMd)

        section("Clignement")

        blink = ToggleRow("Rappeler de cligner des yeux",
                          "Un bandeau minuscule, trois secondes, sans interrompre ce qui est en cours.")
        blink.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.blinkReminders = self.blink.isChecked
            self.pushToReminder()
            self.updateStates()
            self.commit()
        }
        add(blink, Theme.spaceSm)

        blinkInterval = SliderRow("Intervalle", 1, 30, "min")
        blinkInterval.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.blinkIntervalMinutes = Int(self.blinkInterval.value)
            self.pushToReminder()
            self.commitNoSave()
        }
        blinkInterval.onCommit = { [weak self] in self?.commit() }
        add(blinkInterval, Theme.spaceSm)

        let blinkNow = DarkButton("Voir le rappel maintenant") { [weak self] in
            self?.reminder?.triggerBlink()
        }
        blinkNow.frame.size.height = Theme.minTarget
        add(blinkNow, Theme.spaceSm)

        note("Devant un ecran, la frequence de clignement chute de plus de moitie et le "
           + "clignement devient souvent incomplet : c'est la premiere cause de secheresse "
           + "oculaire au travail, et elle pese davantage sur les yeux deja fragiles. "
           + "Le rappel n'attend aucune reponse et disparait tout seul.")

        section("Son")

        volume = SliderRow("Volume general", 0, 100, "%")
        volume.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            SystemVolume.setMaster(self.volume.value)
            self.updateVolumeNote()
        }
        add(volume, Theme.spaceSm)

        raiseButton = DarkButton("Remettre le son au maximum") { [weak self] in
            self?.onRaiseVolume()
        }
        raiseButton.frame.size.height = Theme.minTarget
        add(raiseButton, Theme.spaceSm)

        volumeNote = UiKit.caption("")
        add(volumeNote, Theme.spaceXs)

        note(SystemVolume.platformNote)

        section("Suivi")

        stats = UiKit.caption("")
        add(stats, Theme.spaceSm)

        let reset = DarkButton("Remettre le compteur a zero") { [weak self] in
            self?.reminder?.resetSession()
            self?.updateStats()
        }
        reset.frame.size.height = Theme.minTarget
        add(reset, Theme.spaceSm)

        note("Le rappel s'affiche sans jamais prendre le focus : il ne peut ni "
           + "interrompre une frappe, ni faire perdre une saisie en cours.")
    }

    required init?(coder: NSCoder) { fatalError() }

    // ------------------------------------------------------------------ son

    private func onRaiseVolume() {
        guard SystemVolume.available else {
            volumeNote.text = "Aucune sortie audio utilisable sur cette machine."
            return
        }

        let r = SystemVolume.raiseEverything()
        syncAndLayout()

        if r.nothingToDo {
            // Le cas le plus frequent, et celui qu'il ne faut surtout pas maquiller
            // en succes : annoncer « c'est fait » quand rien n'a bouge enverrait
            // chercher un probleme la ou il n'y en a pas.
            volumeNote.text = "Le son etait deja au maximum, et il n'etait pas coupe. Il n'y avait "
                            + "rien a recuperer, et il ne peut pas monter plus haut cote macOS. "
                            + "Si une video reste faible, c'est dans le lecteur lui-meme qu'il "
                            + "faut chercher."
            return
        }

        var parts: [String] = []
        if r.wasUnmuted { parts.append("Le son etait coupe : il est retabli.") }
        if r.masterRaised {
            parts.append(String(format: "Volume general : %.0f %% -> %.0f %%.", r.masterBefore, r.masterAfter))
        }
        volumeNote.text = parts.joined(separator: " ")
    }

    private func updateVolumeNote() {
        guard SystemVolume.available else {
            volumeNote.text = "Aucune sortie audio utilisable sur cette machine."
            volume.isEnabled = false
            raiseButton.isEnabled = false
            return
        }
        let device = SystemVolume.deviceName
        let ceiling = SystemVolume.ceilingDb
        var text = device.isEmpty ? "Sortie audio active." : "Sortie : " + device + "."
        if ceiling != 0 { text += String(format: " Plafond du materiel : %.1f dB.", ceiling) }
        if SystemVolume.isMuted { text += " Le son est actuellement coupe." }
        volumeNote.text = text
    }

    private func pushToReminder() {
        guard let r = reminder else { return }
        r.enabled = settings.breaksEnabled
        r.intervalMinutes = max(1, settings.breakIntervalMinutes)
        r.durationSeconds = max(5, settings.breakDurationSeconds)
        r.dimDuringBreak = settings.breakDim
        r.playSound = settings.breakSound
        r.blinkReminders = settings.blinkReminders
        r.blinkIntervalMinutes = max(1, settings.blinkIntervalMinutes)
    }

    private func updateStates() {
        let on = settings.breaksEnabled
        interval.isEnabled = on
        duration.isEnabled = on
        dim.isEnabled = on
        sound.isEnabled = on
        blinkInterval.isEnabled = settings.blinkReminders
    }

    public func updateStats() {
        guard let r = reminder else { stats.text = ""; return }
        let t = r.screenTime
        let time = t >= 3600
            ? String(format: "%d h %02d min", Int(t / 3600), Int(t.truncatingRemainder(dividingBy: 3600) / 60))
            : String(format: "%d min", Int(t / 60))

        let next = settings.breaksEnabled
            ? "Prochaine pause dans \(Int(r.untilNextBreak / 60) + 1) min."
            : "Les rappels sont desactives."

        stats.text = "Ecran allume depuis \(time) pour cette session.\n" + next
    }

    public override func sync() {
        loading = true
        defer { loading = false }

        enabled.setCheckedSilent(settings.breaksEnabled)
        interval.setValueSilent(Double(settings.breakIntervalMinutes))
        duration.setValueSilent(Double(settings.breakDurationSeconds))
        dim.setCheckedSilent(settings.breakDim)
        sound.setCheckedSilent(settings.breakSound)
        blink.setCheckedSilent(settings.blinkReminders)
        blinkInterval.setValueSilent(Double(settings.blinkIntervalMinutes))

        let master = SystemVolume.getMaster()
        if master >= 0 { volume.setValueSilent(master) }
        updateVolumeNote()

        pushToReminder()
        updateStates()
        updateStats()
    }
}
