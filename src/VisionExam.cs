using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;

namespace OpusScreen
{
    /// <summary>Une planche du test : un chiffre cache dans un semis de pastilles.</summary>
    public class VisionPlate
    {
        /// <summary>Deficience visee. None = planche de controle, lisible par tout le monde.</summary>
        public ColorFilter Axis;

        /// <summary>
        /// Gravite a partir de laquelle cette planche devient illisible.
        ///
        /// Une planche calibree sur la deficience COMPLETE ne depiste que les cas
        /// complets - c'est-a-dire les plus rares. Les planches les plus subtiles,
        /// dont le chiffre s'efface des une anomalie moderee, sont celles qui
        /// attrapent la grande majorite des personnes concernees.
        /// </summary>
        public double Level = 100;

        public int Digit;
        public int[] Choices = new int[0];
        public Color Background, Figure;

        /// <summary>Graine du semis : la meme planche se redessine a l'identique.</summary>
        public int Seed;
    }

    /// <summary>
    /// Le test guide : ce qui se calcule, sans rien d'affichable.
    ///
    /// Deux temps, et deux raisons.
    ///
    /// Les PLANCHES trouvent le type. Chacune cache un chiffre dont la couleur ne
    /// differe du fond que le long de la direction de confusion d'une deficience
    /// precise : cette vision-la ne lit rien, les deux autres lisent sans peine. Le
    /// choix des couleurs n'est pas decide a la main - il est cherche, puis verifie
    /// par le calcul de l'ecart percu apres simulation.
    ///
    /// L'ESCALIER mesure la gravite. On montre deux couleurs sur cette direction, en
    /// resserrant l'ecart a chaque reponse juste et en l'elargissant a chaque erreur :
    /// la suite converge vers le plus petit ecart que la personne distingue encore.
    /// De ce seuil on remonte a la gravite, puisque l'on sait calculer le seuil que
    /// produirait chaque gravite.
    ///
    /// Classer quelqu'un dans une case - « deuteranope » - serait plus simple et
    /// faux : l'immense majorite des personnes concernees ont une ANOMALIE partielle,
    /// et une correction calibree sur la dichromatie les gene au lieu de les aider.
    /// </summary>
    public static class VisionExam
    {
        public const double JustNoticeable = Vision.JustNoticeable;

        /// <summary>Les trois deficiences testees.</summary>
        public static readonly ColorFilter[] Axes = {
            ColorFilter.Protanopia, ColorFilter.Deuteranopia, ColorFilter.Tritanopia
        };

        private static readonly double[] Anchor = { 0.52, 0.50, 0.48 };

        // ------------------------------------------------------------------ couleurs

        private static ColorFilter Kind(ColorFilter f)
        {
            return (f == ColorFilter.Protanopia || f == ColorFilter.Deuteranopia
                 || f == ColorFilter.Tritanopia) ? f : ColorFilter.Deuteranopia;
        }

        /// <summary>
        /// Plus grand ecart tenable de part et d'autre d'un ancrage sans sortir des
        /// couleurs affichables. Une couleur ecretee quitte la direction de confusion :
        /// la paire cesserait d'etre confondue, mais pour une mauvaise raison.
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
            return Color.FromArgb(Comp(anchor[0] + d[0] * t), Comp(anchor[1] + d[1] * t),
                                  Comp(anchor[2] + d[2] * t));
        }

        private static int Comp(double v)
        {
            int i = (int)Math.Round(v * 255);
            return i < 0 ? 0 : (i > 255 ? 255 : i);
        }

        /// <summary>
        /// Les deux couleurs d'un essai, ecartees de `separation` (0 a 1) le long de
        /// la direction de confusion. 1 = l'ecart maximal que l'ecran permet ici.
        /// </summary>
        public static Color[] PairAt(ColorFilter axis, double separation)
        {
            ColorFilter k = Kind(axis);
            double[] d = Vision.ConfusionDirection(k);
            double t = Math.Max(0, Math.Min(1, separation)) * MaxSpread(Anchor, d);
            return new Color[] { Rgb(Anchor, d, -t / 2), Rgb(Anchor, d, +t / 2) };
        }

