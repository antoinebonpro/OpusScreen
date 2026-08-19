using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Anneau lumineux qui entoure le pointeur.
    ///
    /// Perdre le pointeur de vue est le premier obstacle rapporte en basse vision,
    /// et il empire avec la taille des ecrans : un curseur de 32 pixels sur un bureau
    /// de plusieurs millions n'est pas une cible, c'est une aiguille. Windows propose
    /// bien d'agrandir le curseur, mais un curseur plus gros reste de la meme couleur
    /// que ce qu'il survole. Un anneau de couleur franche, lui, se detache de tout.
    ///
    /// La fenetre est decoupee en anneau par une region : il n'y a donc aucun pixel
    /// au centre, et rien ne recouvre ce que l'on cherche a regarder.
    /// </summary>
    public class CursorBeacon : IDisposable
    {
        private BeaconWindow _window;
        private readonly Timer _follow = new Timer();
        private int _size = 72;
        private Color _color = Color.FromArgb(255, 168, 66);
        private int _opacity = 70;   // en pourcentage

        public const int MinSize = 36;
        public const int MaxSize = 180;

        public bool IsVisible { get { return _window != null && _window.Visible; } }

        public CursorBeacon()
        {
            // 60 images par seconde : en dessous, l'anneau traine visiblement derriere
            // le pointeur, ce qui le rend plus genant qu'utile.
            _follow.Interval = 16;
            _follow.Tick += OnFollow;
        }

        public int Size
        {
            get { return _size; }
            set
            {
                int v = value < MinSize ? MinSize : (value > MaxSize ? MaxSize : value);
                if (v == _size) return;
                _size = v;
                if (_window != null) _window.Reshape(_size);
            }
        }

        public Color Color
        {
            get { return _color; }
            set { _color = value; if (_window != null) _window.SetColor(value); }
        }

        /// <summary>Opacite en pourcentage. Jamais opaque : l'anneau ne doit rien cacher.</summary>
        public int Opacity
        {
            get { return _opacity; }
            set
            {
                int v = value < 10 ? 10 : (value > 100 ? 100 : value);
                _opacity = v;
                if (_window != null) _window.SetOpacity(v);
            }
        }

        public void Show()
        {
            if (_window == null) _window = new BeaconWindow();

            // La forme, la couleur et l'opacite sont reappliquees a chaque affichage,
            // et pas seulement a la creation : la restauration d'urgence met l'opacite
            // de toutes les fenetres connues a zero, et l'anneau serait sinon revenu
            // parfaitement invisible - un interrupteur allume devant un ecran inchange.
            _window.Reshape(_size);
            _window.SetColor(_color);
            _window.ShowNoActivate();
            _window.SetOpacity(_opacity);

            _follow.Start();
            OnFollow(null, EventArgs.Empty);
        }

        public void Hide()
        {
            _follow.Stop();
            if (_window != null) _window.Hide();
        }

        public void SetVisible(bool on) { if (on) Show(); else Hide(); }

        [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point p);

        private void OnFollow(object sender, EventArgs e)
        {
            if (_window == null || !_window.Visible) return;
            Point p;
            if (!GetCursorPos(out p)) return;
            _window.CenterOn(p);
        }

        public void Dispose()
        {
            try { _follow.Stop(); _follow.Dispose(); } catch { }
            try { if (_window != null) _window.Dispose(); } catch { }
            _window = null;
        }

        // ------------------------------------------------------------------ la fenetre

        private class BeaconWindow : Form
        {
            private Color _fill = Color.Orange;

            public BeaconWindow()
            {
                FormBorderStyle = FormBorderStyle.None;
                ShowInTaskbar = false;
                StartPosition = FormStartPosition.Manual;
                TopMost = true;
                Enabled = false;
                DoubleBuffered = true;
            }

            protected override CreateParams CreateParams
            {
                get
                {
                    CreateParams cp = base.CreateParams;
                    cp.ExStyle |= Native.WS_EX_LAYERED
                                | Native.WS_EX_TRANSPARENT   // les clics traversent
                                | Native.WS_EX_TOPMOST
                                | Native.WS_EX_TOOLWINDOW
                                | Native.WS_EX_NOACTIVATE;
                    return cp;
                }
            }

            protected override bool ShowWithoutActivation { get { return true; } }

            [DllImport("user32.dll")]
            private static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);

            private const uint WDA_EXCLUDEFROMCAPTURE = 0x11;

            protected override void OnHandleCreated(EventArgs e)
            {
                base.OnHandleCreated(e);

                // L'anneau est une aide a l'ecran, pas un element du document :
                // il n'a rien a faire dans une capture ni dans un partage d'ecran.
                try { SetWindowDisplayAffinity(Handle, WDA_EXCLUDEFROMCAPTURE); } catch { }
                SafetyGuard.RegisterOverlay(Handle);
            }

            protected override void OnHandleDestroyed(EventArgs e)
            {
                SafetyGuard.UnregisterOverlay(Handle);
                base.OnHandleDestroyed(e);
            }

            /// <summary>
            /// Redecoupe la fenetre en anneau. L'epaisseur suit le diametre : un
            /// anneau fin autour d'un grand cercle disparait, un anneau epais autour
            /// d'un petit cercle masque la cible.
            /// </summary>
            public void Reshape(int diameter)
            {
                Size = new Size(diameter, diameter);
                int thickness = Math.Max(3, diameter / 9);

                using (GraphicsPath outer = new GraphicsPath())
                using (GraphicsPath inner = new GraphicsPath())
                {
                    outer.AddEllipse(0, 0, diameter, diameter);
                    inner.AddEllipse(thickness, thickness, diameter - thickness * 2, diameter - thickness * 2);

                    Region r = new Region(outer);
                    r.Exclude(inner);
                    Region = r;
                }
                Invalidate();
            }

            public void SetColor(Color c)
            {
                _fill = c;
                BackColor = c;
                Invalidate();
            }

            public void SetOpacity(int percent)
            {
                byte a = (byte)Math.Round(percent * 2.55);
                if (a < 26) a = 26;
                if (a > 235) a = 235;   // jamais opaque
                try { Native.SetLayeredWindowAttributes(Handle, 0, a, Native.LWA_ALPHA); } catch { }
            }

            public void ShowNoActivate()
            {
                if (!Visible) Show();
                try
                {
                    Native.SetWindowPos(Handle, Native.HWND_TOPMOST, 0, 0, 0, 0,
                        Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
                }
                catch { }
            }

            public void CenterOn(Point p)
            {
                Location = new Point(p.X - Width / 2, p.Y - Height / 2);
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                // La region a deja decoupe l'anneau ; il ne reste qu'a le remplir.
                // Un bord sombre lui rend sa lisibilite sur un fond de la meme teinte.
                Graphics g = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (SolidBrush b = new SolidBrush(_fill))
                    g.FillEllipse(b, 0, 0, Width, Height);
                using (Pen p = new Pen(Color.FromArgb(150, 0, 0, 0), 1.5f))
                {
                    g.DrawEllipse(p, 0.75f, 0.75f, Width - 1.5f, Height - 1.5f);
                    int t = Math.Max(3, Width / 9);
                    g.DrawEllipse(p, t, t, Width - t * 2, Height - t * 2);
                }
            }
        }
    }
}
