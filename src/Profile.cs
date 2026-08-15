using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Text;

namespace OpusScreen
{
    /// <summary>Filtres qui melangent les canaux entre eux : impossibles avec une simple LUT.</summary>
    public enum ColorFilter
    {
        None = 0,
        Grayscale,      // niveaux de gris
        Invert,         // inversion, le "mode programmation" d'Iris
        Sepia,          // lecture prolongee
        Protanopia,     // daltonisme : deficience du rouge
        Deuteranopia,   // daltonisme : deficience du vert
        Tritanopia      // daltonisme : deficience du bleu
    }

    /// <summary>
    /// Un profil rassemble tout ce qui definit le rendu de l'ecran.
    ///
    /// Les concurrents appellent cela des "modes" (Iris) ou des "presets" (Lunar).
    /// Tout en est un ici, y compris l'etat courant : cela evite d'avoir deux
    /// representations differentes des memes reglages.
    /// </summary>
    public class Profile
    {
        public string Name = "Personnalise";

        // --- etage LUT ---
        public double Brightness = 100;   // 5 - 150
        public int Kelvin = 6500;         // 1200 - 6500
        public double Contrast = 100;     // 50 - 150
        public double GammaCurve = 100;   // 50 - 200, 100 = neutre
        public double RedGain = 100;      // 0 - 150, balance manuelle des canaux
        public double GreenGain = 100;
        public double BlueGain = 100;

        // --- etage matrice de couleur (Magnification API) ---
        public double Saturation = 100;   // 0 = gris, 100 = normal, 200 = tres sature
        public ColorFilter Filter = ColorFilter.None;

        // --- etage voile ---
        public Color Tint = Color.Black;

        public Profile Clone()
        {
            return (Profile)MemberwiseClone();
        }

        public void CopyFrom(Profile o)
        {
            Brightness = o.Brightness; Kelvin = o.Kelvin; Contrast = o.Contrast;
            GammaCurve = o.GammaCurve; RedGain = o.RedGain; GreenGain = o.GreenGain;
            BlueGain = o.BlueGain; Saturation = o.Saturation; Filter = o.Filter; Tint = o.Tint;
        }

        public bool IsNeutral()
        {
            return Math.Abs(Brightness - 100) < 0.01
                && Kelvin >= ColorTemp.MaxKelvin
                && Math.Abs(Contrast - 100) < 0.01
                && Math.Abs(GammaCurve - 100) < 0.01
                && Math.Abs(RedGain - 100) < 0.01
                && Math.Abs(GreenGain - 100) < 0.01
                && Math.Abs(BlueGain - 100) < 0.01
                && Math.Abs(Saturation - 100) < 0.01
                && Filter == ColorFilter.None;
        }

        // ------------------------------------------------------------------ serialisation

        public string Serialize()
        {
            CultureInfo inv = CultureInfo.InvariantCulture;
            StringBuilder sb = new StringBuilder();
            sb.Append(Escape(Name)).Append(';');
            sb.Append(Brightness.ToString("0.##", inv)).Append(';');
            sb.Append(Kelvin.ToString(inv)).Append(';');
            sb.Append(Contrast.ToString("0.##", inv)).Append(';');
            sb.Append(GammaCurve.ToString("0.##", inv)).Append(';');
            sb.Append(RedGain.ToString("0.##", inv)).Append(';');
            sb.Append(GreenGain.ToString("0.##", inv)).Append(';');
            sb.Append(BlueGain.ToString("0.##", inv)).Append(';');
            sb.Append(Saturation.ToString("0.##", inv)).Append(';');
            sb.Append((int)Filter).Append(';');
            sb.Append(Tint.R).Append(',').Append(Tint.G).Append(',').Append(Tint.B);
            return sb.ToString();
        }

        public static Profile Deserialize(string s)
        {
            Profile p = new Profile();
            try
            {
                CultureInfo inv = CultureInfo.InvariantCulture;
                string[] f = s.Split(';');
                if (f.Length < 11) return p;
                p.Name = Unescape(f[0]);
                double.TryParse(f[1], NumberStyles.Float, inv, out p.Brightness);
                int.TryParse(f[2], NumberStyles.Integer, inv, out p.Kelvin);
                double.TryParse(f[3], NumberStyles.Float, inv, out p.Contrast);
                double.TryParse(f[4], NumberStyles.Float, inv, out p.GammaCurve);
                double.TryParse(f[5], NumberStyles.Float, inv, out p.RedGain);
                double.TryParse(f[6], NumberStyles.Float, inv, out p.GreenGain);
                double.TryParse(f[7], NumberStyles.Float, inv, out p.BlueGain);
                double.TryParse(f[8], NumberStyles.Float, inv, out p.Saturation);
                int fi; int.TryParse(f[9], NumberStyles.Integer, inv, out fi);
                p.Filter = (ColorFilter)fi;
                string[] rgb = f[10].Split(',');
                if (rgb.Length == 3)
                    p.Tint = Color.FromArgb(int.Parse(rgb[0]), int.Parse(rgb[1]), int.Parse(rgb[2]));
            }
            catch { }
            p.ClampAll();
            return p;
        }

