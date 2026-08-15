using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// L'icone de l'application - celle de la barre des taches, de l'explorateur et
    /// de la barre de titre. A ne pas confondre avec l'icone de la zone de
    /// notification, redessinee en permanence par TrayApp pour refleter l'etat.
    ///
    /// Le meme fichier .ico est embarque deux fois dans l'executable : en ressource
    /// Win32, seule forme que le shell sait lire pour peindre l'icone d'un programme,
    /// et en ressource managee, la seule que le code puisse relire pour choisir la
    /// taille exacte demandee par l'ecran courant.
    /// </summary>
    public static class AppIcon
    {
        private const string ResourceName = "OpusScreen.ico";

        private static Icon _icon;
        private static bool _loaded;

        /// <summary>Icone multi-taille, ou null si l'executable a ete compile sans.</summary>
        public static Icon Window
        {
            get
            {
                if (_loaded) return _icon;
                _loaded = true;

                try
                {
                    using (Stream st = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName))
                    {
                        // La taille demandee suit la mise a l'echelle de l'ecran ; l'objet
                        // conserve le fichier entier, ce qui laisse Windows Forms en tirer
                        // ensuite le 16x16 de la barre de titre.
                        if (st != null) _icon = new Icon(st, SystemInformation.IconSize);
                    }
                }
                catch { _icon = null; }

                if (_icon == null)
                {
                    try { _icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
                    catch { _icon = null; }
                }

                return _icon;
            }
        }

        /// <summary>Habille une fenetre, sans consequence si l'icone manque.</summary>
        public static void ApplyTo(Form form)
        {
            Icon i = Window;
            if (i == null) return;
            form.Icon = i;
            form.ShowIcon = true;
        }
    }
}
