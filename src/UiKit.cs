using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Briques d'interface reutilisables.
    ///
    /// Avec une quarantaine de reglages, ecrire chaque ligne a la main produirait un
    /// fichier illisible et des alignements approximatifs. Chaque type de reglage a
    /// donc sa brique : la mise en page est decidee une fois, et toutes les lignes
    /// s'alignent d'elles-memes.
    ///
    /// Regles appliquees partout : contraste du texte >= 4.5:1, anneau de focus visible
    /// au clavier, zone cliquable d'au moins 32 px de haut, aucun emoji en guise d'icone.
    /// </summary>
    public static class UiKit
    {
        public const int RowHeight = 34;
        public const int RowHeightTall = 56;
        public const int LabelWidth = 210;

        public static Label SectionTitle(string text)
        {
            Label l = new Label();
            l.Text = text.ToUpperInvariant();
            l.Font = Theme.SectionLabel;
            l.ForeColor = Theme.Dim;
            l.AutoSize = false;
            l.Height = 20;
            l.TextAlign = ContentAlignment.BottomLeft;
            l.BackColor = Color.Transparent;
            return l;
        }

        public static Label Caption(string text)
        {
            Label l = new Label();
            l.Text = text;
            l.Font = Theme.Small;
            l.ForeColor = Theme.Faint;
            l.AutoSize = false;
            l.BackColor = Color.Transparent;
            return l;
        }

        /// <summary>Trait de separation discret entre deux groupes.</summary>
        public static Control Divider()
        {
            Panel p = new Panel();
            p.Height = 1;
            p.BackColor = Theme.Border;
            return p;
        }
    }

    /// <summary>Ligne « intitule + curseur + valeur », la brique la plus employee.</summary>
    public class SliderRow : Panel
    {
        private readonly Label _label = new Label();
        private readonly Label _value = new Label();
        private readonly Label _hint = new Label();
        public readonly Slider Track = new Slider();

        private string _unit = "";
        private string _format = "0";

        public event EventHandler Changed;
        public event EventHandler Committed;

        public SliderRow(string label, double min, double max, string unit)
        {
            _unit = unit;
            Height = UiKit.RowHeightTall;
            BackColor = Color.Transparent;

            _label.Text = label;
            _label.Font = Theme.Body;
            _label.ForeColor = Theme.Fg;
            _label.AutoSize = false;
            _label.BackColor = Color.Transparent;
            Controls.Add(_label);

            _value.Font = Theme.BodyBold;
            _value.ForeColor = Theme.Accent;
            _value.AutoSize = false;
            _value.TextAlign = ContentAlignment.MiddleRight;
            _value.BackColor = Color.Transparent;
            Controls.Add(_value);

            _hint.Font = Theme.Small;
            _hint.ForeColor = Theme.Faint;
            _hint.AutoSize = false;
            _hint.BackColor = Color.Transparent;
            Controls.Add(_hint);

            Track.Minimum = min;
            Track.Maximum = max;
            Track.BackColor = Color.Transparent;
            Track.AccessibleLabel = label;
            Track.AccessibleUnit = unit;
            Track.ValueChanged += delegate
            {
                UpdateValueLabel();
                if (Changed != null) Changed(this, EventArgs.Empty);
            };
            Track.ValueCommitted += delegate
            {
                if (Committed != null) Committed(this, EventArgs.Empty);
            };
            Controls.Add(Track);
        }

        public string Format { get { return _format; } set { _format = value; UpdateValueLabel(); } }
        public string Unit { get { return _unit; } set { _unit = value; UpdateValueLabel(); } }

        public string Hint { get { return _hint.Text; } set { _hint.Text = value; } }

        public double Value
        {
            get { return Track.Value; }
            set { Track.Value = value; UpdateValueLabel(); }
        }

        public void SetValueSilent(double v)
        {
            Track.SetValueSilent(v);
            UpdateValueLabel();
        }

        /// <summary>Graduation de reference et seuil au-dela duquel la barre change de teinte.</summary>
        public void MarkAt(double marker, double warnAbove)
        {
            Track.MarkerValue = marker;
            Track.WarnAbove = warnAbove;
        }

        public void SetAccent(Color fill)
        {
            Track.FillColor = fill;
            _value.ForeColor = fill;
        }

        private void UpdateValueLabel()
        {
            _value.Text = Track.Value.ToString(_format) + (_unit.Length > 0 ? " " + _unit : "");
            if (!double.IsNaN(Track.WarnAbove) && Track.Value > Track.WarnAbove)
                _value.ForeColor = Theme.Boost;
            else
                _value.ForeColor = Track.FillColor;
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            _label.SetBounds(0, 2, UiKit.LabelWidth, 20);
            _value.SetBounds(Width - 90, 2, 90, 20);
            _hint.SetBounds(UiKit.LabelWidth, 4, Width - UiKit.LabelWidth - 95, 18);
            _hint.TextAlign = ContentAlignment.MiddleRight;
            Track.SetBounds(-8, 22, Width + 16, 30);
        }
    }

    /// <summary>Ligne « intitule + explication + interrupteur ».</summary>
    public class ToggleRow : Panel
    {
        private readonly Label _label = new Label();
        private readonly Label _desc = new Label();
        public readonly ToggleSwitch Switch = new ToggleSwitch();

        public event EventHandler Changed;

        public ToggleRow(string label, string description)
        {
            Height = string.IsNullOrEmpty(description) ? UiKit.RowHeight + 4 : 46;
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;

            _label.Text = label;
            _label.Font = Theme.Body;
            _label.ForeColor = Theme.Fg;
            _label.AutoSize = false;
            _label.BackColor = Color.Transparent;
            _label.Click += delegate { Switch.Checked = !Switch.Checked; };
            Controls.Add(_label);

            _desc.Text = description ?? "";
            _desc.Font = Theme.Small;
            _desc.ForeColor = Theme.Faint;
            _desc.AutoSize = false;
            _desc.BackColor = Color.Transparent;
            Controls.Add(_desc);

            Switch.AccessibleLabel = label;
            Switch.AccessibleDescription = description ?? "";
            Switch.CheckedChanged += delegate { if (Changed != null) Changed(this, EventArgs.Empty); };
            Controls.Add(Switch);

            Click += delegate { Switch.Checked = !Switch.Checked; };
        }

        public bool Checked
        {
            get { return Switch.Checked; }
            set { Switch.Checked = value; }
        }

        public void SetCheckedSilent(bool v) { Switch.SetCheckedSilent(v); }

        public string Description { get { return _desc.Text; } set { _desc.Text = value; } }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            int sw = 44, sh = 22;
            Switch.SetBounds(Width - sw - 2, (Height - sh) / 2, sw, sh);
            bool hasDesc = _desc.Text.Length > 0;
            _label.SetBounds(0, hasDesc ? 4 : (Height - 20) / 2, Width - sw - 16, 20);
            _desc.SetBounds(0, 24, Width - sw - 16, 18);
            _desc.Visible = hasDesc;
        }
    }

    /// <summary>Interrupteur a bascule dessine a la main, avec animation courte.</summary>
    public class ToggleSwitch : Control
    {
        private bool _checked;
        private double _anim;          // 0 = eteint, 1 = allume
        private readonly Timer _timer = new Timer();
        private bool _hover;

        public event EventHandler CheckedChanged;

        public ToggleSwitch()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                   | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw
                   | ControlStyles.SupportsTransparentBackColor, true);
            Size = new Size(44, 22);
            Cursor = Cursors.Hand;
            TabStop = true;
            AccessibleRole = AccessibleRole.CheckButton;

            // ~180 ms : en dessous l'oeil percoit un saut, au-dela l'interface traine.
            _timer.Interval = 15;
            _timer.Tick += Animate;
        }

        /// <summary>Intitule de la ligne, renseigne par ToggleRow qui le connait.</summary>
        public string AccessibleLabel = "";

        /// <summary>
        /// Sans cet objet, un lecteur d'ecran ne voit qu'un rectangle : ni le nom du
        /// reglage, ni le fait qu'il s'agisse d'un interrupteur, ni son etat.
        /// </summary>
        protected override AccessibleObject CreateAccessibilityInstance()
        {
            return new SwitchAccessibleObject(this);
        }

        private class SwitchAccessibleObject : Control.ControlAccessibleObject
        {
            private readonly ToggleSwitch _owner;

            public SwitchAccessibleObject(ToggleSwitch owner) : base(owner) { _owner = owner; }

            public override AccessibleRole Role { get { return AccessibleRole.CheckButton; } }

            public override string Name
            {
                get { return _owner.AccessibleLabel.Length > 0 ? _owner.AccessibleLabel : base.Name; }
                set { base.Name = value; }
            }

            public override string DefaultAction
            {
                get { return _owner.Checked ? "Desactiver" : "Activer"; }
            }

            public override void DoDefaultAction() { _owner.Checked = !_owner.Checked; }

            public override AccessibleStates State
            {
                get
                {
                    AccessibleStates s = base.State;
                    if (_owner.Checked) s |= AccessibleStates.Checked;
                    if (!_owner.Enabled) s |= AccessibleStates.Unavailable;
                    return s;
                }
            }
        }

        public bool Checked
        {
            get { return _checked; }
            set
            {
                if (_checked == value) return;
                _checked = value;
                _timer.Start();
                if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty);
            }
        }

        public void SetCheckedSilent(bool v)
        {
            _checked = v;
            _anim = v ? 1 : 0;
            Invalidate();
        }

        private void Animate(object sender, EventArgs e)
        {
            double step = 15.0 / Theme.MotionMs;
            if (_checked) { _anim += step; if (_anim >= 1) { _anim = 1; _timer.Stop(); } }
            else { _anim -= step; if (_anim <= 0) { _anim = 0; _timer.Stop(); } }
            Invalidate();
        }

        protected override void OnClick(EventArgs e) { Checked = !Checked; Focus(); base.OnClick(e); }
        protected override void OnMouseEnter(EventArgs e) { _hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

        protected override bool IsInputKey(Keys k) { return k == Keys.Space || base.IsInputKey(k); }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Space) { Checked = !Checked; e.Handled = true; }
            base.OnKeyDown(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Parent != null ? Parent.BackColor : Theme.Card);

            int h = Height - 2, w = Width - 2;
            Rectangle rail = new Rectangle(1, 1, w, h);

            Color off = _hover ? Theme.BorderStrong : Theme.Sunken;
            Color on = Theme.Accent;
            Color track = Blend(off, on, _anim);

            using (SolidBrush b = new SolidBrush(track))
            using (GraphicsPath p = Rounded(rail, h / 2))
                g.FillPath(b, p);

            if (_anim < 0.5)
            {
                using (Pen pen = new Pen(Theme.BorderStrong))
                using (GraphicsPath p = Rounded(rail, h / 2))
                    g.DrawPath(pen, p);
            }

            int knob = h - 6;
            int x = (int)Math.Round(4 + _anim * (w - knob - 6));
            using (SolidBrush sh = new SolidBrush(Color.FromArgb(60, 0, 0, 0)))
                g.FillEllipse(sh, x, 5, knob, knob);
            using (SolidBrush b = new SolidBrush(Color.White))
                g.FillEllipse(b, x, 4, knob, knob);

            if (Focused)
            {
                using (Pen p = new Pen(Theme.Focus, 2))
                    g.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
            }
        }

        private static Color Blend(Color a, Color b, double t)
        {
            return Color.FromArgb(
                (int)(a.R + (b.R - a.R) * t),
                (int)(a.G + (b.G - a.G) * t),
                (int)(a.B + (b.B - a.B) * t));
        }

        private static GraphicsPath Rounded(Rectangle r, int radius)
        {
            GraphicsPath p = new GraphicsPath();
            int d = radius * 2;
            if (d > r.Height) d = r.Height;
            if (d > r.Width) d = r.Width;
            p.AddArc(r.Left, r.Top, d, d, 90, 180);
            p.AddArc(r.Right - d, r.Top, d, d, 270, 180);
            p.CloseFigure();
            return p;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) { _timer.Stop(); _timer.Dispose(); }
            base.Dispose(disposing);
        }
    }

    /// <summary>Ligne « intitule + liste deroulante ».</summary>
    public class ComboRow : Panel
    {
        private readonly Label _label = new Label();
        public readonly DarkComboBox Box = new DarkComboBox();

        public event EventHandler Changed;

        public ComboRow(string label, IEnumerable<string> items)
        {
            Height = UiKit.RowHeight + 6;
            BackColor = Color.Transparent;

            _label.Text = label;
            _label.Font = Theme.Body;
            _label.ForeColor = Theme.Fg;
            _label.AutoSize = false;
            _label.BackColor = Color.Transparent;
            Controls.Add(_label);

            foreach (string s in items) Box.Items.Add(s);
            Box.SelectedIndexChanged += delegate { if (Changed != null) Changed(this, EventArgs.Empty); };
            Controls.Add(Box);
        }

        public string SelectedText
        {
            get { return Box.SelectedItem != null ? Box.SelectedItem.ToString() : ""; }
        }

        public int SelectedIndex
        {
            get { return Box.SelectedIndex; }
            set { if (value >= 0 && value < Box.Items.Count) Box.SelectedIndex = value; }
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            int boxW = Math.Min(260, Width - UiKit.LabelWidth);
            _label.SetBounds(0, (Height - 20) / 2, UiKit.LabelWidth, 20);
            Box.SetBounds(Width - boxW, (Height - 24) / 2, boxW, 24);
        }
    }

    /// <summary>Barre de navigation verticale : un onglet par domaine de reglages.</summary>
    public class SideNav : Panel
    {
        private readonly List<NavItem> _items = new List<NavItem>();
        private int _selected;

        public event Action<int> SelectionChanged;

        /// <summary>Espace laisse libre au-dessus du premier onglet, pour le nom du produit.</summary>
        public int TopOffset = 8;

        public SideNav()
        {
            BackColor = Theme.Sunken;
            DoubleBuffered = true;
        }

        public void AddTab(string label, string glyph)
        {
            NavItem it = new NavItem(label, glyph, _items.Count);
            it.Width = Width;
            it.Height = 40;
            it.Top = TopOffset + _items.Count * 40;
            it.Clicked += delegate(int idx) { Select(idx); };
            _items.Add(it);
            Controls.Add(it);
            if (_items.Count == 1) it.Selected = true;
        }

        public void Select(int index)
        {
            if (index < 0 || index >= _items.Count) return;
            _selected = index;
            for (int i = 0; i < _items.Count; i++) _items[i].Selected = (i == index);
            if (SelectionChanged != null) SelectionChanged(index);
        }

        public int SelectedIndex { get { return _selected; } }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            foreach (NavItem it in _items) it.Width = Width;
        }

        private class NavItem : Control
        {
            private readonly string _glyph;
            private readonly int _index;
            private bool _selected, _hover;

            public event Action<int> Clicked;

            public NavItem(string label, string glyph, int index)
            {
                SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                       | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
                Text = label;
                _glyph = glyph;
                _index = index;
                Cursor = Cursors.Hand;
                TabStop = true;
                AccessibleRole = AccessibleRole.PageTab;
                AccessibleName = label;
            }

            /// <summary>L'onglet doit s'annoncer comme onglet, et dire s'il est celui affiche.</summary>
            protected override AccessibleObject CreateAccessibilityInstance()
            {
                return new TabAccessibleObject(this);
            }

            private class TabAccessibleObject : Control.ControlAccessibleObject
            {
                private readonly NavItem _owner;

                public TabAccessibleObject(NavItem owner) : base(owner) { _owner = owner; }

                public override AccessibleRole Role { get { return AccessibleRole.PageTab; } }
                public override string DefaultAction { get { return "Afficher"; } }

                public override void DoDefaultAction()
                {
                    if (_owner.Clicked != null) _owner.Clicked(_owner._index);
                }

                public override AccessibleStates State
                {
                    get
                    {
                        AccessibleStates s = base.State;
                        if (_owner.Selected) s |= AccessibleStates.Selected;
                        return s;
                    }
                }
            }

            public bool Selected
            {
                get { return _selected; }
                set { _selected = value; Invalidate(); }
            }

            protected override void OnClick(EventArgs e)
            {
                Focus();
                if (Clicked != null) Clicked(_index);
                base.OnClick(e);
            }

            protected override void OnMouseEnter(EventArgs e) { _hover = true; Invalidate(); base.OnMouseEnter(e); }
            protected override void OnMouseLeave(EventArgs e) { _hover = false; Invalidate(); base.OnMouseLeave(e); }
            protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
            protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

            protected override bool IsInputKey(Keys k)
            {
                return k == Keys.Space || k == Keys.Enter || base.IsInputKey(k);
            }

            protected override void OnKeyDown(KeyEventArgs e)
            {
                if ((e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) && Clicked != null)
                {
                    Clicked(_index);
                    e.Handled = true;
                }
                base.OnKeyDown(e);
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                Graphics g = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(_selected ? Theme.Card : (_hover ? Theme.CardHover : Theme.Sunken));

                if (_selected)
                {
                    using (SolidBrush b = new SolidBrush(Theme.Accent))
                        g.FillRectangle(b, 0, 6, 3, Height - 12);
                }

                Color fg = _selected ? Theme.Fg : Theme.Dim;
                NavGlyph.Draw(g, _glyph, new Rectangle(16, Height / 2 - 8, 16, 16), fg);

                using (Font f = _selected ? Theme.BodyBold : Theme.Body)
                    TextRenderer.DrawText(g, Text, f, new Rectangle(42, 0, Width - 46, Height), fg,
                        TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);

                if (Focused)
                {
                    using (Pen p = new Pen(Theme.Focus, 1))
                        g.DrawRectangle(p, 1, 1, Width - 3, Height - 3);
                }
            }
        }
    }

    /// <summary>
    /// Petites icones tracees au vecteur.
    ///
    /// Regle suivie : jamais d'emoji en guise d'icone. Un emoji change de dessin selon
    /// la police installee, ignore la couleur du theme et rend mal a 16 px.
    /// </summary>
    public static class NavGlyph
    {
        public static void Draw(Graphics g, string name, Rectangle r, Color color)
        {
            using (Pen p = new Pen(color, 1.6f))
            using (SolidBrush b = new SolidBrush(color))
            {
                p.LineJoin = LineJoin.Round;
                p.StartCap = LineCap.Round;
                p.EndCap = LineCap.Round;

                switch (name)
                {
                    case "sun":     // luminosite
                        g.DrawEllipse(p, r.X + 5, r.Y + 5, 6, 6);
                        for (int i = 0; i < 8; i++)
                        {
                            double a = i * Math.PI / 4;
                            float cx = r.X + 8, cy = r.Y + 8;
                            g.DrawLine(p,
                                (float)(cx + Math.Cos(a) * 6.5), (float)(cy + Math.Sin(a) * 6.5),
                                (float)(cx + Math.Cos(a) * 8), (float)(cy + Math.Sin(a) * 8));
                        }
                        break;

                    case "palette": // couleur
                        g.DrawEllipse(p, r.X + 2, r.Y + 2, 12, 12);
                        g.FillEllipse(b, r.X + 5, r.Y + 4, 2.5f, 2.5f);
                        g.FillEllipse(b, r.X + 9, r.Y + 6, 2.5f, 2.5f);
                        g.FillEllipse(b, r.X + 6, r.Y + 9, 2.5f, 2.5f);
                        break;

                    case "clock":   // automatisme
                        g.DrawEllipse(p, r.X + 2, r.Y + 2, 12, 12);
                        g.DrawLine(p, r.X + 8, r.Y + 8, r.X + 8, r.Y + 4.5f);
                        g.DrawLine(p, r.X + 8, r.Y + 8, r.X + 11, r.Y + 9.5f);
                        break;

                    case "screens": // ecrans
                        g.DrawRectangle(p, r.X + 1, r.Y + 3, 9, 7);
                        g.DrawRectangle(p, r.X + 6, r.Y + 7, 9, 6);
                        break;

                    case "eye":     // confort
                        {
                            GraphicsPath path = new GraphicsPath();
                            path.AddBezier(r.X + 1, r.Y + 8, r.X + 5, r.Y + 3, r.X + 11, r.Y + 3, r.X + 15, r.Y + 8);
                            path.AddBezier(r.X + 15, r.Y + 8, r.X + 11, r.Y + 13, r.X + 5, r.Y + 13, r.X + 1, r.Y + 8);
                            g.DrawPath(p, path);
                            g.FillEllipse(b, r.X + 6, r.Y + 6, 4, 4);
                            path.Dispose();
                        }
                        break;

                    case "vision":  // accessibilite visuelle : un oeil, et ce qu'on lui ajoute
                        {
                            GraphicsPath path = new GraphicsPath();
                            path.AddBezier(r.X, r.Y + 7, r.X + 3.5f, r.Y + 2.5f, r.X + 8.5f, r.Y + 2.5f, r.X + 12, r.Y + 7);
                            path.AddBezier(r.X + 12, r.Y + 7, r.X + 8.5f, r.Y + 11.5f, r.X + 3.5f, r.Y + 11.5f, r.X, r.Y + 7);
                            g.DrawPath(p, path);
                            g.FillEllipse(b, r.X + 4, r.Y + 5, 4, 4);
                            path.Dispose();

                            // Le signe plus dit « en mieux » : c'est la convention des
                            // pictogrammes d'assistance, et elle reste lisible a 16 px.
                            g.DrawLine(p, r.X + 12.5f, r.Y + 12, r.X + 12.5f, r.Y + 16);
                            g.DrawLine(p, r.X + 10.5f, r.Y + 14, r.X + 14.5f, r.Y + 14);
                        }
                        break;

                    case "keyboard":
                        g.DrawRectangle(p, r.X + 1, r.Y + 4, 14, 9);
                        for (int i = 0; i < 4; i++) g.FillRectangle(b, r.X + 3 + i * 3, r.Y + 6, 1.6f, 1.6f);
                        g.FillRectangle(b, r.X + 5, r.Y + 10, 7, 1.6f);
                        break;

                    case "sliders": // avance
                        g.DrawLine(p, r.X + 2, r.Y + 4, r.X + 14, r.Y + 4);
                        g.DrawLine(p, r.X + 2, r.Y + 8, r.X + 14, r.Y + 8);
                        g.DrawLine(p, r.X + 2, r.Y + 12, r.X + 14, r.Y + 12);
                        g.FillEllipse(b, r.X + 9, r.Y + 2, 4, 4);
                        g.FillEllipse(b, r.X + 4, r.Y + 6, 4, 4);
                        g.FillEllipse(b, r.X + 10, r.Y + 10, 4, 4);
                        break;

                    case "apps":
                        g.DrawRectangle(p, r.X + 2, r.Y + 2, 5, 5);
                        g.DrawRectangle(p, r.X + 9, r.Y + 2, 5, 5);
                        g.DrawRectangle(p, r.X + 2, r.Y + 9, 5, 5);
                        g.DrawRectangle(p, r.X + 9, r.Y + 9, 5, 5);
                        break;
                }
            }
        }
    }
}
