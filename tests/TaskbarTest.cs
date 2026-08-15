using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using OpusScreen;

/// <summary>
/// Verifie ce dont depend l'epinglage a la barre des taches : une icone complete,
/// un raccourci que le shell sait relire, et une liste de taches acceptee.
///
/// Le raccourci est ecrit dans un dossier temporaire, jamais dans le menu Demarrer :
/// un test ne doit rien laisser derriere lui.
/// </summary>
class TaskbarTest
{
    static int fails = 0;

    static void Check(bool ok, string what)
    {
        Console.WriteLine((ok ? "  OK    " : "  ECHEC ") + what);
        if (!ok) fails++;
    }

    /// <summary>
    /// Nombre d'icones contenues dans un fichier. Icon.ExtractAssociatedIcon ne
    /// convient pas ici : il rend l'icone generique de Windows quand le fichier n'en
    /// contient aucune, et le test passerait sur un executable sans icone.
    /// </summary>
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int ExtractIconEx(string file, int index, IntPtr[] large, IntPtr[] small, int count);

    [STAThread]
    static int Main()
    {
        Console.WriteLine("--- 1. Icone de l'application ---");

        string ico = Path.GetFullPath(Path.Combine(
            AppDomain.CurrentDomain.BaseDirectory, @"..\..\assets\OpusScreen.ico"));
        bool present = File.Exists(ico);
        Check(present, "assets\\OpusScreen.ico present");

        if (present)
        {
            // Toutes ces tailles sont demandees par Windows selon la mise a l'echelle
            // de l'ecran ; celle qui manque donne une icone floue ou vide.
            int[] sizes = { 16, 20, 24, 32, 40, 48, 64, 128 };
            bool all = true;
            foreach (int s in sizes)
            {
                try
                {
                    using (Icon i = new Icon(ico, s, s))
                    using (Bitmap b = i.ToBitmap())
                        if (i.Width != s) all = false;
                }
                catch { all = false; }
            }
            Check(all, "chaque taille de 16 a 128 se charge et se dessine");
        }

        string exe = Path.GetFullPath(Path.Combine(
            AppDomain.CurrentDomain.BaseDirectory, @"..\..\OpusScreen.exe"));
        if (File.Exists(exe))
        {
            int count = 0;
            try { count = ExtractIconEx(exe, -1, null, null, 0); }
            catch { }
            Check(count > 0, "OpusScreen.exe porte une icone en ressource Win32");
        }
        else
        {
            Console.WriteLine("  (OpusScreen.exe absent : verification de la ressource Win32 sautee)");
        }

        Console.WriteLine();
        Console.WriteLine("--- 2. Raccourci ---");

        string lnk = Path.Combine(Path.GetTempPath(), "OpusScreenTest.lnk");
        try { if (File.Exists(lnk)) File.Delete(lnk); }
        catch { }

        bool written = false;
        try
        {
            Taskbar.WriteShortcut(lnk, "--show", "Raccourci de verification");
            written = File.Exists(lnk);
        }
        catch (Exception ex) { Console.WriteLine("  " + ex.Message); }
        Check(written, "le raccourci s'ecrit");

        if (written)
        {
            string target = Taskbar.ReadShortcutTarget(lnk);
            Check(string.Equals(target, Taskbar.ExecutablePath, StringComparison.OrdinalIgnoreCase),
                  "sa cible est relue a l'identique");
        }

        try { if (File.Exists(lnk)) File.Delete(lnk); }
        catch { }
        Check(!File.Exists(lnk), "le test ne laisse rien derriere lui");

        Console.WriteLine();
        Console.WriteLine("--- 3. Liste de taches ---");

        bool published = Taskbar.PublishJumpList(false);
        Check(published, "le shell accepte la liste de raccourcis rapides");

        // Publiee sous l'identite de ce programme de test, elle n'a plus lieu d'etre.
        Taskbar.ClearJumpList();

        Console.WriteLine();
        Console.WriteLine("--- 4. Reconnaissance du verbe d'epinglage ---");

        // Libelles releves sur Windows 11 francais et anglais. Les accents sont ecrits
        // en echappement Unicode : le reste du projet s'en passe, et l'encodage du
        // fichier source ne doit pas decider du resultat d'un test.
        Check(Taskbar.IsPinVerb("&Épingler à la barre des tâches"),
              "\"Epingler a la barre des taches\" reconnu");
        Check(Taskbar.IsPinVerb("Pin to tas&kbar"),
              "\"Pin to taskbar\" reconnu");
        Check(!Taskbar.IsPinVerb("Désépingler de la b&arre des tâches"),
              "\"Desepingler de la barre des taches\" refuse");
        Check(!Taskbar.IsPinVerb("Unpin from tas&kbar"),
              "\"Unpin from taskbar\" refuse");
        Check(!Taskbar.IsPinVerb("&Épingler au menu Démarrer"),
              "l'epinglage au menu Demarrer n'est pas confondu");

        Console.WriteLine();
        Console.WriteLine("--- 5. Ordres de la barre des taches ---");

        Check(CommandLine.HasCommand(new string[] { "--show" }),
              "--show est transmis a l'instance en cours");
        Check(CommandLine.WantsShow(new string[] { "--show" }),
              "--show demande explicitement la fenetre");
        Check(!CommandLine.WantsShow(new string[] { "--pause" }),
              "un autre ordre ne l'ouvre pas");
        Check(!CommandLine.HasCommand(new string[] { "--minimized" }),
              "--minimized reste une option de demarrage, pas un ordre");

        Console.WriteLine();
        Console.WriteLine(fails == 0 ? "TaskbarTest : tout passe" : "TaskbarTest : " + fails + " echec(s)");
        return fails == 0 ? 0 : 1;
    }
}
