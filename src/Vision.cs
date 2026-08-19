using System;
using System.Collections.Generic;
using System.Drawing;

namespace OpusScreen
{
    /// <summary>
    /// Ce que l'on sait des deficiences visuelles, mis a la portee de l'interface :
    /// les intitules, les explications, et les paires de couleurs sur lesquelles se
    /// juge reellement l'efficacite d'un filtre.
    ///
    /// Aucun appel systeme ici : uniquement du savoir metier, testable a froid.
    ///
    /// Sources du contenu : nomenclature clinique usuelle des dyschromatopsies,
    /// planches de confusion de type Ishihara pour le choix des paires, et
    /// recommandations d'accessibilite en basse vision (contraste et luminance).
    /// </summary>
    public static class Vision
    {
        // ------------------------------------------------------------------ intitules

        /// <summary>Nom courant, celui qu'une personne concernee reconnaitra.</summary>
        public static string PlainName(ColorFilter f)
        {
            switch (f)
            {
                case ColorFilter.Protanopia: return "Rouge mal percu";
                case ColorFilter.Deuteranopia: return "Vert mal percu";
                case ColorFilter.Tritanopia: return "Bleu mal percu";
                default: return "Aucune correction";
            }
        }

        /// <summary>Nom clinique, avec la frequence dans la population.</summary>
        public static string ClinicalName(ColorFilter f)
        {
            switch (f)
            {
                case ColorFilter.Protanopia:
                    return "Protanopie / protanomalie - environ 1 homme sur 100";
                case ColorFilter.Deuteranopia:
                    return "Deuteranopie / deuteranomalie - environ 6 hommes sur 100, "
                         + "la forme de loin la plus repandue";
                case ColorFilter.Tritanopia:
                    return "Tritanopie / tritanomalie - moins de 1 personne sur 1000, "
                         + "sans difference entre les sexes";
                default:
                    return "";
            }
        }

        /// <summary>Ce que la personne confond concretement, en langage ordinaire.</summary>
        public static string Confusions(ColorFilter f)
        {
            switch (f)
            {
                case ColorFilter.Protanopia:
                    return "Le rouge parait sombre, presque noir. Rouge et vert se confondent, "
                         + "mais aussi rouge et brun, rose et gris, violet et bleu.";
                case ColorFilter.Deuteranopia:
                    return "Le vert et le rouge se confondent sans que le rouge s'assombrisse. "
                         + "Vert et brun, rose et gris, turquoise et gris se melangent aussi.";
                case ColorFilter.Tritanopia:
                    return "Bleu et vert se confondent, jaune et rose egalement. "
                         + "Le violet devient indistinguable du rouge.";
                default:
                    return "";
            }
        }

        /// <summary>Gravite en mots. Un pourcentage seul ne dit rien a personne.</summary>
        public static string SeverityWord(double severity)
        {
            if (severity < 5) return "vision normale";
            if (severity < 35) return "anomalie legere";
            if (severity < 70) return "anomalie moderee";
            if (severity < 95) return "anomalie severe";
            return "dichromatie complete";
        }

        // ------------------------------------------------------------------ paires de confusion

        /// <summary>Deux couleurs qu'une deficience donnee tend a rendre identiques.</summary>
        public class Pair
        {
            public readonly Color A, B;
            public readonly string Label;
            public Pair(Color a, Color b, string label) { A = a; B = b; Label = label; }
        }

