using System;
using System.IO;
using OpusScreen;

class SafetyTest
{
    static int fails = 0;
    static void Check(bool ok, string what)
    {
        Console.WriteLine((ok ? "  OK    " : "  ECHEC ") + what);
        if (!ok) fails++;
    }

    static int Deviation()
    {
        int max = 0;
        foreach (MonitorInfo m in MonitorEnum.All())
        {
            Native.RampTable now = GammaEngine.Capture(m);
            Native.RampTable id = Native.RampTable.Identity();
            for (int i = 0; i < 256; i++)
            {
                max = Math.Max(max, Math.Abs(now.Red[i] - id.Red[i]));
                max = Math.Max(max, Math.Abs(now.Green[i] - id.Green[i]));
                max = Math.Max(max, Math.Abs(now.Blue[i] - id.Blue[i]));
            }
        }
        return max;
    }

    static void Main()
    {
        string flag = Path.Combine(Settings.DataFolder, "active.flag");

        Console.WriteLine("--- 1. Le pire scenario : 5 %, 1200 K, couleurs inversees ---");
        Profile bad = new Profile();
        bad.Brightness = 5; bad.Kelvin = 1200; bad.Filter = ColorFilter.Invert; bad.Saturation = 0;
        BrightnessPlan plan = GammaEngine.Plan(bad.Brightness, false, false);
        foreach (MonitorInfo m in MonitorEnum.All())
            GammaEngine.Apply(m, GammaEngine.BuildRamp(plan, bad));
        bool matrixOn = ColorMatrixEffect.Apply(bad.Saturation, bad.Filter);
        SafetyGuard.MarkDirty();

        Check(Deviation() > 10000, "LUT effectivement extreme (ecart " + Deviation() + ")");
        Console.WriteLine("        matrice plein ecran appliquee : " + matrixOn
            + (ColorMatrixEffect.Available ? "" : "  (indisponible sur ce systeme)"));

        Console.WriteLine();
        Console.WriteLine("--- 2. Restauration d'urgence : LUT ET matrice ---");
        SafetyGuard.EmergencyRestore();
        Check(Deviation() == 0, "LUT revenue a l'identite exacte");
        Check(!ColorMatrixEffect.IsActive, "matrice de couleur remise a l'identite");
        Check(!File.Exists(flag), "temoin efface");

        Console.WriteLine();
        Console.WriteLine("--- 3. Recuperation apres plantage ---");
        foreach (MonitorInfo m in MonitorEnum.All())
            GammaEngine.Apply(m, GammaEngine.BuildRamp(plan, bad));
        ColorMatrixEffect.Apply(0, ColorFilter.Invert);
        SafetyGuard.MarkDirty();
        Check(SafetyGuard.RecoverFromCrash(), "recuperation declenchee par le temoin");
        Check(Deviation() == 0, "ecran redevenu normal");
        Check(!ColorMatrixEffect.IsActive, "matrice neutralisee aussi");

        Console.WriteLine();
        Console.WriteLine("--- 4. Bornes : aucune valeur ne peut sortir de la plage ---");
        Profile p = new Profile();
        p.Brightness = -999; p.Contrast = 9999; p.Saturation = -50;
        p.RedGain = 1e9; p.GammaCurve = double.NaN; p.Kelvin = 99999;
        p.ClampAll();
        Check(p.Brightness == 5, "luminosite ramenee a 5 %");
        Check(p.Contrast == 150, "contraste ramene a 150");
        Check(p.Saturation == 0, "saturation ramenee a 0");
        Check(p.RedGain == 150, "gain rouge ramene a 150");
        Check(p.GammaCurve >= 50 && p.GammaCurve <= 200, "NaN ramene dans la plage");
        Check(p.Kelvin == 6500, "kelvin ramene a 6500");

        Console.WriteLine();
        Console.WriteLine("--- 5. Reglages par defaut coherents ---");
        Settings fresh = new Settings();
        // Le nombre suit la liste par defaut plutot qu'une constante recopiee : une
        // action ajoutee ne doit pas faire echouer un test qui ne la concerne pas.
        int expected = Settings.DefaultHotkeys().Count;
        Check(fresh.Hotkeys.Count == expected,
              expected + " raccourcis presents sans chargement de fichier");
        Check(fresh.Current.IsNeutral(), "profil de depart neutre");

        Console.WriteLine();
        Console.WriteLine("--- 6. Aller-retour de la configuration ---");
        Settings orig = new Settings();
        orig.Current.Brightness = 137.5; orig.Current.Kelvin = 2900;
        orig.Current.Saturation = 65; orig.Current.Filter = ColorFilter.Deuteranopia;
        orig.AdaptiveEnabled = true; orig.AdaptiveMax = 143;
        orig.CustomProfiles.Add(Profile.Deserialize("Test;120;3000;105;100;100;100;100;90;2;10,20,30"));
        orig.AppRules.Add(AppRule.Deserialize("vlc>Film>0"));
        orig.Hotkeys[0].Modifiers = 0x6; orig.Hotkeys[0].Key = 0x71;

        Settings back = Settings.FromText(orig.Export());
        Check(Math.Abs(back.Current.Brightness - 137.5) < 0.01, "luminosite conservee");
        Check(back.Current.Kelvin == 2900, "kelvin conserve");
        Check(back.Current.Filter == ColorFilter.Deuteranopia, "filtre conserve");
        Check(back.AdaptiveEnabled && Math.Abs(back.AdaptiveMax - 143) < 0.01, "adaptatif conserve");
        Check(back.CustomProfiles.Count == 1 && back.CustomProfiles[0].Name == "Test", "mode personnalise conserve");
        Check(back.AppRules.Count == 1 && back.AppRules[0].ProcessName == "vlc", "regle d'application conservee");
        Check(back.Hotkeys.Count == expected, "pas de doublon de raccourcis apres relecture");
        Check(back.Hotkeys[0].Key == 0x71 && back.Hotkeys[0].Modifiers == 0x6, "raccourci modifie conserve");

        Console.WriteLine();
        Console.WriteLine("--- 7. Politique de plein ecran ---");
        // Tout suspendre en plein ecran annulait un boost qui, lui, ne gene rien :
        // seul le voile a une raison d'etre retire.
        Check(new Settings().OnFullscreen == FullscreenSuspend.OverlayOnly,
              "par defaut, seul le voile est retire en plein ecran");

        Check(Settings.FromText("disableFullscreen=1").OnFullscreen == FullscreenSuspend.OverlayOnly,
              "ancienne case cochee -> voile seulement");
        Check(Settings.FromText("disableFullscreen=0").OnFullscreen == FullscreenSuspend.Never,
              "ancienne case decochee -> aucune suspension");

        Settings fs = new Settings();
        fs.OnFullscreen = FullscreenSuspend.Everything;
        Check(Settings.FromText(fs.Export()).OnFullscreen == FullscreenSuspend.Everything,
              "reglage conserve par l'aller-retour");
        Check(Settings.FromText("onFullscreen=0\ndisableFullscreen=1").OnFullscreen == FullscreenSuspend.Never,
              "la cle recente l'emporte sur l'ancienne");

        Console.WriteLine();
        Console.WriteLine("--- 8. Contrastes du theme (exigence 4.5:1) ---");
        double c1 = Theme.ContrastRatio(Theme.Fg, Theme.Card);
        double c2 = Theme.ContrastRatio(Theme.Dim, Theme.Card);
        double c3 = Theme.ContrastRatio(Theme.Accent, Theme.Card);
        double c4 = Theme.ContrastRatio(Theme.Fg, Theme.Sunken);
        Console.WriteLine(string.Format("        texte principal / carte : {0:0.00}:1", c1));
        Console.WriteLine(string.Format("        texte attenue  / carte : {0:0.00}:1", c2));
        Console.WriteLine(string.Format("        accent         / carte : {0:0.00}:1", c3));
        Console.WriteLine(string.Format("        texte principal / creux : {0:0.00}:1", c4));
        Check(c1 >= 4.5, "texte principal conforme");
        Check(c2 >= 4.5, "texte attenue conforme");
        Check(c3 >= 4.5, "accent conforme");
        Check(c4 >= 4.5, "texte sur fond creux conforme");

        Console.WriteLine();
        Console.WriteLine("--- 9. Etat final ---");
        SafetyGuard.EmergencyRestore();
        Console.WriteLine("        ecart LUT final : " + Deviation());

        Console.WriteLine();
        Console.WriteLine(fails == 0 ? ">>> TOUS LES TESTS PASSENT" : ">>> " + fails + " ECHEC(S)");
        Environment.Exit(fails == 0 ? 0 : 1);
    }
}