        /// <summary>Ecart que percoit reellement une vision de cette gravite.</summary>
        public static double PerceivedDelta(ColorFilter axis, double severity, Color a, Color b)
        {
            float[] sim = ColorMatrixEffect.BuildMatrix(100, Kind(axis), severity, 100, FilterMode.Simulation);
            return Vision.DeltaE(ColorMatrixEffect.Transform(sim, a), ColorMatrixEffect.Transform(sim, b));
        }

        /// <summary>
        /// Le plus petit ecart qu'une vision de cette gravite distingue encore.
        ///
        /// Au-dela de 1, l'ecart maximal de l'ecran ne suffit plus : la valeur se
        /// prolonge alors au-dela pour rester croissante avec la gravite, sans quoi
        /// toutes les gravites severes rendraient le meme seuil et la mesure ne
        /// pourrait plus les distinguer.
        /// </summary>
        public static double SeparationThreshold(ColorFilter axis, double severity)
        {
            Color[] full = PairAt(axis, 1.0);
            double atFull = PerceivedDelta(axis, severity, full[0], full[1]);
            if (atFull < JustNoticeable)
                return 1.0 + (JustNoticeable - atFull) / JustNoticeable;

            double lo = 0.0, hi = 1.0;
            for (int i = 0; i < 24; i++)
            {
                double mid = (lo + hi) / 2;
                Color[] p = PairAt(axis, mid);
                if (PerceivedDelta(axis, severity, p[0], p[1]) >= JustNoticeable) hi = mid;
                else lo = mid;
            }
            return hi;
        }

        /// <summary>
        /// Gravite qui produirait ce seuil : l'operation inverse de la precedente,
        /// par dichotomie, puisque le seuil croit avec la gravite.
        /// </summary>
        public static double SeverityFromThreshold(ColorFilter axis, double threshold)
        {
            double lo = 0, hi = 100;
            for (int i = 0; i < 24; i++)
            {
                double mid = (lo + hi) / 2;
                if (SeparationThreshold(axis, mid) < threshold) lo = mid;
                else hi = mid;
            }
            return Math.Round((lo + hi) / 2);
        }

        /// <summary>Seuil conventionnel de qui ne distingue rien, meme a l'ecart maximal.</summary>
        public static double CeilingThreshold(ColorFilter axis)
        {
            return SeparationThreshold(axis, 100);
        }

        /// <summary>
        /// Seuil qu'un observateur donne obtiendrait sur les couleurs d'un AUTRE axe.
        ///
        /// C'est la piece qui manquait pour distinguer le rouge du vert. Leurs axes de
        /// confusion sont voisins : mesurer « le rouge est mauvais » ne dit pas si la
        /// personne est protanope ou deuteranope, car les deux echouent un peu partout.
        /// Ce qui les separe, c'est le PROFIL des trois mesures - et le profil ne se
        /// lit qu'en sachant predire ce que chaque vision donnerait sur chaque axe.
        /// </summary>
        public static double PredictedThreshold(ColorFilter pairAxis, ColorFilter observerAxis, double severity)
        {
            Color[] full = PairAt(pairAxis, 1.0);
            double atFull = PerceivedDelta(observerAxis, severity, full[0], full[1]);
            if (atFull < JustNoticeable)
                return 1.0 + (JustNoticeable - atFull) / JustNoticeable;

            double lo = 0.0, hi = 1.0;
            for (int i = 0; i < 20; i++)
            {
                double mid = (lo + hi) / 2;
                Color[] p = PairAt(pairAxis, mid);
                if (PerceivedDelta(observerAxis, severity, p[0], p[1]) >= JustNoticeable) hi = mid;
                else lo = mid;
            }
            return hi;
        }

