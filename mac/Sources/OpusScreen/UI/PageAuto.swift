import Foundation
import AppKit

/// Tout ce qui decide a votre place : l'heure, et le contenu affiche.
///
/// f.lux ne connait que l'heure. Gammy ne connait que le contenu. Les avoir tous
/// les deux, et pouvoir les combiner, est ce qui manque partout ailleurs.
public final class PageAuto: SettingsPage {

    private var mode: ComboRow!
    private var preset: ComboRow!
    private var bedtime: SliderRow!
    private var fixedDay: SliderRow!
    private var fixedNight: SliderRow!
    private var transition: SliderRow!
    private var latitude: SliderRow!
    private var longitude: SliderRow!
    private var affectsBrightness: ToggleRow!
    private var dayBright: SliderRow!
    private var nightBright: SliderRow!
    private var status: LabelView!

    private var adaptive: ToggleRow!
    private var adMin: SliderRow!
    private var adMax: SliderRow!
    private var adReact: SliderRow!
    private var adInterval: SliderRow!
    private var adStatus: LabelView!

    public var engine: ContentAdaptive?

    public override var pageTitle: String { "Automatisme" }
    public override var pageSubtitle: String { "Suivre l'heure, et le contenu affiche" }

    private static let modeNames = [
        "Manuel - rien d'automatique",
        "Suivre le soleil (calcul local)",
        "Horaires fixes",
    ]

    public override init(_ s: Settings, _ d: DisplayController, _ push: @escaping () -> Void) {
        super.init(s, d, push)

        section("Rythme de la journee")

        mode = ComboRow("Mode", PageAuto.modeNames)
        mode.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.schedule = ScheduleMode(rawValue: max(0, self.mode.selectedIndex)) ?? .manual
            self.syncAndLayout()
            self.commit()
        }
        add(mode, Theme.spaceSm)

