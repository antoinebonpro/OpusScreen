using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Curseur dessine a la main. Le TrackBar natif de Windows ne se theme pas et ne
    /// sait pas montrer qu'une partie de la course est particuliere - or ici il faut
    /// rendre visible la zone au-dela de 100 %, la ou l'on quitte le territoire des
    /// deux applications d'origine.
    /// </summary>
    public class Slider : Control
    {
        private double _min = 0, _max = 100, _value = 50;
        private bool _dragging;
        private double _markerValue = double.NaN;
        private double _warnAbove = double.NaN;

        public event EventHandler ValueChanged;
        /// <summary>Emis au relachement de la souris : c'est la que l'on confirme un reglage risque.</summary>
        public event EventHandler ValueCommitted;

        public Color RailColor = Color.FromArgb(58, 62, 72);
        public Color FillColor = Color.FromArgb(94, 160, 255);
        public Color WarnColor = Color.FromArgb(255, 168, 66);
        public Color KnobColor = Color.FromArgb(240, 244, 252);

        public Slider()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
                   | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw
                   | ControlStyles.SupportsTransparentBackColor, true);
            Height = 34;
            TabStop = true;
        }

        public double Minimum { get { return _min; } set { _min = value; Invalidate(); } }
        public double Maximum { get { return _max; } set { _max = value; Invalidate(); } }

        /// <summary>Graduation de reference, ex. 100 % = "etat normal".</summary>
        public double MarkerValue { get { return _markerValue; } set { _markerValue = value; Invalidate(); } }

        /// <summary>Au-dela de cette valeur, la barre change de couleur.</summary>
        public double WarnAbove { get { return _warnAbove; } set { _warnAbove = value; Invalidate(); } }

        public double Value
        {
            get { return _value; }
            set
            {
                double v = Math.Max(_min, Math.Min(_max, value));
                if (Math.Abs(v - _value) < 1e-9) return;
                _value = v;
                Invalidate();
                if (ValueChanged != null) ValueChanged(this, EventArgs.Empty);
            }
        }

        /// <summary>Modifie la valeur sans declencher d'evenement (synchronisation depuis le modele).</summary>
        public void SetValueSilent(double v)
        {
            _value = Math.Max(_min, Math.Min(_max, v));
            Invalidate();
        }

        private Rectangle RailRect
        {
            get
            {
                int y = Height / 2 - 3;
                return new Rectangle(10, y, Math.Max(1, Width - 20), 6);
            }
        }

        private double ValueFromX(int x)
        {
            Rectangle r = RailRect;
            double p = (x - r.Left) / (double)r.Width;
            p = Math.Max(0, Math.Min(1, p));
            return _min + p * (_max - _min);
        }

        private int XFromValue(double v)
        {
            Rectangle r = RailRect;
            double p = (v - _min) / (_max - _min);
            return r.Left + (int)Math.Round(p * r.Width);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;
            Focus();
            _dragging = true;
            Value = ValueFromX(e.X);
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (_dragging) Value = ValueFromX(e.X);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (!_dragging) return;
            _dragging = false;
            if (ValueCommitted != null) ValueCommitted(this, EventArgs.Empty);
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            base.OnMouseWheel(e);
            double step = (_max - _min) / 100.0;
            Value = _value + (e.Delta > 0 ? step : -step) * 3;
            if (ValueCommitted != null) ValueCommitted(this, EventArgs.Empty);
        }

        protected override bool IsInputKey(Keys key)
        {
            if (key == Keys.Left || key == Keys.Right) return true;
            return base.IsInputKey(key);
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            double step = (_max - _min) / 100.0;
            if (e.KeyCode == Keys.Left) { Value = _value - step; e.Handled = true; }
            else if (e.KeyCode == Keys.Right) { Value = _value + step; e.Handled = true; }
            if (e.Handled && ValueCommitted != null) ValueCommitted(this, EventArgs.Empty);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(BackColor);

            Rectangle rail = RailRect;

            // Grise quand le curseur est pilote automatiquement.
            Color fillCol = Enabled ? FillColor : Color.FromArgb(78, 84, 98);
            Color warnCol = Enabled ? WarnColor : Color.FromArgb(96, 90, 78);
            Color knobCol = Enabled ? KnobColor : Color.FromArgb(140, 146, 158);

            using (SolidBrush b = new SolidBrush(RailColor))
                FillRounded(g, b, rail, 3);

            // portion remplie, coupee a la valeur d'alerte si elle existe
            int knobX = XFromValue(_value);
            bool warn = !double.IsNaN(_warnAbove) && _value > _warnAbove;

            if (warn)
            {
                int warnX = XFromValue(_warnAbove);
                Rectangle normal = new Rectangle(rail.Left, rail.Top, warnX - rail.Left, rail.Height);
                Rectangle boost = new Rectangle(warnX, rail.Top, knobX - warnX, rail.Height);
                if (normal.Width > 0) using (SolidBrush b = new SolidBrush(fillCol)) FillRounded(g, b, normal, 3);
                if (boost.Width > 0) using (SolidBrush b = new SolidBrush(warnCol)) g.FillRectangle(b, boost);
            }
            else
            {
                Rectangle fill = new Rectangle(rail.Left, rail.Top, Math.Max(0, knobX - rail.Left), rail.Height);
                if (fill.Width > 0) using (SolidBrush b = new SolidBrush(fillCol)) FillRounded(g, b, fill, 3);
            }

            // graduation de reference
            if (!double.IsNaN(_markerValue))
            {
                int mx = XFromValue(_markerValue);
                using (Pen p = new Pen(Color.FromArgb(150, 160, 175), 1))
                {
                    g.DrawLine(p, mx, rail.Top - 6, mx, rail.Bottom + 6);
                }
            }

            // poignee
            int knobR = 9;
            Rectangle knob = new Rectangle(knobX - knobR, Height / 2 - knobR, knobR * 2, knobR * 2);
            using (SolidBrush shadow = new SolidBrush(Color.FromArgb(70, 0, 0, 0)))
                g.FillEllipse(shadow, knob.X + 1, knob.Y + 2, knob.Width, knob.Height);
            using (SolidBrush b = new SolidBrush(knobCol))
                g.FillEllipse(b, knob);
            using (Pen p = new Pen(warn ? warnCol : fillCol, 2))
                g.DrawEllipse(p, knob);

            if (Focused)
            {
                using (Pen p = new Pen(Color.FromArgb(120, 255, 255, 255), 1))
                    g.DrawEllipse(p, knob.X - 3, knob.Y - 3, knob.Width + 6, knob.Height + 6);
            }
        }

        private static void FillRounded(Graphics g, Brush b, Rectangle r, int radius)
        {
            if (r.Width <= 0 || r.Height <= 0) return;
            if (r.Width < radius * 2) { g.FillRectangle(b, r); return; }
            using (GraphicsPath path = new GraphicsPath())
            {
                int d = radius * 2;
                path.AddArc(r.Left, r.Top, d, d, 180, 90);
                path.AddArc(r.Right - d, r.Top, d, d, 270, 90);
                path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
                path.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
                path.CloseFigure();
                g.FillPath(b, path);
            }
        }
    }
}
