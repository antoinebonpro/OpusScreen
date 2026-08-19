using System;
using System.Collections.Generic;
using System.Drawing;
using System.Reflection;
using System.Windows.Forms;
using OpusScreen;

/// <summary>
/// Verifie ce qui touche a l'accessibilite visuelle et a l'identification des ecrans.
///
/// Ces deux sujets ont en commun d'etre invisibles a l'usage courant : une correction
/// de daltonisme mal calibree ressemble a une correction bien calibree pour qui n'est
/// pas daltonien, et un identifiant d'ecran duplique ne se voit qu'avec deux ecrans du
/// meme modele sous la main. Ce sont donc exactement les regles qui doivent etre
/// tenues par un test plutot que par l'oeil.
/// </summary>
class VisionTest
{
    static int fails = 0;
    static void Check(bool ok, string what)
    {
        if (!ok) { Console.WriteLine("  ECHEC : " + what); fails++; }
    }

    static double[] Apply(float[] m, double r, double g, double b)
    {
        double rr = r, gg = g, bb = b;
        ColorMatrixEffect.Transform(m, ref rr, ref gg, ref bb);
        return new double[] { rr, gg, bb };
    }

    /// <summary>Matrice brute, sans bornage : indispensable pour verifier une identite.</summary>
    static double[] Raw(float[] m, double r, double g, double b)
    {
        double[] inp = { r, g, b, 1, 1 };
        double[] outp = new double[3];
        for (int j = 0; j < 3; j++)
        {
            double s = 0;
            for (int i = 0; i < 5; i++) s += inp[i] * m[i * 5 + j];
            outp[j] = s;
        }
        return outp;
    }

    static readonly ColorFilter[] Kinds = {
        ColorFilter.Protanopia, ColorFilter.Deuteranopia, ColorFilter.Tritanopia
    };

    [STAThread]
    static void Main()
    {
        TestSeverityZeroIsNeutral();
        TestGrayNeverDrifts();
        TestStrengthZeroIsNeutral();
        TestCorrectionSeparatesConfusedPairs();
        TestSimulationCollapsesPairs();
        TestInvertKeepHue();
        TestNeutralDetection();
        TestColorNaming();
        TestProfileRoundTrip();
        TestCommandLine();
        TestEveryCustomControlIsAnnounced();
        TestMonitorIdsAreUnique();

        Console.WriteLine();
        Console.WriteLine(fails == 0 ? ">>> TOUS LES TESTS PASSENT" : ">>> " + fails + " ECHEC(S)");
        Environment.Exit(fails == 0 ? 0 : 1);
    }

    // ------------------------------------------------------------------ gravite

    /// <summary>
    /// Gravite nulle = vision normale = aucune modification. C'est le contrat qui rend
    /// le curseur de gravite sur : quelqu'un qui le descend a zero doit retrouver son
    /// ecran exact, pas « presque » son ecran.
    /// </summary>
    static void TestSeverityZeroIsNeutral()
    {
        Console.WriteLine("=== Gravite 0 : aucune modification, dans les deux modes ===");
        foreach (ColorFilter f in Kinds)
        {
            foreach (FilterMode mode in new[] { FilterMode.Correction, FilterMode.Simulation })
            {
                float[] m = ColorMatrixEffect.BuildMatrix(100, f, 0, 100, mode);
                double[] o = Raw(m, 0.3, 0.6, 0.9);
                Check(Math.Abs(o[0] - 0.3) < 1e-4 && Math.Abs(o[1] - 0.6) < 1e-4 && Math.Abs(o[2] - 0.9) < 1e-4,
                      f + " / " + mode + " a gravite 0 doit etre l'identite");
            }
        }
        Console.WriteLine("  OK");
    }