        preset = ComboRow("Ambiance", Preset.builtIn().map { $0.name })
        preset.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.presetName = self.preset.selectedText
            self.updateStatus()
            self.commit()
        }
        add(preset, Theme.spaceSm)

        note("Ces ambiances sont celles de f.lux, relevees dans son propre fichier de "
           + "configuration : jour, soiree et nuit profonde y ont chacun leur temperature.")

        status = UiKit.caption("")
        add(status, Theme.spaceSm)

        section("Horaires")

        bedtime = SliderRow("Heure du coucher", 18, 30, "h")
        bedtime.hint = "bascule vers la teinte la plus chaude"
        bedtime.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.bedtimeHour = PageAuto.wrap(self.bedtime.value)
            self.updateHourHints()
            self.commitNoSave()
        }
        bedtime.onCommit = { [weak self] in self?.commit() }
        add(bedtime, Theme.spaceSm)

        fixedDay = SliderRow("Debut de journee", 0, 23.5, "h")
        fixedDay.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.fixedDayHour = self.fixedDay.value
            self.updateHourHints()
            self.commitNoSave()
        }
        fixedDay.onCommit = { [weak self] in self?.commit() }
        add(fixedDay, Theme.spaceSm)

        fixedNight = SliderRow("Debut de soiree", 0, 23.5, "h")
        fixedNight.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.fixedNightHour = self.fixedNight.value
            self.updateHourHints()
            self.commitNoSave()
        }
        fixedNight.onCommit = { [weak self] in self?.commit() }
        add(fixedNight, Theme.spaceSm)

        transition = SliderRow("Duree du fondu", 5, 180, "min")
        transition.hint = "etalement de la bascule"
        transition.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.transitionMinutes = Int(self.transition.value)
            self.commitNoSave()
        }
        transition.onCommit = { [weak self] in self?.commit() }
        add(transition, Theme.spaceSm)

        section("Position")

        latitude = SliderRow("Latitude", -66, 66, "")
        latitude.setFormat("0.00")
        latitude.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.latitude = self.latitude.value
            self.updateStatus()
            self.commitNoSave()
        }
        latitude.onCommit = { [weak self] in self?.commit() }
        add(latitude, Theme.spaceSm)

        longitude = SliderRow("Longitude", -180, 180, "")
        longitude.setFormat("0.00")
        longitude.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.longitude = self.longitude.value
            self.updateStatus()
            self.commitNoSave()
        }
        longitude.onCommit = { [weak self] in self?.commit() }
        add(longitude, Theme.spaceSm)

        let detect = DarkButton("Deduire de mon fuseau horaire") { [weak self] in
            guard let self = self else { return }
            let hours = Double(TimeZone.current.secondsFromGMT()) / 3600.0
            self.settings.longitude = (hours * 15 * 100).rounded() / 100
            self.syncAndLayout()
            self.commit()
        }
        detect.frame.size.height = Theme.minTarget
        add(detect, Theme.spaceSm)

        note("Le lever et le coucher sont calcules sur place, avec l'algorithme solaire "
           + "de la NOAA. Aucune connexion, aucune position envoyee nulle part - et aucune "
           + "autorisation de localisation demandee, contrairement a f.lux qui interroge "
           + "un service en ligne.")

        section("Luminosite selon l'heure")

        affectsBrightness = ToggleRow("Faire varier aussi la luminosite",
                                      "f.lux ne change que la couleur ; il fallait baisser la luminosite a la main.")
        affectsBrightness.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.scheduleAffectsBrightness = self.affectsBrightness.isChecked
            self.updateEnabledStates()
            self.commit()
        }
        add(affectsBrightness, Theme.spaceSm)

        dayBright = SliderRow("Luminosite de jour", GammaEngine.minBrightness, GammaEngine.maxBrightness, "%")
        dayBright.mark(at: 100, warnAbove: 135)
        dayBright.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.dayBrightness = self.dayBright.value
            self.commitNoSave()
        }
        dayBright.onCommit = { [weak self] in self?.commit() }
        add(dayBright, Theme.spaceSm)

        nightBright = SliderRow("Luminosite de nuit", GammaEngine.minBrightness, GammaEngine.maxBrightness, "%")
        nightBright.mark(at: 100, warnAbove: 135)
        nightBright.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.nightBrightness = self.nightBright.value
            self.commitNoSave()
        }
        nightBright.onCommit = { [weak self] in self?.commit() }
        add(nightBright, Theme.spaceSm)

        section("Adaptation au contenu")

        adaptive = ToggleRow("Suivre ce qui est affiche",
                             "Une page blanche fait baisser l'ecran, une scene sombre le fait remonter.")
        adaptive.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.adaptiveEnabled = self.adaptive.isChecked
            self.updateEnabledStates()
            self.commit()
        }
        add(adaptive, Theme.spaceSm)

        adMin = SliderRow("Plancher", GammaEngine.minBrightness, 100, "%")
        adMin.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.adaptiveMin = self.adMin.value
            self.pushEngine()
            self.commitNoSave()
        }
        adMin.onCommit = { [weak self] in self?.commit() }
        add(adMin, Theme.spaceSm)

        adMax = SliderRow("Plafond", 50, GammaEngine.maxBrightness, "%")
        adMax.mark(at: 100, warnAbove: 135)
        adMax.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.adaptiveMax = self.adMax.value
            self.pushEngine()
            self.commitNoSave()
        }
        adMax.onCommit = { [weak self] in self?.commit() }
        add(adMax, Theme.spaceSm)

        adReact = SliderRow("Reactivite", 1, 10, "")
        adReact.hint = "au-dela de 6, l'ecran respire visiblement"
        adReact.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.adaptiveReactivity = self.adReact.value
            self.pushEngine()
            self.commitNoSave()
        }
        adReact.onCommit = { [weak self] in self?.commit() }
        add(adReact, Theme.spaceSm)

        adInterval = SliderRow("Intervalle de mesure", 300, 5000, "ms")
        adInterval.onChange = { [weak self] in
            guard let self = self, !self.loading else { return }
            self.settings.adaptiveIntervalMs = Int(self.adInterval.value)
            self.pushEngine()
            self.commitNoSave()
        }
        adInterval.onCommit = { [weak self] in self?.commit() }
        add(adInterval, Theme.spaceSm)

        adStatus = UiKit.caption("")
        add(adStatus, Theme.spaceSm)

        note("La mesure est prise sur la memoire d'image, donc avant que la carte graphique "
           + "n'applique nos reglages, et nos propres fenetres en sont exclues : "
           + "l'automatisme ne peut donc pas se mesurer lui-meme et partir en oscillation.")
    }

    required init?(coder: NSCoder) { fatalError() }

    private func pushEngine() {
        guard let engine = engine else { return }
        engine.minBrightness = settings.adaptiveMin
        engine.maxBrightness = settings.adaptiveMax
        engine.reactivity = settings.adaptiveReactivity
        engine.intervalMs = settings.adaptiveIntervalMs
        engine.reschedule()
    }

    private static func wrap(_ h: Double) -> Double { h >= 24 ? h - 24 : h }

    private func updateHourHints() {
        bedtime.hint = SolarClock.formatHour(settings.bedtimeHour)
        fixedDay.hint = SolarClock.formatHour(settings.fixedDayHour)
        fixedNight.hint = SolarClock.formatHour(settings.fixedNightHour)
    }

    private func updateStatus() {
        let r = Scheduler.evaluate(settings, Date())
        var text = Scheduler.describe(settings, r)
        if !r.sunValid && settings.schedule == .solar {
            text += "  (le soleil ne se leve ou ne se couche pas ici aujourd'hui)"
        }
        status.text = text
    }

    private func updateEnabledStates() {
        let solar = settings.schedule == .solar
        let fixedH = settings.schedule == .fixedHours
        let auto = solar || fixedH

        preset.isEnabled = auto
        bedtime.isEnabled = auto
        transition.isEnabled = auto
        fixedDay.isEnabled = fixedH
        fixedNight.isEnabled = fixedH
        latitude.isEnabled = solar
        longitude.isEnabled = solar

        affectsBrightness.isEnabled = auto
        let sb = auto && settings.scheduleAffectsBrightness
        dayBright.isEnabled = sb
        nightBright.isEnabled = sb

        let ad = settings.adaptiveEnabled
        adMin.isEnabled = ad
        adMax.isEnabled = ad
        adReact.isEnabled = ad
        adInterval.isEnabled = ad

        if ad && settings.scheduleAffectsBrightness && auto {
            adStatus.text = "L'adaptation au contenu a la main sur la luminosite ; "
                          + "la planification ne pilote alors que la couleur."
        } else if ad {
            if let engine = engine, engine.isRunning {
                adStatus.text = String(format: "Actif. Derniere mesure : %.0f %% de luminance a l'ecran.",
                                       engine.lastMeasuredLuminance * 100)
            } else {
                adStatus.text = "Actif."
            }
        } else {
            adStatus.text = "Inactif : la luminosite ne bouge que sur votre commande."
        }
    }

    public override func sync() {
        loading = true
        defer { loading = false }

        mode.selectedIndex = settings.schedule.rawValue
        let all = Preset.builtIn()
        preset.selectedIndex = all.firstIndex(where: { $0.name == settings.presetName }) ?? 0

        bedtime.setValueSilent(settings.bedtimeHour < 18 ? settings.bedtimeHour + 24 : settings.bedtimeHour)
        fixedDay.setValueSilent(settings.fixedDayHour)
        fixedNight.setValueSilent(settings.fixedNightHour)
        transition.setValueSilent(Double(settings.transitionMinutes))
        latitude.setValueSilent(settings.latitude)
        longitude.setValueSilent(settings.longitude)

        affectsBrightness.setCheckedSilent(settings.scheduleAffectsBrightness)
        dayBright.setValueSilent(settings.dayBrightness)
        nightBright.setValueSilent(settings.nightBrightness)

        adaptive.setCheckedSilent(settings.adaptiveEnabled)
        adMin.setValueSilent(settings.adaptiveMin)
        adMax.setValueSilent(settings.adaptiveMax)
        adReact.setValueSilent(settings.adaptiveReactivity)
        adInterval.setValueSilent(Double(settings.adaptiveIntervalMs))

        updateHourHints()
        updateStatus()
        updateEnabledStates()
    }
}