        /// <summary>
        /// Direction de confusion : le deplacement de couleur auquel cette deficience
        /// est le plus aveugle.
        ///
        /// Elle est CALCULEE a partir de la matrice de simulation, et non choisie a la
        /// main. La difference n'est pas theorique : une premiere version listait des
        /// paires « rouge / vert », « rose / gris » ecrites d'apres le sens commun.
        /// Verifiees, elles se revelaient parfaitement distinctes une fois simulees -
        /// elles differaient surtout par la CLARTE, que la deficience ne touche pas.
        /// Le comparateur montrait donc des couleurs que la personne distingue deja,
        /// et concluait a l'inutilite d'une correction qui, elle, fonctionnait.
        ///
        /// La direction cherchee est celle que la simulation ecrase le plus : le
        /// vecteur v qui minimise |v x M|, c'est-a-dire le vecteur propre de M x Mt
        /// associe a la plus petite valeur propre. Il est obtenu par iteration inverse,
        /// qui converge en quelques tours sur une matrice 3x3.
        /// </summary>
        public static double[] ConfusionDirection(ColorFilter f)
        {
            ColorFilter kind = (f == ColorFilter.Protanopia || f == ColorFilter.Deuteranopia
                             || f == ColorFilter.Tritanopia) ? f : ColorFilter.Deuteranopia;

            double[,] m = ColorMatrixEffect.SimulationMatrix(kind);

            // A = M x Mt : symetrique definie positive, ses vecteurs propres sont ceux
            // que l'on cherche et ses valeurs propres mesurent l'ecrasement.
            double[,] a = new double[3, 3];
            for (int i = 0; i < 3; i++)
                for (int j = 0; j < 3; j++)
                {
                    double s = 0;
                    for (int k = 0; k < 3; k++) s += m[i, k] * m[j, k];
                    a[i, j] = s;
                }

            double[,] inv = Invert3(a);
            if (inv == null) return new double[] { 1, -1, 0 };   // repli : l'axe rouge-vert

            // Iteration inverse : multiplier par A^-1 amplifie la plus PETITE valeur
            // propre de A, donc converge vers la direction la plus ecrasee.
            double[] v = { 0.577, -0.577, 0.577 };
            for (int step = 0; step < 60; step++)
            {
                double[] w = new double[3];
                for (int i = 0; i < 3; i++)
                    w[i] = inv[i, 0] * v[0] + inv[i, 1] * v[1] + inv[i, 2] * v[2];

                double norm = Math.Sqrt(w[0] * w[0] + w[1] * w[1] + w[2] * w[2]);
                if (norm < 1e-12) break;
                v[0] = w[0] / norm; v[1] = w[1] / norm; v[2] = w[2] / norm;
            }
            return v;
        }

        private static double[,] Invert3(double[,] m)
        {
            double det = m[0, 0] * (m[1, 1] * m[2, 2] - m[1, 2] * m[2, 1])
                       - m[0, 1] * (m[1, 0] * m[2, 2] - m[1, 2] * m[2, 0])
                       + m[0, 2] * (m[1, 0] * m[2, 1] - m[1, 1] * m[2, 0]);
            if (Math.Abs(det) < 1e-12) return null;

            double[,] r = new double[3, 3];
            r[0, 0] = (m[1, 1] * m[2, 2] - m[1, 2] * m[2, 1]) / det;
            r[0, 1] = (m[0, 2] * m[2, 1] - m[0, 1] * m[2, 2]) / det;
            r[0, 2] = (m[0, 1] * m[1, 2] - m[0, 2] * m[1, 1]) / det;
            r[1, 0] = (m[1, 2] * m[2, 0] - m[1, 0] * m[2, 2]) / det;
            r[1, 1] = (m[0, 0] * m[2, 2] - m[0, 2] * m[2, 0]) / det;
            r[1, 2] = (m[0, 2] * m[1, 0] - m[0, 0] * m[1, 2]) / det;
            r[2, 0] = (m[1, 0] * m[2, 1] - m[1, 1] * m[2, 0]) / det;
            r[2, 1] = (m[0, 1] * m[2, 0] - m[0, 0] * m[2, 1]) / det;
            r[2, 2] = (m[0, 0] * m[1, 1] - m[0, 1] * m[1, 0]) / det;
            return r;
        }

        /// <summary>
        /// Couleurs de depart des paires : des tons moyens, assez ecartes en teinte
        /// pour que le comparateur ne montre pas quatre fois la meme chose. La clarte
        /// reste au milieu de la plage, seul endroit ou l'on peut s'ecarter loin dans
        /// les deux sens sans sortir des couleurs affichables.
        /// </summary>
        private static readonly double[][] Anchors = {
            new double[] { 0.50, 0.50, 0.50 },
            new double[] { 0.60, 0.46, 0.42 },
            new double[] { 0.44, 0.54, 0.46 },
            new double[] { 0.48, 0.46, 0.60 }
        };