    /// <summary>
    /// Le gris doit traverser le filtre sans prendre de teinte, a TOUTE gravite.
    ///
    /// C'est la propriete qui rend le filtre utilisable toute la journee : si les gris
    /// derivent, toute l'interface de Windows se colore et le filtre devient
    /// insupportable au bout d'une heure.
    /// </summary>
    static void TestGrayNeverDrifts()
    {
        Console.WriteLine();
        Console.WriteLine("=== Le gris ne prend jamais de teinte, quelle que soit la gravite ===");
        double worst = 0;
        foreach (ColorFilter f in Kinds)
            foreach (double sev in new double[] { 10, 25, 50, 75, 100 })
                foreach (double strength in new double[] { 50, 100, 150 })
                {
                    float[] m = ColorMatrixEffect.BuildMatrix(100, f, sev, strength, FilterMode.Correction);
                    foreach (double v in new double[] { 0.2, 0.5, 0.8 })
                    {
                        double[] o = Raw(m, v, v, v);
                        double spread = Math.Max(Math.Max(o[0], o[1]), o[2]) - Math.Min(Math.Min(o[0], o[1]), o[2]);
                        if (spread > worst) worst = spread;
                        Check(spread < 0.01, string.Format(
                            "{0} gravite {1} intensite {2} : gris {3} teinte de {4:0.000}", f, sev, strength, v, spread));
                        Check(Math.Abs(o[0] - v) < 0.01,
                            string.Format("{0} gravite {1} : le gris doit aussi garder sa clarte", f, sev));
                    }
                }
        Console.WriteLine(string.Format("  derive maximale mesuree : {0:0.00000}  (tolerance 0,01)", worst));
    }

    static void TestStrengthZeroIsNeutral()
    {
        Console.WriteLine();
        Console.WriteLine("=== Intensite 0 : la correction ne fait rien ===");
        foreach (ColorFilter f in Kinds)
        {
            float[] m = ColorMatrixEffect.BuildMatrix(100, f, 100, 0, FilterMode.Correction);
            double[] o = Raw(m, 0.8, 0.2, 0.4);
            Check(Math.Abs(o[0] - 0.8) < 1e-4 && Math.Abs(o[1] - 0.2) < 1e-4 && Math.Abs(o[2] - 0.4) < 1e-4,
                  f + " a intensite 0 doit etre l'identite");
        }
        Console.WriteLine("  OK");
    }

    // ------------------------------------------------------------------ efficacite reelle

    /// <summary>
    /// Le test qui justifie l'existence de la fonction.
    ///
    /// On prend les paires que la deficience confond, on les fait passer par la
    /// simulation - ce que la personne voit - puis par correction PUIS simulation -
    /// ce qu'elle verrait avec le filtre. L'ecart doit augmenter. Sinon le filtre
    /// change les couleurs sans rien apporter, ce qui est pire que de ne rien faire.
    /// </summary>
    static void TestCorrectionSeparatesConfusedPairs()
    {
        Console.WriteLine();
        Console.WriteLine("=== La correction ecarte bien les couleurs confondues ===");

        foreach (ColorFilter f in Kinds)
        {
            float[] sim = ColorMatrixEffect.BuildMatrix(100, f, 100, 100, FilterMode.Simulation);
            float[] fix = ColorMatrixEffect.BuildMatrix(100, f, 100, 100, FilterMode.Correction);

            int improved = 0;
            List<Vision.Pair> pairs = Vision.ConfusionPairs(f);

            foreach (Vision.Pair p in pairs)
            {
                Color beforeA = ColorMatrixEffect.Transform(sim, p.A);
                Color beforeB = ColorMatrixEffect.Transform(sim, p.B);
                Color afterA = ColorMatrixEffect.Transform(sim, ColorMatrixEffect.Transform(fix, p.A));
                Color afterB = ColorMatrixEffect.Transform(sim, ColorMatrixEffect.Transform(fix, p.B));

                double before = Vision.DeltaE(beforeA, beforeB);
                double after = Vision.DeltaE(afterA, afterB);
                if (after > before + 0.5) improved++;

                Console.WriteLine(string.Format("  {0,-14} {1,-26} avant {2,5:0.0}  apres {3,5:0.0}  {4}",
                    f, p.Label, before, after, after > before + 0.5 ? "+" : "="));

                // La colonne « aujourd'hui » du comparateur doit vraiment montrer deux
                // couleurs confondues : c'est tout le propos de la demonstration.
                Check(before <= Vision.JustNoticeable + 0.01, string.Format(
                    "{0} / {1} : la paire proposee doit etre indistinguable avant correction (ecart {2:0.0})",
                    f, p.Label, before));
            }

            Check(improved == pairs.Count, string.Format(
                "{0} : les {1} paires doivent gagner en ecart, {2} seulement",
                f, pairs.Count, improved));
        }
    }

