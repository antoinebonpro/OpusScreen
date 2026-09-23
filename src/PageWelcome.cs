using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// La page qui explique l'application - a quoi elle sert, ou elle se cache, et
    /// comment la garder sous la main.
    ///
    /// Elle existe parce qu'une application sans fenetre permanente pose un probleme
    /// que les autres n'ont pas : une fois lancee, elle DISPARAIT. Elle se range dans
    /// la zone de notification, que Windows 11 replie par defaut derriere un chevron,
    /// et l'utilisateur qui vient de la telecharger ne voit plus rien se passer. Le
    /// premier geste a lui apprendre n'est donc pas un reglage : c'est ou regarder.
    ///
    /// Elle s'ouvre d'elle-meme au tout premier lancement, et reste consultable comme
    /// n'importe quel onglet ensuite - le jour ou l'on change de machine, la question
    /// « ou est-elle passee » se repose a l'identique.
    /// </summary>
    public class PageWelcome : SettingsPage
    {
        private Label _raccourci;

        public override string Title { get { return "Decouvrir"; } }
        public override string Subtitle { get { return "A quoi sert OpusScreen, et ou la retrouver"; } }

        public PageWelcome(Settings s, DisplayController d, Action push) : base(s, d, push)
        {
            Section("A quoi sert cette application");

            Note("Elle regle la lumiere de votre ecran au-dela de ce que Windows autorise : la "
               + "luminosite descend a 5 % pour une piece sombre et monte a 150 % en plein jour, "
               + "la temperature de couleur retire le bleu le soir, et la partie daltonisme "
               + "ecarte les couleurs que l'oeil confond. Tout se regle ecran par ecran.");

            Note("Rien n'est installe : un seul fichier, pose ou vous voulez. Aucun compte, "
               + "aucune connexion reseau, aucune donnee transmise.");

            Section("Ou se trouve l'application");

            Note("Elle n'a pas de fenetre permanente. Une fois lancee, elle se range dans la ZONE "
               + "DE NOTIFICATION - en bas a droite, a cote de l'heure. C'est normal qu'elle "
               + "semble avoir disparu : elle travaille.");

            Note("Son icone est un oeil, et sa pupille prend la couleur que votre ecran rend a cet "
               + "instant : pale le jour, ambre le soir, grise quand les effets sont suspendus. "
               + "Un regard suffit donc a savoir ce qu'elle fait.");

            Note("Windows 11 replie les icones recentes derriere le chevron « ^ » de la barre des "
               + "taches. Pour la garder visible en permanence : cliquez sur ce chevron, puis "
               + "FAITES GLISSER l'oeil jusque sur la barre des taches. Il y reste ensuite.");

            DarkButton reglagesBarre = new DarkButton();
            reglagesBarre.Text = "Ouvrir les parametres de la barre des taches";
            reglagesBarre.Height = Theme.MinTarget;
            reglagesBarre.Click += OnOpenTaskbarSettings;
            Add(reglagesBarre, Theme.SpaceSm);

            Section("L'attacher en bas, une fois pour toutes");

            Note("Epingler OpusScreen pose son icone dans la barre des taches en permanence, meme "
               + "quand l'application ne tourne pas : un clic la relance, un clic droit ouvre "
               + "directement un mode ou une pause sans passer par les reglages.");

            DarkButton epingler = new DarkButton();
            epingler.Text = "Epingler OpusScreen a la barre des taches";
            epingler.Height = Theme.MinTarget;
            epingler.Click += OnPin;
            Add(epingler, Theme.SpaceSm);

            _raccourci = UiKit.Caption("");
            _raccourci.Height = 20;
            Add(_raccourci, Theme.SpaceXs);

            Note("Depuis Windows 10, aucune application ne peut s'epingler toute seule : le "
               + "systeme reserve ce geste a l'utilisateur, et le lui reserve expres. Le bouton "
               + "prepare donc le raccourci et vous amene dessus - le dernier clic vous revient.");

            Section("Les trois gestes du quotidien");

            Note("MOLETTE sur l'icone : la luminosite monte et descend, sans rien ouvrir. C'est le "
               + "geste le plus utile de l'application.");

            Note("CLIC GAUCHE sur l'icone : cette fenetre de reglages.");

            Note("CLIC DROIT sur l'icone : les modes prets a l'emploi, la pause et la remise a "
               + "zero. Les memes se retrouvent au clic droit sur l'icone epinglee.");

            Section("Si jamais l'ecran devient illisible");

            Note("Ctrl + Alt + Maj + R retablit un ecran strictement normal, meme si "
               + "l'application ne repond plus. Le raccourci est pose aupres de Windows, pas "
               + "dans la fenetre : il fonctionne aussi quand plus rien d'autre ne repond.");

            Note("Et si la machine s'eteint brutalement pendant qu'un reglage est actif, "
               + "l'application le detecte au demarrage suivant et rend l'ecran d'elle-meme.");
        }

        private void OnPin(object sender, EventArgs e)
        {
            Taskbar.PinWithGuidance(FindForm());
            UpdateShortcutState();
        }

        /// <summary>
        /// Ouvre le panneau de Windows qui regle les icones de la zone de
        /// notification. On ne peut pas y placer l'icone a la place de l'utilisateur -
        /// aucune application ne le peut - mais on peut lui epargner la chasse dans
        /// les parametres.
        /// </summary>
        private void OnOpenTaskbarSettings(object sender, EventArgs e)
        {
            try { Process.Start("ms-settings:taskbar"); }
            catch
            {
                MessageBox.Show(FindForm(),
                    "Les parametres de la barre des taches n'ont pas pu etre ouverts.\n\n"
                  + "Ils se trouvent dans : Parametres de Windows, Personnalisation, "
                  + "Barre des taches, Autres icones de la barre d'etat systeme.",
                    "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void UpdateShortcutState()
        {
            bool pose = false;
            try { pose = File.Exists(Taskbar.ShortcutPath); }
            catch { }

            _raccourci.Text = pose
                ? "Raccourci en place dans le menu Demarrer : OpusScreen s'y trouve deja."
                : "Aucun raccourci dans le menu Demarrer pour l'instant.";
        }

        public override void Sync()
        {
            Loading = true;
            try { UpdateShortcutState(); }
            finally { Loading = false; }
        }
    }
}
