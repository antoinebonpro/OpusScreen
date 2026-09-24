import Foundation

public enum DayPhase { case day, sunset, night, late }

/// Calcul du lever et du coucher du soleil, puis de la temperature de couleur qui
/// convient a l'instant present.
///
/// f.lux interroge un service en ligne pour la position ; ici tout est calcule sur
/// place avec l'algorithme solaire de la NOAA : aucune connexion, aucune donnee
/// envoyee nulle part. C'est aussi ce qui evite a l'application de demander
/// l'autorisation de localisation, qu'elle n'a aucune raison d'obtenir.
public enum SolarClock {

    /// Duree du fondu autour du coucher du soleil.
    private static let transitionMinutes = 60.0

    /// Heures locales du lever et du coucher, en heures decimales (13.5 = 13 h 30).
    /// Renvoie false aux latitudes ou le soleil ne se leve ou ne se couche pas.
    public static func sunTimes(_ localDate: Date, _ latitude: Double, _ longitude: Double)
        -> (sunrise: Double, sunset: Double)? {

        let jd = julianDay(localDate)
        let t = (jd - 2451545.0) / 36525.0

        let meanLong = mod360(280.46646 + t * (36000.76983 + t * 0.0003032))
        let meanAnom = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccent = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)

        let center = sin(rad(meanAnom)) * (1.914602 - t * (0.004817 + 0.000014 * t))
                   + sin(rad(2 * meanAnom)) * (0.019993 - 0.000101 * t)
                   + sin(rad(3 * meanAnom)) * 0.000289

        let trueLong = meanLong + center
        let omega = 125.04 - 1934.136 * t
        let appLong = trueLong - 0.00569 - 0.00478 * sin(rad(omega))

        let meanObliq = 23.0 + (26.0 + ((21.448 - t * (46.815 + t * (0.00059 - t * 0.001813)))) / 60.0) / 60.0
        let obliq = meanObliq + 0.00256 * cos(rad(omega))

        let declination = deg(asin(sin(rad(obliq)) * sin(rad(appLong))))

        let y = tan(rad(obliq / 2)) * tan(rad(obliq / 2))
        let eqTime = 4 * deg(
              y * sin(2 * rad(meanLong))
            - 2 * eccent * sin(rad(meanAnom))
            + 4 * eccent * y * sin(rad(meanAnom)) * cos(2 * rad(meanLong))
            - 0.5 * y * y * sin(4 * rad(meanLong))
            - 1.25 * eccent * eccent * sin(2 * rad(meanAnom)))

        // 90,833 deg : centre du disque solaire + refraction atmospherique
        let cosHa = (cos(rad(90.833)) / (cos(rad(latitude)) * cos(rad(declination))))
                  - tan(rad(latitude)) * tan(rad(declination))

        if cosHa > 1.0 || cosHa < -1.0 { return nil }   // nuit ou jour polaire

        let hourAngle = deg(acos(cosHa))

        let utcOffset = Double(TimeZone.current.secondsFromGMT(for: localDate)) / 60.0
        let solarNoonMin = 720 - 4 * longitude - eqTime + utcOffset

        let sunrise = wrap24((solarNoonMin - hourAngle * 4) / 60.0)
        let sunset = wrap24((solarNoonMin + hourAngle * 4) / 60.0)
        return (sunrise, sunset)
    }

    /// Temperature a appliquer maintenant, fondus compris.
    /// `bedtimeHour` marque le passage a la teinte « tard » du preset.
    public static func currentKelvin(_ preset: Preset, _ latitude: Double, _ longitude: Double,
                                     _ bedtimeHour: Double, _ now: Date) -> (kelvin: Int, phase: DayPhase) {
        var sunrise = 7.0, sunset = 19.0
        if let t = sunTimes(now, latitude, longitude) { sunrise = t.sunrise; sunset = t.sunset }

        let h = hourOfDay(now)
        let fade = transitionMinutes / 60.0

        // --- nuit profonde : entre l'heure du coucher et le lever du soleil ---
        if isBetweenWrapped(h, bedtimeHour, sunrise) { return (preset.late, .late) }

        // --- fondu du coucher de soleil ---
        if h >= sunset - fade && h < sunset + fade {
            let p = (h - (sunset - fade)) / (2 * fade)   // 0 -> 1
            return (lerp(preset.day, preset.night, p), .sunset)
        }

        // --- fondu du lever de soleil ---
        if h >= sunrise && h < sunrise + fade {
            let p = (h - sunrise) / fade
            return (lerp(preset.night, preset.day, p), .sunset)
        }

        if h >= sunset + fade || h < sunrise { return (preset.night, .night) }

        return (preset.day, .day)
    }

    public static func describePhase(_ p: DayPhase) -> String {
        switch p {
        case .day: return "journee"
        case .sunset: return "transition"
        case .night: return "soiree"
        case .late: return "nuit"
        }
    }

    public static func formatHour(_ raw: Double) -> String {
        let h = wrap24(raw)
        var hh = Int(h.rounded(.down))
        var mm = Int(((h - Double(hh)) * 60).rounded())
        if mm == 60 { mm = 0; hh = (hh + 1) % 24 }
        return String(format: "%02d:%02d", hh, mm)
    }

    /// Heure decimale locale de cet instant.
    public static func hourOfDay(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0 + Double(c.second ?? 0) / 3600.0
    }

    // ---------------------------------------------------------------- utilitaires

    static func lerp(_ a: Int, _ b: Int, _ pRaw: Double) -> Int {
        var p = pRaw
        if p < 0 { p = 0 }
        if p > 1 { p = 1 }
        return Int((Double(a) + (Double(b) - Double(a)) * p).rounded())
    }

    /// Vrai si h est dans [from, to) en tenant compte du passage par minuit.
    static func isBetweenWrapped(_ h: Double, _ from: Double, _ to: Double) -> Bool {
        if from <= to { return h >= from && h < to }
        return h >= from || h < to
    }

    private static func julianDay(_ d: Date) -> Double {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: d)
        var year = c.year ?? 2000
        var month = c.month ?? 1
        let day = c.day ?? 1
        if month <= 2 { year -= 1; month += 12 }
        let a = year / 100
        let b = 2 - a + a / 4
        return (365.25 * Double(year + 4716)).rounded(.down)
             + (30.6001 * Double(month + 1)).rounded(.down)
             + Double(day) + Double(b) - 1524.5
    }

    private static func rad(_ d: Double) -> Double { d * Double.pi / 180.0 }
    private static func deg(_ r: Double) -> Double { r * 180.0 / Double.pi }
    private static func mod360(_ v: Double) -> Double {
        let m = v.truncatingRemainder(dividingBy: 360.0)
        return m < 0 ? m + 360 : m
    }
    static func wrap24(_ h: Double) -> Double {
        let m = h.truncatingRemainder(dividingBy: 24.0)
        return m < 0 ? m + 24 : m
    }
}