    /// <summary>
    /// La simulation, elle, doit RAPPROCHER les paires : c'est ce qui fait qu'elle
    /// montre bien une confusion. Une simulation qui n'efface rien ne simule rien.
    /// </summary>
    static void TestSimulationCollapsesPairs()
    {
        Console.WriteLine();
        Console.WriteLine("=== La simulation rapproche bien ce que la deficience confond ===");

        foreach (ColorFilter f in Kinds)
        {
            float[] sim = ColorMatrixEffect.BuildMatrix(100, f, 100, 100, FilterMode.Simulation);
            List<Vision.Pair> pairs = Vision.ConfusionPairs(f);

            int collapsed = 0;
            foreach (Vision.Pair p in pairs)
            {
                double normal = Vision.DeltaE(p.A, p.B);
                double seen = Vision.DeltaE(ColorMatrixEffect.Transform(sim, p.A),
                                            ColorMatrixEffect.Transform(sim, p.B));
                if (seen < normal) collapsed++;
            }
            Check(collapsed == pairs.Count, string.Format(
                "{0} : les {1} paires doivent se rapprocher, {2} seulement", f, pairs.Count, collapsed));
            Console.WriteLine(string.Format("  {0,-14} {1}/{2} paires rapprochees", f, collapsed, pairs.Count));
        }
    }

    // ------------------------------------------------------------------ inversion douce

    static void TestInvertKeepHue()
    {
        Console.WriteLine();
        Console.WriteLine("=== Inversion a teintes conservees ===");
        float[] m = ColorMatrixEffect.BuildMatrix(100, ColorFilter.InvertKeepHue, 100, 100, FilterMode.Correction);

        double[] white = Apply(m, 1, 1, 1);
        double[] black = Apply(m, 0, 0, 0);
        Console.WriteLine(string.Format("  blanc -> ({0:0.00},{1:0.00},{2:0.00})   noir -> ({3:0.00},{4:0.00},{5:0.00})",
            white[0], white[1], white[2], black[0], black[1], black[2]));

        Check(white[0] < 0.02 && white[1] < 0.02 && white[2] < 0.02, "le blanc doit devenir noir");
        Check(black[0] > 0.98 && black[1] > 0.98 && black[2] > 0.98, "le noir doit devenir blanc");

        // Un rouge sombre doit ressortir clair ET rouge - c'est toute la difference
        // avec l'inversion classique, qui en ferait un cyan.
        double[] red = Apply(m, 0.7, 0.1, 0.1);
        Console.WriteLine(string.Format("  rouge sombre -> ({0:0.00},{1:0.00},{2:0.00})", red[0], red[1], red[2]));
        Check(red[0] > red[1] && red[0] > red[2], "le rouge doit rester la composante dominante");

        double[] gray = Apply(m, 0.5, 0.5, 0.5);
        Check(Math.Abs(gray[0] - gray[1]) < 0.01 && Math.Abs(gray[1] - gray[2]) < 0.01,
              "un gris doit rester gris");

        // Applique deux fois, on doit revenir au point de depart : la transformation
        // est une involution, ce qui garantit qu'aucune couleur ne derive a l'usage.
        double[] twice = Apply(m, 0.35, 0.55, 0.45);
        double[] back = Apply(m, twice[0], twice[1], twice[2]);
        Check(Math.Abs(back[0] - 0.35) < 0.01 && Math.Abs(back[1] - 0.55) < 0.01 && Math.Abs(back[2] - 0.45) < 0.01,
              "deux inversions successives doivent rendre la couleur d'origine");
        Console.WriteLine("  OK");
    }

    // ------------------------------------------------------------------ etat neutre

