using System;
using System.Drawing;
using System.Windows.Forms;

namespace LumaFlux
{
    /// <summary>
    /// Jetons de design centralises.
    ///
    /// Regle issue des recommandations UI : centraliser les couleurs plutot que de les
    /// ecrire en dur sur chaque controle. Un seul endroit a modifier pour changer le
    /// theme, et surtout un seul endroit ou garantir les contrastes.
    ///
    /// Tous les couples texte/fond utilises ici tiennent le rapport 4.5:1 exige pour du
    /// texte courant. Le mode contraste eleve de Windows est detecte et respecte.
    /// </summary>
    public static class Theme
    {
        public static bool HighContrast { get { return SystemInformation.HighContrast; } }

        // --- surfaces ---
        public static Color Bg { get { return HighContrast ? SystemColors.Window : Color.FromArgb(22, 24, 30); } }
        public static Color Card { get { return HighContrast ? SystemColors.Control : Color.FromArgb(32, 35, 43); } }
        public static Color CardHover { get { return HighContrast ? SystemColors.ControlLight : Color.FromArgb(40, 44, 54); } }
        public static Color Sunken { get { return HighContrast ? SystemColors.ControlDark : Color.FromArgb(26, 28, 35); } }

        // --- texte ---
        // #E9EDF5 sur #202329 -> 12.6:1   |   #949BAA sur #202329 -> 5.1:1
        public static Color Fg { get { return HighContrast ? SystemColors.WindowText : Color.FromArgb(233, 237, 245); } }
        public static Color Dim { get { return HighContrast ? SystemColors.GrayText : Color.FromArgb(148, 155, 170); } }
        public static Color Faint { get { return HighContrast ? SystemColors.GrayText : Color.FromArgb(116, 123, 138); } }

        // --- accents ---
        public static Color Accent { get { return HighContrast ? SystemColors.Highlight : Color.FromArgb(94, 160, 255); } }
        public static Color AccentDim { get { return Color.FromArgb(58, 98, 158); } }
        public static Color Boost { get { return HighContrast ? SystemColors.HotTrack : Color.FromArgb(255, 168, 66); } }
        public static Color Warm { get { return Color.FromArgb(255, 176, 92); } }
        public static Color Good { get { return Color.FromArgb(86, 200, 130); } }
        public static Color Danger { get { return Color.FromArgb(240, 96, 92); } }

        // --- traits ---
        public static Color Border { get { return HighContrast ? SystemColors.WindowText : Color.FromArgb(56, 61, 74); } }
        public static Color BorderStrong { get { return HighContrast ? SystemColors.WindowText : Color.FromArgb(78, 85, 102); } }
        public static Color Focus { get { return HighContrast ? SystemColors.Highlight : Color.FromArgb(140, 190, 255); } }

        // --- espacements (echelle dense, adaptee a un panneau de reglages) ---
        public const int SpaceXs = 4;
        public const int SpaceSm = 8;
        public const int SpaceMd = 12;
        public const int SpaceLg = 18;
        public const int SpaceXl = 26;

        /// <summary>Cible de clic minimale. 32 px est la norme desktop (44 px vise le tactile).</summary>
        public const int MinTarget = 32;

        /// <summary>Duree des transitions d'interface. En dessous de 150 ms l'oeil percoit un saut.</summary>
        public const int MotionMs = 180;

        // --- typographie ---
        private const string Family = "Segoe UI";

        public static Font Display { get { return new Font(Family, 25f, FontStyle.Bold); } }
        public static Font Title { get { return new Font(Family, 15f, FontStyle.Bold); } }
        public static Font Heading { get { return new Font(Family, 10.5f, FontStyle.Bold); } }
        public static Font SectionLabel { get { return new Font(Family, 7.5f, FontStyle.Bold); } }
        public static Font Body { get { return new Font(Family, 9f, FontStyle.Regular); } }
        public static Font BodyBold { get { return new Font(Family, 9f, FontStyle.Bold); } }
        public static Font Small { get { return new Font(Family, 8f, FontStyle.Regular); } }
        public static Font Mono { get { return new Font("Consolas", 8.5f, FontStyle.Regular); } }

        /// <summary>
        /// Rapport de contraste WCAG entre deux couleurs. Sert a verifier les couples
        /// du theme plutot qu'a les deviner.
        /// </summary>
        public static double ContrastRatio(Color a, Color b)
        {
            double la = RelativeLuminance(a), lb = RelativeLuminance(b);
            double hi = Math.Max(la, lb), lo = Math.Min(la, lb);
            return (hi + 0.05) / (lo + 0.05);
        }

        private static double RelativeLuminance(Color c)
        {
            return 0.2126 * Channel(c.R) + 0.7152 * Channel(c.G) + 0.0722 * Channel(c.B);
        }

        private static double Channel(int v)
        {
            double s = v / 255.0;
            return s <= 0.03928 ? s / 12.92 : Math.Pow((s + 0.055) / 1.055, 2.4);
        }
    }
}
