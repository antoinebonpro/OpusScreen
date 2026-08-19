using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Tout ce qui sert a voir, plutot qu'a etre confortable.
    ///
    /// La separation avec la page Couleur n'est pas cosmetique. Regler une saturation
    /// est un gout ; regler une correction de daltonisme est un besoin, et cela demande
    /// des choses que la page Couleur n'offrait pas : dire quelle deficience, a quel
    /// degre, et - surtout - VERIFIER que le reglage separe bien les couleurs que l'on
    /// confond. Un curseur sans verification n'aide personne : sans point de comparaison,
    /// il est impossible de savoir si l'on vient d'ameliorer ou d'aggraver la situation.
    /// </summary>
    public class PageVision : SettingsPage
    {
        private ComboRow _type, _mode;
        private SliderRow _severity, _strength;
        private Label _clinical, _confusions;
        private ConfusionBoard _board;

        private ToggleRow _reader, _beaconOn, _magOn;
        private SliderRow _zoom, _beaconSize, _beaconOpacity;
        private DarkButton _beaconColor, _copyColor;
        private Label _magNote;

        /// <summary>Fournis par TrayApp : la page decide, l'application execute.</summary>
        public Action AidsChanged;
        public Func<string> CopyColorUnderCursor;

        public override string Title { get { return "Vision"; } }
        public override string Subtitle { get { return "Daltonisme, basse vision et reperage"; } }

        private static readonly ColorFilter[] Types = {
            ColorFilter.None, ColorFilter.Protanopia, ColorFilter.Deuteranopia, ColorFilter.Tritanopia
        };

        public PageVision(Settings s, DisplayController d, Action push) : base(s, d, push)
        {
            BuildColorVision();
            BuildComparator();
            BuildColorIdentifier();
            BuildLowVision();
            BuildReadingTints();
            BuildWindowsLinks();
        }

        // ------------------------------------------------------------------ daltonisme

        private void BuildColorVision()
        {
            Section("Vision des couleurs");

            List<string> names = new List<string>();
            foreach (ColorFilter f in Types) names.Add(Vision.PlainName(f));
            _type = new ComboRow("Ce que je distingue mal", names);
            _type.Changed += delegate
            {
                if (Loading) return;
                ColorFilter chosen = Types[Math.Max(0, _type.SelectedIndex)];

                // Passer d'un filtre esthetique a une correction de vision, ou
                // l'inverse, ne doit pas effacer l'autre : seuls les filtres de vision
                // sont pilotes ici.
                if (chosen == ColorFilter.None && ColorMatrixEffect.IsVisionFilter(S.Current.Filter))
                    S.Current.Filter = ColorFilter.None;
                else if (chosen != ColorFilter.None)
                    S.Current.Filter = chosen;

                UpdateTexts();
                UpdateStates();
                Commit();
            };
            Add(_type, Theme.SpaceSm);

            _clinical = UiKit.Caption("");
            _clinical.Height = 32;
            Add(_clinical, Theme.SpaceXs);

            _confusions = UiKit.Caption("");
            _confusions.Height = 48;
            Add(_confusions, Theme.SpaceXs);

            _severity = new SliderRow("Gravite", 0, 100, "%");
            _severity.MarkAt(100, double.NaN);
            _severity.Changed += delegate
            {
                S.Current.VisionSeverity = _severity.Value;
                UpdateTexts();
                Live();
            };
            _severity.Committed += delegate { Commit(); };
            Add(_severity, Theme.SpaceSm);

            Note("La dichromatie - un type de cone totalement absent - est le cas rare. "
               + "Le cas frequent est l'anomalie : le cone existe mais reagit a cote, et la "
               + "confusion n'est que partielle. Une correction calibree sur la dichromatie "
               + "sur-corrige alors, et l'ecran devient criard sans etre plus lisible. "
               + "Descendez la gravite jusqu'a ce que les paires ci-dessous se separent tout "
               + "juste : c'est le reglage juste.");

            _strength = new SliderRow("Intensite de la correction", 0, 150, "%");
            _strength.MarkAt(100, 120);
            _strength.Changed += delegate
            {
                S.Current.FilterStrength = _strength.Value;
                UpdateTexts();
                Live();
            };
            _strength.Committed += delegate { Commit(); };
            Add(_strength, Theme.SpaceSm);

            _mode = new ComboRow("Usage", new string[] {
                "Corriger : ecarter les couleurs que je confonds",
                "Simuler : montrer ce que percoit cette vision"
            });
            _mode.Changed += delegate
            {
                if (Loading) return;
                S.Current.Mode = _mode.SelectedIndex == 1 ? FilterMode.Simulation : FilterMode.Correction;
                UpdateTexts();
                UpdateStates();
                Commit();
            };
            Add(_mode, Theme.SpaceSm);

            Note("Le mode simulation ne sert pas la personne daltonienne : il sert a qui "
               + "concoit une interface, un graphique ou un support de cours et veut verifier "
               + "qu'il reste lisible. Le raccourci Ctrl + Alt + D bascule la correction sans "
               + "ouvrir cette fenetre.");
        }

        // ------------------------------------------------------------------ comparateur

        private void BuildComparator()
        {
            Section("Verification");

            _board = new ConfusionBoard(S);
            _board.HeightChanged += delegate { Relayout(); };
            Add(_board, Theme.SpaceSm);

            Note("A gauche, deux couleurs telles que vous les percevez aujourd'hui. A droite, "
               + "les memes une fois la correction appliquee, puis percues par cette meme vision. "
               + "L'ecart est chiffre en Delta E : en dessous de 2,3 l'oeil humain ne distingue "
               + "plus rien, au-dela il distingue. Le reglage est bon quand le nombre de droite "
               + "est nettement plus grand que celui de gauche.");
        }

        // ------------------------------------------------------------------ identificateur

        private void BuildColorIdentifier()
        {
            Section("Identifier une couleur");

            _reader = new ToggleRow("Etiquette qui suit le pointeur",
                "Nomme en continu la couleur survolee, avec sa valeur exacte.");
            _reader.Changed += delegate
            {
                S.ColorReaderEnabled = _reader.Checked;
                Aids();
                Commit();
            };
            Add(_reader, Theme.SpaceSm);

            _copyColor = new DarkButton();
            _copyColor.Text = "Copier la couleur sous le pointeur";
            _copyColor.Height = Theme.MinTarget;
            _copyColor.Click += delegate
            {
                if (CopyColorUnderCursor == null) return;
                string what = CopyColorUnderCursor();
                _copyColor.Text = what.Length > 0 ? "Copie : " + what : "Copier la couleur sous le pointeur";
            };
            Add(_copyColor, Theme.SpaceSm);

            Note("La couleur annoncee est celle que l'application a reellement dessinee, "
               + "avant la table de couleurs de la carte graphique et avant les filtres : "
               + "les reglages en cours ne faussent donc jamais la reponse. "
               + "Ctrl + Alt + C affiche l'etiquette, Ctrl + Alt + Maj + C copie la valeur.");
        }

        // ------------------------------------------------------------------ basse vision

        private void BuildLowVision()
        {
            Section("Basse vision");

            _magOn = new ToggleRow("Loupe plein ecran",
                "Agrandit tout le bureau et suit le pointeur. Se cumule avec les filtres de couleur.");
            _magOn.Changed += delegate
            {
                S.MagnifierEnabled = _magOn.Checked;
                Aids();
                UpdateMagNote();
                UpdateStates();
                Commit();
            };
            Add(_magOn, Theme.SpaceSm);

            _zoom = new SliderRow("Agrandissement", ScreenMagnifier.MinZoom, ScreenMagnifier.MaxZoom, "x");
            _zoom.Format = "0.0";
            _zoom.MarkAt(2, double.NaN);
            _zoom.Changed += delegate { S.MagnifierZoom = _zoom.Value; Aids(); };
            _zoom.Committed += delegate { Commit(); };
            Add(_zoom, Theme.SpaceSm);

            _magNote = UiKit.Caption("");
            _magNote.Height = 32;
            Add(_magNote, Theme.SpaceXs);

            _beaconOn = new ToggleRow("Anneau autour du pointeur",
                "Un cercle de couleur franche entoure le curseur, sans rien masquer au centre.");
            _beaconOn.Changed += delegate
            {
                S.BeaconEnabled = _beaconOn.Checked;
                Aids();
                UpdateStates();
                Commit();
            };
            Add(_beaconOn, Theme.SpaceSm);

            _beaconSize = new SliderRow("Taille de l'anneau", CursorBeacon.MinSize, CursorBeacon.MaxSize, "px");
            _beaconSize.Changed += delegate { S.BeaconSize = (int)_beaconSize.Value; Aids(); };
            _beaconSize.Committed += delegate { Commit(); };
            Add(_beaconSize, Theme.SpaceSm);

            _beaconOpacity = new SliderRow("Opacite de l'anneau", 10, 100, "%");
            _beaconOpacity.Changed += delegate { S.BeaconOpacity = (int)_beaconOpacity.Value; Aids(); };
            _beaconOpacity.Committed += delegate { Commit(); };
            Add(_beaconOpacity, Theme.SpaceSm);

            _beaconColor = new DarkButton();
            _beaconColor.Text = "Couleur de l'anneau...";
            _beaconColor.Height = Theme.MinTarget;
            _beaconColor.Click += OnPickBeaconColor;
            Add(_beaconColor, Theme.SpaceSm);

            Note("Perdre le pointeur de vue est le premier obstacle rapporte en basse vision, "
               + "et un curseur simplement agrandi reste de la meme couleur que ce qu'il survole. "
               + "L'anneau, lui, se detache de n'importe quel fond. Il ne recoit aucun clic et "
               + "n'apparait ni dans les captures d'ecran ni dans les partages.");
        }

        private void OnPickBeaconColor(object sender, EventArgs e)
        {
            using (ColorDialog dlg = new ColorDialog())
            {
                dlg.Color = S.BeaconColor;
                dlg.FullOpen = true;
                dlg.AnyColor = true;
                if (dlg.ShowDialog(FindForm()) != DialogResult.OK) return;
                S.BeaconColor = dlg.Color;
                UpdateBeaconButton();
                Aids();
                Commit();
            }
        }

        private void UpdateBeaconButton()
        {
            Color c = S.BeaconColor;
            _beaconColor.BackColor = c;
            double lum = 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B;
            _beaconColor.ForeColor = lum > 140 ? Color.Black : Color.White;
            _beaconColor.Text = string.Format("Couleur de l'anneau : {0},{1},{2}", c.R, c.G, c.B);
        }

        private void UpdateMagNote()
        {
            if (!ScreenMagnifier.Available)
                _magNote.Text = "L'agrandissement plein ecran est refuse par ce systeme. "
                              + "Le bouton ci-dessous ouvre la loupe de Windows a la place.";
            else if (S.MagnifierEnabled)
                _magNote.Text = "La loupe est active. Ctrl + Alt + Z l'arrete, "
                              + "Ctrl + Alt + Maj + R aussi, en meme temps que tout le reste.";
            else
                _magNote.Text = "Ctrl + Alt + Z active et arrete la loupe sans ouvrir cette fenetre.";
        }

        // ------------------------------------------------------------------ teintes de lecture

        private class Tint
        {
            public readonly string Name;
            public readonly double R, G, B;
            public Tint(string n, double r, double g, double b) { Name = n; R = r; G = g; B = b; }
        }

        /// <summary>
        /// Teintes douces appliquees par la BALANCE DES CANAUX, et non par le voile.
        ///
        /// Le voile ne sert que sous 35 % de luminosite : une teinte posee par lui
        /// disparaitrait des que l'ecran remonte a un niveau de lecture normal. La
        /// balance, elle, agit a n'importe quelle luminosite - c'est le seul etage
        /// qui rende ces teintes utilisables pour lire.
        /// </summary>
        private static readonly Tint[] ReadingTints = {
            new Tint("Aucune", 100, 100, 100),
            new Tint("Bleue", 88, 94, 100),
            new Tint("Verte", 88, 100, 92),
            new Tint("Ambre", 100, 96, 78),
            new Tint("Saumon", 100, 90, 92),
            new Tint("Grise", 92, 92, 92)
        };

        private void BuildReadingTints()
        {
            Section("Teintes de lecture");

            TintStrip strip = new TintStrip();
            strip.Height = 56;
            foreach (Tint t in ReadingTints) strip.AddTint(t.Name, t.R, t.G, t.B);
            strip.Picked += delegate(int index)
            {
                Tint t = ReadingTints[index];
                S.Current.RedGain = t.R;
                S.Current.GreenGain = t.G;
                S.Current.BlueGain = t.B;
                Commit();
            };
            Add(strip, Theme.SpaceSm);

            Note("Une legere teinte posee sur toute la page aide certaines personnes a lire "
               + "plus longtemps sans fatigue - dyslexie, migraine visuelle, sensibilite au "
               + "contraste. La teinte efficace n'est pas la meme d'une personne a l'autre et "
               + "ne se devine pas : elle se choisit a l'essai, sur un texte reel. "
               + "Le reglage fin reste dans la page Couleur.");
        }

        // ------------------------------------------------------------------ Windows

        private void BuildWindowsLinks()
        {
            Section("Accessibilite de Windows");

            AddLink("Taille du texte et mise a l'echelle...", "ms-settings:easeofaccess-display");
            AddLink("Pointeur de souris et curseur...", "ms-settings:easeofaccess-cursorandpointer");
            AddLink("Contraste eleve...", "ms-settings:easeofaccess-highcontrast");

            Note("OpusScreen agit sur la lumiere et la couleur ; la taille des elements, le "
               + "curseur et le narrateur restent du ressort de Windows, qui les applique a "
               + "toutes les applications a la fois. Les reproduire ici les aurait limites a "
               + "cette seule fenetre.");
        }

        private void AddLink(string label, string uri)
        {
            DarkButton b = new DarkButton();
            b.Text = label;
            b.Height = Theme.MinTarget;
            b.Click += delegate
            {
                try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); }
                catch { }
            };
            Add(b, Theme.SpaceXs);
        }

        // ------------------------------------------------------------------ etat

        private void Aids()
        {
            if (Loading) return;
            if (AidsChanged != null) AidsChanged();
        }

        private void Live()
        {
            if (_board != null) _board.Rebuild();
            CommitNoSave();
        }

        private void UpdateTexts()
        {
            ColorFilter f = ColorMatrixEffect.IsVisionFilter(S.Current.Filter) ? S.Current.Filter : ColorFilter.None;

            _clinical.Text = Vision.ClinicalName(f);
            _confusions.Text = Vision.Confusions(f);
            _severity.Hint = Vision.SeverityWord(S.Current.VisionSeverity);

            _strength.Hint = S.Current.FilterStrength > 115 ? "couleurs poussees, verifiez le confort"
                           : (S.Current.FilterStrength < 40 ? "correction discrete" : "");

            if (_board != null) _board.Rebuild();
        }

        private void UpdateStates()
        {
            bool vision = ColorMatrixEffect.IsVisionFilter(S.Current.Filter);
            bool matrixReady = S.UseColorMatrix && ColorMatrixEffect.Available;

            _type.Box.Enabled = matrixReady;
            _severity.Track.Enabled = vision && matrixReady;
            _mode.Box.Enabled = vision && matrixReady;
            _strength.Track.Enabled = vision && matrixReady && S.Current.Mode == FilterMode.Correction;

            _zoom.Track.Enabled = S.MagnifierEnabled;
            _beaconSize.Track.Enabled = S.BeaconEnabled;
            _beaconOpacity.Track.Enabled = S.BeaconEnabled;
            _beaconColor.Enabled = S.BeaconEnabled;
        }

        public override void Sync()
        {
            Loading = true;
            try
            {
                ColorFilter f = ColorMatrixEffect.IsVisionFilter(S.Current.Filter)
                              ? S.Current.Filter : ColorFilter.None;
                int idx = Array.IndexOf(Types, f);
                _type.SelectedIndex = idx >= 0 ? idx : 0;

                _severity.SetValueSilent(S.Current.VisionSeverity);
                _strength.SetValueSilent(S.Current.FilterStrength);
                _mode.SelectedIndex = S.Current.Mode == FilterMode.Simulation ? 1 : 0;

                _reader.SetCheckedSilent(S.ColorReaderEnabled);
                _magOn.SetCheckedSilent(S.MagnifierEnabled);
                _zoom.SetValueSilent(S.MagnifierZoom);
                _beaconOn.SetCheckedSilent(S.BeaconEnabled);
                _beaconSize.SetValueSilent(S.BeaconSize);
                _beaconOpacity.SetValueSilent(S.BeaconOpacity);

                UpdateBeaconButton();
                UpdateMagNote();
                UpdateTexts();
                UpdateStates();
            }
            finally { Loading = false; }
        }
    }

    /// <summary>
    /// Le tableau qui repond a la seule question qui compte : est-ce que je vois
    /// maintenant une difference la ou je n'en voyais pas ?
    ///
    /// Chaque ligne montre une paire de couleurs reputee confondue par la deficience
    /// choisie, d'abord telle qu'elle est percue aujourd'hui, puis telle qu'elle le
    /// serait apres correction. Les deux colonnes passent par la MEME simulation : ce
    /// qui est compare, c'est bien ce que verra la personne, pas ce que verrait
    /// quelqu'un d'autre.
    /// </summary>
    public class ConfusionBoard : Control
    {
        private readonly Settings _s;
        private const int RowH = 34;
        private const int SwatchW = 46;
        private const int SwatchH = 24;

        private List<Vision.Pair> _pairs = new List<Vision.Pair>();

        /// <summary>Emis quand la hauteur a change : la page doit alors se replier.</summary>
        public event EventHandler HeightChanged;

        public ConfusionBoard(Settings s)
        {
            _s = s;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                   | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Sunken;
            AccessibleRole = AccessibleRole.Graphic;
            AccessibleName = "Comparateur de couleurs confondues";
            Rebuild();
        }

        /// <summary>
        /// Recalcule les paires et la hauteur necessaire.
        ///
        /// Le nombre de lignes n'est pas fixe : plus la gravite est faible, moins il
        /// existe de couleurs reellement confondues, et une ligne ou les deux pastilles
        /// tombent sur la meme valeur n'apprend rien. Une hauteur figee laisserait un
        /// grand vide sous le tableau dans ces cas-la.
        /// </summary>
        public void Rebuild()
        {
            ColorFilter f = _s.Current.Filter;
            bool vision = ColorMatrixEffect.IsVisionFilter(f);

            // Sans correction choisie, les paires sont construites a pleine gravite :
            // elles restent alors des couleurs franchement differentes, et la ligne
            // montre bien ce qu'une deficience effacerait. Les batir sur une gravite
            // qui ne s'applique a rien ne donnerait que des nuances indiscernables.
            _pairs = Vision.ConfusionPairs(vision ? f : ColorFilter.None,
                                           vision ? _s.Current.VisionSeverity : 100);

            int wanted = 22 + RowH * Math.Max(1, _pairs.Count) + 10;
            if (wanted != Height)
            {
                Height = wanted;
                if (HeightChanged != null) HeightChanged(this, EventArgs.Empty);
            }
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(BackColor);

            ColorFilter f = _s.Current.Filter;
            bool vision = ColorMatrixEffect.IsVisionFilter(f);

            float[] sim = ColorMatrixEffect.BuildMatrix(100, vision ? f : ColorFilter.None,
                                                        _s.Current.VisionSeverity, 100, FilterMode.Simulation);
            float[] correction = _s.Current.BuildMatrix();

            int left = 10;
            int colA = Math.Max(150, Width / 2 - 90);
            int colB = Math.Max(colA + 150, Width - 200);

            using (Font h = Theme.Small)
            {
                TextRenderer.DrawText(g, "Couleurs confondues", h, new Rectangle(left, 4, colA - left, 16),
                    Theme.Dim, TextFormatFlags.Left);
                TextRenderer.DrawText(g, "Aujourd'hui", h, new Rectangle(colA, 4, colB - colA, 16),
                    Theme.Dim, TextFormatFlags.Left);
                TextRenderer.DrawText(g, vision ? "Avec la correction" : "Sans correction active", h,
                    new Rectangle(colB, 4, Width - colB - 8, 16), Theme.Dim, TextFormatFlags.Left);
            }

            int y = 24;

            foreach (Vision.Pair p in _pairs)
            {
                Color beforeA = ColorMatrixEffect.Transform(sim, p.A);
                Color beforeB = ColorMatrixEffect.Transform(sim, p.B);
                Color afterA = ColorMatrixEffect.Transform(sim, ColorMatrixEffect.Transform(correction, p.A));
                Color afterB = ColorMatrixEffect.Transform(sim, ColorMatrixEffect.Transform(correction, p.B));

                using (Font body = Theme.Small)
                    TextRenderer.DrawText(g, p.Label, body, new Rectangle(left, y + 4, colA - left - 8, 18),
                        Theme.Fg, TextFormatFlags.Left | TextFormatFlags.EndEllipsis);

                DrawPair(g, colA, y, beforeA, beforeB);
                DrawPair(g, colB, y, afterA, afterB);

                y += RowH;
            }
        }

        private void DrawPair(Graphics g, int x, int y, Color a, Color b)
        {
            using (SolidBrush ba = new SolidBrush(a)) g.FillRectangle(ba, x, y, SwatchW, SwatchH);
            using (SolidBrush bb = new SolidBrush(b)) g.FillRectangle(bb, x + SwatchW, y, SwatchW, SwatchH);
            using (Pen pen = new Pen(Theme.Border))
                g.DrawRectangle(pen, x, y, SwatchW * 2, SwatchH);

            // Le trait de separation rappelle qu'il s'agit bien de DEUX couleurs :
            // quand elles sont confondues, rien d'autre ne le montrerait.
            using (Pen split = new Pen(Theme.Sunken))
                g.DrawLine(split, x + SwatchW, y + 1, x + SwatchW, y + SwatchH - 1);

            double de = Vision.DeltaE(a, b);
            bool distinct = de >= Vision.JustNoticeable;
            string text = string.Format("{0:0.0}  {1}", de, distinct ? "distinctes" : "identiques");

            using (Font f = Theme.Small)
                TextRenderer.DrawText(g, text, f,
                    new Rectangle(x + SwatchW * 2 + 8, y + 4, 130, 18),
                    distinct ? Theme.Good : Theme.Danger, TextFormatFlags.Left);
        }
    }

    /// <summary>Bande de pastilles : chaque teinte est montree telle qu'elle rendra.</summary>
    public class TintStrip : Control
    {
        private class Item
        {
            public string Name;
            public double R, G, B;
        }

        private readonly List<Item> _items = new List<Item>();
        private int _hover = -1;

        public event Action<int> Picked;

        public TintStrip()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                   | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Card;
            Cursor = Cursors.Hand;
            TabStop = true;
            AccessibleRole = AccessibleRole.List;
            AccessibleName = "Teintes de lecture";
        }

        public void AddTint(string name, double r, double g, double b)
        {
            Item it = new Item();
            it.Name = name; it.R = r; it.G = g; it.B = b;
            _items.Add(it);
            Invalidate();
        }

        private int CellWidth { get { return _items.Count == 0 ? Width : Width / _items.Count; } }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            int i = CellWidth > 0 ? e.X / CellWidth : -1;
            if (i != _hover) { _hover = i; Invalidate(); }
            base.OnMouseMove(e);
        }

        protected override void OnMouseLeave(EventArgs e) { _hover = -1; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnMouseClick(MouseEventArgs e)
        {
            int i = CellWidth > 0 ? e.X / CellWidth : -1;
            if (i >= 0 && i < _items.Count && Picked != null) Picked(i);
            base.OnMouseClick(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(BackColor);

            int w = CellWidth;
            for (int i = 0; i < _items.Count; i++)
            {
                Item it = _items[i];

                // La pastille montre la teinte appliquee a un blanc de page : c'est
                // sur du texte noir sur blanc qu'elle sera jugee, pas sur une pastille
                // de couleur pure.
                Color c = Color.FromArgb(
                    (int)Math.Round(255 * it.R / 100.0),
                    (int)Math.Round(255 * it.G / 100.0),
                    (int)Math.Round(255 * it.B / 100.0));

                Rectangle cell = new Rectangle(i * w + 3, 2, w - 6, 32);
                using (SolidBrush b = new SolidBrush(c)) g.FillRectangle(b, cell);
                using (Pen p = new Pen(i == _hover ? Theme.Accent : Theme.Border, i == _hover ? 2 : 1))
                    g.DrawRectangle(p, cell);

                using (Font f = Theme.Small)
                {
                    TextRenderer.DrawText(g, "Aa", f, cell, Color.FromArgb(30, 30, 30),
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                    TextRenderer.DrawText(g, it.Name, f, new Rectangle(i * w, 36, w, 16),
                        i == _hover ? Theme.Fg : Theme.Dim, TextFormatFlags.HorizontalCenter);
                }
            }
        }
    }
}
