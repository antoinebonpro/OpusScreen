using System;
using System.Drawing;
using System.Windows.Forms;

namespace OpusScreen
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
        //
        // Base sombre teintee de vert-bleu plutot que le gris-bleu neutre d'avant.
        // Le registre visait le logiciel technique ; il vise maintenant le soin de soi,
        // ce que fait reellement cette application - lumiere, pauses, fatigue oculaire.
        // La teinte est celle du logo, mesuree dans le fichier et non choisie a l'oeil.
        //
        // Le fond reste SOMBRE, et ce n'est pas negociable : une application de confort
        // visuel s'ouvre le soir. Le registre bien-etre penche d'ordinaire vers les
        // fonds clairs ; imposer un fond clair a 22 h serait un contresens d'usage.
        public static Color Bg { get { return HighContrast ? SystemColors.Window : Color.FromArgb(14, 21, 23); } }
        public static Color Card { get { return HighContrast ? SystemColors.Control : Color.FromArgb(24, 35, 37); } }
        public static Color CardHover { get { return HighContrast ? SystemColors.ControlLight : Color.FromArgb(33, 47, 50); } }
        public static Color Sunken { get { return HighContrast ? SystemColors.ControlDark : Color.FromArgb(18, 27, 29); } }

        // --- texte ---
        //
        // Blanc adouci plutot que blanc pur : sur un fond sombre, le blanc franc
        // produit un halo qui fatigue en lecture prolongee.
        //
        // Faint passe de 3,70:1 a 5,43:1. L'ancienne valeur servait TOUS les textes
        // explicatifs de l'interface - donc du texte courant sous le seuil de 4,5:1,
        // dans une application dont l'accessibilite est l'argument principal. La suite
        // de tests ne verifiait que quatre couples et ne l'avait jamais vu passer.
        public static Color Fg { get { return HighContrast ? SystemColors.WindowText : Color.FromArgb(228, 240, 238); } }
        public static Color Dim { get { return HighContrast ? SystemColors.GrayText : Color.FromArgb(152, 176, 173); } }
        public static Color Faint { get { return HighContrast ? SystemColors.GrayText : Color.FromArgb(130, 155, 152); } }

        // --- accents ---
        //
        // Turquoise repris du logo (#008484 a #00B4A8 selon les zones), eclairci
        // jusqu'a 8,18:1 sur la carte. L'accent bleu d'avant n'avait aucun rapport
        // avec la marque affichee juste a cote dans la colonne de navigation.
        public static Color Accent { get { return HighContrast ? SystemColors.Highlight : Color.FromArgb(45, 206, 190); } }
        public static Color AccentDim { get { return Color.FromArgb(22, 104, 96); } }
        public static Color Boost { get { return HighContrast ? SystemColors.HotTrack : Color.FromArgb(255, 180, 112); } }
        public static Color Warm { get { return Color.FromArgb(255, 186, 124); } }
        public static Color Good { get { return Color.FromArgb(110, 207, 151); } }
        public static Color Danger { get { return Color.FromArgb(244, 124, 116); } }

        // --- traits ---
        //
        // Deux niveaux, et la distinction n'est pas cosmetique : WCAG 1.4.11 exige
        // 3:1 pour un trait qui IDENTIFIE un composant - le cadre d'un champ, d'une
        // liste, d'une case. Un simple filet decoratif entre deux blocs n'est soumis
        // a aucun seuil. L'ancien BorderStrong plafonnait a 2,11:1 et servait pourtant
        // de contour a des composants.
        public static Color Border { get { return HighContrast ? SystemColors.WindowText : Color.FromArgb(41, 58, 60); } }
        public static Color BorderStrong { get { return HighContrast ? SystemColors.WindowText : Color.FromArgb(96, 124, 126); } }
        public static Color Focus { get { return HighContrast ? SystemColors.Highlight : Color.FromArgb(134, 235, 222); } }

        // --- controles ---
        //
        // Ces trois jetons existent parce que Slider, DarkComboBox et DarkButton
        // portaient leurs couleurs ECRITES EN DUR. Changer le theme laissait donc
        // l'essentiel de l'interface inchange : les quatre curseurs de la page
        // principale restaient bleus au milieu d'une palette turquoise. Une couleur
        // ecrite dans un controle est une couleur que le theme ne pilote pas.
        public static Color Track { get { return HighContrast ? SystemColors.ControlDark : Color.FromArgb(38, 53, 56); } }
        public static Color Field { get { return HighContrast ? SystemColors.Window : Color.FromArgb(33, 47, 50); } }
        public static Color Knob { get { return HighContrast ? SystemColors.WindowText : Color.FromArgb(232, 244, 242); } }

        // --- espacements ---
        //
        // Echelle elargie : l'ancienne etait calibree pour faire tenir le maximum de
        // reglages a l'ecran. C'est le bon reflexe pour un outil technique, le mauvais
        // pour une application de confort - le tassement se lit comme de l'urgence.
        // Les pages defilent de toute facon ; ce qui se gagne en densite se paie en
        // fatigue de lecture.
        public const int SpaceXs = 6;
        public const int SpaceSm = 10;
        public const int SpaceMd = 16;
        public const int SpaceLg = 22;
        public const int SpaceXl = 32;

        /// <summary>
        /// Cible de clic minimale. 36 px plutot que 32 : le minimum desktop est un
        /// plancher, pas un objectif, et viser une cible se degrade avec la fatigue -
        /// precisement l'etat dans lequel on ouvre cette application.
        /// </summary>
        public const int MinTarget = 36;

        /// <summary>
        /// Duree des transitions d'interface. En dessous de 150 ms l'oeil percoit un
        /// saut ; 220 ms adoucit sans donner l'impression que l'interface traine.
        /// </summary>
        public const int MotionMs = 220;

        // --- typographie ---
        private const string Family = "Segoe UI";

        public static Font Display { get { return new Font(Family, 25f, FontStyle.Bold); } }
        public static Font Title { get { return new Font(Family, 15f, FontStyle.Bold); } }
        public static Font Heading { get { return new Font(Family, 10.5f, FontStyle.Bold); } }
        public static Font SectionLabel { get { return new Font(Family, 8f, FontStyle.Bold); } }
        public static Font Body { get { return new Font(Family, 9f, FontStyle.Regular); } }
        public static Font BodyBold { get { return new Font(Family, 9f, FontStyle.Bold); } }

        /// <summary>
        /// Textes explicatifs et legendes. Remonte de 7,5 a 8,5 pt : a 96 ppp, 8 pt
        /// fait environ 10,7 px, sous le plancher de 12 px retenu pour du texte
        /// courant. Ces legendes portent l'essentiel des explications de l'interface -
        /// les reduire revenait a compter sur le fait qu'on ne les lit pas.
        /// </summary>
        public static Font Small { get { return new Font(Family, 8.5f, FontStyle.Regular); } }
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
