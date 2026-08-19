using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Loupe plein ecran : le bureau entier est agrandi et suit le pointeur.
    ///
    /// Meme DLL que la matrice de couleur - magnification.dll - donc meme
    /// initialisation et, surtout, meme compositeur : l'agrandissement et les filtres
    /// pour daltoniens se cumulent sans se genonner. C'est ce qui manque a la loupe
    /// de Windows, qui ne connait pas les reglages de couleur de OpusScreen.
    ///
    /// La regle de securite vaut ici comme pour la gamma : une transformation plein
    /// ecran laissee en place rend la machine difficile a piloter. Elle est donc
    /// annulee par le raccourci de secours, a la fermeture, et sur exception.
    /// </summary>
    public static class ScreenMagnifier
    {
        [DllImport("magnification.dll")]
        private static extern bool MagSetFullscreenTransform(float magLevel, int xOffset, int yOffset);

        [DllImport("magnification.dll")]
        private static extern bool MagGetFullscreenTransform(ref float magLevel, ref int xOffset, ref int yOffset);

        [DllImport("magnification.dll")]
        private static extern bool MagShowSystemCursor(bool showCursor);

        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out Point p);

        public const double MinZoom = 1.0;
        public const double MaxZoom = 8.0;

        /// <summary>
        /// Cree a la premiere activation, et non a l'initialisation de la classe.
        ///
        /// Une minuterie Windows Forms appartient au thread qui la cree et n'egrene
        /// que si ce thread possede une file de messages. Or le premier contact avec
        /// cette classe peut venir du thread de SECOURS - il appelle ForceReset - ou
        /// du thread de sortie du processus. La minuterie serait alors attachee a un
        /// thread sans file de messages, et la loupe cesserait de suivre le pointeur
        /// sans que rien ne le signale. La creer dans SetZoom la lie au thread
        /// d'interface, seul a en avoir une.
        /// </summary>
        private static Timer _follow;

        private static double _zoom = 1.0;
        private static bool _active;
        private static bool _unavailable;

        /// <summary>Vrai quand la loupe agrandit reellement l'ecran.</summary>
        public static bool IsActive { get { return _active; } }

        /// <summary>Faux quand l'API a refuse : l'interface propose alors la loupe de Windows.</summary>
        public static bool Available { get { return !_unavailable; } }

        public static double Zoom { get { return _zoom; } }

        /// <summary>
        /// Regle le facteur d'agrandissement. 1,0 eteint la loupe.
        /// Retourne faux si le systeme n'accepte pas l'agrandissement plein ecran.
        /// </summary>
        public static bool SetZoom(double zoom)
        {
            if (zoom < MinZoom) zoom = MinZoom;
            if (zoom > MaxZoom) zoom = MaxZoom;
            _zoom = zoom;

            if (zoom <= MinZoom + 0.001)
            {
                Stop();
                return true;
            }

            if (_unavailable) return false;
            if (!ColorMatrixEffect.EnsureInit()) { _unavailable = true; return false; }

            if (_follow == null)
            {
                // 30 images par seconde : au-dela le suivi ne parait pas plus fluide,
                // en dessous le pointeur semble glisser hors de la zone agrandie.
                _follow = new Timer();
                _follow.Interval = 33;
                _follow.Tick += OnFollow;
            }

            if (!ApplyTransform())
            {
                // Un echec au tout premier appel signifie que la fonction n'est pas
                // servie par ce systeme ; inutile de reessayer trente fois par seconde.
                if (!_active) _unavailable = true;
                return false;
            }

            _active = true;
            _follow.Start();
            return true;
        }

        /// <summary>Remet l'ecran a l'echelle 1. Sans effet si la loupe n'est pas active.</summary>
        public static void Stop()
        {
            if (_follow != null) _follow.Stop();
            if (!_active) return;
            _active = false;
            try { MagSetFullscreenTransform(1.0f, 0, 0); } catch { }
            try { MagShowSystemCursor(true); } catch { }
        }

        /// <summary>
        /// Annulation inconditionnelle, appelable depuis n'importe quel etat.
        /// Utilisee par le filet de securite : elle ne suppose rien de l'etat interne.
        /// </summary>
        public static void ForceReset()
        {
            _active = false;
            try { if (_follow != null) _follow.Stop(); } catch { }
            try { MagSetFullscreenTransform(1.0f, 0, 0); } catch { }
            try { MagShowSystemCursor(true); } catch { }
        }

        private static void OnFollow(object sender, EventArgs e)
        {
            if (!_active) { if (_follow != null) _follow.Stop(); return; }
            ApplyTransform();
        }

        /// <summary>
        /// Centre la zone agrandie sur le pointeur, sans jamais sortir du bureau.
        ///
        /// Les decalages attendus par l'API sont exprimes en coordonnees NON agrandies
        /// du coin superieur gauche de la zone montree. La plage utile va donc de 0 a
        /// la taille du bureau moins la taille de la fenetre visible - au-dela, on
        /// afficherait du vide.
        /// </summary>
        private static bool ApplyTransform()
        {
            try
            {
                Point cursor;
                if (!GetCursorPos(out cursor)) return false;

                Rectangle desktop = SystemInformation.VirtualScreen;
                double visibleW = desktop.Width / _zoom;
                double visibleH = desktop.Height / _zoom;

                double x = cursor.X - visibleW / 2.0;
                double y = cursor.Y - visibleH / 2.0;

                double maxX = desktop.Left + desktop.Width - visibleW;
                double maxY = desktop.Top + desktop.Height - visibleH;

                if (x < desktop.Left) x = desktop.Left;
                if (y < desktop.Top) y = desktop.Top;
                if (x > maxX) x = maxX;
                if (y > maxY) y = maxY;

                return MagSetFullscreenTransform((float)_zoom, (int)Math.Round(x), (int)Math.Round(y));
            }
            catch { return false; }
        }

        // ------------------------------------------------------------------ repli

        /// <summary>
        /// Ouvre la loupe de Windows.
        ///
        /// Repli assume : sur les systemes ou l'agrandissement plein ecran est refuse
        /// - Windows 7, sessions distantes, certaines strategies d'entreprise -
        /// mieux vaut conduire l'utilisateur vers l'outil integre que lui laisser un
        /// interrupteur qui ne fait rien.
        /// </summary>
        public static bool StartWindowsMagnifier()
        {
            try
            {
                Process.Start(new ProcessStartInfo("magnify.exe") { UseShellExecute = true });
                return true;
            }
            catch { return false; }
        }
    }
}