        public void ClampAll()
        {
            Brightness = SafetyGuard.ClampBrightness(Brightness);
            Kelvin = Clamp(Kelvin, ColorTemp.MinKelvin, ColorTemp.MaxKelvin);
            Contrast = Clamp(Contrast, 50, 150);
            GammaCurve = Clamp(GammaCurve, 50, 200);
            RedGain = Clamp(RedGain, 0, 150);
            GreenGain = Clamp(GreenGain, 0, 150);
            BlueGain = Clamp(BlueGain, 0, 150);
            Saturation = Clamp(Saturation, 0, 200);
        }

        private static double Clamp(double v, double lo, double hi)
        {
            if (double.IsNaN(v)) return (lo + hi) / 2;
            return v < lo ? lo : (v > hi ? hi : v);
        }

        private static int Clamp(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

        private static string Escape(string s) { return s.Replace(";", "%3B").Replace("|", "%7C"); }
        private static string Unescape(string s) { return s.Replace("%3B", ";").Replace("%7C", "|"); }

        // ------------------------------------------------------------------ modes livres

        /// <summary>
        /// Les modes prets a l'emploi, inspires de ceux d'Iris (Health, Sleep, Reading,
        /// Programming, Movie, Sunglasses...) et de FaceLight chez Lunar.
        /// </summary>
        public static List<Profile> BuiltInModes()
        {
            List<Profile> list = new List<Profile>();

            list.Add(Make("Normal", 100, 6500, 100, 100, 100, ColorFilter.None));
            list.Add(Make("Confort", 90, 5000, 100, 100, 100, ColorFilter.None));
            list.Add(Make("Lecture", 85, 4200, 95, 100, 92, ColorFilter.None));
            list.Add(Make("Soiree", 70, 3400, 100, 100, 100, ColorFilter.None));
            list.Add(Make("Nuit profonde", 35, 2000, 95, 100, 88, ColorFilter.None));
            list.Add(Make("Bougie", 20, 1500, 90, 100, 85, ColorFilter.None));
            list.Add(Make("Film", 115, 6000, 112, 100, 118, ColorFilter.None));
            list.Add(Make("Jeu", 125, 6500, 110, 100, 115, ColorFilter.None));
            list.Add(Make("Plein soleil", 150, 6500, 115, 100, 110, ColorFilter.None));
            list.Add(Make("Visioconference", 140, 5800, 100, 100, 105, ColorFilter.None));
            list.Add(Make("Programmation", 100, 5500, 100, 100, 100, ColorFilter.Invert));
            list.Add(Make("Papier", 95, 4000, 100, 100, 60, ColorFilter.Sepia));
            list.Add(Make("Monochrome", 100, 6500, 105, 100, 0, ColorFilter.Grayscale));

            return list;
        }

        private static Profile Make(string name, double bright, int kelvin, double contrast,
                                    double gamma, double sat, ColorFilter filter)
        {
            Profile p = new Profile();
            p.Name = name;
            p.Brightness = bright;
            p.Kelvin = kelvin;
            p.Contrast = contrast;
            p.GammaCurve = gamma;
            p.Saturation = sat;
            p.Filter = filter;
            return p;
        }

        /// <summary>Description courte pour l'interface, generee a partir des valeurs.</summary>
        public string Summary()
        {
            List<string> bits = new List<string>();
            bits.Add(((int)Math.Round(Brightness)) + " %");
            if (Kelvin < ColorTemp.MaxKelvin) bits.Add(Kelvin + " K");
            if (Math.Abs(Contrast - 100) > 0.5) bits.Add("contraste " + (int)Contrast);
            if (Math.Abs(Saturation - 100) > 0.5) bits.Add("saturation " + (int)Saturation);
            if (Filter != ColorFilter.None) bits.Add(FilterName(Filter));
            return string.Join(" - ", bits.ToArray());
        }

        public static string FilterName(ColorFilter f)
        {
            switch (f)
            {
                case ColorFilter.Grayscale: return "niveaux de gris";
                case ColorFilter.Invert: return "inverse";
                case ColorFilter.Sepia: return "sepia";
                case ColorFilter.Protanopia: return "protanopie";
                case ColorFilter.Deuteranopia: return "deuteranopie";
                case ColorFilter.Tritanopia: return "tritanopie";
                default: return "aucun";
            }
        }
    }
}