        /// <summary>
        /// La vision qui explique le mieux les seuils mesures sur plusieurs axes.
        ///
        /// On essaie chaque deficience a chaque gravite, on predit les seuils qu'elle
        /// donnerait, et l'on garde celle dont les predictions collent le mieux aux
        /// mesures. Comparer betement « quel axe est le plus mauvais » se trompait de
        /// type une fois sur deux entre le rouge et le vert, parce que le plus mauvais
        /// axe d'un deuteranope n'est pas toujours le sien.
        ///
        /// `quality` vaut 1 pour un accord parfait et tend vers 0 quand rien ne colle.
        /// </summary>
        public static void Fit(Dictionary<ColorFilter, double> measured,
                               out ColorFilter axis, out double severity, out double quality)
        {
            axis = ColorFilter.None;
            severity = 0;
            quality = 0;
            if (measured == null || measured.Count == 0) return;

            // Hypothese de reference : une vision normale. Une deficience ne sera
            // annoncee que si elle explique NETTEMENT mieux les mesures - sans cette
            // comparaison, le moindre bruit de mesure se voyait promu en diagnostic.
            double normalError = 0;
            foreach (KeyValuePair<ColorFilter, double> kv in measured)
            {
                double predicted = PredictedThreshold(kv.Key, Axes[0], 0);
                double d = Math.Log(Math.Max(1e-3, kv.Value)) - Math.Log(Math.Max(1e-3, predicted));
                normalError += d * d;
            }

            double bestError = double.MaxValue, secondBest = double.MaxValue;
            foreach (ColorFilter candidate in Axes)
            {
                double bestForAxis = double.MaxValue, bestSeverity = 0;
                for (double s = 0; s <= 100.0001; s += 2.5)
                {
                    double error = 0;
                    foreach (KeyValuePair<ColorFilter, double> kv in measured)
                    {
                        double predicted = PredictedThreshold(kv.Key, candidate, s);
                        double d = Math.Log(Math.Max(1e-3, kv.Value)) - Math.Log(Math.Max(1e-3, predicted));
                        error += d * d;
                    }
                    if (error < bestForAxis) { bestForAxis = error; bestSeverity = s; }
                }

                if (bestForAxis < bestError)
                {
                    secondBest = bestError;
                    bestError = bestForAxis;
                    axis = candidate;
                    severity = bestSeverity;
                }
                else if (bestForAxis < secondBest) secondBest = bestForAxis;
            }

            // Qualite : combien la deficience explique mieux les mesures qu'une vision
            // normale, tempere par l'ecart avec la deuxieme hypothese. Deux
            // explications aussi bonnes signifient que la mesure ne tranche pas entre
            // elles, et il faut le dire plutot que de choisir au hasard.
            double gainPart = normalError <= 1e-9 ? 0
                            : Math.Max(0, Math.Min(1, 1.0 - bestError / normalError));
            double gapPart = secondBest == double.MaxValue ? 1.0
                           : Math.Min(1.0, (secondBest - bestError) / Math.Max(0.05, bestError + 0.05));
            quality = gainPart * (0.45 + 0.55 * gapPart);
            severity = Math.Round(severity);
        }

        // ------------------------------------------------------------------ escalier

        /// <summary>
        /// Escalier adaptatif : l'ecart se resserre apres une reponse juste, s'elargit
        /// apres une erreur. Le pas diminue a chaque retournement, et le seuil retenu
        /// est la moyenne geometrique des derniers retournements.
        ///
        /// C'est la methode des mesures de seuil en psychophysique. Elle vaut mieux
        /// qu'une liste fixe d'ecarts : elle passe l'essentiel de ses essais autour de
        /// la limite de la personne, la ou l'information se trouve, au lieu de
        /// gaspiller des ecrans sur des ecarts evidents ou impossibles.
        /// </summary>
        public class Staircase
        {
            private readonly ColorFilter _axis;
            private readonly List<double> _reversals = new List<double>();
            private double _sep = 1.0;
            private double _factor = 1.7;
            private bool _lastCorrect;
            private bool _hasLast;
            private int _trials;
            private int _ceilingMisses;
            private double _threshold = double.NaN;

            public const int MaxTrials = 22;

            private readonly int _wantedReversals;
            private readonly int _maxTrials;

            public Staircase(ColorFilter axis) : this(axis, 8, MaxTrials) { }

