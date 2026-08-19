using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>Reconfiguration des raccourcis globaux.</summary>
    public class PageHotkeys : SettingsPage
    {
        private ToggleRow _enabled, _wheel;
        private HotkeyList _list;

        /// <summary>Appelee quand les raccourcis doivent etre reenregistres aupres de Windows.</summary>
        public Action Rebind;

        public override string Title { get { return "Raccourcis"; } }
        public override string Subtitle { get { return "Piloter sans ouvrir la fenetre"; } }

        public PageHotkeys(Settings s, DisplayController d, Action push) : base(s, d, push)
        {
            Section("General");

            _enabled = new ToggleRow("Activer les raccourcis globaux", null);
            _enabled.Changed += delegate
            {
                S.HotkeysEnabled = _enabled.Checked;
                _list.Enabled = _enabled.Checked;
                if (Rebind != null) Rebind();
                Commit();
            };
            Add(_enabled, Theme.SpaceSm);

            _wheel = new ToggleRow("Molette sur l'icone de la zone de notification",
                "Faire rouler la molette au-dessus de l'icone change la luminosite.");
            _wheel.Changed += delegate { S.TrayWheelControl = _wheel.Checked; Commit(); };
            Add(_wheel, Theme.SpaceSm);

            Section("Attributions");

            _list = new HotkeyList(S);
            _list.Height = 330;
            _list.Changed += delegate
            {
                if (Rebind != null) Rebind();
                Commit();
            };
            Add(_list, Theme.SpaceSm);

            Note("Cliquez sur une ligne puis pressez la combinaison voulue. Echap annule, "
               + "Suppr desactive le raccourci.");

            DarkButton reset = new DarkButton();
            reset.Text = "Retablir les raccourcis par defaut";
            reset.Height = Theme.MinTarget;
            reset.Click += delegate
            {
                S.Hotkeys = Settings.DefaultHotkeys();
                _list.Reload();
                if (Rebind != null) Rebind();
                Commit();
            };
            Add(reset, Theme.SpaceSm);

            Note("Le raccourci de secours reste actif meme si l'interface se fige : il est "
               + "servi par un thread separe, avec sa propre file de messages. C'est la "
               + "garantie de pouvoir toujours retrouver un ecran normal.");
        }

        public override void Sync()
        {
            Loading = true;
            try
            {
                _enabled.SetCheckedSilent(S.HotkeysEnabled);
                _wheel.SetCheckedSilent(S.TrayWheelControl);
                _list.Enabled = S.HotkeysEnabled;
                _list.Reload();
            }
            finally { Loading = false; }
        }
    }

    /// <summary>Liste des raccourcis, capturant la prochaine combinaison pressee.</summary>
    public class HotkeyList : Control
    {
        private readonly Settings _s;
        private int _selected = -1;
        private int _hover = -1;
        private int _capturing = -1;
        private const int RowH = 32;

        public event EventHandler Changed;

        public HotkeyList(Settings s)
        {
            _s = s;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                   | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Sunken;
            Cursor = Cursors.Hand;
            TabStop = true;
        }

        public void Reload() { Invalidate(); }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            int i = e.Y / RowH;
            if (i != _hover) { _hover = i; Invalidate(); }
            base.OnMouseMove(e);
        }

        protected override void OnMouseLeave(EventArgs e) { _hover = -1; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnMouseClick(MouseEventArgs e)
        {
            int i = e.Y / RowH;
            if (i < 0 || i >= _s.Hotkeys.Count) return;
            _selected = i;
            _capturing = i;
            Focus();
            Invalidate();
            base.OnMouseClick(e);
        }

        protected override bool IsInputKey(Keys k) { return true; }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (_capturing < 0 || _capturing >= _s.Hotkeys.Count) { base.OnKeyDown(e); return; }

            if (e.KeyCode == Keys.Escape) { _capturing = -1; Invalidate(); e.Handled = true; return; }

            if (e.KeyCode == Keys.Delete)
            {
                _s.Hotkeys[_capturing].Enabled = false;
                _capturing = -1;
                Invalidate();
                if (Changed != null) Changed(this, EventArgs.Empty);
                e.Handled = true;
                return;
            }

            // On ignore les touches de modification seules : il faut une vraie touche.
            if (e.KeyCode == Keys.ControlKey || e.KeyCode == Keys.Menu
             || e.KeyCode == Keys.ShiftKey || e.KeyCode == Keys.LWin || e.KeyCode == Keys.RWin)
            { e.Handled = true; return; }

            uint mods = 0;
            if (e.Control) mods |= 0x2;
            if (e.Alt) mods |= 0x1;
            if (e.Shift) mods |= 0x4;

            if (mods == 0)
            {
                // Sans modificateur, le raccourci capterait la touche dans toutes les
                // applications : on refuse.
                e.Handled = true;
                return;
            }

            HotkeyBinding h = _s.Hotkeys[_capturing];
            h.Modifiers = mods;
            h.Key = (uint)e.KeyCode;
            h.Enabled = true;

            _capturing = -1;
            Invalidate();
            if (Changed != null) Changed(this, EventArgs.Empty);
            e.Handled = true;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(Enabled ? BackColor : Theme.Bg);

            for (int i = 0; i < _s.Hotkeys.Count; i++)
            {
                int y = i * RowH;
                if (y > Height) break;

                HotkeyBinding h = _s.Hotkeys[i];
                bool sel = i == _selected, hov = i == _hover, cap = i == _capturing;

                if (cap)
                {
                    using (SolidBrush b = new SolidBrush(Theme.AccentDim))
                        g.FillRectangle(b, 0, y, Width, RowH);
                }
                else if (sel || hov)
                {
                    using (SolidBrush b = new SolidBrush(sel ? Theme.CardHover : Theme.Card))
                        g.FillRectangle(b, 0, y, Width, RowH);
                }

                Color fg = Enabled ? Theme.Fg : Theme.Faint;
                using (Font f = Theme.Body)
                    TextRenderer.DrawText(g, Settings.ActionLabel(h.Action), f,
                        new Rectangle(10, y, Width / 2, RowH), fg,
                        TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);

                string right = cap ? "pressez une combinaison..."
                                   : (h.Enabled ? h.Describe() : "desactive");
                Color rc = cap ? Color.White : (h.Enabled ? Theme.Accent : Theme.Faint);
                using (Font f = cap ? Theme.BodyBold : Theme.Body)
                    TextRenderer.DrawText(g, right, f,
                        new Rectangle(Width / 2, y, Width / 2 - 12, RowH), rc,
                        TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);

                using (Pen p = new Pen(Theme.Border))
                    g.DrawLine(p, 0, y + RowH - 1, Width, y + RowH - 1);
            }

            using (Pen p = new Pen(Focused ? Theme.Focus : Theme.Border))
                g.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
        }
    }

    /// <summary>
    /// Etages du moteur, comportement systeme, diagnostics et transfert de configuration.
    /// Tout ce qu'on ne regarde qu'une fois - d'ou sa place en derniere page.
    /// </summary>
    public class PageAdvanced : SettingsPage
    {
        private ToggleRow _hardware, _overlay, _matrix, _smooth;
        private SliderRow _speed;
        private ToggleRow _startup, _startMin, _trayPercent, _conflicts, _darkConfirm;
        private Label _diag, _dpstNote;
        private DarkButton _dpstButton;

        public override string Title { get { return "Avance"; } }
        public override string Subtitle { get { return "Moteur, systeme et diagnostics"; } }

        public PageAdvanced(Settings s, DisplayController d, Action push) : base(s, d, push)
        {
            Section("Etages du moteur");

            _hardware = new ToggleRow("Retroeclairage physique",
                "DDC/CI sur ecran externe, WMI sur portable. Le seul etage qui emet vraiment plus de lumiere.");
            _hardware.Changed += delegate { S.UseHardwareBacklight = _hardware.Checked; Commit(); };
            Add(_hardware, Theme.SpaceSm);

            _overlay = new ToggleRow("Voile logiciel",
                "Sert uniquement sous 35 %. C'est lui qui permet de descendre jusqu'a 5 %.");
            _overlay.Changed += delegate { S.UseOverlay = _overlay.Checked; Commit(); };
            Add(_overlay, Theme.SpaceSm);

            _matrix = new ToggleRow("Matrice de couleur plein ecran",
                "Necessaire a la saturation et aux filtres. S'applique au bureau entier, pas par ecran.");
            _matrix.Changed += delegate { S.UseColorMatrix = _matrix.Checked; Commit(); };
            Add(_matrix, Theme.SpaceSm);

            Section("Transitions");

            _smooth = new ToggleRow("Fondu entre deux reglages",
                "Evite le saut brutal quand un mode ou une regle change l'ecran.");
            _smooth.Changed += delegate { S.SmoothTransitions = _smooth.Checked; _speed.Track.Enabled = _smooth.Checked; Commit(); };
            Add(_smooth, Theme.SpaceSm);

            _speed = new SliderRow("Duree du fondu", 60, 3000, "ms");
            _speed.Changed += delegate { S.TransitionSpeedMs = (int)_speed.Value; CommitNoSave(); };
            _speed.Committed += delegate { Commit(); };
            Add(_speed, Theme.SpaceSm);

            Section("Systeme");

            _startup = new ToggleRow("Lancer au demarrage de Windows", null);
            _startup.Changed += delegate
            {
                S.StartWithWindows = _startup.Checked;
                S.ApplyStartupRegistration();
                Commit();
            };
            Add(_startup, Theme.SpaceSm);

            _startMin = new ToggleRow("Demarrer sans ouvrir la fenetre", null);
            _startMin.Changed += delegate
            {
                S.StartMinimized = _startMin.Checked;
                S.ApplyStartupRegistration();
                Commit();
            };
            Add(_startMin, Theme.SpaceSm);

            _trayPercent = new ToggleRow("Afficher le pourcentage sur l'icone", null);
            _trayPercent.Changed += delegate { S.ShowTrayPercentage = _trayPercent.Checked; Commit(); };
            Add(_trayPercent, Theme.SpaceSm);

            _darkConfirm = new ToggleRow("Demander confirmation sous 20 %",
                "Retour automatique au reglage precedent si vous ne repondez pas.");
            _darkConfirm.Changed += delegate { S.SkipDarkConfirm = !_darkConfirm.Checked; Commit(); };
            Add(_darkConfirm, Theme.SpaceSm);

            _conflicts = new ToggleRow("Signaler les applications concurrentes",
                "f.lux, PangoBright, Iris... Windows n'a qu'une table de couleurs par carte graphique.");
            _conflicts.Changed += delegate { S.IgnoreConflicts = !_conflicts.Checked; Commit(); };
            Add(_conflicts, Theme.SpaceSm);

            DarkButton pin = new DarkButton();
            pin.Text = "Epingler OpusScreen a la barre des taches...";
            pin.Height = Theme.MinTarget;
            pin.Click += OnPin;
            Add(pin, Theme.SpaceSm);

            Note("Un clic sur l'icone epinglee ouvre cette fenetre ; un clic droit donne "
               + "les reglages, la suspension et les modes principaux, sans rien ouvrir.");

            Section("Configuration");

            DarkButton export = new DarkButton();
            export.Text = "Exporter la configuration...";
            export.Height = Theme.MinTarget;
            export.Click += OnExport;
            Add(export, Theme.SpaceSm);

            DarkButton import = new DarkButton();
            import.Text = "Importer une configuration...";
            import.Height = Theme.MinTarget;
            import.Click += OnImport;
            Add(import, Theme.SpaceXs);

            DarkButton folder = new DarkButton();
            folder.Text = "Ouvrir le dossier des reglages";
            folder.Height = Theme.MinTarget;
            folder.Click += delegate
            {
                try
                {
                    Directory.CreateDirectory(Settings.DataFolder);
                    System.Diagnostics.Process.Start("explorer.exe", Settings.DataFolder);
                }
                catch { }
            };
            Add(folder, Theme.SpaceXs);

            Section("Diagnostics");

            _diag = new Label();
            _diag.Font = Theme.Mono;
            _diag.ForeColor = Theme.Dim;
            _diag.AutoSize = false;
            _diag.Height = 150;
            _diag.BackColor = Color.Transparent;
            Add(_diag, Theme.SpaceSm);

            DarkButton unlock = new DarkButton();
            unlock.Text = "Debloquer la plage gamma complete (administrateur)";
            unlock.Height = Theme.MinTarget;
            unlock.Click += OnUnlock;
            Add(unlock, Theme.SpaceSm);

            _dpstButton = new DarkButton();
            _dpstButton.Text = "Arreter la luminosite automatique du pilote Intel...";
            _dpstButton.Height = Theme.MinTarget;
            _dpstButton.Click += OnFixDpst;
            Add(_dpstButton, Theme.SpaceXs);

            _dpstNote = Note("");

            DarkButton reset = new DarkButton();
            reset.Text = "Tout remettre a zero et redemarrer les reglages";
            reset.Height = Theme.MinTarget;
            reset.ForeColor = Theme.Danger;
            reset.Click += OnFactoryReset;
            Add(reset, Theme.SpaceMd);
        }

        /// <summary>
        /// Depuis Windows 10 version 1607, une application ne peut plus s'epingler
        /// elle-meme : le verbe existe toujours, le shell l'ignore. Tout ce qu'on peut
        /// faire est de preparer un raccourci correct et d'amener l'utilisateur dessus.
        /// </summary>
        private void OnPin(object sender, EventArgs e)
        {
            if (!Taskbar.EnsureShortcut())
            {
                MessageBox.Show(FindForm(),
                    "Le raccourci n'a pas pu etre cree dans le menu Demarrer.\n\n"
                  + "Vous pouvez tout de meme epingler OpusScreen : clic droit sur "
                  + "OpusScreen.exe dans l'explorateur, puis « Epingler a la barre des taches ».",
                    "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            if (Taskbar.TryPin())
            {
                MessageBox.Show(FindForm(),
                    "OpusScreen est maintenant epingle a la barre des taches.",
                    "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            DialogResult r = MessageBox.Show(FindForm(),
                "Le raccourci OpusScreen est en place dans le menu Demarrer.\n\n"
              + "Depuis Windows 10, seul un geste de l'utilisateur peut epingler un "
              + "programme - aucune application ne peut le faire a votre place :\n\n"
              + "   1.  l'explorateur s'ouvre sur le raccourci\n"
              + "   2.  clic droit dessus, puis « Epingler a la barre des taches »\n"
              + "        (sous Windows 11, via « Afficher plus d'options »)\n\n"
              + "Ouvrir l'explorateur maintenant ?",
                "Epingler OpusScreen", MessageBoxButtons.YesNo, MessageBoxIcon.Information);

            if (r == DialogResult.Yes) Taskbar.RevealShortcut();
        }

        private void OnExport(object sender, EventArgs e)
        {
            using (SaveFileDialog dlg = new SaveFileDialog())
            {
                dlg.Filter = "Configuration OpusScreen (*.ini)|*.ini|Tous les fichiers (*.*)|*.*";
                dlg.FileName = "opusscreen-config.ini";
                if (dlg.ShowDialog(FindForm()) != DialogResult.OK) return;
                try
                {
                    File.WriteAllText(dlg.FileName, S.Export());
                    MessageBox.Show(FindForm(), "Configuration exportee.", "OpusScreen",
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                catch (Exception ex)
                {
                    MessageBox.Show(FindForm(), "Export impossible : " + ex.Message, "OpusScreen",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
        }

        private void OnImport(object sender, EventArgs e)
        {
            using (OpenFileDialog dlg = new OpenFileDialog())
            {
                dlg.Filter = "Configuration OpusScreen (*.ini)|*.ini|Tous les fichiers (*.*)|*.*";
                if (dlg.ShowDialog(FindForm()) != DialogResult.OK) return;
                try
                {
                    string text = File.ReadAllText(dlg.FileName);
                    Settings imported = Settings.FromText(text);

                    // On recopie dans l'instance vivante : toute l'application la referme.
                    CopyInto(imported, S);
                    S.Save();

                    MessageBox.Show(FindForm(),
                        "Configuration importee.\n\nLes reglages sont appliques immediatement.",
                        "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Information);

                    Form f = FindForm() as Form;
                    ControlPanel cp = f as ControlPanel;
                    if (cp != null) cp.SyncAll();
                    Commit();
                }
                catch (Exception ex)
                {
                    MessageBox.Show(FindForm(), "Import impossible : " + ex.Message, "OpusScreen",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
        }

        private static void CopyInto(Settings src, Settings dst)
        {
            dst.Current = src.Current;
            dst.ActiveModeName = src.ActiveModeName;
            dst.CustomProfiles = src.CustomProfiles;
            dst.Schedule = src.Schedule;
            dst.PresetName = src.PresetName;
            dst.Latitude = src.Latitude; dst.Longitude = src.Longitude;
            dst.BedtimeHour = src.BedtimeHour; dst.WakeHour = src.WakeHour;
            dst.FixedDayHour = src.FixedDayHour; dst.FixedNightHour = src.FixedNightHour;
            dst.TransitionMinutes = src.TransitionMinutes;
            dst.ScheduleAffectsBrightness = src.ScheduleAffectsBrightness;
            dst.DayBrightness = src.DayBrightness; dst.NightBrightness = src.NightBrightness;
            dst.AdaptiveEnabled = src.AdaptiveEnabled;
            dst.AdaptiveMin = src.AdaptiveMin; dst.AdaptiveMax = src.AdaptiveMax;
            dst.AdaptiveReactivity = src.AdaptiveReactivity; dst.AdaptiveIntervalMs = src.AdaptiveIntervalMs;
            dst.Monitors = src.Monitors; dst.LinkMonitors = src.LinkMonitors;
            dst.AppRulesEnabled = src.AppRulesEnabled; dst.AppRules = src.AppRules;
            dst.OnFullscreen = src.OnFullscreen; dst.DisableOnBattery = src.DisableOnBattery;
            dst.BreaksEnabled = src.BreaksEnabled; dst.BreakIntervalMinutes = src.BreakIntervalMinutes;
            dst.BreakDurationSeconds = src.BreakDurationSeconds; dst.BreakDim = src.BreakDim;
            dst.BreakSound = src.BreakSound;
            dst.UseHardwareBacklight = src.UseHardwareBacklight; dst.UseOverlay = src.UseOverlay;
            dst.UseColorMatrix = src.UseColorMatrix; dst.SmoothTransitions = src.SmoothTransitions;
            dst.TransitionSpeedMs = src.TransitionSpeedMs;
            dst.TrayWheelControl = src.TrayWheelControl; dst.ShowTrayPercentage = src.ShowTrayPercentage;
            dst.Hotkeys = src.Hotkeys;
        }

        private void OnUnlock(object sender, EventArgs e)
        {
            if (GammaUnlock.IsUnlocked())
            {
                MessageBox.Show(FindForm(), "La plage gamma complete est deja active sur ce systeme.",
                    "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            string msg =
                "Windows limite par defaut l'amplitude des courbes gamma qu'une application peut appliquer.\n\n"
              + "Le deblocage ecrit cette valeur dans le registre :\n\n"
              + "  HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\\n"
              + "  CurrentVersion\\ICM\\GdiIcmGammaRange = 256\n\n"
              + "Droits administrateur requis, puis fermeture de session pour prise en compte.\n\n"
              + "Continuer ?";

            if (MessageBox.Show(FindForm(), msg, "Debloquer la plage gamma",
                                MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;

            if (GammaUnlock.TryUnlock())
                MessageBox.Show(FindForm(),
                    "C'est fait. Fermez puis rouvrez votre session Windows pour que la plage complete soit active.",
                    "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Information);
            else
                MessageBox.Show(FindForm(),
                    "Echec : relancez OpusScreen en tant qu'administrateur (clic droit sur l'application).",
                    "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Warning);

            Sync();
        }

        /// <summary>
        /// Le pilote Intel fait varier la luminosite de lui-meme, en aval de tout ce que
        /// OpusScreen controle. Sans cette explication, le symptome est naturellement
        /// attribue a l'application.
        /// </summary>
        private void OnFixDpst(object sender, EventArgs e)
        {
            List<IntelDpst.Adapter> adapters = IntelDpst.FindIntelAdapters();

            if (adapters.Count == 0)
            {
                MessageBox.Show(FindForm(),
                    "Aucune carte graphique Intel detectee : ce reglage ne s'applique pas ici.",
                    "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            if (!IntelDpst.IsAnyDpstActive())
            {
                MessageBox.Show(FindForm(),
                    "L'economiseur d'energie de l'affichage Intel est deja desactive.\n\n"
                  + IntelDpst.Describe(),
                    "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            string msg = IntelDpst.Explanation + "\n\n"
                       + "Etat actuel :\n  " + IntelDpst.Describe() + "\n\n"
                       + "Ecrire le reglage dans le registre maintenant ?";

            if (MessageBox.Show(FindForm(), msg, "Luminosite automatique du pilote Intel",
                                MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;

            int n = IntelDpst.DisableDpst();
            if (n > 0)
            {
                MessageBox.Show(FindForm(),
                    "C'est fait sur " + n + " carte(s).\n\n"
                  + "Redemarrez l'ordinateur pour que le pilote en tienne compte.\n\n"
                  + "Pour annuler plus tard, ce meme bouton proposera de remettre l'etat d'origine.",
                    "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                MessageBox.Show(FindForm(),
                    "Ecriture refusee : cette cle appartient au systeme.\n\n"
                  + "Relancez OpusScreen en tant qu'administrateur, ou utilisez plutot "
                  + "l'Intel Graphics Command Center :\n\n"
                  + "  Systeme > Alimentation > Economie d'energie de l'affichage > Desactiver\n\n"
                  + "Cette seconde voie est immediate et ne demande pas de redemarrage.",
                    "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }

            Sync();
        }

        private void OnFactoryReset(object sender, EventArgs e)
        {
            if (MessageBox.Show(FindForm(),
                "Tous les reglages, modes personnalises et regles seront perdus.\n\nContinuer ?",
                "Remise a zero", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;

            CopyInto(new Settings(), S);
            S.Hotkeys = Settings.DefaultHotkeys();
            S.Save();

            ControlPanel cp = FindForm() as ControlPanel;
            if (cp != null) cp.SyncAll();
            Commit();
        }

        public override void Sync()
        {
            Loading = true;
            try
            {
                _hardware.SetCheckedSilent(S.UseHardwareBacklight);
                _overlay.SetCheckedSilent(S.UseOverlay);
                _matrix.SetCheckedSilent(S.UseColorMatrix);
                _matrix.Enabled = ColorMatrixEffect.Available;
                _smooth.SetCheckedSilent(S.SmoothTransitions);
                _speed.SetValueSilent(S.TransitionSpeedMs);
                _speed.Track.Enabled = S.SmoothTransitions;
                _startup.SetCheckedSilent(S.StartWithWindows);
                _startMin.SetCheckedSilent(S.StartMinimized);
                _trayPercent.SetCheckedSilent(S.ShowTrayPercentage);
                _darkConfirm.SetCheckedSilent(!S.SkipDarkConfirm);
                _conflicts.SetCheckedSilent(!S.IgnoreConflicts);

                List<string> lines = new List<string>();
                lines.Add("Ecrans detectes            : " + Display.Monitors.Count);
                foreach (MonitorInfo m in Display.Monitors)
                    lines.Add("  " + m.FriendlyName + "  " + m.Bounds.Width + "x" + m.Bounds.Height
                            + "  gamma=" + (GammaEngine.SupportsGamma(m) ? "oui" : "non"));
                lines.Add("Retroeclairage physique    : " + Display.HardwareStatus);
                lines.Add("Plage gamma complete       : " + (GammaUnlock.IsUnlocked() ? "debloquee" : "bridee par Windows"));
                lines.Add("Rampes rabotees            : " + (Display.GammaClamped ? "oui" : "non"));
                lines.Add("Matrice plein ecran        : " + (ColorMatrixEffect.Available
                    ? (ColorMatrixEffect.IsActive ? "active" : "disponible") : "indisponible"));
                lines.Add("Contraste eleve de Windows : " + (Theme.HighContrast ? "actif" : "inactif"));
                lines.Add("Economiseur pilote Intel   : " + IntelDpst.Describe());
                lines.Add("Etat courant               : " + Display.DescribeCurrentPlan());
                _diag.Text = string.Join("\n", lines.ToArray());

                bool dpst = IntelDpst.IsAnyDpstActive() || IntelDpst.IsLaceActive();
                _dpstButton.Visible = IntelDpst.FindIntelAdapters().Count > 0;
                _dpstButton.ForeColor = dpst ? Theme.Boost : Theme.Fg;
                _dpstNote.Text = dpst
                    ? "Attention : le pilote Intel ajuste la luminosite selon le contenu affiche. "
                    + "L'ecran semble alors « respirer » et aucun reglage ne tient - OpusScreen n'y "
                    + "peut rien, cela se passe apres la table de couleurs."
                    : "L'economiseur d'energie de l'affichage Intel est desactive : rien ne vient "
                    + "perturber les reglages.";
            }
            finally { Loading = false; }
        }
    }
}