        /// <summary>
        /// Les paires servent a repondre a la seule question qui vaille devant un
        /// filtre : « est-ce que je vois maintenant une difference la ou je n'en
        /// voyais pas ? » Un nuancier ordinaire ne repond pas a cette question,
        /// parce qu'il ne met pas cote a cote les couleurs qui se confondent.
        ///
        /// Chaque paire est construite en s'ecartant d'un ton moyen dans les deux sens
        /// le long de la direction de confusion : par construction, la simulation les
        /// ramene donc a la meme couleur. Le nom affiche est celui que l'identificateur
        /// donnerait a chacune - les deux outils disent ainsi la meme chose.
        /// </summary>
        public static List<Pair> ConfusionPairs(ColorFilter f)
        {
            return ConfusionPairs(f, 100);
        }

        /// <summary>
        /// Version tenant compte de la gravite reglee.
        ///
        /// Le parametre n'est pas un raffinement : les paires doivent etre confondues
        /// PAR CETTE PERSONNE. Construites a gravite maximale puis montrees a quelqu'un
        /// regle sur une anomalie moderee, elles ressortaient parfaitement distinctes -
        /// le comparateur affichait « distinctes » des la colonne de gauche et donnait
        /// l'impression que la correction ne servait a rien.
        /// </summary>
        public static List<Pair> ConfusionPairs(ColorFilter f, double severityPercent)
        {
            List<Pair> pairs = new List<Pair>();
            double[] d = ConfusionDirection(f);

            ColorFilter kind = (f == ColorFilter.Protanopia || f == ColorFilter.Deuteranopia
                             || f == ColorFilter.Tritanopia) ? f : ColorFilter.Deuteranopia;
            float[] sim = ColorMatrixEffect.BuildMatrix(100, kind, severityPercent, 100, FilterMode.Simulation);

            foreach (double[] anchor in Anchors)
            {
                double t = ConfusedSpread(anchor, d, sim);

                Color a = Rgb(anchor, d, -t / 2);
                Color b = Rgb(anchor, d, +t / 2);

                // Seul cas ou l'ancrage n'apprend rien : les deux couleurs tombent sur
                // la meme valeur affichable. Le seuil porte donc sur le resultat et non
                // sur l'ecart theorique - un ecart de trois niveaux sur 255 suffit a
                // produire deux pastilles distinctes une fois la correction appliquee.
                if (a.R == b.R && a.G == b.G && a.B == b.B) continue;

                // Quand l'ecart tenable est faible, les deux couleurs tombent sous le
                // meme nom. « gris / gris » ne dit rien : on annonce alors la nuance.
                string na = NameOf(a), nb = NameOf(b);
                pairs.Add(new Pair(a, b, na == nb ? na + ", deux nuances" : na + " / " + nb));
            }

            // Toujours au moins une paire a montrer, meme si la geometrie se derobe.
            if (pairs.Count == 0)
                pairs.Add(new Pair(Color.FromArgb(214, 62, 62), Color.FromArgb(88, 158, 62), "rouge / vert"));

            return pairs;
        }

        /// <summary>
        /// Le plus grand ecart qui reste INDISTINGUABLE une fois simule.
        ///
        /// Prendre simplement l'ecart maximal que la gamme autorise ne convient pas :
        /// les modeles de simulation ecrasent l'axe de confusion sans l'annuler tout a
        /// fait, si bien que deux couleurs tres eloignees finissent par se distinguer
        /// meme apres simulation. Le comparateur affichait alors « distinctes » dans la
        /// colonne « aujourd'hui » - c'est-a-dire l'inverse de ce qu'il doit montrer.
        ///
        /// On cherche donc par dichotomie le plus grand ecart dont la difference percue
        /// reste sous le seuil de perception. Les couleurs obtenues sont, par mesure et
        /// non par affirmation, celles que la personne ne peut pas separer.
        /// </summary>
        private static double ConfusedSpread(double[] anchor, double[] d, float[] sim)
        {
            double max = MaxSpread(anchor, d);
            if (max < 0.05) return 0;

            // Meme au maximum la paire reste confondue : autant la montrer bien ecartee.
            if (SimulatedDelta(anchor, d, max, sim) <= JustNoticeable) return max;

            double lo = 0, hi = max;
            for (int i = 0; i < 24; i++)
            {
                double mid = (lo + hi) / 2;
                if (SimulatedDelta(anchor, d, mid, sim) <= JustNoticeable) lo = mid;
                else hi = mid;
            }
            return lo;
        }