    static void TestNeutralDetection()
    {
        Console.WriteLine();
        Console.WriteLine("=== Detection de l'etat neutre ===");

        Check(ColorMatrixEffect.IsNeutralRequest(100, ColorFilter.None, 100, 100, FilterMode.Correction),
              "aucun filtre, saturation 100 : neutre");
        Check(ColorMatrixEffect.IsNeutralRequest(100, ColorFilter.Deuteranopia, 0, 100, FilterMode.Correction),
              "gravite 0 : neutre");
        Check(ColorMatrixEffect.IsNeutralRequest(100, ColorFilter.Deuteranopia, 100, 0, FilterMode.Correction),
              "intensite 0 en correction : neutre");
        Check(!ColorMatrixEffect.IsNeutralRequest(100, ColorFilter.Deuteranopia, 100, 0, FilterMode.Simulation),
              "en simulation, l'intensite ne doit PAS neutraliser");
        Check(!ColorMatrixEffect.IsNeutralRequest(120, ColorFilter.None, 100, 100, FilterMode.Correction),
              "saturation 120 : pas neutre");
        Check(!ColorMatrixEffect.IsNeutralRequest(100, ColorFilter.Sepia, 0, 0, FilterMode.Correction),
              "sepia n'est pas pilote par la gravite : pas neutre");

        Profile p = new Profile();
        Check(p.IsNeutral(), "un profil neuf est neutre");
        p.Filter = ColorFilter.Protanopia;
        Check(!p.IsNeutral(), "une correction active rend le profil non neutre");
        p.VisionSeverity = 0;
        Check(p.IsNeutral(), "gravite 0 : le profil redevient neutre");
        Console.WriteLine("  OK");
    }

    // ------------------------------------------------------------------ nom des couleurs

    /// <summary>
    /// L'identificateur de couleur est un outil de confiance : quelqu'un qui ne voit
    /// pas la difference entre un rouge et un vert ne peut pas verifier sa reponse.
    /// Se tromper de nom serait donc pire que ne rien dire.
    /// </summary>
    static void TestColorNaming()
    {
        Console.WriteLine();
        Console.WriteLine("=== Nom des couleurs ===");

        Check(Vision.NameOf(Color.FromArgb(255, 0, 0)) == "rouge", "255,0,0 doit se dire rouge");
        Check(Vision.NameOf(Color.FromArgb(0, 160, 70)).IndexOf("vert") >= 0, "0,160,70 doit contenir vert");
        Check(Vision.NameOf(Color.FromArgb(40, 100, 210)).IndexOf("bleu") >= 0, "40,100,210 doit contenir bleu");
        Check(Vision.NameOf(Color.White) == "blanc", "le blanc doit se dire blanc");
        Check(Vision.NameOf(Color.Black) == "noir", "le noir doit se dire noir");
        Check(Vision.NameOf(Color.FromArgb(128, 128, 128)) == "gris", "128,128,128 doit se dire gris");
        Check(Vision.NameOf(Color.FromArgb(246, 140, 30)).IndexOf("orange") >= 0, "246,140,30 doit contenir orange");

        // Un rouge et un vert de meme clarte ne doivent surtout pas porter le meme nom.
        Check(Vision.NameOf(Color.FromArgb(196, 64, 54)) != Vision.NameOf(Color.FromArgb(104, 132, 46)),
              "deux couleurs confondues par un daltonien doivent porter des noms differents");

        Check(Math.Abs(Vision.DeltaE(Color.Red, Color.Red)) < 1e-9, "l'ecart d'une couleur a elle-meme est nul");
        Check(Vision.DeltaE(Color.Black, Color.White) > 90, "noir et blanc doivent etre tres eloignes");
        Console.WriteLine("  OK  (" + Vision.DescribeColor(Color.FromArgb(20, 60, 30)) + " pour 20,60,30)");
    }

    // ------------------------------------------------------------------ persistance

