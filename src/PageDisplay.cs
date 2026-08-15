using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace LumaFlux
{
    /// <summary>
    /// Page principale : ce que l'on touche tous les jours.
    ///
    /// Les reglages rares vivent sur les autres pages. Regrouper ici les quatre
    /// curseurs reellement quotidiens evite que l'ajout de trente options ne rende
    /// l'application penible pour l'usage courant.
    /// </summary>
    public class PageDisplay : SettingsPage
    {
        private ModeStrip _modes;
        private SliderRow _brightness, _temperature, _contrast, _saturation;
        private Label _planLabel;
        private DarkButton _saveProfile;

        public override string Title { get { return "Ecran"; } }
        public override string Subtitle { get { return "Les reglages du quotidien"; } }

        public PageDisplay(Settings s, DisplayController d, Action push) : base(s, d, push)
        {
            Section("Modes");

            _modes = new ModeStrip();
            _modes.Height = 96;
            _modes.ModeChosen += OnModeChosen;
            Add(_modes, Theme.SpaceSm);

            Section("Reglages");

            _brightness = new SliderRow("Luminosite", GammaEngine.MinBrightness, GammaEngine.MaxBrightness, "%");
            _brightness.MarkAt(100, 100);
            _brightness.Hint = "5 % a 150 %";
            _brightness.Changed += delegate { S.Current.Brightness = SafetyGuard.ClampBrightness(_brightness.Value); CommitNoSave(); UpdatePlan(); };
            _brightness.Committed += OnBrightnessCommitted;
            Add(_brightness, Theme.SpaceMd);

            _temperature = new SliderRow("Temperature de couleur", ColorTemp.MinKelvin, ColorTemp.MaxKelvin, "K");
            _temperature.SetAccent(Theme.Warm);
            _temperature.Changed += delegate { S.Current.Kelvin = (int)Math.Round(_temperature.Value); UpdateHints(); CommitNoSave(); };
            _temperature.Committed += delegate { Commit(); };
            Add(_temperature, Theme.SpaceMd);

            _contrast = new SliderRow("Contraste", 50, 150, "%");
            _contrast.MarkAt(100, double.NaN);
            _contrast.Changed += delegate { S.Current.Contrast = _contrast.Value; CommitNoSave(); };
            _contrast.Committed += delegate { Commit(); };
            Add(_contrast, Theme.SpaceMd);

            _saturation = new SliderRow("Saturation", 0, 200, "%");
            _saturation.MarkAt(100, double.NaN);
            _saturation.SetAccent(Color.FromArgb(146, 200, 132));
            _saturation.Changed += delegate { S.Current.Saturation = _saturation.Value; CommitNoSave(); };
            _saturation.Committed += delegate { Commit(); };
            Add(_saturation, Theme.SpaceMd);

            _planLabel = UiKit.Caption("");
            _planLabel.Height = 34;
            Add(_planLabel, Theme.SpaceMd);

            _saveProfile = new DarkButton();
            _saveProfile.Text = "Enregistrer ces reglages comme mode...";
            _saveProfile.Height = Theme.MinTarget;
            _saveProfile.Click += OnSaveProfile;
            Add(_saveProfile, Theme.SpaceSm);
        }

        private void OnModeChosen(Profile p)
        {
            S.Current.CopyFrom(p);
            S.ActiveModeName = p.Name;
            Sync();
            Commit();
        }

        /// <summary>
        /// Confirmation a rebours quand on plonge dans le tres sombre. Declenchee au
        /// relachement seulement : la demander pendant le glissement serait intenable.
        /// </summary>
        private double _lastSafe = 100;

        private void OnBrightnessCommitted(object sender, EventArgs e)
        {
            double now = S.Current.Brightness;
            if (now < SafetyGuard.ConfirmBelow && _lastSafe >= SafetyGuard.ConfirmBelow && !S.SkipDarkConfirm)
            {
                using (ConfirmDialog dlg = new ConfirmDialog(now, 10))
                {
                    DialogResult r = dlg.ShowDialog(FindForm());
                    if (dlg.DontAskAgain) S.SkipDarkConfirm = true;
                    if (r != DialogResult.OK)
                    {
                        S.Current.Brightness = _lastSafe;
                        Loading = true;
                        _brightness.SetValueSilent(_lastSafe);
                        Loading = false;
                        CommitNoSave();
                        S.Save();
                        return;
                    }
                }
            }
            _lastSafe = now;
            Commit();
        }

        private void OnSaveProfile(object sender, EventArgs e)
        {
            string name = PromptDialog.Ask(FindForm(), "Enregistrer un mode",
                "Nom du mode :", "Mon mode " + (S.CustomProfiles.Count + 1));
            if (string.IsNullOrEmpty(name)) return;

            Profile p = S.Current.Clone();
            p.Name = name.Trim();

            for (int i = 0; i < S.CustomProfiles.Count; i++)
                if (S.CustomProfiles[i].Name == p.Name) { S.CustomProfiles.RemoveAt(i); break; }

            S.CustomProfiles.Add(p);
            S.ActiveModeName = p.Name;
            S.Save();
            Sync();
        }

        private void UpdatePlan()
        {
            _planLabel.Text = Display.DescribeCurrentPlan();
        }

        private void UpdateHints()
        {
            // En mode automatique, le curseur n'est pas manoeuvrable : le dire vaut mieux
            // que de laisser croire a une panne.
            _temperature.Hint = S.Schedule == ScheduleMode.Manual
                ? ColorTemp.Describe(S.Current.Kelvin)
                : "pilotee par l'automatisme";
            _saturation.Hint = S.Current.Saturation < 5 ? "niveaux de gris"
                             : (S.Current.Saturation > 140 ? "couleurs tres marquees" : "");
            _contrast.Hint = S.Current.Contrast > 100 ? "noirs plus profonds" : (S.Current.Contrast < 100 ? "image plus douce" : "");
        }

        public override void Sync()
        {
            Loading = true;
            try
            {
                _brightness.SetValueSilent(S.Current.Brightness);
                _temperature.SetValueSilent(S.Current.Kelvin);
                _contrast.SetValueSilent(S.Current.Contrast);
                _saturation.SetValueSilent(S.Current.Saturation);
                _lastSafe = S.Current.Brightness;

                List<Profile> all = new List<Profile>(Profile.BuiltInModes());
                all.AddRange(S.CustomProfiles);
                _modes.SetModes(all, S.ActiveModeName);

                _temperature.Track.Enabled = S.Schedule == ScheduleMode.Manual;
                UpdateHints();
                UpdatePlan();
            }
            finally { Loading = false; }
        }
    }

    /// <summary>
    /// Bande de pastilles de modes. Chaque pastille affiche un apercu reel de la
    /// couleur et de la luminosite qu'elle applique : on choisit avec l'oeil plutot
    /// qu'en lisant une liste.
    /// </summary>
    public class ModeStrip : Panel
    {
        private List<Profile> _modes = new List<Profile>();
        private string _active = "";
        private int _hover = -1;
        private int _scroll;

        public event Action<Profile> ModeChosen;

        private const int ChipW = 84;
        private const int ChipH = 76;
        private const int Gap = 8;

        public ModeStrip()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                   | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Card;
            Cursor = Cursors.Hand;
        }

        public void SetModes(List<Profile> modes, string active)
        {
            _modes = modes;
            _active = active ?? "";
            Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            int h = IndexAt(e.X, e.Y);
            if (h != _hover) { _hover = h; Invalidate(); }
            base.OnMouseMove(e);
        }

        protected override void OnMouseLeave(EventArgs e) { _hover = -1; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnMouseClick(MouseEventArgs e)
        {
            int i = IndexAt(e.X, e.Y);
            if (i >= 0 && i < _modes.Count && ModeChosen != null) ModeChosen(_modes[i]);
            base.OnMouseClick(e);
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            int total = _modes.Count * (ChipW + Gap);
            int max = Math.Max(0, total - Width);
            _scroll = Math.Max(0, Math.Min(max, _scroll - Math.Sign(e.Delta) * 60));
            Invalidate();
            // pas d'appel a base : la roulette pilote cette bande, pas la page
        }

        private int IndexAt(int x, int y)
        {
            if (y < 0 || y > ChipH) return -1;
            int i = (x + _scroll) / (ChipW + Gap);
            int within = (x + _scroll) % (ChipW + Gap);
            if (within > ChipW) return -1;
            return i >= 0 && i < _modes.Count ? i : -1;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.Clear(BackColor);

            for (int i = 0; i < _modes.Count; i++)
            {
                int x = i * (ChipW + Gap) - _scroll;
                if (x + ChipW < 0 || x > Width) continue;

                Profile p = _modes[i];
                bool sel = p.Name == _active;
                bool hov = i == _hover;

                Rectangle r = new Rectangle(x, 0, ChipW, ChipH);

                using (SolidBrush b = new SolidBrush(sel ? Theme.CardHover : (hov ? Theme.CardHover : Theme.Sunken)))
                    g.FillRectangle(b, r);

                // apercu : la couleur reellement produite par ce mode
                double[] mult = ColorTemp.Multipliers(p.Kelvin);
                double lum = Math.Min(1.35, p.Brightness / 100.0);
                int baseLevel = (int)Math.Round(58 + 150 * Math.Min(1.0, lum));
                Color swatch = Color.FromArgb(
                    Clamp(baseLevel * mult[0]), Clamp(baseLevel * mult[1]), Clamp(baseLevel * mult[2]));

                if (p.Filter == ColorFilter.Grayscale || p.Saturation < 10)
                {
                    int gray = (int)(0.2126 * swatch.R + 0.7152 * swatch.G + 0.0722 * swatch.B);
                    swatch = Color.FromArgb(gray, gray, gray);
                }
                else if (p.Filter == ColorFilter.Invert)
                {
                    swatch = Color.FromArgb(255 - swatch.R, 255 - swatch.G, 255 - swatch.B);
                }

                Rectangle sw = new Rectangle(x + 24, 12, 36, 22);
                using (SolidBrush b = new SolidBrush(swatch))
                    g.FillRectangle(b, sw);

                if (p.Brightness > 100)
                {
                    using (Pen pen = new Pen(Theme.Boost, 2))
                        g.DrawRectangle(pen, sw);
                }

                using (Font f = sel ? Theme.BodyBold : Theme.Small)
                    TextRenderer.DrawText(g, p.Name, f, new Rectangle(x + 3, 40, ChipW - 6, 16),
                        sel ? Theme.Fg : Theme.Dim,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);

                using (Font f = Theme.Small)
                    TextRenderer.DrawText(g, ((int)p.Brightness) + " % - " + p.Kelvin + " K", f,
                        new Rectangle(x + 3, 56, ChipW - 6, 14), Theme.Faint,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);

                using (Pen pen = new Pen(sel ? Theme.Accent : Theme.Border, sel ? 2 : 1))
                    g.DrawRectangle(pen, r.X, r.Y, r.Width - 1, r.Height - 1);
            }

            // indication de defilement quand la bande deborde
            int total = _modes.Count * (ChipW + Gap);
            if (total > Width)
            {
                using (Font f = Theme.Small)
                    TextRenderer.DrawText(g, "Roulette pour faire defiler", f,
                        new Rectangle(0, ChipH + 2, Width, 16), Theme.Faint,
                        TextFormatFlags.Right | TextFormatFlags.VerticalCenter);
            }
        }

        private static int Clamp(double v) { return v < 0 ? 0 : (v > 255 ? 255 : (int)Math.Round(v)); }
    }

    /// <summary>Boite de saisie d'une ligne de texte, au theme de l'application.</summary>
    public static class PromptDialog
    {
        public static string Ask(IWin32Window owner, string title, string label, string initial)
        {
            using (Form f = new Form())
            {
                f.Text = title;
                f.FormBorderStyle = FormBorderStyle.FixedDialog;
                f.StartPosition = FormStartPosition.CenterParent;
                f.MinimizeBox = false;
                f.MaximizeBox = false;
                f.ShowInTaskbar = false;
                f.ClientSize = new Size(380, 130);
                f.BackColor = Theme.Card;
                f.ForeColor = Theme.Fg;
                f.Font = Theme.Body;

                Label l = new Label();
                l.Text = label;
                l.ForeColor = Theme.Fg;
                l.SetBounds(18, 18, 344, 20);
                f.Controls.Add(l);

                TextBox t = new TextBox();
                t.Text = initial;
                t.BackColor = Theme.Sunken;
                t.ForeColor = Theme.Fg;
                t.BorderStyle = BorderStyle.FixedSingle;
                t.SetBounds(18, 44, 344, 24);
                t.SelectAll();
                f.Controls.Add(t);

                DarkButton ok = new DarkButton();
                ok.Text = "Enregistrer";
                ok.DialogResult = DialogResult.OK;
                ok.SetBounds(186, 84, 86, Theme.MinTarget);
                f.Controls.Add(ok);

                DarkButton cancel = new DarkButton();
                cancel.Text = "Annuler";
                cancel.DialogResult = DialogResult.Cancel;
                cancel.SetBounds(278, 84, 84, Theme.MinTarget);
                f.Controls.Add(cancel);

                f.AcceptButton = ok;
                f.CancelButton = cancel;
                f.Shown += delegate { DarkTitleBar.Apply(f.Handle); t.Focus(); };

                return f.ShowDialog(owner) == DialogResult.OK ? t.Text : null;
            }
        }
    }
}