        private static double SimulatedDelta(double[] anchor, double[] d, double t, float[] sim)
        {
            Color a = ColorMatrixEffect.Transform(sim, Rgb(anchor, d, -t / 2));
            Color b = ColorMatrixEffect.Transform(sim, Rgb(anchor, d, +t / 2));
            return DeltaE(a, b);
        }

        /// <summary>
        /// Plus grand ecart tenable de part et d'autre de l'ancrage sans sortir des
        /// couleurs affichables. Les bornes s'arretent avant 0 et 1 : une couleur
        /// ecretee cesse d'etre sur la direction de confusion, et la paire ne serait
        /// alors plus confondue pour de mauvaises raisons.
        /// </summary>
        private static double MaxSpread(double[] anchor, double[] d)
        {
            const double lo = 0.06, hi = 0.94;
            double t = 2.0;
            for (int i = 0; i < 3; i++)
            {
                if (Math.Abs(d[i]) < 1e-6) continue;
                double roomLow = (anchor[i] - lo) / Math.Abs(d[i]);
                double roomHigh = (hi - anchor[i]) / Math.Abs(d[i]);
                t = Math.Min(t, 2.0 * Math.Min(roomLow, roomHigh));
            }
            return t;
        }

        private static Color Rgb(double[] anchor, double[] d, double t)
        {
            return Color.FromArgb(
                Component(anchor[0] + d[0] * t),
                Component(anchor[1] + d[1] * t),
                Component(anchor[2] + d[2] * t));
        }

        private static int Component(double v)
        {
            int i = (int)Math.Round(v * 255);
            return i < 0 ? 0 : (i > 255 ? 255 : i);
        }

        /// <summary>
        /// Ecart percu entre deux couleurs, en Delta E CIE76.
        ///
        /// Sert a chiffrer ce que l'oeil constate : un filtre est utile si l'ecart
        /// entre les deux couleurs d'une paire AUGMENTE une fois le filtre passe.
        /// En dessous de 2,3 - le seuil de perception habituellement retenu - deux
        /// couleurs sont considerees comme identiques.
        /// </summary>
        public const double JustNoticeable = 2.3;

        public static double DeltaE(Color a, Color b)
        {
            double[] la = ToLab(a), lb = ToLab(b);
            double dl = la[0] - lb[0], da = la[1] - lb[1], db = la[2] - lb[2];
            return Math.Sqrt(dl * dl + da * da + db * db);
        }

        /// <summary>sRGB -> CIE L*a*b*, illuminant D65. Etape obligee pour parler d'ecart percu.</summary>
        public static double[] ToLab(Color c)
        {
            double r = Linear(c.R / 255.0), g = Linear(c.G / 255.0), b = Linear(c.B / 255.0);

            // sRGB -> XYZ (D65)
            double x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375;
            double y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750;
            double z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041;

            // Normalisation par le blanc de reference D65
            x /= 0.95047; y /= 1.00000; z /= 1.08883;

            double fx = Pivot(x), fy = Pivot(y), fz = Pivot(z);
            return new double[] { 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz) };
        }

        private static double Linear(double s)
        {
            return s <= 0.04045 ? s / 12.92 : Math.Pow((s + 0.055) / 1.055, 2.4);
        }

