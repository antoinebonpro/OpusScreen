using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Onglet dedie au daltonisme.
    ///
    /// La correction vivait en haut de la page Vision, melee a la loupe, a l'anneau
    /// du pointeur et aux teintes de lecture. Or c'est de loin le besoin le plus
    /// repandu de l'application - pres d'un homme sur douze - et le seul qui se regle
    /// en plusieurs etapes : dire quelle deficience, a quel degre, puis VERIFIER que
    /// les couleurs confondues se separent. Il merite son onglet, et d'etre
    /// joignable d'un clic depuis la colonne.
    ///
    /// La page commence par ce qui se fait le plus souvent : allumer ou couper la
    /// correction, et choisir en un clic la couleur mal percue. Le reglage fin et le
    /// comparateur viennent ensuite, pour qui veut aller plus loin.
    /// </summary>
    public class PageColorBlind : SettingsPage
    {
        private ToggleRow _active;
        private ComboRow _type, _mode;
        private SliderRow _severity, _strength;
        private Label _clinical, _confusions, _status;
        private ConfusionBoard _board;
        private ToggleRow _reader;
        private DarkButton _copyColor;
        private readonly List<DarkButton> _tiles = new List<DarkButton>();

        /// <summary>Derniere correction choisie : l'interrupteur la retrouve quand on le rallume.</summary>
        private ColorFilter _lastFilter = ColorFilter.Deuteranopia;

        /// <summary>Fournis par TrayApp : la page decide, l'application execute.</summary>
        public Action AidsChanged;
        public Func<string> CopyColorUnderCursor;

        public override string Title { get { return "Daltonisme"; } }
        public override string Subtitle { get { return "Corriger, verifier et identifier les couleurs"; } }

        private static readonly ColorFilter[] Types = {
            ColorFilter.None, ColorFilter.Protanopia, ColorFilter.Deuteranopia, ColorFilter.Tritanopia
        };

        private static readonly ColorFilter[] Deficiencies = {
            ColorFilter.Protanopia, ColorFilter.Deuteranopia, ColorFilter.Tritanopia
        };

        public PageColorBlind(Settings s, DisplayController d, Action push) : base(s, d, push)
        {
            BuildQuickStart();
            BuildTuning();
            BuildComparator();
            BuildColorIdentifier();
        }

        // ------------------------------------------------------------------ en un clic

        private void BuildQuickStart()
        {
            Section("Correction");

            _active = new ToggleRow("Correction des couleurs active",
                "Coupe et retablit la correction choisie. Ctrl + Alt + D fait de meme, fenetre fermee.");
            _active.Changed += delegate
            {
                if (Loading) return;
                SetFilter(_active.Checked ? _lastFilter : ColorFilter.None);
            };
            Add(_active, Theme.SpaceSm);

            _status = UiKit.Caption("");
            _status.Height = 20;
            Add(_status, Theme.SpaceXs);

            // Trois tuiles plutot qu'une liste : le choix se fait en un clic, et le nom
            // dit ce que l'on vit (« rouge mal percu ») avant le terme medical.
            Panel tiles = new Panel();
            tiles.BackColor = Color.Transparent;
            tiles.Height = Theme.MinTarget + 4;
            foreach (ColorFilter f in Deficiencies)
            {
                ColorFilter captured = f;
                DarkButton b = new DarkButton();
                b.Text = Vision.PlainName(f);
                b.Height = Theme.MinTarget;
                b.AccessibleDescription = Vision.ClinicalName(f);
                b.Click += delegate { SetFilter(captured); };
                tiles.Controls.Add(b);
                _tiles.Add(b);
            }
            tiles.Resize += delegate { LayoutTiles(tiles); };
            Add(tiles, Theme.SpaceSm);

            Note("Choisissez la couleur que vous distinguez mal. En cas de doute, le vert "
               + "(deuteranomalie) est de loin le cas le plus frequent : commencez par lui, "
               + "puis verifiez plus bas que les paires de couleurs se separent.");
        }

        private void LayoutTiles(Panel host)
        {
            int n = _tiles.Count;
            if (n == 0) return;
            int gap = Theme.SpaceSm;
            int w = Math.Max(80, (host.ClientSize.Width - gap * (n - 1)) / n);
            for (int i = 0; i < n; i++)
                _tiles[i].SetBounds(i * (w + gap), 2, w, Theme.MinTarget);
        }

        // ------------------------------------------------------------------ reglage fin

        private void BuildTuning()
        {
            Section("Reglage fin");

            List<string> names = new List<string>();
            foreach (ColorFilter f in Types) names.Add(Vision.PlainName(f));
            _type = new ComboRow("Ce que je distingue mal", names);
            _type.Changed += delegate
            {
                if (Loading) return;
                SetFilter(Types[Math.Max(0, _type.SelectedIndex)]);
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
                if (Loading) return;
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
                if (Loading) return;
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
                Sync();
                Commit();
            };
            Add(_mode, Theme.SpaceSm);

            Note("Le mode simulation ne sert pas la personne daltonienne : il sert a qui "
               + "concoit une interface, un graphique ou un support de cours et veut verifier "
               + "qu'il reste lisible.");
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
                if (Loading) return;
                S.ColorReaderEnabled = _reader.Checked;
                if (AidsChanged != null) AidsChanged();
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

        // ------------------------------------------------------------------ etat

        /// <summary>
        /// Point d'entree unique de tous les choix de filtre - interrupteur, tuiles,
        /// liste. Passer d'un filtre esthetique a une correction de vision, ou
        /// l'inverse, ne doit pas effacer l'autre : seuls les filtres de vision sont
        /// pilotes ici.
        /// </summary>
        private void SetFilter(ColorFilter chosen)
        {
            if (chosen == ColorFilter.None)
            {
                if (ColorMatrixEffect.IsVisionFilter(S.Current.Filter))
                {
                    _lastFilter = S.Current.Filter;
                    S.Current.Filter = ColorFilter.None;
                }
            }
            else
            {
                S.Current.Filter = chosen;
                _lastFilter = chosen;
            }
            Sync();
            Commit();
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

            bool matrixReady = S.UseColorMatrix && ColorMatrixEffect.Available;
            if (!matrixReady)
                _status.Text = "Indisponible : la matrice plein ecran est coupee ou refusee (voir Avance).";
            else if (f == ColorFilter.None)
                _status.Text = "Aucune correction appliquee.";
            else
                _status.Text = (S.Current.Mode == FilterMode.Simulation ? "Simulation : " : "Correction : ")
                             + Vision.PlainName(f).ToLowerInvariant()
                             + string.Format(", gravite {0:0} %.", S.Current.VisionSeverity);

            if (_board != null) _board.Rebuild();
        }

        private void UpdateStates()
        {
            ColorFilter f = S.Current.Filter;
            bool vision = ColorMatrixEffect.IsVisionFilter(f);
            bool matrixReady = S.UseColorMatrix && ColorMatrixEffect.Available;

            _active.Enabled = matrixReady;
            _type.Box.Enabled = matrixReady;
            foreach (DarkButton b in _tiles) b.Enabled = matrixReady;
            _severity.Track.Enabled = vision && matrixReady;
            _mode.Box.Enabled = vision && matrixReady;
            _strength.Track.Enabled = vision && matrixReady && S.Current.Mode == FilterMode.Correction;

            // La tuile de la correction en cours est mise en avant : on voit d'un coup
            // d'oeil ce qui est applique, sans lire la liste.
            for (int i = 0; i < _tiles.Count; i++)
            {
                bool on = vision && Deficiencies[i] == f;
                _tiles[i].BackColor = on ? Theme.AccentDim : Theme.Field;
                _tiles[i].ForeColor = Theme.Fg;
            }
        }

        public override void Sync()
        {
            Loading = true;
            try
            {
                ColorFilter f = ColorMatrixEffect.IsVisionFilter(S.Current.Filter)
                              ? S.Current.Filter : ColorFilter.None;
                if (f != ColorFilter.None) _lastFilter = f;

                _active.SetCheckedSilent(f != ColorFilter.None);
                int idx = Array.IndexOf(Types, f);
                int want = idx >= 0 ? idx : 0;
                if (_type.SelectedIndex != want) _type.SelectedIndex = want;

                _severity.SetValueSilent(S.Current.VisionSeverity);
                _strength.SetValueSilent(S.Current.FilterStrength);
                int mode = S.Current.Mode == FilterMode.Simulation ? 1 : 0;
                if (_mode.SelectedIndex != mode) _mode.SelectedIndex = mode;

                _reader.SetCheckedSilent(S.ColorReaderEnabled);

                UpdateTexts();
                UpdateStates();
            }
            finally { Loading = false; }
        }
    }
}
