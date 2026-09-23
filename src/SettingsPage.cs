using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace OpusScreen
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

        private static int Pad { get { return Theme.Px(24); } }

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
            Add(UiKit.SectionTitle(title), _items.Count == 0 ? Theme.Px(6) : Theme.SpaceXl);
            Add(UiKit.Divider(), Theme.Px(2));
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
            get { return Math.Max(Theme.Px(160), ClientSize.Width - Pad * 2 - (VerticalScroll.Visible ? Theme.Px(16) : 0)); }
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
                // Dans un panneau qui defile, Top se compte depuis le haut de la zone
                // VISIBLE, pas depuis le haut du contenu. Empiler depuis 14 sans tenir
                // compte du defilement posait donc la pile a partir de l'endroit ou l'on
                // se trouvait : une page defilee de 800 px voyait tout son contenu
                // descendre de 800 px a chaque redisposition - et rafraichir la page
                // Ecrans en declenchait une a chaque reglage.
                int y = Theme.Px(14) + AutoScrollPosition.Y;
                foreach (Item it in _items)
                {
                    if (!it.Control.Visible && it.Control.Height == 0) continue;

                    // Le texte mesure est celui que l'etiquette porte MAINTENANT, et
                    // non celui qu'on lui avait donne a la construction : la page
                    // Avance remplace le sien par l'etat reel du pilote, et sa boite
                    // restait calculee sur la chaine vide qu'elle contenait au depart.
                    if (it.WrapText != null)
                        it.Control.Height = HauteurDuTexte(TexteDe(it.Control, it.WrapText),
                                                           PoliceDe(it.Control), w);
                    else
                        GrandirPourSonTexte(it.Control, w);

                    y += it.Gap;
                    it.Control.SetBounds(Pad, y, w, it.Control.Height);
                    y += it.Control.Height;
                }
            }
            finally { ResumeLayout(true); }
        }

        /// <summary>
        /// Hauteur qu'il faut reserver a un texte pour qu'il tienne en entier.
        ///
        /// Mesuree avec TextRenderer, c'est-a-dire avec le MEME moteur que celui qui
        /// dessinera ces etiquettes. La version precedente mesurait avec
        /// Graphics.MeasureString - GDI+ - alors que Windows Forms peint un Label
        /// avec GDI : les deux ne coupent pas les lignes au meme endroit, et l'ecart
        /// se paie en texte tranche. Sur la page Confort, la boite calculee faisait
        /// 49 pixels pour un texte qui en demandait 60 : deux lignes lisibles, la
        /// troisieme coupee en son milieu, a 100 % comme a 200 %.
        /// </summary>
        private static int HauteurDuTexte(string text, Font police, int width)
        {
            Size besoin = TextRenderer.MeasureText(text, police,
                new Size(Math.Max(60, width), int.MaxValue), TextFormatFlags.WordBreak);
            return besoin.Height + 2;
        }

        /// <summary>
        /// Agrandit une etiquette dont le texte ne tient plus, sans jamais la
        /// retrecir.
        ///
        /// Certaines etiquettes recoivent leur texte APRES la mise en page - l'etat
        /// du pilote Intel, le resume du dernier test, le nombre d'applications au
        /// mixeur. Leur boite avait ete mesuree sur un texte vide : la page Avance en
        /// affichait une haute de deux pixels pour trois lignes d'explication. Le
        /// texte n'etait pas tronque, il etait invisible.
        ///
        /// On ne retrecit pas : une boite dessinee volontairement plus grande - pour
        /// aerer un titre de section - garde sa respiration.
        /// </summary>
        private static void GrandirPourSonTexte(Control c, int width)
        {
            Label l = c as Label;
            if (l == null || l.Text.Length == 0) return;

            int besoin = HauteurDuTexte(l.Text, PoliceDe(l), width);
            if (besoin > l.Height) l.Height = besoin;
        }

        private static Font PoliceDe(Control c)
        {
            return c.Font ?? Theme.Small;
        }

        /// <summary>Le texte affiche, ou celui d'origine si le controle n'en porte pas.</summary>
        private static string TexteDe(Control c, string origine)
        {
            return (c.Text != null && c.Text.Length > 0) ? c.Text : origine;
        }

        /// <summary>Recharge l'affichage a partir des reglages. Appelee a chaque ouverture.</summary>
        public abstract void Sync();

        /// <summary>
        /// Recharge, puis redispose la pile.
        ///
        /// L'ordre compte : Sync pose des textes dont on ne connait la longueur
        /// qu'a cet instant - l'etat du pilote, un resume, un compte. Sans la
        /// redisposition qui suit, ces textes attendaient le prochain
        /// redimensionnement de la fenetre pour obtenir leur place, c'est-a-dire
        /// souvent jamais.
        /// </summary>
        public void SyncAndLayout()
        {
            Sync();
            Relayout();
        }

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
