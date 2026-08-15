using System;

namespace LumaFlux
{
    public enum DayPhase { Day, Sunset, Night, Late }

    /// <summary>
    /// Calcul du lever et du coucher du soleil, puis de la temperature de couleur qui
    /// convient a l'instant present.
    ///
    /// f.lux interroge un service en ligne pour la position ; ici tout est calcule sur
    /// place avec l'algorithme solaire de la NOAA : aucune connexion, aucune donnee
    /// envoyee nulle part.
    /// </summary>
    public static class SolarClock
    {
        /// <summary>Duree du fondu autour du coucher du soleil.</summary>
        private const double TransitionMinutes = 60.0;

        /// <summary>
        /// Heures locales du lever et du coucher, en heures decimales (13.5 = 13 h 30).
        /// Renvoie false aux latitudes ou le soleil ne se leve ou ne se couche pas.
        /// </summary>
        public static bool SunTimes(DateTime localDate, double latitude, double longitude,
                                    out double sunriseHour, out double sunsetHour)
        {
            sunriseHour = 7.0;
            sunsetHour = 19.0;

            try
            {
                double jd = JulianDay(localDate.Date);
                double t = (jd - 2451545.0) / 36525.0;

                double meanLong = Mod360(280.46646 + t * (36000.76983 + t * 0.0003032));
                double meanAnom = 357.52911 + t * (35999.05029 - 0.0001537 * t);
                double eccent = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);

                double center = Math.Sin(Rad(meanAnom)) * (1.914602 - t * (0.004817 + 0.000014 * t))
                              + Math.Sin(Rad(2 * meanAnom)) * (0.019993 - 0.000101 * t)
                              + Math.Sin(Rad(3 * meanAnom)) * 0.000289;

                double trueLong = meanLong + center;
                double omega = 125.04 - 1934.136 * t;
                double appLong = trueLong - 0.00569 - 0.00478 * Math.Sin(Rad(omega));

                double meanObliq = 23.0 + (26.0 + ((21.448 - t * (46.815 + t * (0.00059 - t * 0.001813)))) / 60.0) / 60.0;
                double obliq = meanObliq + 0.00256 * Math.Cos(Rad(omega));

                double declination = Deg(Math.Asin(Math.Sin(Rad(obliq)) * Math.Sin(Rad(appLong))));

                double y = Math.Tan(Rad(obliq / 2)) * Math.Tan(Rad(obliq / 2));
                double eqTime = 4 * Deg(
                      y * Math.Sin(2 * Rad(meanLong))
                    - 2 * eccent * Math.Sin(Rad(meanAnom))
                    + 4 * eccent * y * Math.Sin(Rad(meanAnom)) * Math.Cos(2 * Rad(meanLong))
                    - 0.5 * y * y * Math.Sin(4 * Rad(meanLong))
                    - 1.25 * eccent * eccent * Math.Sin(2 * Rad(meanAnom)));

                // 90.833 deg : centre du disque solaire + refraction atmospherique
                double cosHa = (Math.Cos(Rad(90.833)) / (Math.Cos(Rad(latitude)) * Math.Cos(Rad(declination))))
                             - Math.Tan(Rad(latitude)) * Math.Tan(Rad(declination));

                if (cosHa > 1.0 || cosHa < -1.0) return false;   // nuit ou jour polaire

                double hourAngle = Deg(Math.Acos(cosHa));

                double utcOffset = TimeZoneInfo.Local.GetUtcOffset(localDate).TotalMinutes;
                double solarNoonMin = 720 - 4 * longitude - eqTime + utcOffset;

                sunriseHour = (solarNoonMin - hourAngle * 4) / 60.0;
                sunsetHour = (solarNoonMin + hourAngle * 4) / 60.0;

                sunriseHour = Wrap24(sunriseHour);
                sunsetHour = Wrap24(sunsetHour);
                return true;
            }
            catch { return false; }
        }

        /// <summary>
        /// Temperature a appliquer maintenant, fondus compris.
        /// bedtimeHour marque le passage a la teinte "tard" du preset.
        /// </summary>
        public static int CurrentKelvin(Preset preset, double latitude, double longitude,
                                        double bedtimeHour, DateTime now, out DayPhase phase)
        {
            double sunrise, sunset;
            if (!SunTimes(now, latitude, longitude, out sunrise, out sunset))
            {
                sunrise = 7.0;
                sunset = 19.0;
            }

            double h = now.Hour + now.Minute / 60.0 + now.Second / 3600.0;
            double fade = TransitionMinutes / 60.0;

            // --- nuit profonde : entre l'heure du coucher et le lever du soleil ---
            if (IsBetweenWrapped(h, bedtimeHour, sunrise))
            {
                phase = DayPhase.Late;
                return preset.Late;
            }

            // --- fondu du coucher de soleil ---
            if (h >= sunset - fade && h < sunset + fade)
            {
                phase = DayPhase.Sunset;
                double p = (h - (sunset - fade)) / (2 * fade);   // 0 -> 1
                return Lerp(preset.Day, preset.Night, p);
            }

            // --- fondu du lever de soleil ---
            if (h >= sunrise && h < sunrise + fade)
            {
                phase = DayPhase.Sunset;
                double p = (h - sunrise) / fade;
                return Lerp(preset.Night, preset.Day, p);
            }

            if (h >= sunset + fade || h < sunrise)
            {
                phase = DayPhase.Night;
                return preset.Night;
            }

            phase = DayPhase.Day;
            return preset.Day;
        }

        public static string DescribePhase(DayPhase p)
        {
            switch (p)
            {
                case DayPhase.Day: return "journee";
                case DayPhase.Sunset: return "transition";
                case DayPhase.Night: return "soiree";
                default: return "nuit";
            }
        }

        public static string FormatHour(double h)
        {
            h = Wrap24(h);
            int hh = (int)Math.Floor(h);
            int mm = (int)Math.Round((h - hh) * 60);
            if (mm == 60) { mm = 0; hh = (hh + 1) % 24; }
            return string.Format("{0:00}:{1:00}", hh, mm);
        }

        // ---------------------------------------------------------------- utilitaires

        private static int Lerp(int a, int b, double p)
        {
            if (p < 0) p = 0;
            if (p > 1) p = 1;
            return (int)Math.Round(a + (b - a) * p);
        }

        /// <summary>Vrai si h est dans [from, to) en tenant compte du passage par minuit.</summary>
        private static bool IsBetweenWrapped(double h, double from, double to)
        {
            if (from <= to) return h >= from && h < to;
            return h >= from || h < to;
        }

        private static double JulianDay(DateTime d)
        {
            int year = d.Year, month = d.Month, day = d.Day;
            if (month <= 2) { year -= 1; month += 12; }
            int a = year / 100;
            int b = 2 - a + a / 4;
            return Math.Floor(365.25 * (year + 4716))
                 + Math.Floor(30.6001 * (month + 1))
                 + day + b - 1524.5;
        }

        private static double Rad(double deg) { return deg * Math.PI / 180.0; }
        private static double Deg(double rad) { return rad * 180.0 / Math.PI; }
        private static double Mod360(double v) { v = v % 360.0; return v < 0 ? v + 360 : v; }
        private static double Wrap24(double h) { h = h % 24.0; return h < 0 ? h + 24 : h; }
    }
}