            /// <summary>
            /// Version courte, pour comparer plusieurs axes : moins de retournements,
            /// donc un seuil moins fin, mais trois mesures tiennent alors dans le temps
            /// d'une seule. La precision se rattrape ensuite sur l'axe retenu.
            /// </summary>
            public Staircase(ColorFilter axis, int wantedReversals, int maxTrials)
            {
                _axis = axis;
                _wantedReversals = wantedReversals;
                _maxTrials = maxTrials;
            }

            public ColorFilter Axis { get { return _axis; } }
            public double Separation { get { return _sep; } }
            public int Trials { get { return _trials; } }
            public bool Done { get { return !double.IsNaN(_threshold); } }

            /// <summary>Avancement affichable, de 0 a 1.</summary>
            public double Progress
            {
                get
                {
                    double byTrials = _trials / (double)_maxTrials;
                    double byReversals = _reversals.Count / (double)_wantedReversals;
                    return Math.Min(1, Math.Max(byTrials, byReversals));
                }
            }

            public double Threshold { get { return _threshold; } }

            public void Answer(bool distinguished)
            {
                if (Done) return;
                _trials++;

                if (!distinguished && _sep >= 0.999)
                {
                    // Meme au maximum, les deux couleurs restent identiques pour cette
                    // personne : il n'y a pas de seuil a mesurer, la deficience est
                    // complete sur cet axe.
                    if (++_ceilingMisses >= 2) { _threshold = CeilingThreshold(_axis); return; }
                }

                if (_hasLast && distinguished != _lastCorrect)
                {
                    _reversals.Add(_sep);
                    _factor = Math.Max(1.08, Math.Sqrt(_factor));
                }
                _lastCorrect = distinguished;
                _hasLast = true;

                _sep = distinguished ? _sep / _factor : Math.Min(1.0, _sep * _factor);
                if (_sep < 0.004) _sep = 0.004;

                if (_reversals.Count >= _wantedReversals || _trials >= _maxTrials) Finish();
            }

            private void Finish()
            {
                if (_reversals.Count == 0) { _threshold = _sep; return; }

                int take = Math.Min(Math.Max(3, _wantedReversals - 2), _reversals.Count);
                double sum = 0;
                for (int i = _reversals.Count - take; i < _reversals.Count; i++)
                    sum += Math.Log(Math.Max(1e-4, _reversals[i]));
                _threshold = Math.Exp(sum / take);
            }
        }

        // ------------------------------------------------------------------ planches

        private static readonly int[] DigitPool = { 2, 3, 5, 6, 8, 9 };
        private static readonly List<int> _recentDigits = new List<int>();

        /// <summary>
        /// Ancrages candidats. Une planche n'est bonne que si, autour de cet ancrage,
        /// on trouve un ecart qui disparait pour la deficience visee tout en restant
        /// franc pour les deux autres - sinon la planche accuserait le mauvais axe.
        /// </summary>
        private static List<double[]> Candidates()
        {
            // Une liste ecrite a la main ne donnait pas deux planches utilisables pour
            // chaque deficience : la place disponible autour d'un ancrage depend de la
            // direction de confusion, et l'axe bleu en laisse beaucoup moins. On balaie
            // donc une grille, et l'on garde ce qui passe les criteres.
            List<double[]> list = new List<double[]>();
            double[] levels = { 0.38, 0.46, 0.54, 0.62 };
            double[] tints = { -0.10, -0.05, 0.0, 0.05, 0.10 };
            foreach (double l in levels)
                foreach (double a in tints)
                    foreach (double b in tints)
                        list.Add(new double[] { l + a, l, l + b });
            return list;
        }

        private static double HiddenSpread(double[] anchor, double[] d, ColorFilter target, double level)
        {
            float[] sim = ColorMatrixEffect.BuildMatrix(100, target, level, 100, FilterMode.Simulation);
            double max = MaxSpread(anchor, d);
            if (max < 0.05) return 0;

            if (SimDelta(anchor, d, max, sim) <= JustNoticeable * 0.8) return max;

            double lo = 0, hi = max;
            for (int i = 0; i < 24; i++)
            {
                double mid = (lo + hi) / 2;
                if (SimDelta(anchor, d, mid, sim) <= JustNoticeable * 0.8) lo = mid;
                else hi = mid;
            }
            return lo;
        }

