using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Tout ce qui decide a votre place : l'heure, et le contenu affiche.
    ///
    /// f.lux ne connait que l'heure. Gammy ne connait que le contenu. Les avoir tous
    /// les deux, et pouvoir les combiner, est ce qui manque partout ailleurs.
    /// </summary>
    public class PageAuto : SettingsPage
    {
        private ComboRow _mode, _preset;
        private SliderRow _bedtime, _fixedDay, _fixedNight, _transition;
        private SliderRow _lat, _lon;
        private ToggleRow _affectsBrightness;
        private SliderRow _dayBright, _nightBright;
        private Label _status;

        private ToggleRow _adaptive;
        private SliderRow _adMin, _adMax, _adReact, _adInterval;
        private Label _adStatus;

        public ContentAdaptive Engine;

        public override string Title { get { return "Automatisme"; } }
        public override string Subtitle { get { return "Suivre l'heure, et le contenu affiche"; } }

        private static readonly string[] ModeNames = {
            "Manuel - rien d'automatique",
            "Suivre le soleil (calcul local)",
            "Horaires fixes"
        };

        public PageAuto(Settings s, DisplayController d, Action push) : base(s, d, push)
        {
            Section("Rythme de la journee");

            _mode = new ComboRow("Mode", ModeNames);
            _mode.Changed += delegate
            {
                if (Loading) return;
                S.Schedule = (ScheduleMode)Math.Max(0, _mode.SelectedIndex);
                Sync();
                Commit();
            };
            Add(_mode, Theme.SpaceSm);

            List<string> presets = new List<string>();
            foreach (Preset p in Preset.BuiltIn()) presets.Add(p.Name);
            _preset = new ComboRow("Ambiance", presets);
            _preset.Changed += delegate
            {
                if (Loading) return;
                S.PresetName = _preset.SelectedText;
                UpdateStatus();
                Commit();
            };
            Add(_preset, Theme.SpaceSm);

            Note("Ces ambiances sont celles de f.lux, relevees dans son propre fichier de "
               + "configuration : jour, soiree et nuit profonde y ont chacun leur temperature.");

            _status = UiKit.Caption("");
            _status.Height = 34;
            Add(_status, Theme.SpaceSm);

            Section("Horaires");

            _bedtime = new SliderRow("Heure du coucher", 18, 30, "h");
            _bedtime.Hint = "bascule vers la teinte la plus chaude";
            _bedtime.Changed += delegate { S.BedtimeHour = Wrap(_bedtime.Value); UpdateHourHints(); CommitNoSave(); };
            _bedtime.Committed += delegate { Commit(); };
            Add(_bedtime, Theme.SpaceSm);

            _fixedDay = new SliderRow("Debut de journee", 0, 23.5, "h");
            _fixedDay.Changed += delegate { S.FixedDayHour = _fixedDay.Value; UpdateHourHints(); CommitNoSave(); };
            _fixedDay.Committed += delegate { Commit(); };
            Add(_fixedDay, Theme.SpaceSm);

            _fixedNight = new SliderRow("Debut de soiree", 0, 23.5, "h");
            _fixedNight.Changed += delegate { S.FixedNightHour = _fixedNight.Value; UpdateHourHints(); CommitNoSave(); };
            _fixedNight.Committed += delegate { Commit(); };
            Add(_fixedNight, Theme.SpaceSm);

            _transition = new SliderRow("Duree du fondu", 5, 180, "min");
            _transition.Hint = "etalement de la bascule";
            _transition.Changed += delegate { S.TransitionMinutes = (int)_transition.Value; CommitNoSave(); };
            _transition.Committed += delegate { Commit(); };
            Add(_transition, Theme.SpaceSm);

            Section("Position");

            _lat = new SliderRow("Latitude", -66, 66, "");
            _lat.Format = "0.00";
            _lat.Changed += delegate { S.Latitude = _lat.Value; UpdateStatus(); CommitNoSave(); };
            _lat.Committed += delegate { Commit(); };
            Add(_lat, Theme.SpaceSm);

            _lon = new SliderRow("Longitude", -180, 180, "");
            _lon.Format = "0.00";
            _lon.Changed += delegate { S.Longitude = _lon.Value; UpdateStatus(); CommitNoSave(); };
            _lon.Committed += delegate { Commit(); };
            Add(_lon, Theme.SpaceSm);

            DarkButton detect = new DarkButton();
            detect.Text = "Deduire de mon fuseau horaire";
            detect.Height = Theme.MinTarget;
            detect.Click += delegate
            {
                S.Longitude = Math.Round(TimeZoneInfo.Local.BaseUtcOffset.TotalHours * 15, 2);
                Sync();
                Commit();
            };
            Add(detect, Theme.SpaceSm);

            Note("Le lever et le coucher sont calcules sur place, avec l'algorithme solaire "
               + "de la NOAA. Aucune connexion, aucune position envoyee nulle part - "
               + "contrairement a f.lux qui interroge un service en ligne.");

            Section("Luminosite selon l'heure");

            _affectsBrightness = new ToggleRow("Faire varier aussi la luminosite",
                "f.lux ne change que la couleur ; il fallait baisser la luminosite a la main.");
            _affectsBrightness.Changed += delegate
            {
                S.ScheduleAffectsBrightness = _affectsBrightness.Checked;
                UpdateEnabledStates();
                Commit();
            };
            Add(_affectsBrightness, Theme.SpaceSm);

            _dayBright = new SliderRow("Luminosite de jour", GammaEngine.MinBrightness, GammaEngine.MaxBrightness, "%");
            _dayBright.MarkAt(100, 100);
            _dayBright.Changed += delegate { S.DayBrightness = _dayBright.Value; CommitNoSave(); };
            _dayBright.Committed += delegate { Commit(); };
            Add(_dayBright, Theme.SpaceSm);

            _nightBright = new SliderRow("Luminosite de nuit", GammaEngine.MinBrightness, GammaEngine.MaxBrightness, "%");
            _nightBright.MarkAt(100, 100);
            _nightBright.Changed += delegate { S.NightBrightness = _nightBright.Value; CommitNoSave(); };
            _nightBright.Committed += delegate { Commit(); };
            Add(_nightBright, Theme.SpaceSm);

            Section("Adaptation au contenu");

            _adaptive = new ToggleRow("Suivre ce qui est affiche",
                "Une page blanche fait baisser l'ecran, une scene sombre le fait remonter.");
            _adaptive.Changed += delegate
            {
                S.AdaptiveEnabled = _adaptive.Checked;
                UpdateEnabledStates();
                Commit();
            };
            Add(_adaptive, Theme.SpaceSm);

            _adMin = new SliderRow("Plancher", GammaEngine.MinBrightness, 100, "%");
            _adMin.Changed += delegate { S.AdaptiveMin = _adMin.Value; PushEngine(); CommitNoSave(); };
            _adMin.Committed += delegate { Commit(); };
            Add(_adMin, Theme.SpaceSm);

            _adMax = new SliderRow("Plafond", 50, GammaEngine.MaxBrightness, "%");
            _adMax.MarkAt(100, 100);
            _adMax.Changed += delegate { S.AdaptiveMax = _adMax.Value; PushEngine(); CommitNoSave(); };
            _adMax.Committed += delegate { Commit(); };
            Add(_adMax, Theme.SpaceSm);

            _adReact = new SliderRow("Reactivite", 1, 10, "");
            _adReact.Hint = "au-dela de 6, l'ecran respire visiblement";
            _adReact.Changed += delegate { S.AdaptiveReactivity = _adReact.Value; PushEngine(); CommitNoSave(); };
            _adReact.Committed += delegate { Commit(); };
            Add(_adReact, Theme.SpaceSm);

            _adInterval = new SliderRow("Intervalle de mesure", 300, 5000, "ms");
            _adInterval.Changed += delegate { S.AdaptiveIntervalMs = (int)_adInterval.Value; PushEngine(); CommitNoSave(); };
            _adInterval.Committed += delegate { Commit(); };
            Add(_adInterval, Theme.SpaceSm);

            _adStatus = UiKit.Caption("");
            _adStatus.Height = 34;
            Add(_adStatus, Theme.SpaceSm);

            Note("La mesure est prise avant que la carte graphique n'applique nos reglages : "
               + "l'automatisme ne peut donc pas se mesurer lui-meme et partir en oscillation.");
        }

        private void PushEngine()
        {
            if (Engine == null) return;
            Engine.MinBrightness = S.AdaptiveMin;
            Engine.MaxBrightness = S.AdaptiveMax;
            Engine.Reactivity = S.AdaptiveReactivity;
            Engine.IntervalMs = S.AdaptiveIntervalMs;
        }

        private static double Wrap(double h) { return h >= 24 ? h - 24 : h; }

        private void UpdateHourHints()
        {
            _bedtime.Hint = SolarClock.FormatHour(S.BedtimeHour);
            _fixedDay.Hint = SolarClock.FormatHour(S.FixedDayHour);
            _fixedNight.Hint = SolarClock.FormatHour(S.FixedNightHour);
        }

        private void UpdateStatus()
        {
            ScheduleResult r = Scheduler.Evaluate(S, DateTime.Now);
            _status.Text = Scheduler.Describe(S, r);
            if (!r.SunValid && S.Schedule == ScheduleMode.Solar)
                _status.Text += "  (le soleil ne se leve ou ne se couche pas ici aujourd'hui)";
        }

        private void UpdateEnabledStates()
        {
            bool solar = S.Schedule == ScheduleMode.Solar;
            bool fixedH = S.Schedule == ScheduleMode.FixedHours;
            bool auto = solar || fixedH;

            _preset.Box.Enabled = auto;
            _bedtime.Track.Enabled = auto;
            _transition.Track.Enabled = auto;
            _fixedDay.Track.Enabled = fixedH;
            _fixedNight.Track.Enabled = fixedH;
            _lat.Track.Enabled = solar;
            _lon.Track.Enabled = solar;

            _affectsBrightness.Enabled = auto;
            bool sb = auto && S.ScheduleAffectsBrightness;
            _dayBright.Track.Enabled = sb;
            _nightBright.Track.Enabled = sb;

            bool ad = S.AdaptiveEnabled;
            _adMin.Track.Enabled = ad;
            _adMax.Track.Enabled = ad;
            _adReact.Track.Enabled = ad;
            _adInterval.Track.Enabled = ad;

            if (ad && S.ScheduleAffectsBrightness && auto)
                _adStatus.Text = "L'adaptation au contenu a la main sur la luminosite ; "
                               + "la planification ne pilote alors que la couleur.";
            else if (ad)
                _adStatus.Text = Engine != null && Engine.IsRunning
                    ? string.Format("Actif. Derniere mesure : {0:0} % de luminance a l'ecran.",
                                    Engine.LastMeasuredLuminance * 100)
                    : "Actif.";
            else
                _adStatus.Text = "Inactif : la luminosite ne bouge que sur votre commande.";
        }

        public override void Sync()
        {
            Loading = true;
            try
            {
                _mode.SelectedIndex = (int)S.Schedule;
                int pi = 0;
                List<Preset> all = Preset.BuiltIn();
                for (int i = 0; i < all.Count; i++) if (all[i].Name == S.PresetName) pi = i;
                _preset.SelectedIndex = pi;

                _bedtime.SetValueSilent(S.BedtimeHour < 18 ? S.BedtimeHour + 24 : S.BedtimeHour);
                _fixedDay.SetValueSilent(S.FixedDayHour);
                _fixedNight.SetValueSilent(S.FixedNightHour);
                _transition.SetValueSilent(S.TransitionMinutes);
                _lat.SetValueSilent(S.Latitude);
                _lon.SetValueSilent(S.Longitude);

                _affectsBrightness.SetCheckedSilent(S.ScheduleAffectsBrightness);
                _dayBright.SetValueSilent(S.DayBrightness);
                _nightBright.SetValueSilent(S.NightBrightness);

                _adaptive.SetCheckedSilent(S.AdaptiveEnabled);
                _adMin.SetValueSilent(S.AdaptiveMin);
                _adMax.SetValueSilent(S.AdaptiveMax);
                _adReact.SetValueSilent(S.AdaptiveReactivity);
                _adInterval.SetValueSilent(S.AdaptiveIntervalMs);

                UpdateHourHints();
                UpdateStatus();
                UpdateEnabledStates();
            }
            finally { Loading = false; }
        }
    }

    /// <summary>
    /// Regles par application : Lunar les reserve a sa version payante.
    ///
    /// Le principe est simple mais change l'usage : on cesse d'arbitrer entre « bon
    /// pour les yeux » et « couleurs justes », puisque chaque application obtient ce
    /// qui lui convient.
    /// </summary>
    public class PageApps : SettingsPage
    {
        private ToggleRow _enabled, _fullscreen, _battery;
        private RuleList _list;
        private Label _current;

        public AppWatcher Watcher;

        public override string Title { get { return "Applications"; } }
        public override string Subtitle { get { return "Un reglage different selon le logiciel actif"; } }

        public PageApps(Settings s, DisplayController d, Action push) : base(s, d, push)
        {
            Section("Suspension automatique");

            _fullscreen = new ToggleRow("Suspendre en plein ecran",
                "Jeux et videos plein ecran retrouvent leurs couleurs d'origine.");
            _fullscreen.Changed += delegate { S.DisableOnFullscreen = _fullscreen.Checked; Commit(); };
            Add(_fullscreen, Theme.SpaceSm);

            _battery = new ToggleRow("Ne pas monter au-dessus de 100 % sur batterie",
                "Le boost pousse le retroeclairage au maximum, ce qui vide l'accumulateur.");
            _battery.Changed += delegate { S.DisableOnBattery = _battery.Checked; Commit(); };
            Add(_battery, Theme.SpaceSm);

            Section("Regles par application");

            _enabled = new ToggleRow("Activer les regles par application", null);
            _enabled.Changed += delegate
            {
                S.AppRulesEnabled = _enabled.Checked;
                _list.Enabled = _enabled.Checked;
                Commit();
            };
            Add(_enabled, Theme.SpaceSm);

            _current = UiKit.Caption("");
            _current.Height = 20;
            Add(_current, Theme.SpaceXs);

            _list = new RuleList(S);
            _list.Height = 190;
            _list.Changed += delegate { Commit(); };
            Add(_list, Theme.SpaceSm);

            DarkButton addCurrent = new DarkButton();
            addCurrent.Text = "Ajouter l'application au premier plan";
            addCurrent.Height = Theme.MinTarget;
            addCurrent.Click += OnAddCurrent;
            Add(addCurrent, Theme.SpaceSm);

            DarkButton addKnown = new DarkButton();
            addKnown.Text = "Ajouter depuis la liste des applications courantes...";
            addKnown.Height = Theme.MinTarget;
            addKnown.Click += OnAddKnown;
            Add(addKnown, Theme.SpaceXs);

            DarkButton remove = new DarkButton();
            remove.Text = "Supprimer la regle selectionnee";
            remove.Height = Theme.MinTarget;
            remove.Click += delegate
            {
                if (_list.SelectedIndex >= 0 && _list.SelectedIndex < S.AppRules.Count)
                {
                    S.AppRules.RemoveAt(_list.SelectedIndex);
                    _list.Reload();
                    Commit();
                }
            };
            Add(remove, Theme.SpaceXs);

            Note("Cliquez sur une regle pour changer le mode qu'elle applique. "
               + "La regle la plus specifique l'emporte ; en l'absence de regle, "
               + "les reglages generaux s'appliquent.");
        }

        private void OnAddCurrent(object sender, EventArgs e)
        {
            string proc = Watcher != null ? Watcher.CurrentProcess : "";
            if (string.IsNullOrEmpty(proc) || proc == "opusscreen")
            {
                MessageBox.Show(FindForm(),
                    "Aucune autre application au premier plan.\n\n"
                  + "Laissez cette fenetre ouverte, cliquez sur l'application voulue, "
                  + "puis revenez ici : son nom apparaitra juste au-dessus de la liste.",
                    "Ajouter une regle", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            AddRule(proc);
        }

        private void OnAddKnown(object sender, EventArgs e)
        {
            using (Form f = new Form())
            {
                f.Text = "Applications courantes";
                f.FormBorderStyle = FormBorderStyle.FixedDialog;
                f.StartPosition = FormStartPosition.CenterParent;
                f.MinimizeBox = f.MaximizeBox = false;
                f.ShowInTaskbar = false;
                f.ClientSize = new Size(380, 340);
                f.BackColor = Theme.Card;
                f.ForeColor = Theme.Fg;
                f.Font = Theme.Body;

                ListBox lb = new ListBox();
                lb.BackColor = Theme.Sunken;
                lb.ForeColor = Theme.Fg;
                lb.BorderStyle = BorderStyle.FixedSingle;
                lb.SetBounds(16, 16, 348, 260);
                List<KnownApps.Entry> entries = KnownApps.Suggestions();
                foreach (KnownApps.Entry k in entries) lb.Items.Add(k.Label + "   (" + k.Process + ")");
                f.Controls.Add(lb);

                DarkButton ok = new DarkButton();
                ok.Text = "Ajouter";
                ok.DialogResult = DialogResult.OK;
                ok.SetBounds(190, 290, 84, Theme.MinTarget);
                f.Controls.Add(ok);

                DarkButton cancel = new DarkButton();
                cancel.Text = "Annuler";
                cancel.DialogResult = DialogResult.Cancel;
                cancel.SetBounds(280, 290, 84, Theme.MinTarget);
                f.Controls.Add(cancel);

                f.AcceptButton = ok;
                f.CancelButton = cancel;
                f.Shown += delegate { DarkTitleBar.Apply(f.Handle); };

                if (f.ShowDialog(FindForm()) == DialogResult.OK && lb.SelectedIndex >= 0)
                {
                    KnownApps.Entry k = entries[lb.SelectedIndex];
                    AddRule(k.Process, k.Suggested);
                }
            }
        }

        private void AddRule(string process, string mode)
        {
            foreach (AppRule r in S.AppRules)
                if (r.ProcessName == process) { _list.Reload(); return; }

            AppRule nr = new AppRule();
            nr.ProcessName = process;
            nr.ProfileName = mode;
            S.AppRules.Add(nr);
            _list.Reload();
            Commit();
        }

        private void AddRule(string process) { AddRule(process, "Normal"); }

        public override void Sync()
        {
            Loading = true;
            try
            {
                _enabled.SetCheckedSilent(S.AppRulesEnabled);
                _fullscreen.SetCheckedSilent(S.DisableOnFullscreen);
                _battery.SetCheckedSilent(S.DisableOnBattery);
                _list.Enabled = S.AppRulesEnabled;
                _list.Reload();

                string proc = Watcher != null ? Watcher.CurrentProcess : "";
                _current.Text = string.IsNullOrEmpty(proc) || proc == "opusscreen"
                    ? "Application au premier plan : (cette fenetre)"
                    : "Application au premier plan : " + proc;
            }
            finally { Loading = false; }
        }
    }

    /// <summary>Liste des regles, avec choix du mode par clic.</summary>
    public class RuleList : Control
    {
        private readonly Settings _s;
        private int _selected = -1;
        private int _hover = -1;
        private int _scroll;
        private const int RowH = 30;

        public event EventHandler Changed;

        public RuleList(Settings s)
        {
            _s = s;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                   | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Sunken;
            Cursor = Cursors.Hand;
        }

        public int SelectedIndex { get { return _selected; } }

        public void Reload() { Invalidate(); }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            int i = (e.Y + _scroll) / RowH;
            if (i != _hover) { _hover = i; Invalidate(); }
            base.OnMouseMove(e);
        }

        protected override void OnMouseLeave(EventArgs e) { _hover = -1; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            int max = Math.Max(0, _s.AppRules.Count * RowH - Height);
            _scroll = Math.Max(0, Math.Min(max, _scroll - Math.Sign(e.Delta) * RowH));
            Invalidate();
        }

        protected override void OnMouseClick(MouseEventArgs e)
        {
            int i = (e.Y + _scroll) / RowH;
            if (i < 0 || i >= _s.AppRules.Count) return;
            _selected = i;

            // Le clic dans la moitie droite fait tourner le mode applique.
            if (e.X > Width / 2)
            {
                List<string> names = ModeNames();
                AppRule r = _s.AppRules[i];
                int cur = names.IndexOf(r.ProfileName);
                int next = (cur + 1) % (names.Count + 1);
                if (next == names.Count) { r.Disable = true; }
                else { r.Disable = false; r.ProfileName = names[next]; }
                if (Changed != null) Changed(this, EventArgs.Empty);
            }
            Invalidate();
            base.OnMouseClick(e);
        }

        private List<string> ModeNames()
        {
            List<string> n = new List<string>();
            foreach (Profile p in Profile.BuiltInModes()) n.Add(p.Name);
            foreach (Profile p in _s.CustomProfiles) n.Add(p.Name);
            return n;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Enabled ? BackColor : Theme.Bg);

            if (_s.AppRules.Count == 0)
            {
                using (Font f = Theme.Body)
                    TextRenderer.DrawText(g, "Aucune regle. Ajoutez-en une ci-dessous.", f,
                        new Rectangle(0, 0, Width, Height), Theme.Faint,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            }

            for (int i = 0; i < _s.AppRules.Count; i++)
            {
                int y = i * RowH - _scroll;
                if (y + RowH < 0 || y > Height) continue;

                AppRule r = _s.AppRules[i];
                bool sel = i == _selected, hov = i == _hover;

                if (sel || hov)
                {
                    using (SolidBrush b = new SolidBrush(sel ? Theme.CardHover : Theme.Card))
                        g.FillRectangle(b, 0, y, Width, RowH);
                }

                Color fg = Enabled ? Theme.Fg : Theme.Faint;
                using (Font f = Theme.Body)
                    TextRenderer.DrawText(g, r.ProcessName, f,
                        new Rectangle(10, y, Width / 2 - 14, RowH), fg,
                        TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);

                string right = r.Disable ? "aucun effet" : r.ProfileName;
                using (Font f = Theme.Body)
                    TextRenderer.DrawText(g, right, f,
                        new Rectangle(Width / 2, y, Width / 2 - 12, RowH),
                        r.Disable ? Theme.Faint : Theme.Accent,
                        TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);

                using (Pen p = new Pen(Theme.Border))
                    g.DrawLine(p, 0, y + RowH - 1, Width, y + RowH - 1);
            }

            using (Pen p = new Pen(Theme.Border))
                g.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
        }
    }
}
