using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace LumaFlux
{
    /// <summary>
    /// Rappels de repos oculaire, sur la regle 20-20-20 : toutes les 20 minutes,
    /// regarder a 6 metres pendant 20 secondes. Fonctionnalite payante chez CareUEyes
    /// et Iris.
    ///
    /// Le rappel s'affiche sans jamais voler le focus : interrompre une frappe ou un
    /// raccourci en cours serait pire que le probleme qu'on cherche a resoudre.
    /// </summary>
    public class BreakReminder : IDisposable
    {
        private readonly Timer _tick = new Timer();
        private DateTime _lastBreak = DateTime.Now;
        private DateTime _sessionStart = DateTime.Now;
        private BreakWindow _window;

        public bool Enabled;
        public int IntervalMinutes = 20;
        public int DurationSeconds = 20;
        public bool DimDuringBreak;        // assombrir doucement pendant la pause
        public bool PlaySound;

        /// <summary>Emis au debut et a la fin d'une pause, pour laisser l'appelant assombrir.</summary>
        public event Action<bool> BreakStateChanged;

        public TimeSpan ScreenTime { get { return DateTime.Now - _sessionStart; } }

        public TimeSpan UntilNextBreak
        {
            get
            {
                TimeSpan elapsed = DateTime.Now - _lastBreak;
                TimeSpan total = TimeSpan.FromMinutes(IntervalMinutes);
                TimeSpan left = total - elapsed;
                return left < TimeSpan.Zero ? TimeSpan.Zero : left;
            }
        }

        public BreakReminder()
        {
            _tick.Interval = 5000;
            _tick.Tick += OnTick;
            _tick.Start();
        }

        public void ResetTimer()
        {
            _lastBreak = DateTime.Now;
        }

        public void ResetSession()
        {
            _sessionStart = DateTime.Now;
            _lastBreak = DateTime.Now;
        }

        private void OnTick(object sender, EventArgs e)
        {
            if (!Enabled || _window != null) return;
            if ((DateTime.Now - _lastBreak).TotalMinutes < IntervalMinutes) return;
            TriggerBreak();
        }

        /// <summary>Declenche une pause immediatement.</summary>
        public void TriggerBreak()
        {
            if (_window != null) return;
            _lastBreak = DateTime.Now;

            Action<bool> h = BreakStateChanged;
            if (h != null && DimDuringBreak) h(true);

            if (PlaySound)
            {
                try { System.Media.SystemSounds.Asterisk.Play(); } catch { }
            }

            _window = new BreakWindow(DurationSeconds);
            _window.FormClosed += delegate
            {
                _window = null;
                _lastBreak = DateTime.Now;
                Action<bool> h2 = BreakStateChanged;
                if (h2 != null && DimDuringBreak) h2(false);
            };
            _window.Show();
        }

        public void Dispose()
        {
            _tick.Stop();
            _tick.Dispose();
            if (_window != null) { try { _window.Close(); } catch { } }
        }

        /// <summary>
        /// Petite carte en bas a droite, avec un anneau de progression et le compte a
        /// rebours. Ne prend jamais le focus.
        /// </summary>
        private class BreakWindow : Form
        {
            private readonly Timer _timer = new Timer();
            private readonly int _total;
            private int _remaining;

            public BreakWindow(int seconds)
            {
                _total = Math.Max(5, seconds);
                _remaining = _total;

                FormBorderStyle = FormBorderStyle.None;
                ShowInTaskbar = false;
                TopMost = true;
                StartPosition = FormStartPosition.Manual;
                ClientSize = new Size(320, 132);
                BackColor = Theme.Card;
                DoubleBuffered = true;

                Rectangle wa = Screen.PrimaryScreen.WorkingArea;
                Location = new Point(wa.Right - Width - 24, wa.Bottom - Height - 24);

                _timer.Interval = 1000;
                _timer.Tick += delegate
                {
                    _remaining--;
                    if (_remaining <= 0) { _timer.Stop(); Close(); }
                    else Invalidate();
                };
                _timer.Start();

                Click += delegate { Close(); };
            }

            protected override CreateParams CreateParams
            {
                get
                {
                    CreateParams cp = base.CreateParams;
                    cp.ExStyle |= Native.WS_EX_TOPMOST | Native.WS_EX_NOACTIVATE | Native.WS_EX_TOOLWINDOW;
                    return cp;
                }
            }

            protected override bool ShowWithoutActivation { get { return true; } }

            protected override void OnPaint(PaintEventArgs e)
            {
                Graphics g = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Theme.Card);

                using (Pen border = new Pen(Theme.Border))
                    g.DrawRectangle(border, 0, 0, Width - 1, Height - 1);

                // anneau de progression
                int d = 62, cx = 26, cy = 34;
                using (Pen track = new Pen(Theme.Sunken, 6))
                    g.DrawEllipse(track, cx, cy, d, d);

                float sweep = 360f * _remaining / _total;
                using (Pen arc = new Pen(Theme.Good, 6))
                {
                    arc.StartCap = LineCap.Round;
                    arc.EndCap = LineCap.Round;
                    g.DrawArc(arc, cx, cy, d, d, -90, -sweep);
                }

                using (Font f = Theme.Heading)
                {
                    string txt = _remaining.ToString();
                    SizeF sz = g.MeasureString(txt, f);
                    using (SolidBrush b = new SolidBrush(Theme.Fg))
                        g.DrawString(txt, f, b, cx + d / 2f - sz.Width / 2, cy + d / 2f - sz.Height / 2);
                }

                using (Font f = Theme.Title)
                using (SolidBrush b = new SolidBrush(Theme.Fg))
                    g.DrawString("Pause pour les yeux", f, b, 108, 26);

                using (Font f = Theme.Body)
                using (SolidBrush b = new SolidBrush(Theme.Dim))
                {
                    g.DrawString("Regardez au loin, a 6 metres environ.", f, b, 110, 56);
                    g.DrawString("Cliquez pour passer.", f, b, 110, 76);
                }

                using (Font f = Theme.Small)
                using (SolidBrush b = new SolidBrush(Theme.Faint))
                    g.DrawString("Regle 20-20-20", f, b, 110, 100);
            }

            protected override void Dispose(bool disposing)
            {
                if (disposing) { _timer.Stop(); _timer.Dispose(); }
                base.Dispose(disposing);
            }
        }
    }
}
