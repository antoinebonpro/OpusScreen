using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Un bloc de reglages par ecran.
    ///
    /// PangoBright savait seulement exclure un ecran ; Iris facture les reglages
    /// independants par moniteur. Ici chaque ecran peut suivre le reglage general,
    /// s'en ecarter d'un decalage, ou vivre entierement sa vie.
    /// </summary>
    public class PageScreens : SettingsPage
    {
        private ToggleRow _link;
        private ComboRow _matrixSource;
        private readonly List<Control> _dynamic = new List<Control>();
        private readonly List<string> _sourceIds = new List<string>();
        private Panel _host;

        public override string Title { get { return "Ecrans"; } }
        public override string Subtitle { get { return "Regler chaque moniteur separement"; } }

        public PageScreens(Settings s, DisplayController d, Action push) : base(s, d, push)
        {
            Section("General");

            _link = new ToggleRow("Lier tous les ecrans",
                "Un seul reglage pour tous. Decochez pour donner a chacun son propre profil.");
            _link.Changed += delegate { S.LinkMonitors = _link.Checked; Rebuild(); Commit(); };
            Add(_link, Theme.SpaceSm);

            DarkButton refresh = new DarkButton();
            refresh.Text = "Redetecter les ecrans";
            refresh.Height = Theme.MinTarget;
            refresh.Click += delegate { Display.RefreshMonitors(); Sync(); };
            Add(refresh, Theme.SpaceSm);

            Section("Filtres et saturation");

            _matrixSource = new ComboRow("Ecran de reference", new string[] { "Ecran principal" });
            _matrixSource.Changed += delegate
            {
                if (Loading) return;
                int i = _matrixSource.SelectedIndex;
                S.MatrixSourceId = (i > 0 && i - 1 < _sourceIds.Count) ? _sourceIds[i - 1] : "";
                Commit();
            };
            Add(_matrixSource, Theme.SpaceSm);

            Note("La saturation et les filtres - dont la correction du daltonisme - passent par "
               + "une matrice de couleur que Windows n'expose que pour le bureau ENTIER : elle ne "
               + "peut pas differer d'un ecran a l'autre. C'est une limite de l'API, pas un choix. "
               + "Plutot que de laisser un ecran quelconque decider pour les autres, on designe "
               + "ici celui dont les reglages de couleur s'appliquent partout. La luminosite, la "
               + "temperature et le voile, eux, restent bien reglables ecran par ecran.");

            Section("Ecrans detectes");

            _host = new Panel();
            _host.BackColor = Color.Transparent;
            _host.Height = 10;
            Add(_host, Theme.SpaceSm);

            Note("Le mode « ecran eteint » reprend le BlackOut de Lunar : l'ecran est "
               + "occulte sans etre deconnecte, les fenetres qui s'y trouvent restent en place.");
        }

        /// <summary>
        /// Recharge la liste des ecrans de reference.
        ///
        /// Le nom seul ne suffit pas quand deux ecrans sont du meme modele - c'est
        /// justement le cas ou le choix compte : la sortie et la definition sont donc
        /// rappelees dans l'intitule.
        /// </summary>
        private void RebuildSourceList()
        {
            _sourceIds.Clear();
            _matrixSource.Box.Items.Clear();
            _matrixSource.Box.Items.Add("Ecran principal (automatique)");

            int selected = 0;
            foreach (MonitorInfo m in Display.Monitors)
            {
                _sourceIds.Add(m.StableId);
                _matrixSource.Box.Items.Add(string.Format("Ecran {0} - {1} ({2})",
                    m.Index + 1, m.FriendlyName, m.Detail));
                if (m.StableId == S.MatrixSourceId) selected = _sourceIds.Count;
            }

            _matrixSource.SelectedIndex = selected;
        }

        private void Rebuild()
        {
            foreach (Control c in _dynamic) { _host.Controls.Remove(c); c.Dispose(); }
            _dynamic.Clear();

            int y = 0;
            foreach (MonitorInfo m in Display.Monitors)
            {
                MonitorInfo captured = m;
                MonitorSettings ms = S.For(m);

                MonitorCard card = new MonitorCard(S, captured, ms, !S.LinkMonitors);
                card.Left = 0;
                card.Top = y;
                card.Width = ContentWidth;
                card.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
                card.Changed += delegate { Commit(); };
                card.LiveChanged += delegate { CommitNoSave(); };
                _host.Controls.Add(card);
                _dynamic.Add(card);
                y += card.Height + Theme.SpaceSm;
            }

            _host.Height = Math.Max(10, y);
            Relayout();   // le bloc a change de hauteur : la note qui suit doit redescendre
        }

        public override void Sync()
        {
            Loading = true;
            try
            {
                _link.SetCheckedSilent(S.LinkMonitors);
                RebuildSourceList();
                Rebuild();
            }
            finally { Loading = false; }
        }
    }

    /// <summary>Bloc de reglages d'un ecran.</summary>
    public class MonitorCard : Panel
    {
        private readonly Settings _s;
        private readonly MonitorInfo _m;
        private readonly MonitorSettings _ms;
        private readonly ToggleRow _enabled, _blackout, _independent;
        private readonly SliderRow _offset, _ownBright, _ownKelvin;
        private readonly Label _title, _detail;
        private bool _loading;

        public event EventHandler Changed;
        public event EventHandler LiveChanged;

        public MonitorCard(Settings s, MonitorInfo m, MonitorSettings ms, bool allowIndependent)
        {
            _s = s; _m = m; _ms = ms;
            BackColor = Theme.Sunken;
            Padding = new Padding(14, 12, 14, 12);

            _title = new Label();
            _title.Text = m.Label;
            _title.Font = Theme.BodyBold;
            _title.ForeColor = Theme.Fg;
            _title.AutoSize = false;
            _title.BackColor = Color.Transparent;
            Controls.Add(_title);

            _detail = new Label();

            // L'identifiant materiel etait affiche ici. Il ne dit rien a personne et,
            // pire, il etait identique pour deux ecrans du meme modele : la seule
            // information censee les distinguer les confondait. La sortie physique et
            // le mode de reglage materiel, eux, se verifient d'un coup d'oeil derriere
            // la machine.
            string extra = HardwareBacklight.DescribeFor(m);
            _detail.Text = m.Detail + (extra.Length > 0 ? "  -  " + extra : "");
            _detail.Font = Theme.Small;
            _detail.ForeColor = Theme.Faint;
            _detail.AutoSize = false;
            _detail.BackColor = Color.Transparent;
            Controls.Add(_detail);

            _enabled = new ToggleRow("Appliquer les effets sur cet ecran", null);
            _enabled.BackColor = Color.Transparent;
            _enabled.Changed += delegate { _ms.Enabled = _enabled.Checked; Fire(); };
            Controls.Add(_enabled);

            _blackout = new ToggleRow("Ecran eteint", null);
            _blackout.BackColor = Color.Transparent;
            _blackout.Changed += delegate { _ms.Blackout = _blackout.Checked; Fire(); };
            Controls.Add(_blackout);

            _independent = new ToggleRow("Profil independant", null);
            _independent.BackColor = Color.Transparent;
            _independent.Visible = allowIndependent;
            _independent.Changed += delegate { _ms.Independent = _independent.Checked; UpdateStates(); Fire(); };
            Controls.Add(_independent);

            _offset = new SliderRow("Decalage de luminosite", -50, 50, "pts");
            _offset.MarkAt(0, double.NaN);
            _offset.Format = "+0;-0;0";
            _offset.BackColor = Color.Transparent;
            _offset.Changed += delegate { _ms.BrightnessOffset = _offset.Value; FireLive(); };
            _offset.Committed += delegate { Fire(); };
            Controls.Add(_offset);

            _ownBright = new SliderRow("Luminosite propre", GammaEngine.MinBrightness, GammaEngine.MaxBrightness, "%");
            _ownBright.MarkAt(100, 100);
            _ownBright.BackColor = Color.Transparent;
            _ownBright.Changed += delegate { _ms.Own.Brightness = _ownBright.Value; FireLive(); };
            _ownBright.Committed += delegate { Fire(); };
            Controls.Add(_ownBright);

            _ownKelvin = new SliderRow("Temperature propre", ColorTemp.MinKelvin, ColorTemp.MaxKelvin, "K");
            _ownKelvin.SetAccent(Theme.Warm);
            _ownKelvin.BackColor = Color.Transparent;
            _ownKelvin.Changed += delegate { _ms.Own.Kelvin = (int)_ownKelvin.Value; FireLive(); };
            _ownKelvin.Committed += delegate { Fire(); };
            Controls.Add(_ownKelvin);

            Sync();
            Height = ComputeHeight();
        }

        private void Fire()
        {
            if (_loading) return;
            Height = ComputeHeight();
            if (Parent != null) RepositionSiblings();
            if (Changed != null) Changed(this, EventArgs.Empty);
        }

        private void FireLive()
        {
            if (_loading) return;
            if (LiveChanged != null) LiveChanged(this, EventArgs.Empty);
        }

        /// <summary>Quand une carte change de hauteur, les suivantes doivent redescendre.</summary>
        private void RepositionSiblings()
        {
            int y = 0;
            foreach (Control c in Parent.Controls)
            {
                MonitorCard card = c as MonitorCard;
                if (card == null) continue;
                card.Top = y;
                y += card.Height + Theme.SpaceSm;
            }
            Parent.Height = Math.Max(10, y);
        }

        private int ComputeHeight()
        {
            int h = 12 + 20 + 18 + Theme.SpaceSm;
            h += _enabled.Height + _blackout.Height;
            if (_independent.Visible) h += _independent.Height;
            if (_ms.Independent && _independent.Visible) h += _ownBright.Height + _ownKelvin.Height + Theme.SpaceSm;
            else h += _offset.Height + Theme.SpaceSm;
            return h + 12;
        }

        private void UpdateStates()
        {
            bool indep = _ms.Independent && _independent.Visible;
            _offset.Visible = !indep;
            _ownBright.Visible = indep;
            _ownKelvin.Visible = indep;

            bool on = _ms.Enabled && !_ms.Blackout;
            _offset.Track.Enabled = on;
            _ownBright.Track.Enabled = on;
            _ownKelvin.Track.Enabled = on;
            _independent.Enabled = on;
        }

        public void Sync()
        {
            _loading = true;
            try
            {
                _enabled.SetCheckedSilent(_ms.Enabled);
                _blackout.SetCheckedSilent(_ms.Blackout);
                _independent.SetCheckedSilent(_ms.Independent);
                _offset.SetValueSilent(_ms.BrightnessOffset);
                _ownBright.SetValueSilent(_ms.Own.Brightness);
                _ownKelvin.SetValueSilent(_ms.Own.Kelvin);
                UpdateStates();
            }
            finally { _loading = false; }
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            int w = Width - 28;
            int y = 12;
            _title.SetBounds(14, y, w, 20); y += 20;
            _detail.SetBounds(14, y, w, 18); y += 18 + Theme.SpaceSm;
            _enabled.SetBounds(14, y, w, _enabled.Height); y += _enabled.Height;
            _blackout.SetBounds(14, y, w, _blackout.Height); y += _blackout.Height;
            if (_independent.Visible) { _independent.SetBounds(14, y, w, _independent.Height); y += _independent.Height; }
            y += Theme.SpaceSm;
            _offset.SetBounds(14, y, w, _offset.Height);
            _ownBright.SetBounds(14, y, w, _ownBright.Height);
            _ownKelvin.SetBounds(14, y + _ownBright.Height, w, _ownKelvin.Height);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (Pen p = new Pen(_ms.Blackout ? Theme.Danger : Theme.Border))
                e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
        }
    }

    /// <summary>Confort visuel : pauses regulieres et temps d'ecran.</summary>
    public class PageComfort : SettingsPage
    {
        private ToggleRow _enabled, _dim, _sound, _blink;
        private SliderRow _interval, _duration, _blinkInterval, _volume;
        private Label _stats, _volumeNote;
        private DarkButton _now, _raise;

        public BreakReminder Reminder;

        public override string Title { get { return "Confort"; } }
        public override string Subtitle { get { return "Pauses oculaires et temps d'ecran"; } }

        public PageComfort(Settings s, DisplayController d, Action push) : base(s, d, push)
        {
            Section("Pauses pour les yeux");

            _enabled = new ToggleRow("Rappeler de faire une pause",
                "Regle 20-20-20 : toutes les 20 minutes, regarder a 6 metres pendant 20 secondes.");
            _enabled.Changed += delegate { S.BreaksEnabled = _enabled.Checked; PushToReminder(); UpdateStates(); Commit(); };
            Add(_enabled, Theme.SpaceSm);

            _interval = new SliderRow("Intervalle", 5, 90, "min");
            _interval.Changed += delegate { S.BreakIntervalMinutes = (int)_interval.Value; PushToReminder(); CommitNoSave(); };
            _interval.Committed += delegate { Commit(); };
            Add(_interval, Theme.SpaceSm);

            _duration = new SliderRow("Duree de la pause", 5, 300, "s");
            _duration.Changed += delegate { S.BreakDurationSeconds = (int)_duration.Value; PushToReminder(); CommitNoSave(); };
            _duration.Committed += delegate { Commit(); };
            Add(_duration, Theme.SpaceSm);

            _dim = new ToggleRow("Assombrir pendant la pause",
                "Rend le rappel difficile a ignorer sans bloquer le travail en cours.");
            _dim.Changed += delegate { S.BreakDim = _dim.Checked; PushToReminder(); Commit(); };
            Add(_dim, Theme.SpaceSm);

            _sound = new ToggleRow("Signal sonore", null);
            _sound.Changed += delegate { S.BreakSound = _sound.Checked; PushToReminder(); Commit(); };
            Add(_sound, Theme.SpaceSm);

            _now = new DarkButton();
            _now.Text = "Faire une pause maintenant";
            _now.Height = Theme.MinTarget;
            _now.Click += delegate { if (Reminder != null) Reminder.TriggerBreak(); };
            Add(_now, Theme.SpaceMd);

            Section("Clignement");

            _blink = new ToggleRow("Rappeler de cligner des yeux",
                "Un bandeau minuscule, trois secondes, sans interrompre ce qui est en cours.");
            _blink.Changed += delegate { S.BlinkReminders = _blink.Checked; PushToReminder(); UpdateStates(); Commit(); };
            Add(_blink, Theme.SpaceSm);

            _blinkInterval = new SliderRow("Intervalle", 1, 30, "min");
            _blinkInterval.Changed += delegate { S.BlinkIntervalMinutes = (int)_blinkInterval.Value; PushToReminder(); CommitNoSave(); };
            _blinkInterval.Committed += delegate { Commit(); };
            Add(_blinkInterval, Theme.SpaceSm);

            DarkButton blinkNow = new DarkButton();
            blinkNow.Text = "Voir le rappel maintenant";
            blinkNow.Height = Theme.MinTarget;
            blinkNow.Click += delegate { if (Reminder != null) Reminder.TriggerBlink(); };
            Add(blinkNow, Theme.SpaceSm);

            Note("Devant un ecran, la frequence de clignement chute de plus de moitie et le "
               + "clignement devient souvent incomplet : c'est la premiere cause de secheresse "
               + "oculaire au travail, et elle pese davantage sur les yeux deja fragiles. "
               + "Le rappel n'attend aucune reponse et disparait tout seul.");

            Section("Son");

            _volume = new SliderRow("Volume general", 0, 100, "%");
            _volume.Changed += delegate
            {
                if (Loading) return;
                SystemVolume.SetMaster(_volume.Value);
                UpdateVolumeNote();
            };
            Add(_volume, Theme.SpaceSm);

            _raise = new DarkButton();
            _raise.Text = "Tout remettre au maximum";
            _raise.Height = Theme.MinTarget;
            _raise.Click += OnRaiseVolume;
            Add(_raise, Theme.SpaceSm);

            _volumeNote = UiKit.Caption("");
            _volumeNote.Height = 46;
            Add(_volumeNote, Theme.SpaceXs);

            // Le libelle du bouton dit « remettre au maximum », pas « amplifier ».
            // C'est la seule formulation exacte, et la note ci-dessous explique
            // pourquoi il ne peut pas y en avoir d'autre.
            Note("Ce bouton ne rend pas le son plus fort que ne le permet Windows : il "
               + "recupere ce qui a ete perdu en chemin. Chaque application memorise son "
               + "propre volume dans le mixeur de Windows - un curseur baisse une fois par "
               + "megarde le reste pour toujours, et le mixeur est un panneau que peu de gens "
               + "savent ou trouver. Une video trop faible vient de la bien plus souvent que "
               + "du volume general.");

            Note("Aller AU-DELA de 100 % est impossible depuis une application ordinaire. "
               + "La sortie audio declare sa plage en decibels, et son maximum vaut 0 dB : "
               + "le 100 % de Windows EST le plafond, et demander davantage ne donne pas une "
               + "valeur ecretee - l'appel echoue. C'est la meme limite que le voile de "
               + "PangoBright sur la luminosite : un attenuateur retire du signal, il n'en "
               + "ajoute pas. La luminosite a pu depasser 100 % parce qu'un autre etage "
               + "existait - la table de couleurs de la carte graphique. Le son n'a pas "
               + "d'equivalent : amplifier demanderait de s'inserer dans le flux audio, "
               + "donc un pilote a installer. Le lecteur video, lui, peut le faire sur son "
               + "propre son - VLC monte a 200 %, et les extensions de navigateur aussi.");

            Section("Suivi");

            _stats = UiKit.Caption("");
            _stats.Height = 60;
            Add(_stats, Theme.SpaceSm);

            DarkButton reset = new DarkButton();
            reset.Text = "Remettre le compteur a zero";
            reset.Height = Theme.MinTarget;
            reset.Click += delegate { if (Reminder != null) { Reminder.ResetSession(); UpdateStats(); } };
            Add(reset, Theme.SpaceSm);

            Note("Le rappel s'affiche sans jamais prendre le focus : il ne peut ni "
               + "interrompre une frappe, ni faire perdre une saisie en cours.");
        }

        // ------------------------------------------------------------------ son

        private void OnRaiseVolume(object sender, EventArgs e)
        {
            if (!SystemVolume.Available)
            {
                _volumeNote.Text = "Aucune sortie audio utilisable sur cette machine.";
                return;
            }

            SystemVolume.RaiseResult r = SystemVolume.RaiseEverything();
            Sync();

            if (r.NothingToDo)
            {
                // Le cas le plus frequent, et celui qu'il ne faut surtout pas maquiller
                // en succes : annoncer « c'est fait » quand rien n'a bouge enverrait
                // chercher un probleme la ou il n'y en a pas.
                _volumeNote.Text = "Tout etait deja au maximum : volume general et volume de "
                                + "chaque application. Il n'y avait rien a recuperer, et le son "
                                + "ne peut pas monter plus haut cote Windows. Si une video reste "
                                + "faible, c'est dans le lecteur lui-meme qu'il faut chercher.";
                return;
            }

            System.Text.StringBuilder sb = new System.Text.StringBuilder();
            if (r.MasterRaised)
                sb.AppendFormat("Volume general : {0:0} % -> {1:0} %. ", r.MasterBefore, r.MasterAfter);
            if (r.AppsRaised > 0 || r.AppsUnmuted > 0)
                sb.Append(string.Join("  -  ", r.Changed.ToArray()));
            _volumeNote.Text = sb.ToString();
        }

        private void UpdateVolumeNote()
        {
            if (!SystemVolume.Available)
            {
                _volumeNote.Text = "Aucune sortie audio utilisable sur cette machine.";
                _volume.Track.Enabled = false;
                _raise.Enabled = false;
                return;
            }

            List<SystemVolume.AppSession> sessions = SystemVolume.Sessions();
            int below = 0;
            foreach (SystemVolume.AppSession a in sessions)
                if (a.Headroom > 1) below++;

            _volumeNote.Text = below == 0
                ? string.Format("{0} application(s) au mixeur, toutes au maximum. "
                              + "Plafond du materiel : {1:0.0} dB.", sessions.Count, SystemVolume.CeilingDb)
                : string.Format("{0} application(s) sous 100 % dans le mixeur de Windows : "
                              + "il y a du volume a recuperer.", below);
        }

        private void PushToReminder()
        {
            if (Reminder == null) return;
            Reminder.Enabled = S.BreaksEnabled;
            Reminder.IntervalMinutes = Math.Max(1, S.BreakIntervalMinutes);
            Reminder.DurationSeconds = Math.Max(5, S.BreakDurationSeconds);
            Reminder.DimDuringBreak = S.BreakDim;
            Reminder.PlaySound = S.BreakSound;
            Reminder.BlinkReminders = S.BlinkReminders;
            Reminder.BlinkIntervalMinutes = Math.Max(1, S.BlinkIntervalMinutes);
        }

        private void UpdateStates()
        {
            bool on = S.BreaksEnabled;
            _interval.Track.Enabled = on;
            _duration.Track.Enabled = on;
            _dim.Enabled = on;
            _sound.Enabled = on;
            _blinkInterval.Track.Enabled = S.BlinkReminders;
        }

        public void UpdateStats()
        {
            if (Reminder == null) { _stats.Text = ""; return; }
            TimeSpan t = Reminder.ScreenTime;
            string time = t.TotalHours >= 1
                ? string.Format("{0} h {1:00} min", (int)t.TotalHours, t.Minutes)
                : string.Format("{0} min", (int)t.TotalMinutes);

            string next = S.BreaksEnabled
                ? string.Format("Prochaine pause dans {0} min.", Math.Max(0, (int)Reminder.UntilNextBreak.TotalMinutes) + 1)
                : "Les rappels sont desactives.";

            _stats.Text = string.Format("Ecran allume depuis {0} pour cette session.\n{1}", time, next);
        }

        public override void Sync()
        {
            Loading = true;
            try
            {
                _enabled.SetCheckedSilent(S.BreaksEnabled);
                _interval.SetValueSilent(S.BreakIntervalMinutes);
                _duration.SetValueSilent(S.BreakDurationSeconds);
                _dim.SetCheckedSilent(S.BreakDim);
                _sound.SetCheckedSilent(S.BreakSound);
                _blink.SetCheckedSilent(S.BlinkReminders);
                _blinkInterval.SetValueSilent(S.BlinkIntervalMinutes);

                double master = SystemVolume.GetMaster();
                if (master >= 0) _volume.SetValueSilent(master);
                UpdateVolumeNote();

                PushToReminder();
                UpdateStates();
                UpdateStats();
            }
            finally { Loading = false; }
        }
    }
}
