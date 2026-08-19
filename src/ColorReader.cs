using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Identificateur de couleur : dit a voix d'ecrit ce que le pointeur survole.
    ///
    /// C'est l'outil que reclament en premier les personnes daltoniennes, et celui
    /// qu'aucun des concurrents ne propose. Un filtre ecarte les couleurs les unes
    /// des autres ; il ne repond pas a la question posee cent fois par jour :
    /// « ce fil, ce graphique, ce bouton - il est de quelle couleur ? »
    ///
    /// La lecture se fait sur le bureau AVANT la table de couleurs de la carte
    /// graphique et avant la matrice plein ecran : les deux s'appliquent a la sortie
    /// video, pas au dessin. La couleur annoncee est donc celle que l'application
    /// a reellement dessinee, et non celle deformee par les reglages en cours -
    /// c'est la seule reponse qui ait une valeur.
    /// </summary>
    public class ColorReader : IDisposable
    {
        private ReaderWindow _window;
        private readonly Timer _tick = new Timer();

        /// <summary>Taille du carre echantillonne autour du pointeur, en pixels d'ecran.</summary>
        private const int GridPixels = 9;

        public bool IsVisible { get { return _window != null && _window.Visible; } }

        public ColorReader()
        {
            _tick.Interval = 60;
            _tick.Tick += OnTick;
        }

        public void Toggle()
        {
            if (IsVisible) Hide(); else Show();
        }

        public void Show()
        {
            if (_window == null) _window = new ReaderWindow();
            Update();
            _window.ShowNoActivate();
            _tick.Start();
        }

        public void Hide()
        {
            _tick.Stop();
            if (_window != null) _window.Hide();
        }

        private void OnTick(object sender, EventArgs e) { Update(); }

        private void Update()
        {
            if (_window == null) return;
            Point p;
            if (!GetCursorPos(out p)) return;
            _window.Follow(p, Sample(p, GridPixels));
        }

        /// <summary>
        /// Copie la couleur sous le pointeur dans le presse-papiers, et montre
        /// brievement la lecture pour que le geste ne soit pas silencieux.
        /// </summary>
        public string CopyColorUnderCursor()
        {
            Point p;
            if (!GetCursorPos(out p)) return "";

            Color c = PixelAt(p.X, p.Y);
            string hex = string.Format("#{0:X2}{1:X2}{2:X2}", c.R, c.G, c.B);
            try { Clipboard.SetText(hex); } catch { }

            if (!IsVisible)
            {
                Show();
                // La lecture reste affichee assez longtemps pour etre lue, puis
                // disparait : l'outil rend service sans rien laisser trainer.
                Timer once = new Timer();
                once.Interval = 2500;
                once.Tick += delegate
                {
                    once.Stop();
                    once.Dispose();
                    Hide();
                };
                once.Start();
            }
            return hex + "  " + Vision.DescribeColor(c);
        }

        // ------------------------------------------------------------------ lecture d'ecran

        [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point p);
        [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);
        [DllImport("gdi32.dll")] private static extern uint GetPixel(IntPtr hdc, int x, int y);

        public static Color PixelAt(int x, int y)
        {
            IntPtr dc = GetDC(IntPtr.Zero);
            if (dc == IntPtr.Zero) return Color.Black;
            try
            {
                uint v = GetPixel(dc, x, y);
                if (v == 0xFFFFFFFF) return Color.Black;   // CLR_INVALID
                return Color.FromArgb((int)(v & 0xFF), (int)((v >> 8) & 0xFF), (int)((v >> 16) & 0xFF));
            }
            finally { ReleaseDC(IntPtr.Zero, dc); }
        }

        /// <summary>Carre de pixels centre sur le pointeur, pour la grille agrandie.</summary>
        private static Color[,] Sample(Point center, int size)
        {
            Color[,] grid = new Color[size, size];
            int half = size / 2;

            IntPtr dc = GetDC(IntPtr.Zero);
            if (dc == IntPtr.Zero) return grid;
            try
            {
                for (int y = 0; y < size; y++)
                    for (int x = 0; x < size; x++)
                    {
                        uint v = GetPixel(dc, center.X - half + x, center.Y - half + y);
                        grid[x, y] = v == 0xFFFFFFFF
                            ? Color.FromArgb(24, 24, 24)
                            : Color.FromArgb((int)(v & 0xFF), (int)((v >> 8) & 0xFF), (int)((v >> 16) & 0xFF));
                    }
            }
            finally { ReleaseDC(IntPtr.Zero, dc); }
            return grid;
        }

        public void Dispose()
        {
            try { _tick.Stop(); _tick.Dispose(); } catch { }
            try { if (_window != null) _window.Dispose(); } catch { }
            _window = null;
        }

        // ------------------------------------------------------------------ la fenetre

        /// <summary>
        /// Etiquette qui suit le pointeur. Elle ne prend jamais le focus et laisse
        /// passer les clics : lire une couleur ne doit pas empecher de travailler
        /// dessus au meme moment.
        /// </summary>
        private class ReaderWindow : Form
        {
            private Color[,] _grid;
            private Color _center = Color.Black;
            private const int CellSize = 13;
            private const int GridSide = GridPixels * CellSize;
            private const int PanelW = 214;

            public ReaderWindow()
            {
                FormBorderStyle = FormBorderStyle.None;
                ShowInTaskbar = false;
                StartPosition = FormStartPosition.Manual;
                TopMost = true;
                Enabled = false;
                BackColor = Theme.Bg;
                ClientSize = new Size(GridSide + PanelW + 24, GridSide + 16);
                SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                       | ControlStyles.OptimizedDoubleBuffer, true);
            }

            protected override CreateParams CreateParams
            {
                get
                {
                    CreateParams cp = base.CreateParams;
                    cp.ExStyle |= Native.WS_EX_LAYERED
                                | Native.WS_EX_TRANSPARENT
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

                // Sans cette exclusion, la fenetre finirait par se lire elle-meme
                // des qu'elle passe sous la zone echantillonnee - et annoncerait
                // sa propre couleur de fond.
                try { SetWindowDisplayAffinity(Handle, WDA_EXCLUDEFROMCAPTURE); } catch { }
                try { Native.SetLayeredWindowAttributes(Handle, 0, 248, Native.LWA_ALPHA); } catch { }
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

            /// <summary>
            /// Se place a cote du pointeur, en basculant de cote quand le bord de
            /// l'ecran approche : une etiquette a moitie sortie ne se lit pas.
            /// </summary>
            public void Follow(Point cursor, Color[,] grid)
            {
                _grid = grid;
                _center = grid[GridPixels / 2, GridPixels / 2];

                Screen sc = Screen.FromPoint(cursor);
                int x = cursor.X + 26;
                int y = cursor.Y + 26;
                if (x + Width > sc.WorkingArea.Right) x = cursor.X - Width - 26;
                if (y + Height > sc.WorkingArea.Bottom) y = cursor.Y - Height - 26;
                if (x < sc.WorkingArea.Left) x = sc.WorkingArea.Left;
                if (y < sc.WorkingArea.Top) y = sc.WorkingArea.Top;

                Location = new Point(x, y);
                Invalidate();
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                Graphics g = e.Graphics;
                g.Clear(Theme.Bg);

                using (Pen border = new Pen(Theme.BorderStrong))
                    g.DrawRectangle(border, 0, 0, Width - 1, Height - 1);

                DrawGrid(g, 8, 8);
                DrawReadout(g, GridSide + 18, 8);
            }

            /// <summary>Grille agrandie : chaque carre est un pixel reel de l'ecran.</summary>
            private void DrawGrid(Graphics g, int ox, int oy)
            {
                if (_grid == null) return;

                for (int y = 0; y < GridPixels; y++)
                    for (int x = 0; x < GridPixels; x++)
                        using (SolidBrush b = new SolidBrush(_grid[x, y]))
                            g.FillRectangle(b, ox + x * CellSize, oy + y * CellSize, CellSize, CellSize);

                using (Pen grid = new Pen(Color.FromArgb(70, 0, 0, 0)))
                    for (int i = 0; i <= GridPixels; i++)
                    {
                        g.DrawLine(grid, ox + i * CellSize, oy, ox + i * CellSize, oy + GridSide);
                        g.DrawLine(grid, ox, oy + i * CellSize, ox + GridSide, oy + i * CellSize);
                    }

                // Le pixel effectivement mesure, cercle de blanc puis de noir : le
                // repere reste visible quel que soit le fond qu'il entoure.
                int c = GridPixels / 2;
                Rectangle target = new Rectangle(ox + c * CellSize, oy + c * CellSize, CellSize, CellSize);
                using (Pen outer = new Pen(Color.White, 2)) g.DrawRectangle(outer, target);
                using (Pen inner = new Pen(Color.Black, 1))
                    g.DrawRectangle(inner, target.X - 1, target.Y - 1, target.Width + 2, target.Height + 2);

                using (Pen frame = new Pen(Theme.Border))
                    g.DrawRectangle(frame, ox, oy, GridSide, GridSide);
            }

            private void DrawReadout(Graphics g, int ox, int oy)
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;

                using (SolidBrush b = new SolidBrush(_center))
                    g.FillRectangle(b, ox, oy, 44, 44);
                using (Pen p = new Pen(Theme.BorderStrong))
                    g.DrawRectangle(p, ox, oy, 44, 44);

                string name = Vision.DescribeColor(_center);
                string hex = string.Format("#{0:X2}{1:X2}{2:X2}", _center.R, _center.G, _center.B);
                string rgb = string.Format("R {0}   V {1}   B {2}", _center.R, _center.G, _center.B);

                using (Font big = Theme.Heading)
                    TextRenderer.DrawText(g, Cap(name), big,
                        new Rectangle(ox + 54, oy - 2, PanelW - 62, 22), Theme.Fg,
                        TextFormatFlags.Left | TextFormatFlags.EndEllipsis);

                using (Font mono = Theme.Mono)
                {
                    TextRenderer.DrawText(g, hex, mono,
                        new Rectangle(ox + 54, oy + 20, PanelW - 62, 16), Theme.Accent, TextFormatFlags.Left);
                    TextRenderer.DrawText(g, rgb, mono,
                        new Rectangle(ox + 54, oy + 36, PanelW - 62, 16), Theme.Dim, TextFormatFlags.Left);
                }

                using (Font small = Theme.Small)
                    TextRenderer.DrawText(g, "Ctrl+Alt+Maj+C : copier   -   Ctrl+Alt+C : fermer", small,
                        new Rectangle(ox, oy + GridSide - 20, PanelW, 16), Theme.Faint, TextFormatFlags.Left);
            }

            private static string Cap(string s)
            {
                if (string.IsNullOrEmpty(s)) return s;
                return char.ToUpperInvariant(s[0]) + s.Substring(1);
            }
        }
    }
}
