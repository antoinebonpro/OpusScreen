import Foundation

/// Ce que la planification impose a un instant donne.
public struct ScheduleResult {
    public var kelvin: Int = 6500
    public var brightness: Double = 100
    public var brightnessApplies = false
    public var phase: DayPhase = .day
    public var sunrise: Double = 7
    public var sunset: Double = 19
    public var sunValid = false
    public init() {}
}

/// Traduit l'heure qu'il est en consigne de couleur et, si l'utilisateur le
/// souhaite, de luminosite.
///
/// f.lux ne fait varier que la couleur. Faire aussi descendre la luminosite le soir
/// est ce qui manque le plus quand on utilise les deux applications d'origine cote
/// a cote : il fallait bouger deux reglages a la main.
public enum Scheduler {

    public static func evaluate(_ s: Settings, _ now: Date) -> ScheduleResult {
        var r = ScheduleResult()
        r.kelvin = s.current.kelvin
        r.brightness = s.current.brightness
        r.brightnessApplies = false
        r.phase = .day

        let preset = findPreset(s.presetName)

        var sunrise = 7.0, sunset = 19.0
        if let t = SolarClock.sunTimes(now, s.latitude, s.longitude) {
            sunrise = t.sunrise; sunset = t.sunset; r.sunValid = true
        } else {
            r.sunValid = false
        }

        if s.schedule == .fixedHours {
            sunrise = s.fixedDayHour
            sunset = s.fixedNightHour
            r.sunValid = true
        } else if !r.sunValid {
            // Nuit ou jour polaire : on retombe sur des horaires raisonnables.
            sunrise = 7.0
            sunset = 19.0
        }

        r.sunrise = sunrise
        r.sunset = sunset

        if s.schedule == .manual { return r }

        let fade = max(5.0, Double(s.transitionMinutes)) / 60.0
        let h = SolarClock.hourOfDay(now)

        let interpolated = interpolate(preset, h, sunrise, sunset, s.bedtimeHour, fade)
        r.kelvin = interpolated.kelvin
        r.phase = interpolated.phase

        if s.scheduleAffectsBrightness {
            r.brightnessApplies = true
            r.brightness = interpolateBrightness(s, h, sunrise, sunset, fade, r.phase)
        }

        return r
    }

    private static func interpolate(_ preset: Preset, _ h: Double, _ sunrise: Double,
                                    _ sunset: Double, _ bedtime: Double, _ fade: Double)
        -> (kelvin: Int, phase: DayPhase) {

        if SolarClock.isBetweenWrapped(h, bedtime, sunrise) { return (preset.late, .late) }

        if h >= sunset - fade && h < sunset + fade {
            return (SolarClock.lerp(preset.day, preset.night, (h - (sunset - fade)) / (2 * fade)), .sunset)
        }

        if h >= sunrise && h < sunrise + fade {
            return (SolarClock.lerp(preset.night, preset.day, (h - sunrise) / fade), .sunset)
        }

        if h >= sunset + fade || h < sunrise { return (preset.night, .night) }

        return (preset.day, .day)
    }

    private static func interpolateBrightness(_ s: Settings, _ h: Double, _ sunrise: Double,
                                              _ sunset: Double, _ fade: Double, _ phase: DayPhase) -> Double {
        let day = s.dayBrightness, night = s.nightBrightness

        if phase == .day { return day }
        if phase == .night || phase == .late { return night }

        // En transition, on suit la meme rampe que la couleur.
        if h >= sunset - fade && h < sunset + fade {
            return day + (night - day) * ((h - (sunset - fade)) / (2 * fade))
        }
        if h >= sunrise && h < sunrise + fade {
            return night + (day - night) * ((h - sunrise) / fade)
        }

        return day
    }

    public static func findPreset(_ name: String) -> Preset {
        for p in Preset.builtIn() where p.name == name { return p }
        return Preset.builtIn()[0]
    }

    /// Resume lisible de l'etat de la planification, pour l'interface.
    public static func describe(_ s: Settings, _ r: ScheduleResult) -> String {
        if s.schedule == .manual { return "Mode manuel : les curseurs commandent seuls." }

        let times = s.schedule == .fixedHours
            ? "Jour \(SolarClock.formatHour(r.sunrise)) - nuit \(SolarClock.formatHour(r.sunset))"
            : "Lever \(SolarClock.formatHour(r.sunrise)) - coucher \(SolarClock.formatHour(r.sunset))"

        return "\(times) - actuellement : \(SolarClock.describePhase(r.phase)) (\(r.kelvin) K)"
    }
}
