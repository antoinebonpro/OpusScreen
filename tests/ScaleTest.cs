using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using OpusScreen;

/// <summary>
/// Verifie que l'interface reste lisible sur un ecran a forte densite.
///
/// Le defaut a corriger, signale par une utilisatrice sur un portable regle a
/// 200 % : les titres etaient coupes en deux, les intitules des curseurs tranches
/// par leur propre reglette, les onglets abreges en « Daltonis... » et les boutons
/// en « Suspe... ». L'application etait inutilisable, et rien ne le disait.
///
/// La cause tient en deux moities qui ne parlaient pas la meme langue. Les polices
/// sont exprimees en POINTS : Windows les rend 1,5 ou 2 fois plus hautes selon le
/// reglage de l'ecran. Les boites qui les contiennent etaient des constantes en
/// PIXELS : elles ne bougeaient pas. Le texte debordait donc de sa boite.
///
/// Ce test monte la VRAIE fenetre a cinq echelles et mesure, controle par controle,
/// si le texte tient dans la place qu'on lui donne. C'est la seule facon de repondre
/// a « est-ce que ca marche partout » sans posseder toutes les machines.
/// </summary>
class ScaleTest
{
    static int fails = 0;

    static void Check(bool ok, string quoi)
    {
        if (!ok) { Console.WriteLine("  ECHEC : " + quoi); fails++; }
    }

    /// <summary>Les reglages que Windows propose, du plus courant au plus extreme.</summary>
    static readonly float[] Echelles = { 1.0f, 1.25f, 1.5f, 1.75f, 2.0f };

    [STAThread]
    static void Main()
    {
        foreach (float echelle in Echelles) Verifier(echelle);

        Console.WriteLine();
        Console.WriteLine(fails == 0 ? ">>> TOUS LES TESTS PASSENT" : ">>> " + fails + " ECHEC(S)");
        Environment.Exit(fails == 0 ? 0 : 1);
    }

    static void Verifier(float echelle)
    {
        Console.WriteLine();
        Console.WriteLine(string.Format("=== Ecran a {0:0} % ===", echelle * 100));

        // Ce que fait un ecran a forte densite : Windows agrandit les polices, et
        // l'application doit agrandir ses boites d'autant.
        Theme.FontSimulation = echelle;
        Theme.Scale = echelle;

        int coupes = 0, abreges = 0, petits = 0;
        try
        {
            Ui.Setup(2);
            Ui.P.Size = new Size(Theme.Px(1000), Theme.Px(760));
            Ui.Pump();

            foreach (SettingsPage page in Ui.Pages())
            {
                Ui.Show(page);
                Ui.Pump();

                // La fenetre ENTIERE, et pas seulement la page : l'en-tete et le pied
                // vivent en dehors, et c'est precisement la que le titre restait coupe
                // en deux apres une premiere correction. Un test qui ne regarde qu'une
                // partie de la fenetre declare saine une fenetre qui ne l'est pas.
                foreach (Control c in Ui.All(Ui.P))
                {
                    if (!c.Visible || c.Width < 2 || c.Height < 2) continue;

                    if (Coupe(c)) Rapporter(page.Title, c, "coupe", ref coupes);
                    if (Abrege(c)) Rapporter(page.Title, c, "abrege", ref abreges);
                    if (TropPetit(c)) Rapporter(page.Title, c, "sous la cible minimale", ref petits);
                }
            }

            // La colonne de navigation est le cas le plus visible : c'est la que
            // l'utilisatrice lisait « Daltonis... » au lieu de « Daltonisme ».
            foreach (Control it in Ui.All(Ui.P))
            {
                if (it.GetType().Name != "NavItem" || !it.Visible || it.Text.Length == 0) continue;
                int large = TexteLarge(it.Text, Theme.Body);
                Check(it.Width >= large + Theme.Px(46),
                      string.Format("l'onglet « {0} » est abrege a {1:0} % : {2} px de colonne pour {3} px de texte",
                                    it.Text, echelle * 100, it.Width, large));
            }
        }
        finally
        {
            try { Ui.Teardown(); } catch { }
            Theme.FontSimulation = 1f;
            Theme.Scale = 1f;
        }

        Check(coupes == 0, string.Format("{0} texte(s) coupe(s) a {1:0} %", coupes, echelle * 100));
        Check(abreges == 0, string.Format("{0} libelle(s) abrege(s) a {1:0} %", abreges, echelle * 100));
        Check(petits == 0, string.Format("{0} cible(s) de clic trop petite(s) a {1:0} %", petits, echelle * 100));
        if (coupes == 0 && abreges == 0 && petits == 0) Console.WriteLine("  OK");
    }

    /// <summary>Les cinq premiers cas suffisent : au-dela, la liste ne s'ecoute plus.</summary>
    static void Rapporter(string page, Control c, string quoi, ref int compteur)
    {
        compteur++;
        if (compteur <= 5)
            Console.WriteLine(string.Format("    {0} : {1} « {2} » ({3}x{4} px)",
                page, quoi, Court(c.Text), c.Width, c.Height));
    }

    static string Court(string t)
    {
        t = (t ?? "").Replace("\n", " ");
        return t.Length > 42 ? t.Substring(0, 42) + "..." : t;
    }

    /// <summary>
    /// Vrai si le texte demande plus de hauteur que sa boite n'en offre.
    ///
    /// La mesure se fait a la largeur REELLE du controle et avec retour a la ligne :
    /// une legende qui s'enroule sur trois lignes doit disposer de trois lignes, et
    /// un intitule d'une seule ligne ne doit pas etre tranche en deux.
    /// </summary>
    static bool Coupe(Control c)
    {
        Label l = c as Label;
        if (l == null || l.Text.Length == 0) return false;

        Size besoin = TextRenderer.MeasureText(l.Text, l.Font,
            new Size(Math.Max(1, l.Width), int.MaxValue), TextFormatFlags.WordBreak);
        return besoin.Height > l.Height + 1;
    }

    /// <summary>Vrai si un bouton n'a pas la place d'afficher son libelle en entier.</summary>
    static bool Abrege(Control c)
    {
        if (!(c is Button) || c.Text.Length == 0) return false;
        return TexteLarge(c.Text, c.Font) > c.Width - Theme.Px(16);
    }

    /// <summary>
    /// Vrai si une cible de clic est descendue sous le plancher. Un bouton de 36 px
    /// a 96 ppp doit en faire 72 sur un ecran a 200 %, sinon il devient
    /// physiquement plus petit qu'avant - l'inverse de ce que le reglage demande.
    /// </summary>
    static bool TropPetit(Control c)
    {
        if (!(c is Button)) return false;

        // Theme.MinTarget est DEJA exprime dans les pixels de l'ecran courant. Une
        // premiere version de ce test le remettait a l'echelle une seconde fois et
        // exigeait 144 pixels la ou 72 suffisaient : l'instrument accusait un code
        // correct. Une mesure fausse coute plus cher qu'une mesure absente.
        return c.Height < Theme.MinTarget - 2;
    }

    static int TexteLarge(string texte, Font police)
    {
        return TextRenderer.MeasureText(texte, police).Width;
    }
}