        private static double SimDelta(double[] anchor, double[] d, double t, float[] sim)
        {
            return Vision.DeltaE(ColorMatrixEffect.Transform(sim, Rgb(anchor, d, -t / 2)),
                                 ColorMatrixEffect.Transform(sim, Rgb(anchor, d, +t / 2)));
        }

        /// <summary>
        /// Les planches du test : deux par deficience, plus deux planches de controle.
        ///
        /// Les couleurs sont CHERCHEES, pas choisies : pour chaque ancrage candidat on
        /// mesure ce que verrait chacune des trois visions, et l'on garde les deux
        /// meilleures - celles ou le chiffre s'efface le mieux pour la deficience visee
        /// tout en restant le plus lisible pour les deux autres.
        /// </summary>
        /// <summary>
        /// Gravites visees, et l'ecart minimal que la planche doit garder pour une
        /// vision normale. Une planche cachee des 30 % de gravite est forcement
        /// subtile : son chiffre ne peut pas etre franc, sans quoi tout le monde le
        /// lirait. C'est le prix du depistage des anomalies legeres.
        /// </summary>
        /// <summary>
        /// Deux niveaux seulement, et c'est une limite physique, pas un choix.
        ///
        /// Verifie a l'image : en dessous d'un ecart d'environ 9 Delta E, le chiffre
        /// n'est plus lisible par PERSONNE une fois disperse en pastilles. Une planche
        /// plus subtile n'aurait donc pas depiste les anomalies legeres, elle aurait
        /// piege tout le monde.
        ///
        /// Cacher un chiffre a une anomalie LEGERE demanderait un ecart de couleur si
        /// faible qu'une vision normale ne le verrait pas non plus : la planche ne
        /// separerait plus rien. Les anomalies legeres ne se depistent donc pas par
        /// des planches - elles se MESURENT, et c'est le role de l'escalier, que la
        /// fenetre lance sur les trois axes quand les planches ne trouvent rien.
        /// </summary>
        private static readonly double[] Levels = { 100 };
        private static readonly double[] MinNormal = { 14 };

        /// <summary>Deux planches par deficience : une erreur d'inattention ne suffit pas a accuser.</summary>
        private const int PlatesPerAxis = 2;

        public static List<VisionPlate> Plates(int seed)
        {
            Random rnd = new Random(seed);
            List<VisionPlate> plates = new List<VisionPlate>();
            _recentDigits.Clear();

            foreach (ColorFilter target in Axes)
            {
                double[] d = Vision.ConfusionDirection(target);

                for (int lvl = 0; lvl < Levels.Length; lvl++)
                {
                    double level = Levels[lvl];
                    List<VisionPlate> found = new List<VisionPlate>();
                    List<double> scores = new List<double>();

                    foreach (double[] anchor in Candidates())
                    {
                        double t = HiddenSpread(anchor, d, target, level);
                        if (t < 0.03) continue;

                        Color a = Rgb(anchor, d, -t / 2), b = Rgb(anchor, d, +t / 2);
                        double normal = Vision.DeltaE(a, b);
                        if (normal < MinNormal[lvl]) continue;       // invisible aussi pour une vision normale

                        // Une planche doit accuser UNE deficience : si les deux autres
                        // ne la lisent pas non plus, elle ne distingue rien.
                        double worstOther = double.MaxValue;
                        foreach (ColorFilter other in Axes)
                        {
                            if (other == target) continue;
                            worstOther = Math.Min(worstOther, PerceivedDelta(other, level, a, b));
                        }
                        if (worstOther < 2.0) continue;

                        VisionPlate candidate = Make(target, a, b, rnd);
                        candidate.Level = level;
                        found.Add(candidate);
                        scores.Add(worstOther);
                    }

                    // Les ancrages qui separent le mieux les trois visions.
                    for (int pick = 0; pick < PlatesPerAxis && found.Count > 0; pick++)
                    {
                        int best = 0;
                        for (int i = 1; i < scores.Count; i++) if (scores[i] > scores[best]) best = i;
                        plates.Add(found[best]);
                        found.RemoveAt(best);
                        scores.RemoveAt(best);
                    }
                }
            }

            // Planches de controle : le chiffre ne differe que par la CLARTE, qu'aucune
            // deficience chromatique ne touche. Les rater, c'est avoir repondu au
            // hasard - et le resultat doit alors le dire.
            plates.Add(Make(ColorFilter.None, Gray(0.34), Gray(0.68), rnd));
            plates.Add(Make(ColorFilter.None, Gray(0.72), Gray(0.40), rnd));

            return plates;
        }