    /// <summary>
    /// Les champs ajoutes ne doivent ni se perdre a l'enregistrement, ni rendre
    /// illisible un fichier ecrit par une version anterieure.
    /// </summary>
    static void TestProfileRoundTrip()
    {
        Console.WriteLine();
        Console.WriteLine("=== Enregistrement et relecture d'un profil ===");

        Profile p = new Profile();
        p.Name = "Essai";
        p.Filter = ColorFilter.Tritanopia;
        p.VisionSeverity = 62.5;
        p.FilterStrength = 118;
        p.Mode = FilterMode.Simulation;
        p.Kelvin = 3400;
        p.Tint = Color.FromArgb(10, 20, 30);

        Profile back = Profile.Deserialize(p.Serialize());
        Check(back.Filter == ColorFilter.Tritanopia, "le filtre survit a l'aller-retour");
        Check(Math.Abs(back.VisionSeverity - 62.5) < 0.01, "la gravite survit a l'aller-retour");
        Check(Math.Abs(back.FilterStrength - 118) < 0.01, "l'intensite survit a l'aller-retour");
        Check(back.Mode == FilterMode.Simulation, "le mode survit a l'aller-retour");
        Check(back.Kelvin == 3400 && back.Tint.B == 30, "les champs d'origine ne sont pas abimes");

        // Fichier d'une version anterieure : onze champs, sans les trois derniers.
        Profile old = Profile.Deserialize("Ancien;80;3000;100;100;100;100;100;100;5;0,0,0");
        Check(old.Name == "Ancien" && old.Kelvin == 3000, "un profil ancien reste lisible");
        Check(old.Filter == ColorFilter.Deuteranopia, "son filtre est bien relu");
        Check(Math.Abs(old.VisionSeverity - 100) < 0.01 && Math.Abs(old.FilterStrength - 100) < 0.01,
              "les champs absents prennent la valeur qui reproduit l'ancien comportement");
        Check(old.Mode == FilterMode.Correction, "un profil ancien est en correction");
        Console.WriteLine("  OK");
    }

    // ------------------------------------------------------------------ ligne de commande

    /// <summary>
    /// Les options d'accessibilite doivent etre reconnues aussi bien par la couleur
    /// mal percue que par le terme clinique : celui qui ecrit un script se souvient
    /// de « vert », pas de « deuteranopie ».
    /// </summary>
    static void TestCommandLine()
    {
        Console.WriteLine();
        Console.WriteLine("=== Ligne de commande ===");

        Settings s = new Settings();
        Check(CommandLine.ApplyTo(s, new string[] { "--vision", "vert" }), "--vision vert est pris en compte");
        Check(s.Current.Filter == ColorFilter.Deuteranopia, "vert -> deuteranopie");

        CommandLine.ApplyTo(s, new string[] { "--vision", "protanopie" });
        Check(s.Current.Filter == ColorFilter.Protanopia, "protanopie -> protanopie");

        CommandLine.ApplyTo(s, new string[] { "--vision", "blue" });
        Check(s.Current.Filter == ColorFilter.Tritanopia, "blue -> tritanopie");

        CommandLine.ApplyTo(s, new string[] { "--vision", "aucune" });
        Check(s.Current.Filter == ColorFilter.None, "aucune -> aucun filtre");

        CommandLine.ApplyTo(s, new string[] { "--severity", "65" });
        Check(Math.Abs(s.Current.VisionSeverity - 65) < 0.01, "--severity 65");

        CommandLine.ApplyTo(s, new string[] { "--severity", "999" });
        Check(Math.Abs(s.Current.VisionSeverity - 100) < 0.01, "une gravite hors plage est ramenee a 100");

        CommandLine.ApplyTo(s, new string[] { "--magnifier", "2.5" });
        Check(s.MagnifierEnabled && Math.Abs(s.MagnifierZoom - 2.5) < 0.01, "--magnifier 2.5 allume la loupe");

        CommandLine.ApplyTo(s, new string[] { "--magnifier", "1" });
        Check(!s.MagnifierEnabled, "--magnifier 1 l'eteint");

        CommandLine.ApplyTo(s, new string[] { "--beacon", "on" });
        Check(s.BeaconEnabled, "--beacon on");
        CommandLine.ApplyTo(s, new string[] { "--colors", "on" });
        Check(s.ColorReaderEnabled, "--colors on");

        Check(CommandLine.HasCommand(new string[] { "--vision", "vert" }),
              "--vision doit etre transmis a l'instance en cours");
        Check(!CommandLine.ApplyTo(s, new string[] { "--vision", "mauve" }),
              "une couleur inconnue ne doit rien changer");

        // Les options existantes ne doivent pas avoir bouge.
        Settings t = new Settings();
        CommandLine.ApplyTo(t, new string[] { "--brightness", "130", "--temp", "3400" });
        Check(Math.Abs(t.Current.Brightness - 130) < 0.01 && t.Current.Kelvin == 3400,
              "les anciennes options fonctionnent toujours");
        Console.WriteLine("  OK");
    }

