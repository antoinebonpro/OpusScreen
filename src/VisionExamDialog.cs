using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// La fenetre du test guide.
    ///
    /// Elle ne calcule rien : tout ce qui decide vit dans VisionExam. Ici on montre,
    /// on recolte des reponses, et on rend le resultat. Cette separation n'est pas de
    /// la coquetterie - c'est ce qui permet de verifier la mesure par le calcul, sans
    /// cliquer, et de faire passer le test a un observateur simule dont on connait la
    /// vision.
    ///
    /// Pendant toute la duree du test, les effets de l'application sont SUSPENDUS :
    /// mesurer une vision a travers une correction deja posee reviendrait a mesurer la
    /// correction. Ils sont retablis a la fermeture, quelle qu'en soit la facon -
    /// bouton, croix, Echap, ou fin du test.
    /// </summary>
    public class VisionExamDialog : Form
    {
        public enum Step { Intro, Plates, Pairs, Result }

        private readonly Settings _s;
        private readonly DisplayController _display;
        private readonly bool _wasSuspended;

        private readonly List<VisionPlate> _plates;
        private readonly List<bool> _read = new List<bool>();
        private int _plateIndex;

        private VisionExam.Staircase _stair;
        private Color[] _pair = new Color[2];

        // Mesure des trois axes, quand les planches n'ont rien trouve.
        private bool _screening;
        private List<ColorFilter> _pending = new List<ColorFilter>();
        private readonly Dictionary<ColorFilter, double> _measured = new Dictionary<ColorFilter, double>();

        private Step _step = Step.Intro;

        // Resultat
        public ColorFilter FoundFilter = ColorFilter.None;
        public double FoundSeverity = 100;
        public int Confidence;
        public bool Applied;

        // Interface
        private Label _title, _text, _progress;
        private PlateView _plate;
        private PairView _pairView;
        private Panel _answers;
        private DarkButton _next, _quit;
        private readonly List<DarkButton> _choiceButtons = new List<DarkButton>();

        public VisionExamDialog(Settings s, DisplayController display)
            : this(s, display, Environment.TickCount) { }

        public VisionExamDialog(Settings s, DisplayController display, int seed)
        {
            _s = s;
            _display = display;
            _plates = VisionExam.Plates(seed);

            _wasSuspended = _display != null && _display.Suspended;
            if (_display != null && !_wasSuspended) _display.Suspend("test de vision en cours");

            BuildUi();
            ShowStep(Step.Intro);
        }

        public Step CurrentStep { get { return _step; } }
        public VisionPlate CurrentPlate { get { return _plateIndex < _plates.Count ? _plates[_plateIndex] : null; } }
        public VisionExam.Staircase Staircase { get { return _stair; } }

        // ------------------------------------------------------------------ construction

        private void BuildUi()
        {
            Text = "Test de vision des couleurs";
            BackColor = Theme.Card;
            ForeColor = Theme.Fg;
            Font = Theme.Body;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MinimizeBox = false;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            ClientSize = new Size(700, 620);
            KeyPreview = true;
            AppIcon.ApplyTo(this);

            _title = new Label();
            _title.Font = Theme.Title;
            _title.ForeColor = Theme.Fg;
            _title.AutoSize = false;
            _title.SetBounds(28, 22, 644, 28);
            Controls.Add(_title);

            _text = new Label();
            _text.Font = Theme.Body;
            _text.ForeColor = Theme.Dim;
            _text.AutoSize = false;
            _text.SetBounds(28, 54, 644, 110);
            Controls.Add(_text);

            _plate = new PlateView();
            _plate.SetBounds(160, 168, 380, 290);
            _plate.Visible = false;
            Controls.Add(_plate);

            _pairView = new PairView();
            _pairView.SetBounds(130, 190, 440, 230);
            _pairView.Visible = false;
            Controls.Add(_pairView);

            _answers = new Panel();
            _answers.BackColor = Color.Transparent;
            _answers.SetBounds(28, 476, 644, 60);
            Controls.Add(_answers);

            _progress = new Label();
            _progress.Font = Theme.Small;
            _progress.ForeColor = Theme.Faint;
            _progress.AutoSize = false;
            _progress.SetBounds(28, 582, 400, 20);
            Controls.Add(_progress);

            _quit = new DarkButton();
            _quit.Text = "Arreter";
            _quit.SetBounds(560, 574, 112, Theme.MinTarget);
            _quit.Click += delegate { Close(); };
            Controls.Add(_quit);

            _next = new DarkButton();
            _next.Text = "Commencer";
            _next.SetBounds(436, 574, 118, Theme.MinTarget);
            _next.Click += delegate { OnNext(); };
            Controls.Add(_next);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            DarkTitleBar.Apply(Handle);
        }

        /// <summary>
        /// Les effets reviennent quoi qu'il arrive : fin du test, croix, Echap, ou
        /// fenetre detruite sans avoir jamais ete montree. Rendre l'ecran est la
        /// seule chose que cette fenetre ne doit jamais oublier.
        /// </summary>
        private void RestoreScreen()
        {
            if (_restored) return;
            _restored = true;
            try { if (_display != null && !_wasSuspended) _display.Resume(); }
            catch { }
        }

        private bool _restored;

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            base.OnFormClosed(e);
            RestoreScreen();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) RestoreScreen();
            base.Dispose(disposing);
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData == Keys.Escape) { Close(); return true; }

            // Les chiffres 1 a 5 choisissent la reponse : un test d'accessibilite doit
            // se passer entierement au clavier.
            int index = -1;
            if (keyData >= Keys.D1 && keyData <= Keys.D5) index = keyData - Keys.D1;
            else if (keyData >= Keys.NumPad1 && keyData <= Keys.NumPad5) index = keyData - Keys.NumPad1;
            if (index >= 0 && index < _choiceButtons.Count)
            {
                _choiceButtons[index].PerformClick();
                return true;
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        // ------------------------------------------------------------------ deroulement

        private void ShowStep(Step step)
        {
            _step = step;
            _plate.Visible = step == Step.Plates;
            _pairView.Visible = step == Step.Pairs;
            ClearAnswers();

            switch (step)
            {
                case Step.Intro:
                    _title.Text = "Trouver votre reglage, en deux minutes";
                    _text.Text = "Deux series de questions.\n\n"
                               + "1. Des planches ou se cache un chiffre : vous dites lequel, ou qu'il n'y en a aucun.\n"
                               + "2. Deux couleurs cote a cote : vous dites si elles vous paraissent identiques.\n\n"
                               + "Ne devinez pas : « aucun chiffre » et « identiques » sont des reponses utiles. "
                               + "Pendant le test, la correction en cours est retiree - c'est votre oeil que l'on "
                               + "mesure, pas votre ecran deja corrige.";
                    _next.Text = "Commencer";
                    _next.Visible = true;
                    _progress.Text = "";
                    break;

                case Step.Plates:
                    _title.Text = "Quel chiffre voyez-vous ?";
                    _text.Text = "Regardez l'ensemble du disque. Si aucun chiffre ne se detache, c'est une reponse "
                               + "comme une autre - souvent la plus instructive.";
                    _next.Visible = false;
                    ShowPlate();
                    break;

                case Step.Pairs:
                    _title.Text = "Ces deux couleurs sont-elles identiques ?";
                    _text.Text = "Parfois elles le sont presque, parfois pas du tout : il n'y a pas de piege. "
                               + "Repondez d'apres ce que vous voyez, sans chercher a bien faire.";
                    _next.Visible = false;
                    ShowPair();
                    break;

                case Step.Result:
                    ShowResult();
                    break;
            }
        }

        private void ClearAnswers()
        {
            List<Control> old = new List<Control>();
            foreach (Control c in _answers.Controls) old.Add(c);
            _answers.Controls.Clear();
            foreach (Control c in old) c.Dispose();
            _choiceButtons.Clear();
        }

        private void AddAnswer(string text, int index, int count, EventHandler click)
        {
            int gap = Theme.SpaceSm;
            int w = (_answers.Width - gap * (count - 1)) / count;
            DarkButton b = new DarkButton();
            b.Text = text;
            b.Font = Theme.BodyBold;
            b.SetBounds(index * (w + gap), 0, w, 52);
            b.Click += click;
            _answers.Controls.Add(b);
            _choiceButtons.Add(b);
        }

        private void OnNext() { Begin(); }

        /// <summary>Passe de l'accueil a la premiere planche. Public : les tests s'en servent.</summary>
        public void Begin()
        {
            if (_step == Step.Intro) ShowStep(Step.Plates);
        }

        // ---------------- planches ----------------

        private void ShowPlate()
        {
            VisionPlate p = _plates[_plateIndex];
            _plate.Show(p);
            _progress.Text = string.Format("Planche {0} sur {1}", _plateIndex + 1, _plates.Count);

            int n = p.Choices.Length + 1;
            for (int i = 0; i < p.Choices.Length; i++)
            {
                int digit = p.Choices[i];
                AddAnswer(digit.ToString(), i, n, delegate { AnswerPlate(digit); });
            }
            AddAnswer("Aucun chiffre", p.Choices.Length, n, delegate { AnswerPlate(-1); });
        }

        /// <summary>Repond a la planche courante. -1 = aucun chiffre vu.</summary>
        public void AnswerPlate(int digit)
        {
            if (_step != Step.Plates) return;
            _read.Add(digit == _plates[_plateIndex].Digit);
            _plateIndex++;

            if (_plateIndex < _plates.Count) { ClearAnswers(); ShowPlate(); return; }

            FoundFilter = VisionExam.TypeFromPlates(_plates, _read, out Confidence);

            // Rouge et vert se confondent aussi entre eux : leurs axes sont voisins, et
            // une planche cachee a l'un l'est souvent presque a l'autre. Quand les
            // planches ne tranchent pas nettement, on ne tire pas a pile ou face - on
            // mesure les axes a egalite, et le plus mauvais l'emporte.
            Dictionary<ColorFilter, int> misses = VisionExam.Misses(_plates, _read);
            int top = 0, second = 0;
            foreach (KeyValuePair<ColorFilter, int> kv in misses)
            {
                if (kv.Value > top) { second = top; top = kv.Value; }
                else if (kv.Value > second) second = kv.Value;
            }

            if (FoundFilter == ColorFilter.None || top - second <= 1)
            {
                // Soit les planches n'ont rien vu - une anomalie legere les traverse,
                // puisqu'un chiffre assez efface pour la tromper le serait aussi pour
                // une vision normale - soit elles hesitent entre deux axes voisins.
                // Dans les deux cas on mesure les trois axes, et c'est le profil des
                // trois mesures qui designe la vision.
                _screening = true;
                _pending = new List<ColorFilter>(VisionExam.Axes);
                _measured.Clear();
                NextScreeningAxis();
            }
            else
            {
                _screening = false;
                _stair = new VisionExam.Staircase(FoundFilter);
            }
            ShowStep(Step.Pairs);
        }

        // ---------------- comparaisons ----------------

        private void ShowPair()
        {
            _pair = VisionExam.PairAt(_stair.Axis, _stair.Separation);

            // L'ordre change a chaque essai : sinon la meme couleur reste a gauche et
            // l'on finit par repondre d'apres la position plutot que d'apres la couleur.
            bool swapped = (_stair.Trials % 2) == 1;
            _pairView.Show(swapped ? _pair[1] : _pair[0], swapped ? _pair[0] : _pair[1]);

            _progress.Text = string.Format("Comparaison {0} - {1} %", _stair.Trials + 1,
                                           (int)Math.Round(_stair.Progress * 100));

            AddAnswer("Identiques", 0, 2, delegate { AnswerPair(false); });
            AddAnswer("Differentes", 1, 2, delegate { AnswerPair(true); });
        }

        /// <summary>Repond a la comparaison : vrai si les deux couleurs paraissent differentes.</summary>
        public void AnswerPair(bool distinguished)
        {
            if (_step != Step.Pairs || _stair == null) return;
            _stair.Answer(distinguished);

            if (!_stair.Done) { ClearAnswers(); ShowPair(); return; }

            if (!_screening)
            {
                FoundSeverity = VisionExam.SeverityFromThreshold(_stair.Axis, _stair.Threshold);
                ShowStep(Step.Result);
                return;
            }

            _measured[_stair.Axis] = _stair.Threshold;
            if (_pending.Count > 0) { NextScreeningAxis(); ClearAnswers(); ShowPair(); return; }

            FinishScreening();
        }

        /// <summary>Mesure courte de l'axe suivant, quand les planches n'ont rien trouve.</summary>
        private void NextScreeningAxis()
        {
            ColorFilter axis = _pending[0];
            _pending.RemoveAt(0);
            _stair = new VisionExam.Staircase(axis, 5, 12);
        }

        /// <summary>
        /// Conclusion de la mesure sur les trois axes : l'axe le plus mauvais, et
        /// seulement s'il l'est nettement plus que les autres. Un ecart faible entre
        /// les trois, c'est une vision normale - l'annoncer daltonienne serait un
        /// faux diagnostic tire du bruit de mesure.
        /// </summary>
        private void FinishScreening()
        {
            ColorFilter axis;
            double severity, quality;
            VisionExam.Fit(_measured, out axis, out severity, out quality);

            // En dessous d'une vingtaine, ou quand la deficience n'explique pas les
            // mesures mieux qu'une vision normale, annoncer un diagnostic serait
            // inventer. Mieux vaut dire « rien trouve » que designer une deficience
            // au hasard : la correction qui s'ensuivrait generait pour rien.
            if (severity < 20 || quality < 0.3)
            {
                FoundFilter = ColorFilter.None;
                FoundSeverity = 0;
                Confidence = 0;
            }
            else
            {
                FoundFilter = axis;
                FoundSeverity = severity;
                // Mesure courte : la confiance plafonne, meme quand tout concorde.
                Confidence = (int)Math.Round(Math.Min(75, quality * 100));
            }
            ShowStep(Step.Result);
        }

        // ---------------- resultat ----------------

        private void ShowResult()
        {
            _progress.Text = "";
            _next.Visible = false;

            if (FoundFilter == ColorFilter.None)
            {
                _title.Text = "Aucune deficience detectee";
                _text.Text = "Vous avez lu toutes les planches : rien n'indique de confusion des couleurs, "
                           + "et aucune correction n'est necessaire.\n\n"
                           + "Si vous savez par ailleurs etre daltonien, c'est que les planches sont passees "
                           + "a cote - la luminosite ou le profil de couleur de l'ecran peuvent fausser le test. "
                           + "Le reglage a la main reste possible dans l'onglet Daltonisme.";
                AddAnswer("Recommencer", 0, 2, delegate { Restart(); });
                AddAnswer("Fermer", 1, 2, delegate { Close(); });
                return;
            }

            _title.Text = "Resultat : " + Vision.PlainName(FoundFilter).ToLowerInvariant();
            _text.Text = string.Format(
                  "{0}\n\nGravite mesuree : {1:0} % - {2}.\nConfiance du depistage : {3} %.\n\n"
                + "La gravite compte autant que le type : une correction calibree sur une deficience "
                + "complete rend l'ecran criard a qui n'en a qu'une partie.",
                Vision.ClinicalName(FoundFilter), FoundSeverity,
                Vision.SeverityWord(FoundSeverity), Confidence);

            if ((FoundFilter == ColorFilter.Protanopia || FoundFilter == ColorFilter.Deuteranopia)
                && Confidence < 60)
                _text.Text += "\n\nRouge ou vert : les deux se ressemblent beaucoup a ce degre, et les "
                            + "separer demande un appareil de cabinet. Si la correction proposee vous "
                            + "parait fausse, essayez l'autre depuis l'onglet Daltonisme.";

            if (Confidence < 50)
                _text.Text += "\n\nConfiance faible : mieux vaut refaire le test au calme que de se fier a ceci.";

            AddAnswer("Appliquer", 0, 3, delegate { Apply(); Close(); });
            AddAnswer("Appliquer et enregistrer...", 1, 3, delegate { ApplyAndSave(); });
            AddAnswer("Recommencer", 2, 3, delegate { Restart(); });
        }

        private void Restart()
        {
            _read.Clear();
            _plateIndex = 0;
            _stair = null;
            _screening = false;
            _pending.Clear();
            _measured.Clear();
            FoundFilter = ColorFilter.None;
            FoundSeverity = 100;
            Confidence = 0;
            ShowStep(Step.Plates);
        }

        /// <summary>Pose le resultat dans les reglages. L'appelant l'applique ensuite a l'ecran.</summary>
        public void Apply()
        {
            if (FoundFilter == ColorFilter.None) return;
            _s.Current.Filter = FoundFilter;
            _s.Current.VisionSeverity = FoundSeverity;
            _s.Current.Mode = FilterMode.Correction;
            _s.LastExamSummary = string.Format("{0:dd/MM/yyyy} - {1}, gravite {2:0} %",
                DateTime.Now, Vision.PlainName(FoundFilter).ToLowerInvariant(), FoundSeverity);
            Applied = true;
        }

        /// <summary>Applique, puis enregistre sous un nom choisi. Public : les tests s'en servent.</summary>
        public void SaveAs(string name)
        {
            Apply();
            if (string.IsNullOrEmpty(name)) return;

            VisionPreset preset = VisionPreset.FromProfile(name.Trim(), _s.Current);
            for (int i = 0; i < _s.VisionPresets.Count; i++)
                if (_s.VisionPresets[i].Name == preset.Name) { _s.VisionPresets.RemoveAt(i); break; }
            _s.VisionPresets.Add(preset);
        }

        private void ApplyAndSave()
        {
            string name = PromptDialog.Ask(this, "Enregistrer ce reglage", "Nom du reglage :",
                Vision.PlainName(FoundFilter));
            SaveAs(name);
            Close();
        }
    }

    /// <summary>
    /// Une planche : un semis de pastilles ou le chiffre ne se distingue que par la
    /// couleur.
    ///
    /// Les pastilles varient de taille ET de clarte, des deux cotes de la meme facon.
    /// Sans cette variation, le chiffre ressortirait par sa regularite - et le test
    /// mesurerait la vue, pas la vision des couleurs.
    /// </summary>
    public class PlateView : Control
    {
        private VisionPlate _plate;
        private readonly List<Dot> _dots = new List<Dot>();

        private struct Dot
        {
            public float X, Y, R;
            public bool Figure;
            public float Shade;    // -1 a 1 : variation de clarte propre a la pastille
            public float Jitter;   // amplitude de cette variation
        }

        /// <summary>
        /// Amplitude de la variation de clarte entre pastilles.
        ///
        /// Elle empeche de lire le chiffre a sa regularite plutot qu'a sa couleur.
        /// Mais sur une planche subtile - celles qui depistent les anomalies moyennes -
        /// l'ecart de couleur du chiffre est lui-meme faible : une variation trop forte
        /// le noierait, et une vision normale ne verrait plus rien non plus. Elle suit
        /// donc la finesse de la planche.
        /// </summary>
        private float _jitter = 0.04f;

        public PlateView()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                   | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Card;
            TabStop = false;
            AccessibleRole = AccessibleRole.Graphic;
            AccessibleName = "Planche de couleurs";
            AccessibleDescription = "Un chiffre est dessine en pastilles d'une couleur voisine du fond.";
        }

        public void Show(VisionPlate p)
        {
            _plate = p;
            Build();
            Invalidate();
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            Build();
        }

        private void Build()
        {
            _dots.Clear();
            if (_plate == null || Width < 40 || Height < 40) return;

            int side = Math.Min(Width, Height);
            float cx = Width / 2f, cy = Height / 2f, radius = side / 2f - 2;

            // Plus la planche est subtile, plus la variation de clarte doit s'effacer :
            // elle se mesure en pourcentage, l'ecart du chiffre aussi.
            double contrast = Vision.DeltaE(_plate.Figure, _plate.Background);
            _jitter = (float)Math.Max(0.008, Math.Min(0.04, contrast / 400.0));

            using (Bitmap mask = DigitMask(_plate.Digit, side))
            {
                Random rnd = new Random(_plate.Seed);
                for (int i = 0; i < 16000 && _dots.Count < 2600; i++)
                {
                    // Des pastilles plus fines que le trait du chiffre : sinon le
                    // chiffre se disloque en taches et devient illisible meme pour une
                    // vision normale - le test accuserait alors tout le monde.
                    float r = 2.0f + (float)rnd.NextDouble() * (side / 70f);
                    double angle = rnd.NextDouble() * Math.PI * 2;
                    double dist = Math.Sqrt(rnd.NextDouble()) * (radius - r);
                    float x = cx + (float)(Math.Cos(angle) * dist);
                    float y = cy + (float)(Math.Sin(angle) * dist);

                    bool overlap = false;
                    foreach (Dot d in _dots)
                    {
                        float dx = d.X - x, dy = d.Y - y;
                        if (dx * dx + dy * dy < (d.R + r) * (d.R + r) * 0.95f) { overlap = true; break; }
                    }
                    if (overlap) continue;

                    int mx = (int)((x - (cx - side / 2f)) * mask.Width / side);
                    int my = (int)((y - (cy - side / 2f)) * mask.Height / side);
                    bool figure = mx >= 0 && my >= 0 && mx < mask.Width && my < mask.Height
                                  && mask.GetPixel(mx, my).R > 128;

                    Dot dot = new Dot();
                    dot.X = x; dot.Y = y; dot.R = r; dot.Figure = figure;
                    dot.Shade = (float)(rnd.NextDouble() * 2 - 1);
                    dot.Jitter = _jitter;
                    _dots.Add(dot);
                }
            }
        }

        /// <summary>Le chiffre, blanc sur noir : sert de pochoir pour trier les pastilles.</summary>
        private static Bitmap DigitMask(int digit, int side)
        {
            Bitmap bmp = new Bitmap(Math.Max(32, side), Math.Max(32, side));
            using (Graphics g = Graphics.FromImage(bmp))
            using (Font f = new Font("Arial Black", side * 0.58f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (StringFormat sf = new StringFormat())
            {
                g.Clear(Color.Black);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                g.DrawString(digit.ToString(), f, Brushes.White,
                             new RectangleF(0, 0, bmp.Width, bmp.Height), sf);
            }
            return bmp;
        }

        private static Color Shaded(Color c, float shade, float jitter)
        {
            // Applique de la meme facon des deux cotes : la variation ne trahit donc
            // jamais le chiffre, elle empeche seulement de le lire a la regularite.
            double k = 1.0 + shade * jitter;
            return Color.FromArgb(Clamp(c.R * k), Clamp(c.G * k), Clamp(c.B * k));
        }

        private static int Clamp(double v) { return v < 0 ? 0 : (v > 255 ? 255 : (int)Math.Round(v)); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(BackColor);
            if (_plate == null) return;

            foreach (Dot d in _dots)
            {
                Color c = Shaded(d.Figure ? _plate.Figure : _plate.Background, d.Shade, d.Jitter);
                using (SolidBrush b = new SolidBrush(c))
                    g.FillEllipse(b, d.X - d.R, d.Y - d.R, d.R * 2, d.R * 2);
            }
        }
    }

    /// <summary>Deux couleurs jointives : l'essai de comparaison.</summary>
    public class PairView : Control
    {
        private Color _left = Color.Gray, _right = Color.Gray;

        public PairView()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                   | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Card;
            TabStop = false;
            AccessibleRole = AccessibleRole.Graphic;
            AccessibleName = "Deux couleurs a comparer";
        }

        public void Show(Color left, Color right)
        {
            _left = left; _right = right;
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(BackColor);

            // Jointives, et non separees par du fond : un ecart fin ne se juge qu'au
            // contact. C'est la difference entre un test qui mesure et un test qui
            // fatigue.
            int w = Width / 2;
            using (SolidBrush b = new SolidBrush(_left)) g.FillRectangle(b, 0, 0, w, Height);
            using (SolidBrush b = new SolidBrush(_right)) g.FillRectangle(b, w, 0, Width - w, Height);
        }
    }
}