        private static Color Gray(double v) { return Color.FromArgb(Comp(v), Comp(v), Comp(v)); }

        private static VisionPlate Make(ColorFilter axis, Color figure, Color background, Random rnd)
        {
            VisionPlate p = new VisionPlate();
            p.Axis = axis;
            p.Figure = figure;
            p.Background = background;
            p.Seed = rnd.Next(int.MaxValue);

            // Un chiffre different d'une planche a l'autre : repeter le meme invite a
            // repondre de memoire plutot qu'a regarder.
            for (int tries = 0; tries < 12; tries++)
            {
                p.Digit = DigitPool[rnd.Next(DigitPool.Length)];
                if (!_recentDigits.Contains(p.Digit)) break;
            }
            _recentDigits.Add(p.Digit);
            if (_recentDigits.Count > 3) _recentDigits.RemoveAt(0);

            List<int> choices = new List<int>();
            choices.Add(p.Digit);
            while (choices.Count < 4)
            {
                int c = DigitPool[rnd.Next(DigitPool.Length)];
                if (!choices.Contains(c)) choices.Add(c);
            }
            // Melange, sinon la bonne reponse serait toujours le premier bouton.
            for (int i = choices.Count - 1; i > 0; i--)
            {
                int j = rnd.Next(i + 1);
                int tmp = choices[i]; choices[i] = choices[j]; choices[j] = tmp;
            }
            p.Choices = choices.ToArray();
            return p;
        }

        /// <summary>
        /// Conclusion des planches : la deficience dont les planches ont ete ratees.
        ///
        /// `confidence` va de 0 a 100. Il retombe quand les planches d'un autre axe
        /// sont ratees aussi, et s'effondre quand une planche de controle l'est : le
        /// test dit alors qu'il ne sait pas, plutot que d'annoncer un diagnostic tire
        /// de reponses au hasard.
        /// </summary>
        /// <summary>
        /// Planches ratees par axe. La fenetre s'en sert pour savoir si les planches
        /// tranchent ou si deux axes restent a egalite - auquel cas elle mesure plutot
        /// que de trancher a pile ou face.
        /// </summary>
        public static Dictionary<ColorFilter, int> Misses(List<VisionPlate> plates, List<bool> read)
        {
            Dictionary<ColorFilter, int> missed = new Dictionary<ColorFilter, int>();
            foreach (ColorFilter f in Axes) missed[f] = 0;
            if (plates == null || read == null || plates.Count != read.Count) return missed;

            for (int i = 0; i < plates.Count; i++)
                if (plates[i].Axis != ColorFilter.None && !read[i]) missed[plates[i].Axis]++;
            return missed;
        }

        /// <summary>Planches de controle ratees : au-dela de zero, le test n'est pas fiable.</summary>
        public static int ControlsMissed(List<VisionPlate> plates, List<bool> read)
        {
            int n = 0;
            if (plates == null || read == null || plates.Count != read.Count) return 0;
            for (int i = 0; i < plates.Count; i++)
                if (plates[i].Axis == ColorFilter.None && !read[i]) n++;
            return n;
        }

