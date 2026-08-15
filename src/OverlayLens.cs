using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace LumaFlux
{
    /// <summary>
    /// La "fade lens" de PangoBright, reimplementee.
    ///
    /// Reverse engineering de PangoBright.exe : classe de fenetre "FadeLensScrClass",
    /// une fenetre par ecran, style WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST,
    /// remplie de la couleur de fondu, dont l'opacite est pilotee par
    /// SetLayeredWindowAttributes. C'est la seule technique qui descend vraiment bas,
    /// mais elle ne peut par nature que retirer de la lumiere - jamais en ajouter.
    ///
    /// Ici elle ne sert que sous le plancher gamma (35 %) : au-dessus, la LUT fait tout,
    /// ce qui evite d'avoir une fenetre posee sur le bureau sans raison.
    /// </summary>
    public class OverlayLens : Form
    {
        private byte _alpha;
        private Color _tint = Color.Black;
        private readonly Timer _topmostKeeper;

        public OverlayLens()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            BackColor = Color.Black;
            TopMost = true;
            Enabled = false;              // ne prend jamais le focus
            Opacity = 0;

            // PangoBright utilisait SetTimer pour se remettre au premier plan :
            // sans cela, toute fenetre passant en topmost apres nous couvrirait le voile.
            _topmostKeeper = new Timer();
            _topmostKeeper.Interval = 3000;
            _topmostKeeper.Tick += KeepOnTop;
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= Native.WS_EX_LAYERED       // opacite reglable
                            | Native.WS_EX_TRANSPARENT   // les clics traversent
                            | Native.WS_EX_TOPMOST       // au-dessus de tout
                            | Native.WS_EX_TOOLWINDOW    // absente d'Alt+Tab
                            | Native.WS_EX_NOACTIVATE;   // ne vole jamais le focus
                return cp;
            }
        }

        /// <summary>Empeche l'affichage de voler le focus a la fenetre active.</summary>
        protected override bool ShowWithoutActivation { get { return true; } }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);

        private const uint WDA_EXCLUDEFROMCAPTURE = 0x11;

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            SafetyGuard.RegisterOverlay(Handle);

            // Retire le voile de toute capture d'ecran. Double benefice : l'analyse de
            // contenu ne se mesure pas elle-meme, et les captures de l'utilisateur
            // sortent propres - defaut bien connu de PangoBright.
            try { SetWindowDisplayAffinity(Handle, WDA_EXCLUDEFROMCAPTURE); }
            catch { /* anterieur a Windows 10 2004 : le voile restera visible en capture */ }

            ApplyAlpha();
        }

        protected override void OnHandleDestroyed(EventArgs e)
        {
            SafetyGuard.UnregisterOverlay(Handle);
            base.OnHandleDestroyed(e);
        }

        private void KeepOnTop(object sender, EventArgs e)
        {
            if (!IsHandleCreated || _alpha == 0) return;
            try
            {
                Native.SetWindowPos(Handle, Native.HWND_TOPMOST, 0, 0, 0, 0,
                    Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
            }
            catch { }
        }

        public void CoverMonitor(MonitorInfo m)
        {
            Native.RECT r = m.Bounds;
            Bounds = new Rectangle(r.Left, r.Top, r.Width, r.Height);
        }

        public Color Tint
        {
            get { return _tint; }
            set { _tint = value; BackColor = value; }
        }

        /// <summary>
        /// transmission = 1.0 -> voile totalement absent ; 0.15 -> ne laisse passer que 15 %.
        /// Le voile est reellement masque quand il ne sert a rien, pour ne pas laisser
        /// tourner une fenetre topmost inutile.
        /// </summary>
        public void SetTransmission(double transmission)
        {
            double a = (1.0 - transmission) * 255.0;
            if (a < 0) a = 0;
            if (a > 250) a = 250;   // garde-fou : jamais totalement opaque
            _alpha = (byte)Math.Round(a);

            if (_alpha == 0)
            {
                _topmostKeeper.Stop();
                ApplyAlpha();
                if (Visible) Hide();
            }
            else
            {
                if (!Visible) Show();
                ApplyAlpha();
                _topmostKeeper.Start();
            }
        }

        private void ApplyAlpha()
        {
            if (!IsHandleCreated) return;
            try { Native.SetLayeredWindowAttributes(Handle, 0, _alpha, Native.LWA_ALPHA); }
            catch { }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _topmostKeeper != null) _topmostKeeper.Dispose();
            base.Dispose(disposing);
        }
    }

    /// <summary>Gere un voile par ecran et les garde alignes sur la liste des ecrans.</summary>
    public class OverlaySet : IDisposable
    {
        private readonly Dictionary<string, OverlayLens> _lenses = new Dictionary<string, OverlayLens>();

        public void Update(MonitorInfo m, double transmission, Color tint)
        {
            OverlayLens lens;
            if (!_lenses.TryGetValue(m.StableId, out lens))
            {
                if (transmission >= 1.0) return;   // rien a montrer : inutile de creer la fenetre
                lens = new OverlayLens();
                _lenses[m.StableId] = lens;
            }
            lens.CoverMonitor(m);
            lens.Tint = tint;
            lens.SetTransmission(transmission);
        }

        public void HideAll()
        {
            foreach (OverlayLens l in _lenses.Values)
            {
                try { l.SetTransmission(1.0); } catch { }
            }
        }

        /// <summary>Supprime les voiles des ecrans qui ne sont plus la (debranchement).</summary>
        public void PruneMissing(List<MonitorInfo> current)
        {
            List<string> alive = new List<string>();
            foreach (MonitorInfo m in current) alive.Add(m.StableId);

            List<string> dead = new List<string>();
            foreach (string id in _lenses.Keys)
                if (!alive.Contains(id)) dead.Add(id);

            foreach (string id in dead)
            {
                try { _lenses[id].Dispose(); } catch { }
                _lenses.Remove(id);
            }
        }

        public void Dispose()
        {
            foreach (OverlayLens l in _lenses.Values)
            {
                try { l.SetTransmission(1.0); l.Dispose(); } catch { }
            }
            _lenses.Clear();
        }
    }
}
