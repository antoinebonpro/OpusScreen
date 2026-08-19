using System;
using System.Runtime.InteropServices;

namespace OpusScreen
{
    /// <summary>
    /// Ce que l'on demande a un filtre de deficience chromatique.
    ///
    /// Les deux usages n'ont rien a voir et sont pourtant servis par les memes
    /// matrices : la personne daltonienne veut ECARTER les couleurs qu'elle confond,
    /// le concepteur d'interface veut VOIR ce qu'elle percoit. Un seul reglage pour
    /// les deux serait ambigu ; deux modes explicites ne le sont pas.
    /// </summary>
    public enum FilterMode
    {
        Correction = 0,   // aide : les couleurs confondues sont ecartees
        Simulation        // demonstration : on affiche la vision deficiente
    }

    /// <summary>
    /// Quatrieme etage du pipeline : une matrice de couleur appliquee par le compositeur
    /// de Windows a tout le bureau, via l'API Magnification.
    ///
    /// Pourquoi cet etage existe : une LUT gamma traite chaque canal SEPAREMENT. Elle
    /// peut assombrir le bleu, mais elle ne peut pas calculer une valeur de rouge qui
    /// depend du vert. Or c'est exactement ce qu'exigent la saturation, l'inversion,
    /// le sepia et les filtres pour daltoniens. La matrice 5x5 de MagSetFullscreenColorEffect
    /// melange les canaux, ce que ni f.lux ni PangoBright ne savent faire.
    ///
    /// Limite assumee : l'effet est global au bureau, pas reglable ecran par ecran.
    /// C'est une contrainte de l'API, pas un choix ; l'ecran de reference est donc
    /// selectionnable dans la page Ecrans.
    /// </summary>
    public static class ColorMatrixEffect
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct MAGCOLOREFFECT
        {
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 25)]
            public float[] transform;
        }

        [DllImport("magnification.dll")] private static extern bool MagInitialize();
        [DllImport("magnification.dll")] private static extern bool MagUninitialize();
        [DllImport("magnification.dll")] private static extern bool MagSetFullscreenColorEffect(ref MAGCOLOREFFECT effect);

        private static bool _initialized;
        private static bool _unavailable;
        private static bool _effectActive;

        public static bool Available { get { return !_unavailable; } }
        public static bool IsActive { get { return _effectActive; } }

        /// <summary>
        /// Initialise magnification.dll. Partage avec la loupe : les deux fonctions
        /// vivent dans la meme DLL et un seul MagInitialize sert aux deux.
        /// </summary>
        internal static bool EnsureInit()
        {
            if (_unavailable) return false;
            if (_initialized) return true;
            try
            {
                _initialized = MagInitialize();
                if (!_initialized) _unavailable = true;
                return _initialized;
            }
            catch
            {
                // magnification.dll absente : Windows Server sans experience de bureau, par exemple.
                _unavailable = true;
                return false;
            }
        }

        // ------------------------------------------------------------------ application

        /// <summary>Applique saturation et filtre simple. Conserve pour les appels historiques.</summary>
        public static bool Apply(double saturationPercent, ColorFilter filter)
        {
            return Apply(saturationPercent, filter, 100, 100, FilterMode.Correction);
        }

        /// <summary>
        /// Applique l'etage complet.
        ///
        ///   severityPercent : gravite de la deficience, 0 = vision normale,
        ///                     100 = dichromatie complete. Entre les deux se trouvent
        ///                     les ANOMALIES (protanomalie, deuteranomalie...), de loin
        ///                     les plus repandues : les ignorer revenait a ne servir
        ///                     qu'une minorite de la minorite.
        ///   strengthPercent : intensite de la correction, sans effet en simulation.
        /// </summary>
        public static bool Apply(double saturationPercent, ColorFilter filter,
                                 double severityPercent, double strengthPercent, FilterMode mode)
        {
            if (IsNeutralRequest(saturationPercent, filter, severityPercent, strengthPercent, mode))
            {
                Reset();
                return true;
            }

            if (!EnsureInit()) return false;

            float[] m = BuildMatrix(saturationPercent, filter, severityPercent, strengthPercent, mode);

            MAGCOLOREFFECT fx = new MAGCOLOREFFECT();
            fx.transform = m;
            try
            {
                bool ok = MagSetFullscreenColorEffect(ref fx);
                _effectActive = ok;
                return ok;
            }
            catch { return false; }
        }

        /// <summary>Vrai si le reglage demande ne modifie rien : inutile d'armer l'etage.</summary>
        public static bool IsNeutralRequest(double saturationPercent, ColorFilter filter,
                                            double severityPercent, double strengthPercent, FilterMode mode)
        {
            if (Math.Abs(saturationPercent - 100) >= 0.5) return false;
            if (filter == ColorFilter.None) return true;

            if (IsVisionFilter(filter))
            {
                if (severityPercent < 0.5) return true;
                if (mode == FilterMode.Correction && strengthPercent < 0.5) return true;
            }
            return false;
        }

        /// <summary>Filtres pilotes par la gravite : ceux qui modelisent une deficience.</summary>
        public static bool IsVisionFilter(ColorFilter f)
        {
            return f == ColorFilter.Protanopia || f == ColorFilter.Deuteranopia || f == ColorFilter.Tritanopia;
        }

        /// <summary>Remet la matrice identite : le bureau retrouve ses couleurs exactes.</summary>
        public static void Reset()
        {
            if (!_initialized || _unavailable) return;
            try
            {
                MAGCOLOREFFECT fx = new MAGCOLOREFFECT();
                fx.transform = Identity();
                MagSetFullscreenColorEffect(ref fx);
                _effectActive = false;
            }
            catch { }
        }

        public static void Shutdown()
        {
            Reset();
            if (!_initialized) return;
            try { MagUninitialize(); } catch { }
            _initialized = false;
        }

        // ------------------------------------------------------------------ algebre
        //
        // Convention de l'API : le pixel est un vecteur ligne [R G B A 1] multiplie a
        // gauche de la matrice. Donc out[col] = somme sur row de in[row] * M[row][col].
        // La cinquieme ligne porte les decalages constants.

        public static float[] Identity()
        {
            float[] m = new float[25];
            for (int i = 0; i < 5; i++) m[i * 5 + i] = 1f;
            return m;
        }

        /// <summary>Produit de deux matrices 5x5 stockees a plat.</summary>
        private static float[] Multiply(float[] a, float[] b)
        {
            float[] r = new float[25];
            for (int i = 0; i < 5; i++)
                for (int j = 0; j < 5; j++)
                {
                    float sum = 0;
                    for (int k = 0; k < 5; k++) sum += a[i * 5 + k] * b[k * 5 + j];
                    r[i * 5 + j] = sum;
                }
            return r;
        }

        /// <summary>
        /// La matrice complete, saturation et filtre compris.
        ///
        /// Expose publiquement pour une raison precise : l'apercu de la page Couleur
        /// doit passer les couleurs par EXACTEMENT le meme calcul que l'ecran. Une
        /// version reecrite a cote avait fini par diverger - l'apercu ignorait purement
        /// et simplement les filtres pour daltoniens, qui sont pourtant ceux que l'on
        /// a le plus besoin de comparer avant de les appliquer.
        /// </summary>
        public static float[] BuildMatrix(double saturationPercent, ColorFilter filter,
                                          double severityPercent, double strengthPercent, FilterMode mode)
        {
            return Multiply(SaturationMatrix(saturationPercent / 100.0),
                            FilterMatrix(filter, severityPercent, strengthPercent, mode));
        }

        // Coefficients de luminance perceptuelle (Rec. 709), les memes que ceux
        // utilises pour convertir en niveaux de gris.
        private const double Lr = 0.2126, Lg = 0.7152, Lb = 0.0722;

        /// <summary>s = 0 -> niveaux de gris, s = 1 -> inchange, s = 2 -> tres sature.</summary>
        private static float[] SaturationMatrix(double s)
        {
            float[] m = Identity();
            double inv = 1.0 - s;

            m[0] = (float)(Lr * inv + s); m[1] = (float)(Lr * inv); m[2] = (float)(Lr * inv);
            m[5] = (float)(Lg * inv); m[6] = (float)(Lg * inv + s); m[7] = (float)(Lg * inv);
            m[10] = (float)(Lb * inv); m[11] = (float)(Lb * inv); m[12] = (float)(Lb * inv + s);
            return m;
        }

        /// <summary>Filtre a pleine gravite, en correction. Conserve pour les appels historiques.</summary>
        private static float[] FilterMatrix(ColorFilter f)
        {
            return FilterMatrix(f, 100, 100, FilterMode.Correction);
        }

        private static float[] FilterMatrix(ColorFilter f, double severityPercent,
                                            double strengthPercent, FilterMode mode)
        {
            switch (f)
            {
                case ColorFilter.Grayscale:
                    return SaturationMatrix(0);

                case ColorFilter.Invert:
                    {
                        float[] m = Identity();
                        m[0] = -1; m[6] = -1; m[12] = -1;
                        m[20] = 1; m[21] = 1; m[22] = 1;   // decalage : out = 1 - in
                        return m;
                    }

                case ColorFilter.InvertKeepHue:
                    return InvertKeepHue();

                case ColorFilter.Sepia:
                    {
                        float[] m = Identity();
                        // colonnes = destination R, G, B
                        m[0] = 0.393f; m[1] = 0.349f; m[2] = 0.272f;
                        m[5] = 0.769f; m[6] = 0.686f; m[7] = 0.534f;
                        m[10] = 0.189f; m[11] = 0.168f; m[12] = 0.131f;
                        return m;
                    }

                case ColorFilter.Protanopia:
                case ColorFilter.Deuteranopia:
                case ColorFilter.Tritanopia:
                    return mode == FilterMode.Simulation
                        ? Expand(Simulation(f, severityPercent / 100.0))
                        : Daltonize(f, severityPercent / 100.0, strengthPercent / 100.0);

                default:
                    return Identity();
            }
        }

        // ------------------------------------------------------------------ inversion douce

        /// <summary>
        /// Inversion de la LUMINOSITE, teintes conservees.
        ///
        /// L'inversion classique retourne aussi les teintes : le rouge devient cyan,
        /// une photo devient un negatif. C'est ce qui rend le « mode programmation »
        /// inutilisable des qu'une image est a l'ecran. Ici on inverse le clair et le
        /// sombre en laissant la teinte ou elle etait, ce que iOS appelle « inversion
        /// intelligente ».
        ///
        ///     inverser puis tourner la teinte d'un demi-tour se resume a
        ///         sortie = entree + (1 - 2 x luminance) x blanc
        ///
        /// Le blanc devient noir, le noir devient blanc, et un rouge sombre devient un
        /// rouge clair au lieu d'un cyan. Les hautes lumieres saturees sortent de la
        /// plage affichable et sont ecretees : c'est le prix de la conservation des
        /// teintes, et c'est le meme compromis que fait iOS.
        /// </summary>
        private static float[] InvertKeepHue()
        {
            float[] m = Identity();
            double[] lum = { Lr, Lg, Lb };
            for (int i = 0; i < 3; i++)
                for (int j = 0; j < 3; j++)
                    m[i * 5 + j] = (float)((i == j ? 1.0 : 0.0) - 2.0 * lum[i]);
            m[20] = 1; m[21] = 1; m[22] = 1;   // le +1 constant
            return m;
        }

        // ------------------------------------------------------------------ daltonisme

        /// <summary>
        /// Matrices de simulation a pleine gravite, en convention entree -> sortie.
        ///
        /// Ce sont les matrices classiques de la litterature (Vienot, Brettel, reprises
        /// par Fidaner) : elles ecrasent fortement l'axe de confusion propre a chaque
        /// deficience, de sorte que deux couleurs separees le long de cet axe ressortent
        /// quasi identiques. L'ecrasement est tres marque sans etre exactement total -
        /// ce sont des approximations publiees, et elles sont utilisees comme telles.
        /// </summary>
        public static double[,] SimulationMatrix(ColorFilter f)
        {
            return FullSimulation(f);
        }

        private static double[,] FullSimulation(ColorFilter f)
        {
            switch (f)
            {
                case ColorFilter.Protanopia:
                    return new double[,] { { 0.567, 0.558, 0.000 },
                                           { 0.433, 0.442, 0.242 },
                                           { 0.000, 0.000, 0.758 } };
                case ColorFilter.Deuteranopia:
                    return new double[,] { { 0.625, 0.700, 0.000 },
                                           { 0.375, 0.300, 0.300 },
                                           { 0.000, 0.000, 0.700 } };
                default: // Tritanopia
                    return new double[,] { { 0.950, 0.000, 0.000 },
                                           { 0.050, 0.433, 0.475 },
                                           { 0.000, 0.567, 0.525 } };
            }
        }

        /// <summary>
        /// Simulation a gravite reglable.
        ///
        /// La dichromatie - l'absence totale d'un type de cone - est le cas rare.
        /// Le cas frequent est l'ANOMALIE : le cone existe mais sa sensibilite est
        /// decalee, et la confusion n'est que partielle. On interpole donc entre
        /// l'identite (vision normale) et la dichromatie complete.
        ///
        /// C'est une approximation, et elle est assumee comme telle : le modele exact
        /// demanderait de decaler le pic d'absorption du cone dans l'espace LMS, ce qui
        /// n'est pas representable par une interpolation lineaire. Mais elle conserve
        /// la propriete qui compte - l'axe de confusion reste le meme, seule son
        /// amplitude change - et c'est ce que fait aussi le reglage d'intensite de
        /// macOS.
        /// </summary>
        private static double[,] Simulation(ColorFilter f, double severity)
        {
            if (severity < 0) severity = 0;
            if (severity > 1) severity = 1;

            double[,] full = FullSimulation(f);
            double[,] sim = new double[3, 3];
            for (int i = 0; i < 3; i++)
                for (int j = 0; j < 3; j++)
                    sim[i, j] = (1.0 - severity) * (i == j ? 1.0 : 0.0) + severity * full[i, j];
            return sim;
        }

        /// <summary>
        /// Filtre d'assistance pour daltoniens, et non simulation de leur vision.
        ///
        /// Principe : on simule ce que la personne ne distingue pas, on mesure l'ecart
        /// avec l'image d'origine, et on reinjecte cet ecart sur les canaux qu'elle
        /// percoit encore. Deux couleurs autrefois confondues redeviennent distinctes.
        ///
        ///     erreur   = pixel x (I - Simulation)
        ///     resultat = pixel + intensite x erreur x Redistribution
        ///     donc  M  = I + intensite x (I - Simulation) x Redistribution
        ///
        /// L'ordre des deux produits n'est pas interchangeable : la redistribution
        /// s'applique A l'erreur, pas l'inverse. Le produit est calcule ici plutot
        /// qu'ecrit a la main pre-multiplie, pour que la formule reste verifiable.
        ///
        /// Propriete a preserver : comme la simulation laisse les gris intacts, chaque
        /// colonne de (I - Simulation) est de somme nulle. Un gris produit donc une
        /// erreur nulle et ressort inchange - le filtre ne teinte jamais l'interface.
        ///
        /// Toutes les matrices sont ecrites en convention entree -> sortie :
        /// m[entree, sortie], la meme que celle attendue par l'API Magnification.
        /// </summary>
        private static float[] Daltonize(ColorFilter f, double severity, double strength)
        {
            if (strength < 0) strength = 0;
            if (strength > 1.5) strength = 1.5;

            double[,] sim = Simulation(f, severity);

            // Ou reverser l'erreur de chaque canal. Le canal deficient cede son erreur
            // aux deux autres ; les canaux sains conservent la leur (diagonale a 1).
            double[,] shift;
            if (f == ColorFilter.Tritanopia)
                shift = new double[,] { { 1.0, 0.0, 0.0 },     // erreur du rouge -> rouge
                                        { 0.0, 1.0, 0.0 },     // erreur du vert  -> vert
                                        { 0.7, 0.7, 0.0 } };   // erreur du bleu  -> rouge et vert
            else
                shift = new double[,] { { 0.0, 0.7, 0.7 },     // erreur du rouge -> vert et bleu
                                        { 0.0, 1.0, 0.0 },
                                        { 0.0, 0.0, 1.0 } };

            // D = I - sim
            double[,] d = new double[3, 3];
            for (int i = 0; i < 3; i++)
                for (int j = 0; j < 3; j++)
                    d[i, j] = ((i == j) ? 1.0 : 0.0) - sim[i, j];

            // M3 = I + intensite x D x shift
            double[,] m3 = new double[3, 3];
            for (int i = 0; i < 3; i++)
                for (int j = 0; j < 3; j++)
                {
                    double acc = 0;
                    for (int k = 0; k < 3; k++) acc += d[i, k] * shift[k, j];
                    m3[i, j] = ((i == j) ? 1.0 : 0.0) + strength * acc;
                }

            return Expand(m3);
        }

        /// <summary>Passe d'une matrice couleur 3x3 a la matrice 5x5 attendue par l'API.</summary>
        private static float[] Expand(double[,] m3)
        {
            float[] m = Identity();
            for (int i = 0; i < 3; i++)
                for (int j = 0; j < 3; j++)
                    m[i * 5 + j] = (float)m3[i, j];
            return m;
        }

        // ------------------------------------------------------------------ usage hors ecran

        /// <summary>
        /// Passe une couleur dans une matrice 5x5, exactement comme le fait le
        /// compositeur. Sert aux apercus et aux tests : une seule implementation de
        /// la regle, donc aucune divergence possible entre ce qui est montre et ce
        /// qui est applique.
        /// </summary>
        public static void Transform(float[] m, ref double r, ref double g, ref double b)
        {
            double[] inp = { r, g, b, 1, 1 };
            double or_ = 0, og = 0, ob = 0;
            for (int i = 0; i < 5; i++)
            {
                or_ += inp[i] * m[i * 5 + 0];
                og += inp[i] * m[i * 5 + 1];
                ob += inp[i] * m[i * 5 + 2];
            }
            r = or_ < 0 ? 0 : (or_ > 1 ? 1 : or_);
            g = og < 0 ? 0 : (og > 1 ? 1 : og);
            b = ob < 0 ? 0 : (ob > 1 ? 1 : ob);
        }

        /// <summary>Version couleur GDI, pour les apercus.</summary>
        public static System.Drawing.Color Transform(float[] m, System.Drawing.Color c)
        {
            double r = c.R / 255.0, g = c.G / 255.0, b = c.B / 255.0;
            Transform(m, ref r, ref g, ref b);
            return System.Drawing.Color.FromArgb(
                (int)Math.Round(r * 255), (int)Math.Round(g * 255), (int)Math.Round(b * 255));
        }
    }
}