        private static double Pivot(double t)
        {
            return t > 0.008856 ? Math.Pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0);
        }

        // ------------------------------------------------------------------ nom des couleurs

        private class Named
        {
            public readonly string Name;
            public readonly Color Color;
            public readonly double[] Lab;
            public Named(string name, int r, int g, int b)
            {
                Name = name;
                Color = Color.FromArgb(r, g, b);
                Lab = ToLab(Color);
            }
        }

        /// <summary>
        /// Repertoire de reference pour nommer une couleur.
        ///
        /// Volontairement court et ordinaire : l'interet de l'outil est d'entendre
        /// « vert olive », pas « chartreuse foncee ». Une liste de 140 noms rendrait
        /// la reponse precise et inutilisable.
        /// </summary>
        private static readonly Named[] Palette = {
            new Named("noir",            0,   0,   0),
            new Named("gris tres fonce", 48,  48,  48),
            new Named("gris fonce",      90,  90,  90),
            new Named("gris",           128, 128, 128),
            new Named("gris clair",     190, 190, 190),
            new Named("blanc",          255, 255, 255),

            new Named("rouge",          220,  20,  30),
            new Named("rouge fonce",    130,  20,  25),
            new Named("bordeaux",       110,  30,  50),
            new Named("rose",           244, 150, 175),
            new Named("rose vif",       236,  70, 140),
            new Named("saumon",         242, 140, 120),
            new Named("corail",         240, 110,  80),

            new Named("orange",         246, 140,  30),
            new Named("orange fonce",   200,  95,  20),
            new Named("brun",           130,  90,  55),
            new Named("brun clair",     176, 138,  96),
            new Named("beige",          226, 208, 176),
            new Named("ocre",           192, 150,  60),

            new Named("jaune",          248, 220,  50),
            new Named("jaune pale",     246, 238, 160),
            new Named("moutarde",       200, 168,  40),
            new Named("vert olive",     128, 140,  50),
            new Named("vert citron",    160, 210,  60),

            new Named("vert",            50, 160,  70),
            new Named("vert fonce",      25,  95,  50),
            new Named("vert clair",     140, 210, 140),
            new Named("turquoise",       40, 180, 170),
            new Named("cyan",            60, 210, 230),

            new Named("bleu ciel",      120, 180, 240),
            new Named("bleu",            40, 100, 210),
            new Named("bleu fonce",      25,  50, 130),
            new Named("bleu marine",     22,  36,  80),
            new Named("indigo",          80,  70, 180),

            new Named("violet",         140,  80, 190),
            new Named("violet fonce",    90,  45, 130),
            new Named("mauve",          190, 150, 215),
            new Named("magenta",        215,  60, 190),
            new Named("prune",          130,  60, 110),
        };

        /// <summary>
        /// Nom francais de la couleur la plus proche, au sens de l'ecart percu.
        ///
        /// La comparaison a lieu en L*a*b* et non en RVB : en RVB, deux couleurs
        /// separees par la meme distance numerique peuvent etre l'une identique et
        /// l'autre franchement differente pour l'oeil. C'est precisement l'erreur
        /// que ne peut pas se permettre un outil dont le seul role est de dire
        /// a quelqu'un ce qu'il ne voit pas.
        /// </summary>
        public static string NameOf(Color c)
        {
            double[] lab = ToLab(c);
            double best = double.MaxValue;
            string name = "couleur";

            foreach (Named n in Palette)
            {
                double dl = lab[0] - n.Lab[0], da = lab[1] - n.Lab[1], db = lab[2] - n.Lab[2];
                double d = dl * dl + da * da + db * db;
                if (d < best) { best = d; name = n.Name; }
            }
            return name;
        }

        /// <summary>Nom complet, avec la nuance quand la couleur est nettement plus claire ou sombre.</summary>
        public static string DescribeColor(Color c)
        {
            string name = NameOf(c);
            double l = ToLab(c)[0];

            // Les noms qui portent deja une nuance de clarte ne se cumulent pas.
            bool alreadyQualified = name.IndexOf("clair") >= 0 || name.IndexOf("fonce") >= 0
                                 || name.IndexOf("pale") >= 0 || name == "noir" || name == "blanc";

            if (!alreadyQualified)
            {
                if (l < 25) return name + " tres fonce";
                if (l > 88) return name + " tres clair";
            }
            return name;
        }
    }
}
