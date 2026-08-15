using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace LumaFlux
{
    /// <summary>
    /// Base commune a toutes les pages de reglages.
    ///
    /// Chaque page ne s'occupe que de son domaine et empile ses lignes ; le
    /// positionnement, le defilement et les marges sont geres ici une bonne fois.
    /// C'est ce qui permet d'ajouter un reglage en une ligne sans toucher a la mise
    /// en page.
    ///
    /// L'empilement est recalcule a chaque redimensionnement plutot que fige a la
    /// construction : les textes explicatifs ne connaissent leur nombre de lignes
    /// qu'une fois la largeur reelle connue.
    /// </summary>
    public abstract class SettingsPage : Panel
    {
        protected readonly Settings S;
        protected readonly DisplayController Display;
        protected readonly Action Push;
        protected bool Loading;

        private const int Pad = 24;

        private class Item
        {
            public Control Control;
            public int Gap;
            public string WrapText;   // non nul pour les textes explicatifs a remesurer
        }

        private readonly List<Item> _items = new List<Item>();
        private int _lastWidth = -1;

        protected SettingsPage(Settings s, DisplayController display, Action push)
        {
            S = s;
            Display = display;
            Push = push;

            BackColor = Theme.Card;
            AutoScroll = true;
        }

        /// <summary>Ajoute un controle a la suite du precedent.</summary>
        protected T Add<T>(T c, int gapBefore) where T : Control
        {
            Item it = new Item();
            it.Control = c;
            it.Gap = gapBefore;
            _items.Add(it);
            Controls.Add(c);
            return c;
        }

        protected T Add<T>(T c) where T : Control { return Add(c, Theme.SpaceSm); }

        protected void Section(string title)
        {
            Add(UiKit.SectionTitle(title), _items.Count == 0 ? 6 : Theme.SpaceXl);
            Add(UiKit.Divider(), 2);
        }

        /// <summary>Texte explicatif, dont la hauteur suit le nombre de lignes reellement occupees.</summary>
        protected Label Note(string text)
        {
            Label l = UiKit.Caption(text);
            Item it = new Item();
            it.Control = l;
            it.Gap = Theme.SpaceXs;
            it.WrapText = text;
            _items.Add(it);
            Controls.Add(l);
            return l;
        }

        protected int ContentWidth
        {
            get { return Math.Max(160, ClientSize.Width - Pad * 2 - (VerticalScroll.Visible ? 16 : 0)); }
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            if (ClientSize.Width != _lastWidth) Relayout();
        }

        protected override void OnVisibleChanged(EventArgs e)
        {
            base.OnVisibleChanged(e);
            if (Visible) Relayout();
        }

        /// <summary>Repositionne toute la pile. Peu couteux : quelques dizaines de controles.</summary>
        protected void Relayout()
        {
            int w = ContentWidth;
            if (w <= 160) return;
            _lastWidth = ClientSize.Width;

            SuspendLayout();
            try
            {
                int y = 14;
                foreach (Item it in _items)
                {
                    if (!it.Control.Visible && it.Control.Height == 0) continue;

                    if (it.WrapText != null)
                        it.Control.Height = MeasureWrapped(it.WrapText, w);

                    y += it.Gap;
                    it.Control.SetBounds(Pad, y, w, it.Control.Height);
                    y += it.Control.Height;
                }
            }
            finally { ResumeLayout(true); }
        }

        private static int MeasureWrapped(string text, int width)
        {
            using (Font f = Theme.Small)
            using (Bitmap b = new Bitmap(1, 1))
            using (Graphics g = Graphics.FromImage(b))
            {
                SizeF sz = g.MeasureString(text, f, Math.Max(60, width));
                return (int)Math.Ceiling(sz.Height) + 2;
            }
        }

        /// <summary>Recharge l'affichage a partir des reglages. Appelee a chaque ouverture.</summary>
        public abstract void Sync();

        /// <summary>Titre affiche en en-tete de la fenetre quand la page est active.</summary>
        public abstract string Title { get; }

        /// <summary>Sous-titre explicatif.</summary>
        public virtual string Subtitle { get { return ""; } }

        protected void Commit()
        {
            if (Loading) return;
            if (Push != null) Push();
            S.Save();
        }

        protected void CommitNoSave()
        {
            if (Loading) return;
            if (Push != null) Push();
        }
    }
}
