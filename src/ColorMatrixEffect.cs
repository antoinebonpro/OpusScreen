using System;
using System.Runtime.InteropServices;

namespace LumaFlux
{
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

        private static bool EnsureInit()
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

        /// <summary>Applique saturation et filtre. Retourne false si l'etage n'est pas disponible.</summary>
        public static bool Apply(double saturationPercent, ColorFilter filter)
        {
            bool neutral = Math.Abs(saturationPercent - 100) < 0.5 && filter == ColorFilter.None;

            if (neutral)
            {
                Reset();
                return true;
            }

            if (!EnsureInit()) return false;

            float[] m = Multiply(SaturationMatrix(saturationPercent / 100.0), FilterMatrix(filter));

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

        private static float[] FilterMatrix(ColorFilter f)
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
                    return Daltonize(f);

                default:
                    return Identity();
            }
        }

        /// <summary>
        /// Filtre d'assistance pour daltoniens, et non simulation de leur vision.
        ///
        /// Principe : on simule ce que la personne ne distingue pas, on mesure l'ecart
        /// avec l'image d'origine, et on reinjecte cet ecart sur les canaux qu'elle
        /// percoit encore. Deux couleurs autrefois confondues redeviennent distinctes.
        ///
        ///     erreur   = pixel x (I - Simulation)
        ///     resultat = pixel + erreur x Redistribution
        ///     donc  M  = I + (I - Simulation) x Redistribution
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
        private static float[] Daltonize(ColorFilter f)
        {
            double[,] sim;
            switch (f)
            {
                case ColorFilter.Protanopia:
                    sim = new double[,] { { 0.567, 0.558, 0.000 },
                                          { 0.433, 0.442, 0.242 },
                                          { 0.000, 0.000, 0.758 } };
                    break;
                case ColorFilter.Deuteranopia:
                    sim = new double[,] { { 0.625, 0.700, 0.000 },
                                          { 0.375, 0.300, 0.300 },
                                          { 0.000, 0.000, 0.700 } };
                    break;
                default: // Tritanopia
                    sim = new double[,] { { 0.950, 0.000, 0.000 },
                                          { 0.050, 0.433, 0.475 },
                                          { 0.000, 0.567, 0.525 } };
                    break;
            }

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

            // M3 = I + D x shift
            double[,] m3 = new double[3, 3];
            for (int i = 0; i < 3; i++)
                for (int j = 0; j < 3; j++)
                {
                    double acc = 0;
                    for (int k = 0; k < 3; k++) acc += d[i, k] * shift[k, j];
                    m3[i, j] = ((i == j) ? 1.0 : 0.0) + acc;
                }

            float[] m = Identity();
            for (int i = 0; i < 3; i++)
                for (int j = 0; j < 3; j++)
                    m[i * 5 + j] = (float)m3[i, j];
            return m;
        }
    }
}
