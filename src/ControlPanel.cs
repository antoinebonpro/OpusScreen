using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Fenetre de reglages.
    ///
    /// Sept pages plutot qu'un long formulaire : avec une quarantaine de reglages,
    /// tout montrer d'un coup rendrait l'application inutilisable pour le geste
    /// quotidien, qui se resume a bouger un curseur. La premiere page porte ce geste ;
    /// les six autres attendent qu'on aille les chercher.
    ///
    /// Cette classe n'assemble que la coquille : chaque page connait son domaine et
    /// rien d'autre.
    /// </summary>
    public class ControlPanel : Form
    {
        private readonly Settings _s;
        private readonly DisplayController _display;
        private readonly Action _push;

        private SideNav _nav;
        private Panel _content, _header, _footer;
        private Label _title, _subtitle, _status;
        private DarkButton _pauseButton;

        private readonly List<SettingsPage> _pages = new List<SettingsPage>();

        public PageWelcome WelcomePage;
        public PageDisplay Display1;
        public PageColor ColorPage;
        public PageColorBlind ColorBlindPage;
        public PageVision VisionPage;
        public PageAuto AutoPage;
        public PageApps AppsPage;
        public PageScreens ScreensPage;
        public PageComfort ComfortPage;
        public PageHotkeys HotkeysPage;
        public PageAdvanced AdvancedPage;

        /// <summary>
        /// Rang de l'onglet Daltonisme, ouvert depuis le menu de la zone de
        /// notification.
        ///
        /// Calcule depuis la liste, et non ecrit a la main : la premiere version
        /// etait une constante, et le jour ou un onglet s'est glisse avant celui-la,
        /// le menu a ouvert la page voisine sans que rien ne le signale.
        /// </summary>
        public int ColorBlindPageIndex { get { return _pages.IndexOf(ColorBlindPage); } }

        /// <summary>Rang de la page Vision (basse vision, pointeur, lecture).</summary>
        public int VisionPageIndex { get { return _pages.IndexOf(VisionPage); } }

        /// <summary>Largeur de la colonne de navigation, referencee par la mise en page de l'en-tete.</summary>
        private static int NavWidth { get { return Theme.Px(196); } }

        /// <summary>Declenche la suspension ou la reprise depuis le bouton du pied de page.</summary>
        public Action TogglePause;

        public ControlPanel(Settings s, DisplayController display, Action push)
        {
            _s = s;
            _display = display;
            _push = push;
            BuildUi();
            SyncAll();
        }

        // ------------------------------------------------------------------ construction

        private void BuildUi()
        {
            Text = "OpusScreen";
            BackColor = Theme.Bg;
            ForeColor = Theme.Fg;
            Font = Theme.Body;
            FormBorderStyle = FormBorderStyle.Sizable;
            MaximizeBox = false;
            StartPosition = FormStartPosition.Manual;

            // La fenetre se montre dans la barre des taches, sous l'icone de
            // l'application : c'est la que Windows regroupe ce qui est epingle.
            ShowInTaskbar = true;
            AppIcon.ApplyTo(this);
            ClientSize = new Size(Theme.Px(806), Theme.Px(660));
            MinimumSize = new Size(Theme.Px(760), Theme.Px(560));
            KeyPreview = true;

            // ---------------- en-tete ----------------
            _header = new Panel();
            _header.Dock = DockStyle.Top;
            _header.Height = Theme.Px(66);
            _header.BackColor = Theme.Bg;
            Controls.Add(_header);

            _title = new Label();
            _title.Font = Theme.Title;
            _title.ForeColor = Theme.Fg;
            _title.AutoSize = false;
            _header.Controls.Add(_title);

            _subtitle = new Label();
            _subtitle.Font = Theme.Small;
            _subtitle.ForeColor = Theme.Dim;
            _subtitle.AutoSize = false;
            _header.Controls.Add(_subtitle);

            _status = new Label();
            _status.Font = Theme.Small;
            _status.ForeColor = Theme.Dim;
            _status.AutoSize = false;
            _status.TextAlign = ContentAlignment.MiddleRight;
            _header.Controls.Add(_status);

            // ---------------- pied ----------------
            _footer = new Panel();
            _footer.Dock = DockStyle.Bottom;
            _footer.Height = Theme.Px(52);
            _footer.BackColor = Theme.Bg;
            Controls.Add(_footer);

            _pauseButton = new DarkButton();
            _pauseButton.Text = "Suspendre";
            _pauseButton.SetBounds(Theme.Px(20), Theme.Px(10), Theme.Px(116), Theme.MinTarget);
            _pauseButton.Click += delegate { if (TogglePause != null) TogglePause(); };
            _footer.Controls.Add(_pauseButton);

            DarkButton reset = new DarkButton();
            reset.Text = "Tout reinitialiser";
            reset.SetBounds(Theme.Px(144), Theme.Px(10), Theme.Px(132), Theme.MinTarget);
            reset.Click += OnReset;
            _footer.Controls.Add(reset);

            Label panic = new Label();
            panic.Text = "Secours : Ctrl + Alt + Maj + R retablit un ecran normal, meme si l'application ne repond plus.";
            panic.Font = Theme.Small;
            panic.ForeColor = Theme.Faint;
            panic.AutoSize = false;
            panic.TextAlign = ContentAlignment.MiddleRight;
            panic.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            panic.SetBounds(Theme.Px(286), Theme.Px(10), ClientSize.Width - Theme.Px(306), Theme.MinTarget);
            _footer.Controls.Add(panic);

            // ---------------- navigation ----------------
            // Le nom du produit vit dans la colonne de navigation, pas dans l'en-tete :
            // l'en-tete est ancre a droite du menu et son espace revient au titre de page.
            _nav = new SideNav();
            _nav.Dock = DockStyle.Left;

            // 196 plutot que 180 : le logo prend la place a gauche du nom, et
            // « OpusScreen » ressortait tronque en « OpusScree ».
            _nav.Width = NavWidth;
            Controls.Add(_nav);

            // Le logo tient a gauche du nom plutot qu'au-dessus : la colonne est
            // etroite, et chaque ligne prise en hauteur est une ligne de moins pour
            // les onglets.
            Image logo = AppIcon.Logo;
            int textLeft = Theme.Px(20);
            if (logo != null)
            {
                PictureBox mark = new PictureBox();
                mark.Image = logo;
                mark.SizeMode = PictureBoxSizeMode.Zoom;
                mark.BackColor = Color.Transparent;
                mark.SetBounds(Theme.Px(14), Theme.Px(15), Theme.Px(38), Theme.Px(32));
                _nav.Controls.Add(mark);
                textLeft = Theme.Px(58);
            }

            Label brand = new Label();
            brand.Text = "OpusScreen";
            brand.Font = Theme.Title;
            brand.ForeColor = Theme.Accent;
            brand.AutoSize = false;
            brand.BackColor = Color.Transparent;
            // Hauteur mesuree sur la police : ecrite en dur a 24 pixels, la marque
            // sortait deja tronquee en « OpusScree » sur un ecran a 150 %.
            int hMarque = TextRenderer.MeasureText("Ag", Theme.Title).Height + Theme.Px(2);
            brand.SetBounds(textLeft, Theme.Px(14), NavWidth - textLeft - Theme.Px(6), hMarque);
            _nav.Controls.Add(brand);

            Label version = new Label();
            // Lue dans l'assemblage plutot qu'ecrite ici : la version affichee avait
            // deja pris du retard sur la version reelle.
            Version v = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
            version.Text = "version " + v.Major + "." + v.Minor;
            version.Font = Theme.Small;
            version.ForeColor = Theme.Faint;
            version.AutoSize = false;
            version.BackColor = Color.Transparent;
            int hVersion = TextRenderer.MeasureText("Ag", Theme.Small).Height + Theme.Px(2);
            version.SetBounds(textLeft + 1, Theme.Px(14) + hMarque, NavWidth - textLeft - Theme.Px(6), hVersion);

            // Les onglets commencent sous la marque, quelle que soit sa taille.
            _nav.TopOffset = Theme.Px(14) + hMarque + hVersion + Theme.SpaceSm;
            _nav.Controls.Add(version);

            // ---------------- contenu ----------------
            _content = new Panel();
            _content.Dock = DockStyle.Fill;
            _content.BackColor = Theme.Card;
            Controls.Add(_content);

            _content.BringToFront();

            // ---------------- pages ----------------
            WelcomePage = new PageWelcome(_s, _display, _push);
            Display1 = new PageDisplay(_s, _display, _push);
            ColorPage = new PageColor(_s, _display, _push);
            ColorBlindPage = new PageColorBlind(_s, _display, _push);
            VisionPage = new PageVision(_s, _display, _push);
            AutoPage = new PageAuto(_s, _display, _push);
            AppsPage = new PageApps(_s, _display, _push);
            ScreensPage = new PageScreens(_s, _display, _push);
            ComfortPage = new PageComfort(_s, _display, _push);
            HotkeysPage = new PageHotkeys(_s, _display, _push);
            AdvancedPage = new PageAdvanced(_s, _display, _push);

            AddPage(WelcomePage, "Decouvrir", "compass");
            AddPage(Display1, "Ecran", "sun");
            AddPage(ColorPage, "Couleur", "palette");
            AddPage(ColorBlindPage, "Daltonisme", "colorblind");
            AddPage(VisionPage, "Vision", "vision");
            AddPage(AutoPage, "Automatisme", "clock");
            AddPage(AppsPage, "Applications", "apps");
            AddPage(ScreensPage, "Ecrans", "screens");
            AddPage(ComfortPage, "Confort", "eye");
            AddPage(HotkeysPage, "Raccourcis", "keyboard");
            AddPage(AdvancedPage, "Avance", "sliders");

            _nav.SelectionChanged += ShowPage;
            LayoutHeader();

            // Le tout premier lancement s'ouvre sur la page qui explique ou
            // l'application se range - sans quoi elle se referme dans la zone de
            // notification et parait avoir disparu. Les lancements suivants ouvrent
            // l'ecran de tous les jours : une explication deja lue qui revient
            // chaque fois devient une porte a pousser.
            ShowPage(_s.IsFirstRun ? 0 : 1);
        }

        private void AddPage(SettingsPage page, string label, string glyph)
        {
            page.Dock = DockStyle.Fill;
            page.Visible = false;
            _content.Controls.Add(page);
            _pages.Add(page);
            _nav.AddTab(label, glyph);
        }

        private void ShowPage(int index)
        {
            if (index < 0 || index >= _pages.Count) return;
            for (int i = 0; i < _pages.Count; i++) _pages[i].Visible = (i == index);
            _pages[index].SyncAndLayout();
            _title.Text = _pages[index].Title;
            _subtitle.Text = _pages[index].Subtitle;
            UpdateStatus();
        }

        // ------------------------------------------------------------------ synchronisation

        /// <summary>Recharge toutes les pages depuis les reglages.</summary>
        public void SyncAll()
        {
            foreach (SettingsPage p in _pages)
            {
                try { p.SyncAndLayout(); } catch { }
            }
            UpdateStatus();
        }

        /// <summary>Recharge seulement la page visible : appelee a chaque changement de valeur.</summary>
        public void RefreshReadouts()
        {
            foreach (SettingsPage p in _pages)
            {
                if (!p.Visible) continue;
                try { p.SyncAndLayout(); } catch { }
            }
            UpdateStatus();
        }

        private void UpdateStatus()
        {
            List<string> bits = new List<string>();

            if (_display.Suspended)
            {
                bits.Add("SUSPENDU - " + _display.SuspendReason);
                _status.ForeColor = Theme.Boost;
            }
            else
            {
                bits.Add(string.Format("{0} % - {1} K",
                    (int)Math.Round(_s.Current.Brightness), _s.Current.Kelvin));
                _status.ForeColor = Theme.Dim;
            }

            // Signale en premier ce qui empeche les reglages de tenir : c'est la cause
            // la plus frequente d'un « ca ne marche pas » attribue a tort a l'application.
            if (IntelDpst.IsAnyDpstActive())
            {
                bits.Add("pilote Intel : luminosite auto active - voir Avance");
                _status.ForeColor = Theme.Boost;
            }
            else if (_display.GammaClamped) bits.Add("Windows rabote les rampes - voir Avance");
            else if (_display.Clipping) bits.Add("hautes lumieres ecretees au-dela de 135 %");
            if (_display.ColorMatrixFailed) bits.Add("matrice plein ecran indisponible");

            _status.Text = string.Join("\n", bits.ToArray());

            _pauseButton.Text = _display.Suspended ? "Reprendre" : "Suspendre";
        }

        // ------------------------------------------------------------------ evenements

        private void OnReset(object sender, EventArgs e)
        {
            _s.Current = new Profile();
            _s.ActiveModeName = "Normal";
            _s.Schedule = ScheduleMode.Manual;
            _s.AdaptiveEnabled = false;
            foreach (MonitorSettings ms in _s.Monitors)
            {
                ms.Blackout = false;
                ms.Enabled = true;
                ms.BrightnessOffset = 0;
            }
            _display.RestoreAll();
            if (_push != null) _push();
            _s.Save();
            SyncAll();
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            DarkTitleBar.Apply(Handle);
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            LayoutHeader();
        }

        /// <summary>
        /// Le badge d'etat est opaque : il faut donc que titre et sous-titre s'arretent
        /// avant lui, sinon leur fin disparait sous son fond.
        /// </summary>
        private void LayoutHeader()
        {
            if (_header == null || _status == null) return;

            // Les hauteurs viennent des POLICES, et non de nombres ecrits ici :
            // le titre etait fixe a 24 pixels, et le sous-titre commencait a 36.
            // Sur un ecran a 200 %, le titre en demandait 40 : il etait tranche
            // en son milieu et le sous-titre lui passait dessus.
            int statusW = Theme.Px(290);
            int left = Theme.Px(24);
            int hTitre = TextRenderer.MeasureText("Ag", Theme.Title).Height + Theme.Px(2);
            int hSous = TextRenderer.MeasureText("Ag", Theme.Small).Height + Theme.Px(2);
            int hEtat = TextRenderer.MeasureText("Ag", Theme.Small).Height * 2 + Theme.Px(4);

            int haut = Theme.Px(12);
            _header.Height = haut * 2 + hTitre + hSous;

            int statusX = Math.Max(left + Theme.Px(160), _header.Width - statusW - Theme.Px(20));
            _status.SetBounds(statusX, haut, statusW, hEtat);

            int textW = Math.Max(Theme.Px(140), statusX - left - Theme.SpaceLg);
            _title.SetBounds(left, haut, textW, hTitre);
            _subtitle.SetBounds(left, haut + hTitre, textW, hSous);
        }

        /// <summary>Ouvre directement une page donnee (0 = Ecran).</summary>
        public void SelectPage(int index)
        {
            if (_nav != null) _nav.Select(index);
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            // Ctrl+1..9 puis Ctrl+0 : acces direct aux pages, sans quitter le clavier.
            // Le zero sert la dixieme, comme sur la rangee de chiffres du clavier.
            if ((keyData & Keys.Control) == Keys.Control)
            {
                Keys k = keyData & Keys.KeyCode;
                if (k >= Keys.D1 && k <= Keys.D9)
                {
                    _nav.Select(k - Keys.D1);
                    return true;
                }
                if (k == Keys.D0)
                {
                    _nav.Select(9);
                    return true;
                }
            }
            if (keyData == Keys.Escape) { Hide(); return true; }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            // La croix range la fenetre ; on ne quitte que par le menu de la zone de notification.
            if (e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                Hide();
            }
            base.OnFormClosing(e);
        }
    }
}
