using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows.Forms;
using OpusScreen;

/// <summary>
/// Photographie la VRAIE fenetre de reglages, onglet par onglet, pour le site.
///
/// Les captures d'un site vitrine mentent vite : on les prend une fois, puis
/// l'application change et plus personne ne les refait. Ici elles se regenerent
/// d'une commande - `run-tests.cmd captures` - a partir de la vraie interface, en
/// mode a blanc et avec des ecrans fictifs. Ce qui est montre est donc ce qui existe.
///
/// Usage : Shots.exe [dossier de sortie]
/// </summary>
class Shots
{
    static string _dir;

    [STAThread]
    static void Main(string[] args)
    {
        _dir = args.Length > 0 ? args[0] : "..\\site\\img";
        Directory.CreateDirectory(_dir);

        Ui.Setup(2);
        Ui.P.Size = new Size(1000, 760);
        Ui.P.Location = new Point(30, 30);

        // Un etat qui montre ce que fait l'application, plutot qu'une fenetre neutre.
        Ui.S.Current.Brightness = 78;
        Ui.S.Current.Kelvin = 4200;
        Ui.S.Current.Contrast = 104;
        Ui.S.Current.Saturation = 108;
        Ui.S.BreaksEnabled = true;
        Ui.P.SyncAll();
        ShowRealVersion();
        Ui.Pump();

        Shoot(Ui.P.Display1, "ecran.png");
        Shoot(Ui.P.ColorPage, "couleur.png");

        Ui.S.Current.Filter = ColorFilter.Deuteranopia;
        Ui.S.Current.VisionSeverity = 62;
        Ui.S.Current.FilterStrength = 100;
        Ui.S.VisionPresets.Clear();
        Ui.S.VisionPresets.Add(Preset("Mon ecran", ColorFilter.Deuteranopia, 62, 100));
        Ui.S.VisionPresets.Add(Preset("Cartes et graphiques", ColorFilter.Deuteranopia, 62, 130));
        Ui.S.LastExamSummary = DateTime.Now.ToString("dd/MM/yyyy") + " - vert mal percu, gravite 62 %";
        Ui.P.SyncAll();
        Ui.Pump();

        Shoot(Ui.PageTitled("Daltonisme"), "daltonisme.png");
        Shoot(Ui.P.ScreensPage, "ecrans.png");
        Shoot(Ui.P.ComfortPage, "confort.png");
        Shoot(Ui.P.VisionPage, "vision.png");

        ShootExam();

        Ui.Teardown();
        Console.WriteLine("Captures ecrites dans " + Path.GetFullPath(_dir));
    }

