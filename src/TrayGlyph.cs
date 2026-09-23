using System;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace OpusScreen
{
    /// <summary>
    /// L'icone de la zone de notification, dessinee a la demande.
    ///
    /// Elle etait un disque plein dont la COULEUR disait l'etat de l'ecran. L'idee
    /// etait juste - un regard suffisait a savoir ce que l'application faisait - mais
    /// elle avait un defaut qu'aucun reglage ne corrigeait : au reglage par defaut,
    /// 100 % et 6500 K, cette couleur est blanche. L'utilisateur voyait donc un point
    /// blanc anonyme au milieu de vingt autres icones, et ne retrouvait pas son
    /// application. Une icone qui ne se reconnait pas est une application perdue.
    ///
    /// La forme reprend donc celle du logo - un oeil - et la couleur d'etat se
    /// deplace du disque entier vers la PUPILLE. On ne perd rien : la teinte du soir,
    /// la pastille de l'adaptation et la pause restent lisibles, mais a l'interieur
    /// d'une silhouette qui, elle, ne change jamais.
    ///
    /// Le dessin est TRACE a chaque taille plutot que reduit depuis le logo en pleine
    /// resolution : c'est la seule facon d'obtenir un 16x16 net, et c'est deja le
    /// choix fait par le generateur d'icone du projet.
    /// </summary>
    public static class TrayGlyph
    {
        /// <summary>Teal du logo. Il tient le contraste aussi bien sur une barre claire que sombre.</summary>
        private static readonly Color Trait = Color.FromArgb(255, 23, 190, 177);

        /// <summary>Gris neutre des effets suspendus : plus aucune couleur d'ecran annoncee.</summary>
        private static readonly Color TraitEteint = Color.FromArgb(255, 150, 156, 172);

        /// <summary>
        /// Dessine l'icone pour un etat donne.
        ///
        /// Fonction pure : elle ne lit aucun reglage global et ne touche a rien.
        /// C'est ce qui permet de la verifier par un test, ce qui etait impossible
        /// tant qu'elle vivait au milieu de la classe de la zone de notification.
        /// </summary>
        public static Bitmap Draw(int taille, Profile p, bool suspendu, bool adaptatif)
        {
            if (taille < 8) taille = 8;
            Bitmap bmp = new Bitmap(taille, taille);

            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);

                float u = taille / 32f;                    // tout est trace en unites de 32
                float epaisseur = Math.Max(1.4f, 2.6f * u);
                Color contour = suspendu ? TraitEteint : Trait;

                // Le halo du boost, sous l'oeil : au-dela de 100 %, l'application
                // ajoute vraiment de la lumiere, et cela se voit sur l'icone.
                if (!suspendu && p.Brightness > 100)
                {
                    Color vive = CouleurEtat(p);
                    using (SolidBrush halo = new SolidBrush(Color.FromArgb(60, vive)))
                        g.FillEllipse(halo, 0.5f * u, 4f * u, 31f * u, 24f * u);
                }

                using (GraphicsPath oeil = Amande(u))
                using (Pen stylo = new Pen(contour, epaisseur))
                {
                    stylo.LineJoin = LineJoin.Round;
                    g.DrawPath(stylo, oeil);
                }

                if (suspendu)
                {
                    // Deux barres, le signe universel de la pause. Elles prennent la
                    // place de la pupille : l'oeil est la, il ne regarde plus.
                    using (SolidBrush barre = new SolidBrush(TraitEteint))
                    {
                        g.FillRectangle(barre, 13f * u, 12f * u, 2.6f * u, 8f * u);
                        g.FillRectangle(barre, 17.4f * u, 12f * u, 2.6f * u, 8f * u);
                    }
                }
                else
                {
                    // La pupille porte l'etat : sa couleur est celle que l'ecran rend.
                    using (SolidBrush encre = new SolidBrush(CouleurEtat(p)))
                        g.FillEllipse(encre, 11f * u, 11f * u, 10f * u, 10f * u);

                    // Un cerne sombre separe une pupille tres claire du fond clair
                    // d'une barre des taches en theme clair.
                    using (Pen cerne = new Pen(Color.FromArgb(150, 12, 32, 38), Math.Max(1f, 1.4f * u)))
                        g.DrawEllipse(cerne, 11f * u, 11f * u, 10f * u, 10f * u);
                }

                if (adaptatif)
                {
                    // La luminosite adaptative agit toute seule : le dire evite de
                    // chercher pourquoi l'ecran bouge sans qu'on y touche.
                    using (SolidBrush pastille = new SolidBrush(Color.FromArgb(255, 86, 200, 130)))
                        g.FillEllipse(pastille, 22f * u, 22f * u, 9f * u, 9f * u);
                    using (Pen bord = new Pen(Color.FromArgb(170, 12, 32, 38), Math.Max(1f, 1.2f * u)))
                        g.DrawEllipse(bord, 22f * u, 22f * u, 9f * u, 9f * u);
                }
            }

            return bmp;
        }

        /// <summary>
        /// La silhouette en amande : deux courbes qui se rejoignent en pointe a
        /// gauche et a droite. C'est ce pincement lateral qui distingue l'oeil d'un
        /// disque, et il doit atteindre le bord - a 16 pixels, deux pixels de marge
        /// suffisent a transformer l'amande en rond.
        /// </summary>
        private static GraphicsPath Amande(float u)
        {
            GraphicsPath chemin = new GraphicsPath();
            PointF gauche = new PointF(1.5f * u, 16f * u);
            PointF droite = new PointF(30.5f * u, 16f * u);

            chemin.AddBezier(gauche,
                             new PointF(9f * u, 4.5f * u), new PointF(23f * u, 4.5f * u), droite);
            chemin.AddBezier(droite,
                             new PointF(23f * u, 27.5f * u), new PointF(9f * u, 27.5f * u), gauche);
            chemin.CloseFigure();
            return chemin;
        }

        /// <summary>
        /// La couleur que rend l'ecran avec ce profil : la temperature donne la
        /// teinte, la luminosite donne le niveau. Reprise telle quelle de l'ancien
        /// disque - c'est l'information qu'il ne fallait pas perdre en changeant de
        /// forme.
        /// </summary>
        public static Color CouleurEtat(Profile p)
        {
            double[] mult = ColorTemp.Multipliers(p.Kelvin);
            double b = p.Brightness / 150.0;
            int niveau = (int)Math.Round(58 + 195 * Math.Min(1.0, b * 1.15));
            return Color.FromArgb(255, Borne(niveau * mult[0]), Borne(niveau * mult[1]), Borne(niveau * mult[2]));
        }

        private static int Borne(double v) { return v < 0 ? 0 : (v > 255 ? 255 : (int)Math.Round(v)); }
    }
}