        public static ColorFilter TypeFromPlates(List<VisionPlate> plates, List<bool> read, out int confidence)
        {
            confidence = 0;
            if (plates == null || read == null || plates.Count != read.Count) return ColorFilter.None;

            Dictionary<ColorFilter, int> missed = Misses(plates, read);
            Dictionary<ColorFilter, int> total = new Dictionary<ColorFilter, int>();
            foreach (ColorFilter f in Axes) total[f] = 0;
            foreach (VisionPlate p in plates) if (p.Axis != ColorFilter.None) total[p.Axis]++;
            int controlsMissed = ControlsMissed(plates, read);

            ColorFilter best = ColorFilter.None;
            int bestMissed = 0, others = 0;
            foreach (ColorFilter f in Axes)
                if (missed[f] > bestMissed) { bestMissed = missed[f]; best = f; }

            if (best == ColorFilter.None || bestMissed == 0) return ColorFilter.None;

            foreach (ColorFilter f in Axes) if (f != best) others += missed[f];

            double share = bestMissed / (double)Math.Max(1, total[best]);
            double score = 100 * share - 25 * others - 60 * controlsMissed;
            confidence = (int)Math.Round(Math.Max(0, Math.Min(100, score)));
            return best;
        }
    }

    /// <summary>
    /// Un reglage de vision enregistre : ce que le test a trouve, ou ce que la
    /// personne a ajuste elle-meme, sous un nom qu'elle a choisi.
    ///
    /// Volontairement limite aux quatre valeurs qui decrivent la correction. Y mettre
    /// un profil complet - luminosite, temperature, gains - reviendrait a changer tout
    /// l'ecran en rappelant un reglage de daltonisme, ce que personne n'attend.
    /// </summary>
    public class VisionPreset
    {
        public string Name = "";
        public ColorFilter Filter = ColorFilter.Deuteranopia;
        public double Severity = 100;
        public double Strength = 100;
        public FilterMode Mode = FilterMode.Correction;

        public static VisionPreset FromProfile(string name, Profile p)
        {
            VisionPreset v = new VisionPreset();
            v.Name = name;
            v.Filter = p.Filter;
            v.Severity = p.VisionSeverity;
            v.Strength = p.FilterStrength;
            v.Mode = p.Mode;
            return v;
        }

        public void ApplyTo(Profile p)
        {
            p.Filter = Filter;
            p.VisionSeverity = Severity;
            p.FilterStrength = Strength;
            p.Mode = Mode;
        }

        /// <summary>Resume affichable : ce que ce reglage fait, en une ligne.</summary>
        public string Describe()
        {
            if (!ColorMatrixEffect.IsVisionFilter(Filter)) return "aucune correction";
            return (Mode == FilterMode.Simulation ? "simulation " : "")
                 + Vision.PlainName(Filter).ToLowerInvariant()
                 + string.Format(CultureInfo.CurrentCulture, ", gravite {0:0} %, intensite {1:0} %",
                                 Severity, Strength);
        }

        public string Serialize()
        {
            CultureInfo inv = CultureInfo.InvariantCulture;
            return string.Join("~", new string[] {
                Esc(Name), ((int)Filter).ToString(inv),
                Severity.ToString("0.##", inv), Strength.ToString("0.##", inv),
                Mode == FilterMode.Simulation ? "1" : "0"
            });
        }

        public static VisionPreset Deserialize(string s)
        {
            VisionPreset v = new VisionPreset();
            try
            {
                CultureInfo inv = CultureInfo.InvariantCulture;
                string[] f = s.Split('~');
                if (f.Length > 0) v.Name = Unesc(f[0]);
                if (f.Length > 1) v.Filter = (ColorFilter)int.Parse(f[1], inv);
                if (f.Length > 2) v.Severity = double.Parse(f[2], inv);
                if (f.Length > 3) v.Strength = double.Parse(f[3], inv);
                if (f.Length > 4) v.Mode = f[4] == "1" ? FilterMode.Simulation : FilterMode.Correction;
            }
            catch { }
            return v;
        }

        // Le nom est libre : il peut contenir les caracteres qui servent de separateurs.
        private static string Esc(string s)
        {
            return s.Replace("\\", "\\\\").Replace("~", "\\t").Replace("|", "\\p").Replace("\n", " ");
        }

        private static string Unesc(string s)
        {
            return s.Replace("\\p", "|").Replace("\\t", "~").Replace("\\\\", "\\");
        }
    }
}