    /// <summary>
    /// La fenetre lit sa version dans l'assemblage qui l'execute : ici, l'outil de
    /// capture, qui n'en a pas. On y remet celle de l'application compilee - une
    /// capture qui annonce « version 0.0 » ferait douter de tout le reste.
    /// </summary>
    static void ShowRealVersion()
    {
        string exe = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(
            System.Reflection.Assembly.GetExecutingAssembly().Location), "..\\..\\OpusScreen.exe"));
        if (!File.Exists(exe)) return;

        System.Diagnostics.FileVersionInfo info = System.Diagnostics.FileVersionInfo.GetVersionInfo(exe);
        string text = "version " + info.FileMajorPart + "." + info.FileMinorPart;
        foreach (Control c in Ui.All(Ui.P))
        {
            Label l = c as Label;
            if (l != null && l.Text.StartsWith("version ")) l.Text = text;
        }
    }

    static VisionPreset Preset(string name, ColorFilter f, double severity, double strength)
    {
        VisionPreset p = new VisionPreset();
        p.Name = name; p.Filter = f; p.Severity = severity; p.Strength = strength;
        p.Mode = FilterMode.Correction;
        return p;
    }

    // ------------------------------------------------------------------ prise de vue

    static void Shoot(SettingsPage page, string file)
    {
        Ui.Show(page);
        Ui.ScrollTo(page, 0);
        Capture(Ui.P, file);
    }

    /// <summary>
    /// Copie d'ecran plutot que DrawToBitmap : tous les controles de cette
    /// application sont dessines a la main, et le rendu hors-ecran de WinForms en
    /// oublie une partie. Ce que l'on photographie ici est exactement ce que voit
    /// l'utilisateur.
    /// </summary>
    static void Capture(Form form, string file)
    {
        form.Activate();
        for (int i = 0; i < 6; i++) { Ui.Pump(); Thread.Sleep(60); }

        // Zone CLIENT seulement : la barre de titre appartient a Windows, pas a
        // l'application, et son theme varie d'une machine a l'autre. La montrer
        // ferait passer un detail du systeme pour un choix du logiciel.
        Rectangle r = form.RectangleToScreen(form.ClientRectangle);
        using (Bitmap bmp = new Bitmap(r.Width, r.Height))
        {
            using (Graphics g = Graphics.FromImage(bmp))
                g.CopyFromScreen(r.Location, Point.Empty, r.Size);
            string path = Path.Combine(_dir, file);
            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            Console.WriteLine("  " + file + "  " + r.Width + " x " + r.Height);
        }
    }

    // ------------------------------------------------------------------ test guide

    static void ShootExam()
    {
        using (VisionExamDialog dlg = new VisionExamDialog(Ui.S, Ui.D, 7))
        {
            dlg.StartPosition = FormStartPosition.Manual;
            dlg.Location = new Point(60, 60);
            dlg.Show();
            Ui.Pump();

            Capture(dlg, "test-accueil.png");

            dlg.Begin();
            Ui.Pump();
            Capture(dlg, "test-planche.png");

            // Repond comme une personne deuteranope moyenne : les planches vertes lui
            // echappent, les comparaisons suivent son seuil reel.
            const double vision = 70;
            int guard = 0;
            while (dlg.CurrentStep == VisionExamDialog.Step.Plates && guard++ < 40)
            {
                VisionPlate plate = dlg.CurrentPlate;
                if (plate == null) break;
                float[] sim = ColorMatrixEffect.BuildMatrix(100, ColorFilter.Deuteranopia, vision, 100,
                                                            FilterMode.Simulation);
                bool readable = Vision.DeltaE(ColorMatrixEffect.Transform(sim, plate.Figure),
                                              ColorMatrixEffect.Transform(sim, plate.Background))
                                >= VisionExam.JustNoticeable;
                dlg.AnswerPlate(readable ? plate.Digit : -1);
            }

            if (dlg.CurrentStep == VisionExamDialog.Step.Pairs)
            {
                // Quelques essais avant la photo : le premier montre l'ecart MAXIMAL,
                // deux couleurs franchement differentes. Le photographier donnerait
                // une image criarde qui ne ressemble pas au test reel, ou l'ecart se
                // resserre vite autour de la limite de la personne.
                for (int i = 0; i < 5 && dlg.CurrentStep == VisionExamDialog.Step.Pairs; i++)
                {
                    Color[] p = VisionExam.PairAt(dlg.Staircase.Axis, dlg.Staircase.Separation);
                    dlg.AnswerPair(VisionExam.PerceivedDelta(ColorFilter.Deuteranopia, vision, p[0], p[1])
                                   >= VisionExam.JustNoticeable);
                }

                Ui.Pump();
                Capture(dlg, "test-comparaison.png");

                guard = 0;
                while (dlg.CurrentStep == VisionExamDialog.Step.Pairs && guard++ < 80)
                {
                    Color[] pair = VisionExam.PairAt(dlg.Staircase.Axis, dlg.Staircase.Separation);
                    bool sees = VisionExam.PerceivedDelta(ColorFilter.Deuteranopia, vision, pair[0], pair[1])
                                >= VisionExam.JustNoticeable;
                    dlg.AnswerPair(sees);
                }
            }

            Ui.Pump();
            Capture(dlg, "test-resultat.png");
            dlg.Close();
        }
    }
}
