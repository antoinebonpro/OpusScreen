using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace OpusScreen
{
    /// <summary>
    /// Coordonne l'ensemble : icone de notification, menu, raccourcis, horloge,
    /// adaptation au contenu, regles par application, pauses et evenements systeme.
    ///
    /// Toute la logique de rendu vit dans DisplayController ; ici on decide seulement
    /// QUAND appliquer, et avec quelles valeurs.
    /// </summary>
    public class TrayApp : ApplicationContext
    {
        private readonly Settings _s;
        private readonly DisplayController _display;
        private readonly NotifyIcon _tray;
        private readonly Timer _slowTick = new Timer();     // planification, statistiques
        private readonly Timer _fastTick = new Timer();     // application au premier plan
        private readonly ContentAdaptive _adaptive = new ContentAdaptive();
        private readonly AppWatcher _watcher = new AppWatcher();
        private readonly BreakReminder _breaks = new BreakReminder();

        private ControlPanel _panel;
        private HotkeyWindow _hotkeys;
        private WakeWindow _wake;
        private TrayWheel _wheel;
        private Icon _currentIcon;
        private DateTime _pauseUntil = DateTime.MinValue;
        private string _appliedRule = "";

        private static readonly double[] Steps =
            { 150, 140, 130, 120, 110, 100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 5 };

        public TrayApp(Settings settings, DisplayController display, string[] args)
        {
            _s = settings;
            _display = display;

            _tray = new NotifyIcon();
            _tray.Visible = true;
            _tray.Text = "OpusScreen";
            _tray.MouseUp += OnTrayClick;

            BuildMenu();
            HookSystemEvents();
            RebindHotkeys();

            _wake = new WakeWindow(this);

            // Un raccourci connu du menu Demarrer est ce que Windows epingle ; la liste
            // de taches vient s'y accrocher. Les deux sont rejoues a chaque demarrage :
            // l'executable a pu changer de dossier entre-temps.
            Taskbar.EnsureShortcut();
            Taskbar.PublishJumpList(false);

            _wheel = new TrayWheel(_tray);
            _wheel.Scrolled += OnTrayWheel;

            SafetyGuard.PanicTriggered += OnPanic;

            _adaptive.SuggestedBrightness += OnAdaptiveSuggestion;
            _watcher.ForegroundChanged += OnForegroundChanged;
            _watcher.FullscreenChanged += OnFullscreenChanged;
            _breaks.BreakStateChanged += OnBreakState;

            _slowTick.Interval = 20000;
            _slowTick.Tick += OnSlowTick;
            _slowTick.Start();

            _fastTick.Interval = 1000;
            _fastTick.Tick += delegate { _watcher.Poll(); CheckPauseExpiry(); CheckPendingCommand(); };
            _fastTick.Start();

            SyncEnginesFromSettings();
            ApplyAll();

            // Le panneau s'ouvre au tout premier lancement - sinon rien ne semble se
            // passer - puis seulement si l'utilisateur n'a pas demande le contraire.
            // --show passe outre : c'est une demande explicite de la fenetre.
            bool wantsQuiet = (CommandLine.StartMinimized(args) || CommandLine.HasCommand(args))
                              && !CommandLine.WantsShow(args);
            if (!wantsQuiet && (_s.IsFirstRun || !_s.StartMinimized || CommandLine.WantsShow(args)))
                ShowPanel();
        }

        /// <summary>
        /// Applique un ordre depose par un second lancement en ligne de commande.
        /// Verifie chaque seconde : suffisamment reactif pour un usage au clavier ou
        /// depuis un script, sans surveiller le disque en permanence.
        /// </summary>
        private void CheckPendingCommand()
        {
            string cmd = CommandLine.ConsumePending();
            if (cmd.Length == 0) return;

            string[] parts = SplitArgs(cmd);

            foreach (string a in parts)
            {
                switch (a.ToLowerInvariant())
                {
                    case "--pause": PauseFor(TimeSpan.MaxValue); return;
                    case "--resume": ResumeEffects(); return;
                    case "--break": _breaks.TriggerBreak(); return;
                    case "--show": ShowPanel(); return;
                }
            }

            if (CommandLine.ApplyTo(_s, parts))
            {
                _s.Save();
                SyncEnginesFromSettings();
                ApplyAll();
                if (_panel != null && _panel.IsHandleCreated) _panel.SyncAll();
            }
        }

        /// <summary>Redecoupe la ligne d'ordre en respectant les guillemets.</summary>
        private static string[] SplitArgs(string line)
        {
            List<string> parts = new List<string>();
            bool inQuotes = false;
            System.Text.StringBuilder cur = new System.Text.StringBuilder();
            foreach (char c in line)
            {
                if (c == '"') { inQuotes = !inQuotes; continue; }
                if (c == ' ' && !inQuotes)
                {
                    if (cur.Length > 0) { parts.Add(cur.ToString()); cur.Length = 0; }
                    continue;
                }
                cur.Append(c);
            }
            if (cur.Length > 0) parts.Add(cur.ToString());
            return parts.ToArray();
        }

        // ------------------------------------------------------------------ menu

        private void BuildMenu()
        {
            ContextMenuStrip menu = new ContextMenuStrip();
            menu.ShowImageMargin = false;
            menu.Renderer = new DarkMenuRenderer();
            menu.Opening += delegate { RebuildMenu(menu); };
            _tray.ContextMenuStrip = menu;
        }

        private void RebuildMenu(ContextMenuStrip menu)
        {
            menu.Items.Clear();

            ToolStripMenuItem header = new ToolStripMenuItem(
                _display.Suspended ? "OpusScreen - suspendu" : string.Format("OpusScreen - {0} % - {1} K",
                    (int)Math.Round(_s.Current.Brightness), _s.Current.Kelvin));
            header.Enabled = false;
            header.Font = Theme.BodyBold;
            menu.Items.Add(header);
            menu.Items.Add(new ToolStripSeparator());

            // --- modes ---
            ToolStripMenuItem modes = new ToolStripMenuItem("Modes");
            List<Profile> all = new List<Profile>(Profile.BuiltInModes());
            all.AddRange(_s.CustomProfiles);
            foreach (Profile p in all)
            {
                Profile captured = p;
                ToolStripMenuItem mi = new ToolStripMenuItem(p.Name + "   " + p.Summary());
                mi.Checked = p.Name == _s.ActiveModeName;
                mi.Click += delegate { ApplyMode(captured); };
                modes.DropDownItems.Add(mi);
            }
            menu.Items.Add(modes);

            // --- luminosite ---
            ToolStripMenuItem levels = new ToolStripMenuItem("Luminosite");
            foreach (double step in Steps)
            {
                double captured = step;
                string label = step == 150 ? "150 %  (boost maximum)"
                             : step == 100 ? "100 %  (normal)"
                             : step == 5 ? "5 %  (minimum)"
                             : string.Format("{0} %", step);
                ToolStripMenuItem mi = new ToolStripMenuItem(label);
                mi.Checked = Math.Abs(step - _s.Current.Brightness) < 0.5;
                if (step > 100) mi.ForeColor = Theme.Boost;
                mi.Click += delegate { SetBrightness(captured); };
                levels.DropDownItems.Add(mi);
            }
            menu.Items.Add(levels);

            // --- ecrans ---
            ToolStripMenuItem screens = new ToolStripMenuItem("Ecrans");
            screens.DropDownOpening += delegate { BuildScreenSubmenu(screens); };
            menu.Items.Add(screens);

            menu.Items.Add(new ToolStripSeparator());

            // --- automatismes rapides ---
            ToolStripMenuItem adaptive = new ToolStripMenuItem("Suivre le contenu affiche");
            adaptive.Checked = _s.AdaptiveEnabled;
            adaptive.Click += delegate { ToggleAdaptive(); };
            menu.Items.Add(adaptive);

            ToolStripMenuItem solar = new ToolStripMenuItem("Suivre le soleil");
            solar.Checked = _s.Schedule != ScheduleMode.Manual;
            solar.Click += delegate
            {
                _s.Schedule = _s.Schedule == ScheduleMode.Manual ? ScheduleMode.Solar : ScheduleMode.Manual;
                _s.Save();
                ApplyAll();
            };
            menu.Items.Add(solar);

            // --- suspension ---
            ToolStripMenuItem pause = new ToolStripMenuItem("Suspendre");
            if (_display.Suspended)
            {
                pause.Text = "Reprendre";
                pause.Click += delegate { ResumeEffects(); };
                menu.Items.Add(pause);
            }
            else
            {
                ToolStripMenuItem p30 = new ToolStripMenuItem("30 minutes");
                p30.Click += delegate { PauseFor(TimeSpan.FromMinutes(30)); };
                ToolStripMenuItem p60 = new ToolStripMenuItem("1 heure");
                p60.Click += delegate { PauseFor(TimeSpan.FromHours(1)); };
                ToolStripMenuItem pInf = new ToolStripMenuItem("Jusqu'a nouvel ordre");
                pInf.Click += delegate { PauseFor(TimeSpan.MaxValue); };
                pause.DropDownItems.Add(p30);
                pause.DropDownItems.Add(p60);
                pause.DropDownItems.Add(pInf);
                menu.Items.Add(pause);
            }

            ToolStripMenuItem brk = new ToolStripMenuItem("Pause pour les yeux");
            brk.Click += delegate { _breaks.TriggerBreak(); };
            menu.Items.Add(brk);

            menu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem settings = new ToolStripMenuItem("Reglages...");
            settings.Font = Theme.BodyBold;
            settings.Click += delegate { ShowPanel(); };
            menu.Items.Add(settings);

            menu.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem reset = new ToolStripMenuItem("Tout reinitialiser   (Ctrl+Alt+Maj+R)");
            reset.Click += delegate { ResetEverything(); };
            menu.Items.Add(reset);

            ToolStripMenuItem quit = new ToolStripMenuItem("Quitter");
            quit.Click += delegate { ExitCleanly(); };
            menu.Items.Add(quit);
        }

        private void BuildScreenSubmenu(ToolStripMenuItem parent)
        {
            parent.DropDownItems.Clear();
            _display.RefreshMonitors();

            foreach (MonitorInfo m in _display.Monitors)
            {
                MonitorInfo captured = m;
                MonitorSettings ms = _s.For(m);

                ToolStripMenuItem item = new ToolStripMenuItem(m.Label);
                item.Checked = ms.Enabled;
                item.Click += delegate
                {
                    MonitorSettings x = _s.For(captured);
                    x.Enabled = !x.Enabled;
                    _s.Save();
                    ApplyAll();
                };
                parent.DropDownItems.Add(item);

                ToolStripMenuItem black = new ToolStripMenuItem("     Eteindre cet ecran");
                black.Checked = ms.Blackout;
                black.Click += delegate
                {
                    MonitorSettings x = _s.For(captured);
                    x.Blackout = !x.Blackout;
                    _s.Save();
                    ApplyAll();
                };
                parent.DropDownItems.Add(black);
            }
        }

        private void OnTrayClick(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left) ShowPanel();
        }

        // ------------------------------------------------------------------ actions

        public void ApplyMode(Profile p)
        {
            _s.Current.CopyFrom(p);
            _s.ActiveModeName = p.Name;
            _s.Save();
            ApplyAll();
            if (_panel != null && _panel.IsHandleCreated && _panel.Visible) _panel.SyncAll();
        }

        public void SetBrightness(double value)
        {
            _s.Current.Brightness = SafetyGuard.ClampBrightness(value);
            _s.Save();
            ApplyAll();
        }

        public void NudgeBrightness(double delta)
        {
            SetBrightness(_s.Current.Brightness + delta);
        }

        public void NudgeTemperature(int delta)
        {
            if (_s.Schedule != ScheduleMode.Manual) return;
            _s.Current.Kelvin = Math.Max(ColorTemp.MinKelvin,
                                Math.Min(ColorTemp.MaxKelvin, _s.Current.Kelvin + delta));
            _s.Save();
            ApplyAll();
        }

        public void NextMode()
        {
            List<Profile> all = new List<Profile>(Profile.BuiltInModes());
            all.AddRange(_s.CustomProfiles);
            if (all.Count == 0) return;
            int idx = 0;
            for (int i = 0; i < all.Count; i++) if (all[i].Name == _s.ActiveModeName) idx = i;
            ApplyMode(all[(idx + 1) % all.Count]);
        }

        public void ToggleAdaptive()
        {
            _s.AdaptiveEnabled = !_s.AdaptiveEnabled;
            _s.Save();
            SyncEnginesFromSettings();
            ApplyAll();
        }

        public void PauseFor(TimeSpan duration)
        {
            _pauseUntil = duration == TimeSpan.MaxValue ? DateTime.MaxValue : DateTime.Now + duration;
            _display.Suspend(duration == TimeSpan.MaxValue
                ? "en pause"
                : "en pause jusqu'a " + _pauseUntil.ToString("HH:mm"));
            UpdateIcon();
            Taskbar.PublishJumpList(true);
            if (_panel != null && _panel.IsHandleCreated) _panel.RefreshReadouts();
        }

        public void ResumeEffects()
        {
            _pauseUntil = DateTime.MinValue;
            _display.Resume();
            UpdateIcon();
            Taskbar.PublishJumpList(false);
            if (_panel != null && _panel.IsHandleCreated) _panel.RefreshReadouts();
        }

        public void TogglePause()
        {
            if (_display.Suspended) ResumeEffects();
            else PauseFor(TimeSpan.MaxValue);
        }

        private void CheckPauseExpiry()
        {
            if (_pauseUntil == DateTime.MinValue || _pauseUntil == DateTime.MaxValue) return;
            if (DateTime.Now >= _pauseUntil) ResumeEffects();
        }

        public void ResetEverything()
        {
            _pauseUntil = DateTime.MinValue;
            _s.Current = new Profile();
            _s.ActiveModeName = "Normal";
            _s.Schedule = ScheduleMode.Manual;
            _s.AdaptiveEnabled = false;
            foreach (MonitorSettings ms in _s.Monitors) { ms.Blackout = false; ms.Enabled = true; }
            _display.Resume();
            _display.RestoreAll();
            _s.Save();
            SyncEnginesFromSettings();
            ApplyAll();
            if (_panel != null && _panel.IsHandleCreated) _panel.SyncAll();
        }

        /// <summary>Applique l'etat courant apres avoir laisse les automatismes s'exprimer.</summary>
        public void ApplyAll()
        {
            if (!_display.Suspended)
            {
                ScheduleResult sched = Scheduler.Evaluate(_s, DateTime.Now);
                if (_s.Schedule != ScheduleMode.Manual)
                {
                    _s.Current.Kelvin = sched.Kelvin;
                    // L'adaptation au contenu, plus reactive, garde la main sur la luminosite.
                    if (sched.BrightnessApplies && !_s.AdaptiveEnabled)
                        _s.Current.Brightness = SafetyGuard.ClampBrightness(sched.Brightness);
                }
            }

            _display.Apply();
            UpdateIcon();
            UpdateTooltip();

            if (_panel != null && _panel.IsHandleCreated && _panel.Visible)
                _panel.RefreshReadouts();
        }

        private void SyncEnginesFromSettings()
        {
            _adaptive.MinBrightness = _s.AdaptiveMin;
            _adaptive.MaxBrightness = _s.AdaptiveMax;
            _adaptive.Reactivity = _s.AdaptiveReactivity;
            _adaptive.IntervalMs = _s.AdaptiveIntervalMs;

            if (_s.AdaptiveEnabled && !_adaptive.IsRunning) _adaptive.Start();
            else if (!_s.AdaptiveEnabled && _adaptive.IsRunning) _adaptive.Stop();

            _breaks.Enabled = _s.BreaksEnabled;
            _breaks.IntervalMinutes = Math.Max(1, _s.BreakIntervalMinutes);
            _breaks.DurationSeconds = Math.Max(5, _s.BreakDurationSeconds);
            _breaks.DimDuringBreak = _s.BreakDim;
            _breaks.PlaySound = _s.BreakSound;
        }

        // ------------------------------------------------------------------ automatismes

        private void OnAdaptiveSuggestion(double suggested)
        {
            // Emis depuis le thread de mesure : on repasse par le thread d'interface.
            try
            {
                if (_tray == null) return;
                Control host = _panel;
                if (host != null && host.IsHandleCreated)
                {
                    host.BeginInvoke((MethodInvoker)delegate { ApplyAdaptive(suggested); });
                }
                else
                {
                    ApplyAdaptive(suggested);
                }
            }
            catch { }
        }

        private void ApplyAdaptive(double suggested)
        {
            if (!_s.AdaptiveEnabled || _display.Suspended) return;
            if (Math.Abs(_s.Current.Brightness - suggested) < 0.4) return;
            _s.Current.Brightness = SafetyGuard.ClampBrightness(suggested);
            _display.Apply();
            UpdateIcon();
            UpdateTooltip();
        }

        private void OnForegroundChanged(string process)
        {
            if (!_s.AppRulesEnabled || string.IsNullOrEmpty(process)) return;
            if (process == "opusscreen") return;

            AppRule match = null;
            foreach (AppRule r in _s.AppRules)
                if (r.ProcessName == process) { match = r; break; }

            if (match == null)
            {
                if (_appliedRule.Length > 0)
                {
                    _appliedRule = "";
                    if (_display.Suspended && _display.SuspendReason.StartsWith("regle")) _display.Resume();
                    ApplyAll();
                }
                return;
            }

            _appliedRule = process;

            if (match.Disable)
            {
                _display.Suspend("regle pour " + process);
                UpdateIcon();
                return;
            }

            if (_display.Suspended && _display.SuspendReason.StartsWith("regle")) _display.Resume();

            foreach (Profile p in Profile.BuiltInModes())
                if (p.Name == match.ProfileName) { ApplyMode(p); return; }
            foreach (Profile p in _s.CustomProfiles)
                if (p.Name == match.ProfileName) { ApplyMode(p); return; }
        }

        private void OnFullscreenChanged(bool fullscreen)
        {
            if (!_s.DisableOnFullscreen) return;
            if (fullscreen) _display.Suspend("application en plein ecran");
            else if (_display.SuspendReason == "application en plein ecran") _display.Resume();
            UpdateIcon();
        }

        private void OnBreakState(bool inBreak)
        {
            if (inBreak) _display.Suspend("pause en cours");
            else if (_display.SuspendReason == "pause en cours") _display.Resume();
        }

        private void OnSlowTick(object sender, EventArgs e)
        {
            if (_s.Schedule != ScheduleMode.Manual) ApplyAll();
            else _display.ReapplyIfNeeded();

            if (_panel != null && _panel.IsHandleCreated && _panel.Visible)
                _panel.RefreshReadouts();
        }

        // ------------------------------------------------------------------ raccourcis

        public void RebindHotkeys()
        {
            if (_hotkeys != null) { _hotkeys.Dispose(); _hotkeys = null; }
            if (!_s.HotkeysEnabled) return;
            _hotkeys = new HotkeyWindow(this, _s);
        }

        public void RunAction(string action)
        {
            switch (action)
            {
                case "brightness.up": NudgeBrightness(+5); break;
                case "brightness.down": NudgeBrightness(-5); break;
                case "temp.warmer": NudgeTemperature(-200); break;
                case "temp.cooler": NudgeTemperature(+200); break;
                case "reset": ResetEverything(); break;
                case "pause.toggle": TogglePause(); break;
                case "mode.next": NextMode(); break;
                case "adaptive.toggle": ToggleAdaptive(); break;
                case "break.now": _breaks.TriggerBreak(); break;
                case "panel.show": ShowPanel(); break;
            }
        }

        private void OnTrayWheel(int delta)
        {
            if (!_s.TrayWheelControl) return;
            NudgeBrightness(delta > 0 ? +5 : -5);
        }

        // ------------------------------------------------------------------ fenetre

        private void ShowPanel()
        {
            if (_panel == null || _panel.IsDisposed)
            {
                _panel = new ControlPanel(_s, _display, ApplyAll);
                _panel.TogglePause = TogglePause;
                _panel.AutoPage.Engine = _adaptive;
                _panel.AppsPage.Watcher = _watcher;
                _panel.ComfortPage.Reminder = _breaks;
                _panel.HotkeysPage.Rebind = RebindHotkeys;
                PositionNearTray(_panel);
            }
            _panel.SyncAll();
            _panel.Show();
            if (_panel.WindowState == FormWindowState.Minimized)
                _panel.WindowState = FormWindowState.Normal;
            _panel.BringToFront();
            _panel.Activate();

            // Activate() suffit quand le clic vient de l'application elle-meme. Venant
            // d'un autre processus - icone epinglee, liste de taches - Windows exige
            // en plus cette demande explicite, sans quoi la fenetre reste derriere.
            try
            {
                IntPtr h = _panel.Handle;
                Native.ShowWindow(h, Native.SW_RESTORE);
                Native.SetForegroundWindow(h);
            }
            catch { }
        }

        private static void PositionNearTray(Form f)
        {
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            f.Location = new Point(
                Math.Max(wa.Left, wa.Right - f.Width - 20),
                Math.Max(wa.Top, wa.Bottom - f.Height - 20));
        }

        // ------------------------------------------------------------------ icone

        private void UpdateTooltip()
        {
            string t = _display.Suspended
                ? "OpusScreen - suspendu"
                : string.Format("OpusScreen - {0} % - {1} K",
                    (int)Math.Round(_s.Current.Brightness), _s.Current.Kelvin);
            // Windows tronque au-dela de 63 caracteres.
            _tray.Text = t.Length > 62 ? t.Substring(0, 62) : t;
        }

        /// <summary>
        /// Icone redessinee a chaque changement : sa couleur suit la temperature, son
        /// remplissage la luminosite. L'etat se lit sans ouvrir quoi que ce soit.
        /// </summary>
        private void UpdateIcon()
        {
            try
            {
                double[] mult = ColorTemp.Multipliers(_s.Current.Kelvin);
                double b = _s.Current.Brightness / 150.0;

                using (Bitmap bmp = new Bitmap(32, 32))
                {
                    using (Graphics g = Graphics.FromImage(bmp))
                    {
                        g.SmoothingMode = SmoothingMode.AntiAlias;
                        g.Clear(Color.Transparent);

                        if (_display.Suspended)
                        {
                            using (Pen p = new Pen(Color.FromArgb(150, 156, 172), 2.5f))
                            {
                                g.DrawEllipse(p, 5, 5, 22, 22);
                                g.DrawLine(p, 11, 10, 11, 22);
                                g.DrawLine(p, 20, 10, 20, 22);
                            }
                        }
                        else
                        {
                            int level = (int)Math.Round(58 + 195 * Math.Min(1.0, b * 1.15));
                            Color disc = Color.FromArgb(255,
                                Clamp255(level * mult[0]), Clamp255(level * mult[1]), Clamp255(level * mult[2]));

                            if (_s.Current.Brightness > 100)
                            {
                                using (SolidBrush halo = new SolidBrush(Color.FromArgb(70, disc)))
                                    g.FillEllipse(halo, 1, 1, 30, 30);
                            }

                            using (SolidBrush br = new SolidBrush(disc))
                                g.FillEllipse(br, 6, 6, 20, 20);
                            using (Pen p = new Pen(Color.FromArgb(210, 18, 20, 26), 2))
                                g.DrawEllipse(p, 6, 6, 20, 20);

                            if (_s.AdaptiveEnabled)
                            {
                                using (SolidBrush dot = new SolidBrush(Color.FromArgb(86, 200, 130)))
                                    g.FillEllipse(dot, 22, 22, 9, 9);
                            }
                        }
                    }

                    IntPtr h = bmp.GetHicon();
                    Icon old = _currentIcon;
                    _currentIcon = Icon.FromHandle(h);
                    _tray.Icon = _currentIcon;
                    if (old != null) { DestroyIcon(old.Handle); old.Dispose(); }
                }
            }
            catch
            {
                if (_tray.Icon == null) _tray.Icon = SystemIcons.Application;
            }
        }

        [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr handle);

        private static int Clamp255(double v) { return v < 0 ? 0 : (v > 255 ? 255 : (int)Math.Round(v)); }

        // ------------------------------------------------------------------ evenements systeme

        private void HookSystemEvents()
        {
            SystemEvents.DisplaySettingsChanged += OnDisplayChanged;
            SystemEvents.PowerModeChanged += OnPowerChanged;
            SystemEvents.SessionSwitch += OnSessionSwitch;
            SystemEvents.SessionEnding += OnSessionEnding;
            SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        }

        private void UnhookSystemEvents()
        {
            try
            {
                SystemEvents.DisplaySettingsChanged -= OnDisplayChanged;
                SystemEvents.PowerModeChanged -= OnPowerChanged;
                SystemEvents.SessionSwitch -= OnSessionSwitch;
                SystemEvents.SessionEnding -= OnSessionEnding;
                SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
            }
            catch { }
        }

        private void OnDisplayChanged(object sender, EventArgs e)
        {
            _display.RefreshMonitors();
            ApplyAll();
            if (_panel != null && _panel.IsHandleCreated) _panel.SyncAll();
        }

        private void OnPowerChanged(object sender, PowerModeChangedEventArgs e)
        {
            // Au reveil, Windows a remis la LUT a l'identite : il faut la reposer.
            if (e.Mode == PowerModes.Resume) ApplyAll();

            if (e.Mode == PowerModes.StatusChange && _s.DisableOnBattery)
            {
                bool onBattery = SystemInformation.PowerStatus.PowerLineStatus == PowerLineStatus.Offline;
                if (onBattery && _s.Current.Brightness > 100)
                {
                    _s.Current.Brightness = 100;
                    ApplyAll();
                }
            }
        }

        private void OnSessionSwitch(object sender, SessionSwitchEventArgs e)
        {
            if (e.Reason == SessionSwitchReason.SessionUnlock
             || e.Reason == SessionSwitchReason.ConsoleConnect) ApplyAll();
        }

        private void OnSessionEnding(object sender, SessionEndingEventArgs e)
        {
            try { _display.RestoreAll(); } catch { }
        }

        private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
        {
            // Bascule du contraste eleve : le theme doit etre relu.
            if (e.Category == UserPreferenceCategory.Accessibility
             || e.Category == UserPreferenceCategory.Color)
            {
                if (_panel != null && _panel.IsHandleCreated) _panel.Invalidate(true);
            }
        }

        private void OnPanic()
        {
            try
            {
                MethodInvoker reset = delegate
                {
                    _pauseUntil = DateTime.MinValue;
                    _s.Current = new Profile();
                    _s.ActiveModeName = "Normal";
                    _s.Schedule = ScheduleMode.Manual;
                    _s.AdaptiveEnabled = false;
                    foreach (MonitorSettings ms in _s.Monitors) { ms.Blackout = false; ms.Enabled = true; }
                    _s.Save();
                    SyncEnginesFromSettings();
                    UpdateIcon();
                    if (_panel != null && _panel.IsHandleCreated) _panel.SyncAll();
                };

                if (_panel != null && _panel.IsHandleCreated) _panel.BeginInvoke(reset);
                else reset();
            }
            catch { }
        }

        // ------------------------------------------------------------------ sortie

        public void ExitCleanly()
        {
            _slowTick.Stop();
            _fastTick.Stop();
            UnhookSystemEvents();

            try { if (_wheel != null) _wheel.Dispose(); } catch { }
            try { if (_hotkeys != null) _hotkeys.Dispose(); } catch { }
            try { if (_wake != null) _wake.Dispose(); } catch { }
            try { _adaptive.Dispose(); } catch { }
            try { _breaks.Dispose(); } catch { }
            try { _display.RestoreAll(); } catch { }
            try { _display.Dispose(); } catch { }

            HardwareBacklight.Stop();
            SafetyGuard.StopGuardThread();
            SafetyGuard.ClearDirtyFlag();

            _tray.Visible = false;
            _tray.Dispose();
            ExitThread();
        }

        /// <summary>
        /// Fenetre invisible qui ecoute la demande d'ouverture emise par un second
        /// lancement - un clic sur l'icone epinglee a la barre des taches, par exemple.
        ///
        /// Elle doit etre de premier niveau, et non rattachee au bureau des messages :
        /// une diffusion a HWND_BROADCAST n'atteint que les fenetres de premier niveau.
        /// Elle vit hors du panneau de reglages, qui n'existe pas tant qu'on ne l'a pas
        /// demande - or c'est justement ce qu'on demande ici.
        /// </summary>
        private class WakeWindow : NativeWindow, IDisposable
        {
            private readonly TrayApp _owner;

            public WakeWindow(TrayApp owner)
            {
                _owner = owner;
                CreateHandle(new CreateParams());
            }

            protected override void WndProc(ref Message m)
            {
                if (m.Msg == (int)Native.WM_OPUSSCREEN_SHOW && Native.WM_OPUSSCREEN_SHOW != 0)
                {
                    try { _owner.ShowPanel(); } catch { }
                    return;
                }
                base.WndProc(ref m);
            }

            public void Dispose() { DestroyHandle(); }
        }

        /// <summary>
        /// Fenetre invisible qui recoit les raccourcis globaux configures.
        /// Le raccourci de secours n'est PAS ici : il vit sur son propre thread pour
        /// rester operationnel meme si l'interface se bloque.
        /// </summary>
        private class HotkeyWindow : NativeWindow, IDisposable
        {
            private readonly TrayApp _owner;
            private readonly Dictionary<int, string> _map = new Dictionary<int, string>();

            public HotkeyWindow(TrayApp owner, Settings s)
            {
                _owner = owner;
                CreateHandle(new CreateParams());

                int id = 100;
                foreach (HotkeyBinding h in s.Hotkeys)
                {
                    if (!h.Enabled || h.Key == 0) continue;
                    // Le secours est deja pris en charge par le thread de securite.
                    if (h.Action == "reset") continue;

                    if (Native.RegisterHotKey(Handle, id, h.Modifiers | Native.MOD_NOREPEAT, h.Key)
                     || Native.RegisterHotKey(Handle, id, h.Modifiers, h.Key))
                    {
                        _map[id] = h.Action;
                        id++;
                    }
                }
            }

            protected override void WndProc(ref Message m)
            {
                if (m.Msg == Native.WM_HOTKEY)
                {
                    string action;
                    if (_map.TryGetValue(m.WParam.ToInt32(), out action)) _owner.RunAction(action);
                }
                base.WndProc(ref m);
            }

            public void Dispose()
            {
                foreach (int id in _map.Keys)
                {
                    try { Native.UnregisterHotKey(Handle, id); } catch { }
                }
                _map.Clear();
                DestroyHandle();
            }
        }
    }

    /// <summary>Rendu sombre du menu de la zone de notification.</summary>
    public class DarkMenuRenderer : ToolStripProfessionalRenderer
    {
        public DarkMenuRenderer() : base(new DarkColors()) { }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            if (!e.Item.Enabled && e.Item.ForeColor == SystemColors.ControlText)
                e.TextColor = Theme.Dim;
            else if (e.Item.ForeColor != SystemColors.ControlText)
                e.TextColor = e.Item.ForeColor;
            else
                e.TextColor = Theme.Fg;
            base.OnRenderItemText(e);
        }

        private class DarkColors : ProfessionalColorTable
        {
            public override Color ToolStripDropDownBackground { get { return Theme.Card; } }
            public override Color MenuItemSelected { get { return Theme.CardHover; } }
            public override Color MenuItemSelectedGradientBegin { get { return Theme.CardHover; } }
            public override Color MenuItemSelectedGradientEnd { get { return Theme.CardHover; } }
            public override Color MenuItemBorder { get { return Theme.Accent; } }
            public override Color MenuBorder { get { return Theme.Border; } }
            public override Color ImageMarginGradientBegin { get { return Theme.Card; } }
            public override Color ImageMarginGradientMiddle { get { return Theme.Card; } }
            public override Color ImageMarginGradientEnd { get { return Theme.Card; } }
            public override Color SeparatorDark { get { return Theme.Border; } }
            public override Color SeparatorLight { get { return Theme.Border; } }
            public override Color CheckBackground { get { return Theme.AccentDim; } }
            public override Color CheckSelectedBackground { get { return Theme.Accent; } }
        }
    }

    /// <summary>
    /// Molette de la souris au-dessus de l'icone de notification.
    ///
    /// NotifyIcon n'expose pas d'evenement de molette : Windows n'envoie pas
    /// WM_MOUSEWHEEL aux icones. On installe donc un crochet souris de bas niveau, et
    /// on ne retient un cran de molette que s'il survient dans la seconde qui suit un
    /// survol de l'icone - ce qui evite de detourner la molette du reste du systeme.
    /// </summary>
    public class TrayWheel : IDisposable
    {
        private delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, HookProc fn, IntPtr module, uint thread);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
        [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr GetModuleHandle(string name);

        private const int WH_MOUSE_LL = 14;
        private const int WM_MOUSEWHEEL = 0x020A;

        [StructLayout(LayoutKind.Sequential)]
        private struct MSLLHOOKSTRUCT
        {
            public int x, y;
            public uint mouseData;
            public uint flags, time;
            public IntPtr extra;
        }

        private IntPtr _hook;
        private readonly HookProc _proc;      // conserve pour empecher le ramasse-miettes
        private DateTime _lastHover = DateTime.MinValue;

        public event Action<int> Scrolled;

        public TrayWheel(NotifyIcon icon)
        {
            icon.MouseMove += delegate { _lastHover = DateTime.Now; };

            _proc = Callback;
            try
            {
                using (System.Diagnostics.Process p = System.Diagnostics.Process.GetCurrentProcess())
                using (System.Diagnostics.ProcessModule m = p.MainModule)
                    _hook = SetWindowsHookEx(WH_MOUSE_LL, _proc, GetModuleHandle(m.ModuleName), 0);
            }
            catch { _hook = IntPtr.Zero; }
        }

        private IntPtr Callback(int code, IntPtr wParam, IntPtr lParam)
        {
            try
            {
                if (code >= 0 && wParam.ToInt32() == WM_MOUSEWHEEL
                 && (DateTime.Now - _lastHover).TotalMilliseconds < 900)
                {
                    MSLLHOOKSTRUCT data = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                    int delta = (short)((data.mouseData >> 16) & 0xFFFF);
                    Action<int> h = Scrolled;
                    if (h != null) h(delta);
                    return new IntPtr(1);   // consomme le cran : la fenetre dessous ne defile pas
                }
            }
            catch { }
            return CallNextHookEx(_hook, code, wParam, lParam);
        }

        public void Dispose()
        {
            if (_hook != IntPtr.Zero)
            {
                try { UnhookWindowsHookEx(_hook); } catch { }
                _hook = IntPtr.Zero;
            }
        }
    }
}
