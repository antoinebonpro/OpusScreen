using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Reglages fins de la couleur : balance des canaux, forme de la courbe, filtres
    /// d'accessibilite, teinte du voile.
    ///
    /// Les trois premiers passent par la LUT. Les filtres, eux, exigent la matrice
    /// plein ecran : une LUT ne peut pas calculer un rouge qui depend du vert.
    /// </summary>
    public class PageColor : SettingsPage
    {
        private SliderRow _red, _green, _blue, _gamma;
        private ComboRow _filter;
        private Label _filterNote;
        private DarkButton _tint, _resetBalance;
        private ColorPreview _preview;

        public override string Title { get { return "Couleur"; } }
        public override string Subtitle { get { return "Balance des canaux, courbe et filtres"; } }

        private static readonly ColorFilter[] Filters = {
            ColorFilter.None, ColorFilter.Grayscale, ColorFilter.Invert, ColorFilter.InvertKeepHue,
            ColorFilter.Sepia,
            ColorFilter.Protanopia, ColorFilter.Deuteranopia, ColorFilter.Tritanopia
        };

        public PageColor(Settings s, DisplayController d, Action push) : base(s, d, push)
        {
            Section("Apercu");

            _preview = new ColorPreview(s);
            _preview.Height = 58;
            Add(_preview, Theme.SpaceSm);

            Section("Balance des canaux");

            _red = MakeGain("Rouge", Color.FromArgb(226, 106, 106));
            _red.Changed += delegate { S.Current.RedGain = _red.Value; Live(); };
            _red.Committed += delegate { Commit(); };
            Add(_red, Theme.SpaceSm);

            _green = MakeGain("Vert", Color.FromArgb(112, 200, 130));
            _green.Changed += delegate { S.Current.GreenGain = _green.Value; Live(); };
            _green.Committed += delegate { Commit(); };
            Add(_green, Theme.SpaceSm);

            _blue = MakeGain("Bleu", Color.FromArgb(104, 154, 246));
            _blue.Changed += delegate { S.Current.BlueGain = _blue.Value; Live(); };
            _blue.Committed += delegate { Commit(); };
            Add(_blue, Theme.SpaceSm);

            _resetBalance = new DarkButton();
            _resetBalance.Text = "Remettre la balance a plat";
            _resetBalance.Height = Theme.MinTarget;
            _resetBalance.Click += delegate
            {
                S.Current.RedGain = S.Current.GreenGain = S.Current.BlueGain = 100;
                Sync();
                Commit();
            };
            Add(_resetBalance, Theme.SpaceSm);

            Note("Sert a corriger une dominante de dalle, ou a pousser la reduction du bleu "
               + "plus loin que ne le permet la seule temperature.");

            Section("Courbe");

            _gamma = new SliderRow("Gamma", 50, 200, "%");
            _gamma.MarkAt(100, double.NaN);
            _gamma.Changed += delegate { S.Current.GammaCurve = _gamma.Value; UpdateGammaHint(); Live(); };
            _gamma.Committed += delegate { Commit(); };
            Add(_gamma, Theme.SpaceSm);

            Note("Au-dessus de 100 %, les tons sombres remontent sans toucher au blanc : "
               + "utile pour distinguer les details d'une image sombre.");

            Section("Filtres");

            List<string> names = new List<string>();
            foreach (ColorFilter f in Filters) names.Add(Cap(Profile.FilterName(f)));
            _filter = new ComboRow("Filtre de couleur", names);
            _filter.Changed += delegate
            {
                if (Loading) return;
                S.Current.Filter = Filters[Math.Max(0, _filter.SelectedIndex)];
                UpdateFilterNote();
                Live();
                Commit();
            };
            Add(_filter, Theme.SpaceSm);

            _filterNote = UiKit.Caption("");
            _filterNote.Height = 46;
            Add(_filterNote, Theme.SpaceXs);

            Section("Teinte du voile");

            _tint = new DarkButton();
            _tint.Text = "Choisir la couleur du voile...";
            _tint.Height = Theme.MinTarget;
            _tint.Click += OnPickTint;
            Add(_tint, Theme.SpaceSm);

            Note("Le voile n'entre en jeu que sous 35 % de luminosite. Le noir est le choix "
               + "neutre ; une teinte ambre pousse plus loin la reduction du bleu le soir. "
               + "C'est le « fade-out color » de PangoBright.");
        }

        private SliderRow MakeGain(string label, Color accent)
        {
            SliderRow r = new SliderRow(label, 0, 150, "%");
            r.MarkAt(100, double.NaN);
            r.SetAccent(accent);
            return r;
        }

        private void Live()
        {
            _preview.Invalidate();
            CommitNoSave();
        }

        private void UpdateGammaHint()
        {
            _gamma.Hint = S.Current.GammaCurve > 100 ? "ombres relevees"
                        : (S.Current.GammaCurve < 100 ? "ombres ecrasees" : "reponse standard");
        }

        private void UpdateFilterNote()
        {
            switch (S.Current.Filter)
            {
                case ColorFilter.None:
                    _filterNote.Text = "Aucun melange de canaux : la matrice plein ecran reste inactive.";
                    break;
                case ColorFilter.Grayscale:
                    _filterNote.Text = "Conversion en luminance Rec. 709. Pratique pour juger d'un contraste "
                                     + "sans se laisser influencer par les couleurs.";
                    break;
                case ColorFilter.Invert:
                    _filterNote.Text = "Inverse toutes les couleurs. C'est le « mode programmation » d'Iris : "
                                     + "il rend sombres les pages web claires, mais transforme aussi les "
                                     + "photos en negatifs.";
                    break;
                case ColorFilter.InvertKeepHue:
                    _filterNote.Text = "Inverse le clair et le sombre en gardant les teintes ou elles sont : "
                                     + "les documents passent au sombre sans que les photos virent au negatif.";
                    break;
                case ColorFilter.Sepia:
                    _filterNote.Text = "Teinte chaude et douce pour la lecture prolongee.";
                    break;
                default:
                    _filterNote.Text = string.Format(
                        "Assistance daltonisme, reglee sur « {0} ». Les couleurs habituellement confondues "
                      + "sont ecartees l'une de l'autre ; les gris restent neutres. La gravite, l'intensite "
                      + "et le comparateur de couleurs sont dans la page Vision.",
                        Vision.SeverityWord(S.Current.VisionSeverity));
                    break;
            }
        }

        private void OnPickTint(object sender, EventArgs e)
        {
            using (ColorDialog dlg = new ColorDialog())
            {
                dlg.Color = S.Current.Tint;
                dlg.FullOpen = true;
                dlg.AnyColor = true;
                if (dlg.ShowDialog(FindForm()) == DialogResult.OK)
                {
                    S.Current.Tint = dlg.Color;
                    UpdateTintButton();
                    Commit();
                }
            }
        }

        private void UpdateTintButton()
        {
            Color c = S.Current.Tint;
            _tint.BackColor = c == Color.Black ? Theme.Sunken : c;
            double lum = 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B;
            _tint.ForeColor = (c != Color.Black && lum > 140) ? Color.Black : Theme.Fg;
            _tint.Text = c == Color.Black ? "Noir (neutre) - cliquer pour changer"
                                          : string.Format("Teinte {0},{1},{2} - cliquer pour changer", c.R, c.G, c.B);
        }

        private static string Cap(string s)
        {
            if (string.IsNullOrEmpty(s)) return s;
            return char.ToUpperInvariant(s[0]) + s.Substring(1);
        }

        public override void Sync()
        {
            Loading = true;
            try
            {
                _red.SetValueSilent(S.Current.RedGain);
                _green.SetValueSilent(S.Current.GreenGain);
                _blue.SetValueSilent(S.Current.BlueGain);
                _gamma.SetValueSilent(S.Current.GammaCurve);

                int idx = Array.IndexOf(Filters, S.Current.Filter);
                _filter.SelectedIndex = idx >= 0 ? idx : 0;
                _filter.Box.Enabled = S.UseColorMatrix && ColorMatrixEffect.Available;

                UpdateGammaHint();
                UpdateFilterNote();
                UpdateTintButton();

                if (!ColorMatrixEffect.Available)
                    _filterNote.Text = "La matrice plein ecran n'est pas disponible sur ce systeme : "
                                     + "les filtres qui melangent les canaux sont inactifs.";
                else if (!S.UseColorMatrix)
                    _filterNote.Text = "L'etage « matrice de couleur » est desactive dans l'onglet Avance.";

                _preview.Invalidate();
            }
            finally { Loading = false; }
        }
    }

    /// <summary>
    /// Bande d'apercu : degrade de gris et pastilles de couleur, telles qu'elles
    /// sortiront apres la LUT et la matrice. Permet de juger un reglage sans avoir a
    /// l'appliquer a tout le bureau.
    /// </summary>
    public class ColorPreview : Control
    {
        private readonly Settings _s;

        public ColorPreview(Settings s)
        {
            _s = s;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                   | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Card;

            // Purement visuel : rien a y faire au clavier, mais un lecteur d'ecran doit
            // pouvoir l'annoncer pour ce qu'il est plutot que de buter sur un rectangle
            // sans nom - et surtout pouvoir le passer.
            //
            // TabStop vaut vrai par defaut sur un Control : sans cette ligne, la
            // tabulation s'arretait sur une image ou il n'y a rien a faire.
            TabStop = false;
            AccessibleRole = AccessibleRole.Graphic;
            AccessibleName = "Apercu des couleurs";
            AccessibleDescription = "Degrade de gris et pastilles de reference, tels qu'ils "
                                  + "sortiront apres les reglages en cours.";
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(BackColor);

            Profile p = _s.Current;
            BrightnessPlan plan = GammaEngine.Plan(p.Brightness, _s.UseOverlay, _s.UseHardwareBacklight);
            Native.RampTable ramp = GammaEngine.BuildRamp(plan, p);

            int steps = 32;
            int w = Math.Max(1, Width / steps);

            // degrade de gris passe dans la LUT
            for (int i = 0; i < steps; i++)
            {
                int src = i * 255 / (steps - 1);
                Color c = Through(ramp, src, src, src);
                using (SolidBrush b = new SolidBrush(c))
                    g.FillRectangle(b, i * w, 0, w + 1, 30);
            }

            // pastilles de couleur de reference
            Color[] refs = {
                Color.FromArgb(220, 60, 60), Color.FromArgb(230, 150, 40),
                Color.FromArgb(220, 210, 70), Color.FromArgb(70, 190, 90),
                Color.FromArgb(60, 140, 230), Color.FromArgb(150, 90, 210),
                Color.FromArgb(240, 240, 240)
            };
            int cw = Math.Max(1, Width / refs.Length);
            for (int i = 0; i < refs.Length; i++)
            {
                Color c = Through(ramp, refs[i].R, refs[i].G, refs[i].B);
                using (SolidBrush b = new SolidBrush(c))
                    g.FillRectangle(b, i * cw, 32, cw + 1, 24);
            }

            using (Pen pen = new Pen(Theme.Border))
                g.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
        }

        /// <summary>
        /// Passe une couleur dans la LUT puis dans la matrice, pour l'apercu.
        ///
        /// La matrice est celle du moteur, pas une reecriture : la version precedente
        /// recopiait a la main la saturation, l'inversion et le sepia, et ne traitait
        /// AUCUN des filtres pour daltoniens. L'apercu montrait donc une image
        /// inchangee alors que l'ecran, lui, changeait - exactement pour les reglages
        /// que l'on a le plus besoin de comparer avant de les appliquer.
        /// </summary>
        private Color Through(Native.RampTable ramp, int r, int gg, int b)
        {
            double rr = ramp.Red[Clamp255(r)] / 65535.0;
            double gv = ramp.Green[Clamp255(gg)] / 65535.0;
            double bv = ramp.Blue[Clamp255(b)] / 65535.0;

            if (_s.UseColorMatrix)
                ColorMatrixEffect.Transform(_s.Current.BuildMatrix(), ref rr, ref gv, ref bv);

            return Color.FromArgb(To255(rr), To255(gv), To255(bv));
        }

        private static int Clamp255(int v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }
        private static int To255(double v)
        {
            int i = (int)Math.Round(v * 255);
            return i < 0 ? 0 : (i > 255 ? 255 : i);
        }
    }
}