    // ------------------------------------------------------------------ lecteurs d'ecran

    /// <summary>
    /// Aucun controle dessine a la main ne doit rester muet.
    ///
    /// Le README annonce « compatible lecteurs d'ecran ». Une affirmation pareille ne
    /// vaut que si elle est tenue par un test : un controle entierement peint par du
    /// code est, par defaut, un rectangle sans nom, sans role et sans valeur pour
    /// Windows. Il suffit d'en ajouter un pour que la promesse devienne fausse, et
    /// rien a l'ecran ne le signalerait - c'est justement le propre de ce defaut.
    ///
    /// La regle verifiee ici :
    ///   1. tout controle peint a la main declare un role, par la propriete ou par un
    ///      objet d'accessibilite dedie ;
    ///   2. tout controle atteignable au clavier (TabStop) repond a une touche.
    ///
    /// La seconde regle vient d'un cas reel : la bande de teintes de lecture etait
    /// atteignable au Tab et ne repondait a aucune touche. Un cul-de-sac au clavier,
    /// dans la page qui parle d'accessibilite.
    /// </summary>
    static void TestEveryCustomControlIsAnnounced()
    {
        Console.WriteLine();
        Console.WriteLine("=== Tout controle dessine a la main doit s'annoncer ===");

        const BindingFlags Any = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        int checkedCount = 0;

        foreach (Type t in typeof(Slider).Assembly.GetTypes())
        {
            // Seuls les controles peints a la main : ceux qui derivent directement de
            // Control. Un Button ou une ComboBox heritent d'un role de Windows.
            if (t.BaseType != typeof(Control)) continue;
            if (t.IsAbstract) continue;

            Control c = Instantiate(t);
            if (c == null)
            {
                Check(false, t.Name + " : le test ne sait pas l'instancier - a completer");
                continue;
            }

            using (c)
            {
                checkedCount++;

                MethodInfo custom = t.GetMethod("CreateAccessibilityInstance", Any);
                bool declaresRole = c.AccessibleRole != AccessibleRole.Default
                                 || (custom != null && custom.DeclaringType == t);

                Check(declaresRole, t.Name + " : doit declarer un role d'accessibilite");

                if (c.TabStop)
                {
                    MethodInfo key = t.GetMethod("OnKeyDown", Any);
                    bool operable = key != null && key.DeclaringType == t;
                    Check(operable, t.Name + " : atteignable au clavier, il doit repondre a une touche");
                }

                Console.WriteLine(string.Format("  {0,-16} role {1,-6} clavier {2}",
                    t.Name, declaresRole ? "oui" : "NON",
                    c.TabStop ? "requis" : "sans objet"));
            }
        }

        Check(checkedCount >= 8, "au moins huit controles peints a la main devraient exister, "
                               + checkedCount + " trouves - le test ne les voit-il plus ?");
    }

