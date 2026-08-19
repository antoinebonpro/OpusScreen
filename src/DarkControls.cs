using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Case a cocher dessinee a la main.
    ///
    /// La CheckBox de WinForms delegue son rendu au theme de Windows : sur un fond
    /// sombre, la coche devient illisible quelle que soit la couleur demandee. La
    /// redessiner entierement est le seul moyen fiable d'obtenir un thema coherent.
    /// </summary>
    public class DarkCheckBox : Control
    {
        private bool _checked;
        private bool _hover;

        public event EventHandler CheckedChanged;

        public Color BoxColor = Color.FromArgb(58, 62, 72);
        public Color BorderColor = Color.FromArgb(88, 94, 108);
        public Color CheckColor = Color.FromArgb(94, 160, 255);
        public Color TickColor = Color.White;

        public DarkCheckBox()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                   | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw
                   | ControlStyles.SupportsTransparentBackColor, true);
            Height = 22;
            Cursor = Cursors.Hand;
            ForeColor = Color.FromArgb(232, 236, 244);
            AccessibleRole = AccessibleRole.CheckButton;
        }

        // Ce controle n'est plus instancie nulle part : ToggleSwitch l'a remplace dans
        // toute l'interface. Il reste neanmoins tenu aux memes regles que les autres,
        // parce qu'un controle laisse en place finit toujours par etre reutilise - et
        // le jour ou il le sera, il ne devra pas rouvrir un trou d'accessibilite.

        protected override bool IsInputKey(Keys key)
        {
            return key == Keys.Space || base.IsInputKey(key);
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Space) { Checked = !Checked; e.Handled = true; }
            base.OnKeyDown(e);
        }

        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

        protected override AccessibleObject CreateAccessibilityInstance()
        {
            return new CheckAccessibleObject(this);
        }

        private class CheckAccessibleObject : Control.ControlAccessibleObject
        {
            private readonly DarkCheckBox _owner;

            public CheckAccessibleObject(DarkCheckBox owner) : base(owner) { _owner = owner; }

            public override AccessibleRole Role { get { return AccessibleRole.CheckButton; } }
            public override string DefaultAction { get { return _owner.Checked ? "Decocher" : "Cocher"; } }
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
                Invalidate();
                if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty);
            }
        }

        /// <summary>Change l'etat sans declencher l'evenement (synchronisation depuis le modele).</summary>
        public void SetCheckedSilent(bool value)
        {
            _checked = value;
            Invalidate();
        }

        protected override void OnClick(EventArgs e)
        {
            Checked = !Checked;
            base.OnClick(e);
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(BackColor);

            int size = 15;
            int top = (Height - size) / 2;
            Rectangle box = new Rectangle(0, top, size, size);

            using (SolidBrush b = new SolidBrush(_checked ? CheckColor : BoxColor))
                FillRounded(g, b, box, 3);

            if (!_checked)
            {
                using (Pen p = new Pen(_hover ? Color.FromArgb(130, 140, 158) : BorderColor, 1))
                    DrawRounded(g, p, box, 3);
            }

            if (_checked)
            {
                using (Pen p = new Pen(TickColor, 2))
                {
                    p.StartCap = LineCap.Round;
                    p.EndCap = LineCap.Round;
                    g.DrawLines(p, new Point[] {
                        new Point(box.Left + 3, box.Top + 8),
                        new Point(box.Left + 6, box.Top + 11),
                        new Point(box.Left + 12, box.Top + 4)
                    });
                }
            }

            Rectangle textRect = new Rectangle(size + 8, 0, Width - size - 8, Height);
            TextRenderer.DrawText(g, Text, Font, textRect, ForeColor,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }

        private static void FillRounded(Graphics g, Brush b, Rectangle r, int radius)
        {
            using (GraphicsPath path = RoundedPath(r, radius)) g.FillPath(b, path);
        }

        private static void DrawRounded(Graphics g, Pen p, Rectangle r, int radius)
        {
            using (GraphicsPath path = RoundedPath(r, radius)) g.DrawPath(p, path);
        }

        private static GraphicsPath RoundedPath(Rectangle r, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            int d = radius * 2;
            path.AddArc(r.Left, r.Top, d, d, 180, 90);
            path.AddArc(r.Right - d - 1, r.Top, d, d, 270, 90);
            path.AddArc(r.Right - d - 1, r.Bottom - d - 1, d, d, 0, 90);
            path.AddArc(r.Left, r.Bottom - d - 1, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    /// <summary>Liste deroulante au theme sombre, obtenue en dessinant les elements soi-meme.</summary>
    public class DarkComboBox : ComboBox
    {
        public DarkComboBox()
        {
            DropDownStyle = ComboBoxStyle.DropDownList;
            DrawMode = DrawMode.OwnerDrawFixed;
            FlatStyle = FlatStyle.Flat;
            BackColor = Color.FromArgb(44, 48, 58);
            ForeColor = Color.FromArgb(232, 236, 244);
            ItemHeight = 20;
        }

        protected override void OnDrawItem(DrawItemEventArgs e)
        {
            if (e.Index < 0) return;

            bool selected = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
            Color bg = selected ? Color.FromArgb(64, 104, 168) : Color.FromArgb(44, 48, 58);

            using (SolidBrush b = new SolidBrush(bg))
                e.Graphics.FillRectangle(b, e.Bounds);

            Rectangle text = new Rectangle(e.Bounds.X + 4, e.Bounds.Y, e.Bounds.Width - 8, e.Bounds.Height);
            TextRenderer.DrawText(e.Graphics, Items[e.Index].ToString(), e.Font, text,
                Enabled ? Color.FromArgb(232, 236, 244) : Color.FromArgb(130, 136, 150),
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            // Le petit triangle natif reste clair : on repeint le bord pour l'attenuer.
            using (Pen p = new Pen(Color.FromArgb(70, 76, 90)))
                e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
        }
    }

    /// <summary>Bouton plat au theme sombre, avec survol.</summary>
    public class DarkButton : Button
    {
        public DarkButton()
        {
            FlatStyle = FlatStyle.Flat;
            BackColor = Color.FromArgb(44, 48, 58);
            ForeColor = Color.FromArgb(232, 236, 244);
            FlatAppearance.BorderColor = Color.FromArgb(74, 80, 94);
            FlatAppearance.MouseOverBackColor = Color.FromArgb(56, 62, 74);
            FlatAppearance.MouseDownBackColor = Color.FromArgb(38, 42, 52);
            Cursor = Cursors.Hand;
        }
    }

    /// <summary>Applique le theme sombre a la barre de titre (Windows 10 1809 et suivants).</summary>
    public static class DarkTitleBar
    {
        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
        private const int DWMWA_USE_IMMERSIVE_DARK_MODE_OLD = 19;

        public static void Apply(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero) return;
            int on = 1;
            try
            {
                if (DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref on, sizeof(int)) != 0)
                    DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE_OLD, ref on, sizeof(int));
            }
            catch { /* versions de Windows anterieures : barre de titre claire, sans consequence */ }
        }
    }
}
