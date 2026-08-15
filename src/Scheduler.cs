using System;

namespace LumaFlux
{
    /// <summary>Ce que la planification impose a un instant donne.</summary>
    public struct ScheduleResult
    {
        public int Kelvin;
        public double Brightness;
        public bool BrightnessApplies;
        public DayPhase Phase;
        public double Sunrise, Sunset;
        public bool SunValid;
    }

    /// <summary>
    /// Traduit l'heure qu'il est en consigne de couleur et, si l'utilisateur le
    /// souhaite, de luminosite.
    ///
    /// f.lux ne fait varier que la couleur. Faire aussi descendre la luminosite le soir
    /// est ce qui manque le plus quand on utilise les deux applications d'origine
    /// cote a cote : il fallait bouger deux reglages a la main.
    /// </summary>
    public static class Scheduler
    {
        public static ScheduleResult Evaluate(Settings s, DateTime now)
        {
            ScheduleResult r = new ScheduleResult();
            r.Kelvin = s.Current.Kelvin;
            r.Brightness = s.Current.Brightness;
            r.BrightnessApplies = false;
            r.Phase = DayPhase.Day;

            Preset preset = FindPreset(s.PresetName);

            double sunrise, sunset;
            r.SunValid = SolarClock.SunTimes(now, s.Latitude, s.Longitude, out sunrise, out sunset);

            if (s.Schedule == ScheduleMode.FixedHours)
            {
                sunrise = s.FixedDayHour;
                sunset = s.FixedNightHour;
                r.SunValid = true;
            }
            else if (!r.SunValid)
            {
                // Nuit ou jour polaire : on retombe sur des horaires raisonnables.
                sunrise = 7.0;
                sunset = 19.0;
            }

            r.Sunrise = sunrise;
            r.Sunset = sunset;

            if (s.Schedule == ScheduleMode.Manual) return r;

            double fade = Math.Max(5, s.TransitionMinutes) / 60.0;
            double h = now.Hour + now.Minute / 60.0 + now.Second / 3600.0;

            DayPhase phase;
            r.Kelvin = Interpolate(preset, h, sunrise, sunset, s.BedtimeHour, fade, out phase);
            r.Phase = phase;

            if (s.ScheduleAffectsBrightness)
            {
                r.BrightnessApplies = true;
                r.Brightness = InterpolateBrightness(s, h, sunrise, sunset, fade, phase);
            }

            return r;
        }

        private static int Interpolate(Preset preset, double h, double sunrise, double sunset,
                                       double bedtime, double fade, out DayPhase phase)
        {
            if (IsBetweenWrapped(h, bedtime, sunrise))
            {
                phase = DayPhase.Late;
                return preset.Late;
            }

            if (h >= sunset - fade && h < sunset + fade)
            {
                phase = DayPhase.Sunset;
                return Lerp(preset.Day, preset.Night, (h - (sunset - fade)) / (2 * fade));
            }

            if (h >= sunrise && h < sunrise + fade)
            {
                phase = DayPhase.Sunset;
                return Lerp(preset.Night, preset.Day, (h - sunrise) / fade);
            }

            if (h >= sunset + fade || h < sunrise)
            {
                phase = DayPhase.Night;
                return preset.Night;
            }

            phase = DayPhase.Day;
            return preset.Day;
        }

        private static double InterpolateBrightness(Settings s, double h, double sunrise,
                                                    double sunset, double fade, DayPhase phase)
        {
            double day = s.DayBrightness, night = s.NightBrightness;

            if (phase == DayPhase.Day) return day;
            if (phase == DayPhase.Night || phase == DayPhase.Late) return night;

            // En transition, on suit la meme rampe que la couleur.
            if (h >= sunset - fade && h < sunset + fade)
                return day + (night - day) * ((h - (sunset - fade)) / (2 * fade));
            if (h >= sunrise && h < sunrise + fade)
                return night + (day - night) * ((h - sunrise) / fade);

            return day;
        }

        private static int Lerp(int a, int b, double p)
        {
            if (p < 0) p = 0;
            if (p > 1) p = 1;
            return (int)Math.Round(a + (b - a) * p);
        }

        private static bool IsBetweenWrapped(double h, double from, double to)
        {
            if (from <= to) return h >= from && h < to;
            return h >= from || h < to;
        }

        public static Preset FindPreset(string name)
        {
            foreach (Preset p in Preset.BuiltIn())
                if (p.Name == name) return p;
            return Preset.BuiltIn()[0];
        }

        /// <summary>Resume lisible de l'etat de la planification, pour l'interface.</summary>
        public static string Describe(Settings s, ScheduleResult r)
        {
            if (s.Schedule == ScheduleMode.Manual)
                return "Mode manuel : les curseurs commandent seuls.";

            string times = s.Schedule == ScheduleMode.FixedHours
                ? string.Format("Jour {0} - nuit {1}", SolarClock.FormatHour(r.Sunrise), SolarClock.FormatHour(r.Sunset))
                : string.Format("Lever {0} - coucher {1}", SolarClock.FormatHour(r.Sunrise), SolarClock.FormatHour(r.Sunset));

            return string.Format("{0} - actuellement : {1} ({2} K)",
                times, SolarClock.DescribePhase(r.Phase), r.Kelvin);
        }
    }
}