    /// <summary>
    /// Fabrique un controle sans connaitre sa signature. Retourne null si aucune des
    /// deux formes attendues ne convient - le test echoue alors plutot que d'ignorer
    /// silencieusement un controle qu'il aurait du couvrir.
    /// </summary>
    static Control Instantiate(Type t)
    {
        const BindingFlags Any = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;

        // Le constructeur le plus court d'abord : moins il demande d'arguments, moins
        // le test fabrique de valeurs arbitraires.
        List<ConstructorInfo> ctors = new List<ConstructorInfo>(t.GetConstructors(Any));
        ctors.Sort(delegate(ConstructorInfo a, ConstructorInfo b)
        {
            return a.GetParameters().Length.CompareTo(b.GetParameters().Length);
        });

        foreach (ConstructorInfo ctor in ctors)
        {
            ParameterInfo[] ps = ctor.GetParameters();
            object[] args = new object[ps.Length];
            bool ok = true;

            for (int i = 0; i < ps.Length && ok; i++)
            {
                Type p = ps[i].ParameterType;
                if (p == typeof(string)) args[i] = "";
                else if (p == typeof(int)) args[i] = 0;
                else if (p == typeof(bool)) args[i] = false;
                else if (p == typeof(double)) args[i] = 0.0;
                else if (p == typeof(Settings)) args[i] = new Settings();
                else if (p == typeof(MonitorInfo)) args[i] = new MonitorInfo();
                else ok = false;
            }
            if (!ok) continue;

            try { return (Control)ctor.Invoke(args); }
            catch { /* signature acceptee mais construction refusee : on essaie la suivante */ }
        }
        return null;
    }

    // ------------------------------------------------------------------ ecrans

    /// <summary>
    /// Deux ecrans du meme modele produisent le meme identifiant materiel. Sans levee
    /// d'ambiguite, ils partagent une seule fiche de reglages : le voile de l'un se
    /// pose sur l'autre et « eteindre cet ecran » en eteint deux. C'est exactement la
    /// configuration a deux ecrans la plus repandue.
    /// </summary>
    static void TestMonitorIdsAreUnique()
    {
        Console.WriteLine();
        Console.WriteLine("=== Identifiants d'ecran uniques ===");

        MethodInfo mi = typeof(MonitorEnum).GetMethod("DisambiguateIds",
            BindingFlags.NonPublic | BindingFlags.Static);
        Check(mi != null, "la levee d'ambiguite doit exister");
        if (mi == null) return;

        // Deux ecrans identiques branches sur deux sorties differentes.
        List<MonitorInfo> twins = new List<MonitorInfo>();
        twins.Add(Fake(0, "\\\\.\\DISPLAY1", "HW:DELA07E"));
        twins.Add(Fake(1, "\\\\.\\DISPLAY2", "HW:DELA07E"));
        mi.Invoke(null, new object[] { twins });

        Console.WriteLine("  deux ecrans identiques -> " + twins[0].StableId + "  |  " + twins[1].StableId);
        Check(twins[0].StableId != twins[1].StableId,
              "deux ecrans du meme modele doivent recevoir des identifiants differents");
        Check(twins[0].StableId.StartsWith("HW:DELA07E") && twins[1].StableId.StartsWith("HW:DELA07E"),
              "l'identifiant materiel doit rester reconnaissable");

        // Un ecran seul de son modele garde son identifiant : les reglages deja
        // memorises ne doivent pas etre perdus par la correction elle-meme.
        List<MonitorInfo> alone = new List<MonitorInfo>();
        alone.Add(Fake(0, "\\\\.\\DISPLAY1", "HW:DELA07E"));
        alone.Add(Fake(1, "\\\\.\\DISPLAY2", "HW:GSM5B09"));
        mi.Invoke(null, new object[] { alone });
        Check(alone[0].StableId == "HW:DELA07E" && alone[1].StableId == "HW:GSM5B09",
              "sans collision, aucun identifiant ne doit changer");

        // Trois ecrans identiques : cas des murs d'ecrans.
        List<MonitorInfo> three = new List<MonitorInfo>();
        for (int i = 0; i < 3; i++) three.Add(Fake(i, "\\\\.\\DISPLAY" + (i + 1), "HW:AUS24B1"));
        mi.Invoke(null, new object[] { three });
        Check(three[0].StableId != three[1].StableId
           && three[1].StableId != three[2].StableId
           && three[0].StableId != three[2].StableId,
              "trois ecrans identiques doivent recevoir trois identifiants distincts");

        Console.WriteLine("  OK");
    }

    static MonitorInfo Fake(int index, string device, string id)
    {
        MonitorInfo m = new MonitorInfo();
        m.Index = index;
        m.DeviceName = device;
        m.StableId = id;
        m.FriendlyName = "Ecran de test";
        return m;
    }
}
