using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using OpusScreen;

/// <summary>
/// Tests d'interface : clics, glisser, molette, defilement, plusieurs ecrans.
///
/// Chaque test correspond a un defaut constate a l'usage, et decrit ce que
/// l'utilisateur doit pouvoir faire - pas la facon dont le code s'y prend. Ils
/// tournent sur la vraie fenetre, en mode a blanc, avec trois ecrans fictifs.
/// </summary>
class UiTest
{
    static int fails = 0;
    static void Check(bool ok, string what)
    {
        if (!ok) { Console.WriteLine("  ECHEC : " + what); fails++; }
    }

    static void Run(string name, Action t)
    {
        Console.WriteLine("- " + name);
        int before = Ui.Errors.Count;
        try { t(); }
        catch (Exception e) { Check(false, "exception : " + e.GetType().Name + " " + e.Message + "\n" + e.StackTrace); }
        for (int i = before; i < Ui.Errors.Count; i++) Check(false, "exception dans l'interface : " + Ui.Errors[i]);
    }

    [STAThread]
    static void Main()
    {
        Ui.Setup(3);
        Ui.P.Size = Ui.P.MinimumSize;   // la plus petite fenetre : c'est la qu'on defile
        Ui.Pump();

        Run("Ecrans : un rafraichissement ne reconstruit pas les cartes", TestScreensNotRebuilt);
        Run("Ecrans : glisser le curseur d'un ecran va jusqu'au bout", TestScreensDrag);
        Run("Ecrans : cliquer en bas de page ne fait pas sauter la page", TestScreensClickKeepsScroll);
        Run("Ecrans : un clic sur un interrupteur ne bascule que cet ecran", TestScreensToggleIsolated);
        Run("Ecrans : copier les reglages d'un ecran sur les autres", TestScreensCopyToOthers);
        Run("Ecrans : remettre tous les ecrans sur le reglage general", TestScreensSyncAll);
        Run("Ecrans : « Lier tous les ecrans » relie vraiment chaque ecran", TestLinkReallyLinks);
        Run("Ecrans : un mode choisi atteint meme un ecran regle a part", TestModeReachesEveryScreen);
        Run("Ecrans : un ecran verrouille ne suit aucun mode", TestLockedScreenIgnoresModes);
        Run("Molette : survoler un curseur ne le modifie pas, la page defile", TestWheelScrollsPage);
        Run("Molette : un curseur actif et survole se regle a la molette", TestWheelFocusedSlider);
        Run("Molette : une liste deroulante fermee ne change pas de choix", TestWheelCombo);
        Run("Souris : capture perdue en plein glisser, le curseur s'arrete", TestCaptureLost);
        Run("Souris : un double-clic sur un interrupteur compte deux clics", TestDoubleClickToggle);
        Run("Mise en page : redisposer une page defilee ne la decale pas", TestRelayoutWhileScrolled);
        Run("Navigation : tous les onglets tiennent dans la colonne", TestNavFits);
        Run("Navigation : Ctrl + chiffre ouvre chaque page", TestNavShortcuts);
        Run("Daltonisme : onglet dedie, reglages relies", TestColorBlindPage);
        Run("Daltonisme : le test guide trouve la deficience et l'applique", TestGuidedExam);
        Run("Daltonisme : le test guide rend l'ecran a la sortie", TestExamRestoresScreen);
        Run("Daltonisme : enregistrer, appliquer et supprimer un reglage", TestPresets);
        Run("Daltonisme : l'interrupteur de demarrage suit les reglages", TestStartupToggle);
        Run("Pages : un rafraichissement ne modifie aucun reglage", TestSyncIsPure);
        Run("Pages : chaque interrupteur repond au clic et revient", TestEveryToggleResponds);

        Ui.Teardown();
        Console.WriteLine();
        Console.WriteLine(fails == 0 ? ">>> TOUS LES TESTS PASSENT" : ">>> " + fails + " ECHEC(S)");
        Environment.Exit(fails == 0 ? 0 : 1);
    }

    // ------------------------------------------------------------------ outils

    static List<MonitorCard> Cards()
    {
        return Ui.AllOf<MonitorCard>(Ui.P.ScreensPage);
    }

    static Slider FirstVisibleSlider(Control root)
    {
        foreach (Slider s in Ui.AllOf<Slider>(root)) if (s.Visible && s.Enabled) return s;
        return null;
    }

    /// <summary>Fait defiler la page pour amener le controle a 40 px du haut.</summary>
    static void Reveal(SettingsPage page, Control c)
    {
        int y = page.PointToClient(c.PointToScreen(Point.Empty)).Y;
        Ui.ScrollTo(page, Math.Max(0, Ui.ScrollY(page) + y - 40));
    }

    static DarkButton ButtonStarting(Control root, string prefix)
    {
        foreach (DarkButton b in Ui.AllOf<DarkButton>(root))
            if (b.Text.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return b;
        return null;
    }

    static void ResetMonitors()
    {
        Ui.S.LinkMonitors = true;
        foreach (MonitorInfo m in Ui.D.Monitors)
        {
            MonitorSettings ms = Ui.S.For(m);
            ms.Independent = false; ms.BrightnessOffset = 0; ms.Own = new Profile();
            ms.Blackout = false; ms.Enabled = true; ms.Locked = false;
        }
        Ui.P.RefreshReadouts(); Ui.Pump();
    }

    // ------------------------------------------------------------------ ecrans

    /// <summary>
    /// La page Ecrans detruisait et recreait toutes ses cartes a chaque
    /// rafraichissement - donc a chaque mouvement de curseur et toutes les 20 s.
    /// Le controle sous la souris disparaissait pendant qu'on s'en servait.
    /// </summary>
    static void TestScreensNotRebuilt()
    {
        Ui.Show(Ui.P.ScreensPage);
        List<MonitorCard> before = Cards();
        Check(before.Count == 3, "3 cartes attendues, " + before.Count + " trouvees");
        Ui.P.RefreshReadouts();
        Ui.Pump();
        List<MonitorCard> after = Cards();
        bool same = before.Count == after.Count;
        for (int i = 0; same && i < before.Count; i++) same = ReferenceEquals(before[i], after[i]) && !after[i].IsDisposed;
        Check(same, "les cartes ont ete reconstruites par un simple rafraichissement");
    }

    static void TestScreensDrag()
    {
        SettingsPage page = Ui.Show(Ui.P.ScreensPage);
        MonitorCard card = Cards()[1];
        Slider s = FirstVisibleSlider(card);
        Check(s != null, "curseur de decalage introuvable");
        if (s == null) return;
        Reveal(page, s);

        MonitorSettings ms = Ui.S.For(Ui.D.Monitors[1]);
        ms.BrightnessOffset = 0;
        Ui.P.RefreshReadouts(); Ui.Pump();
        s = FirstVisibleSlider(Cards()[1]);

        int y = s.Height / 2;
        int x0 = Ui.XFor(s, 0);
        Ui.Down(s, new Point(x0, y));
        for (int k = 1; k <= 10; k++) Ui.Move(s, new Point(x0 + (s.Width - x0) * k / 10, y), true);
        Ui.Up(s, new Point(s.Width - 2, y));
        Ui.Pump();

        Check(!s.IsDisposed, "le curseur a ete detruit pendant qu'on le faisait glisser");
        Check(ms.BrightnessOffset > 40, "le decalage aurait du suivre la souris jusqu'au bout (obtenu "
            + ms.BrightnessOffset + ")");
        ResetMonitors();
        Ui.ScrollTo(page, 0);
    }

    static void TestScreensClickKeepsScroll()
    {
        SettingsPage page = Ui.Show(Ui.P.ScreensPage);
        Check(page.VerticalScroll.Visible, "la page Ecrans devrait defiler a cette taille");
        Ui.ScrollTo(page, 10000);
        int scroll = Ui.ScrollY(page);
        Check(scroll > 0, "la page n'a pas defile");

        MonitorCard card = Cards()[2];
        ToggleSwitch sw = null;
        foreach (ToggleSwitch t in Ui.AllOf<ToggleSwitch>(card)) if (Ui.FullyVisible(t)) sw = t;
        Check(sw != null, "aucun interrupteur visible sur la derniere carte");
        if (sw == null) return;

        int topBefore = card.PointToScreen(Point.Empty).Y;
        Ui.Click(sw);
        Check(Ui.ScrollY(page) == scroll, "la page a saute de " + scroll + " a " + Ui.ScrollY(page) + " apres un clic");
        Check(!card.IsDisposed && card.PointToScreen(Point.Empty).Y == topBefore,
            "la carte a bouge a l'ecran apres un clic");
        if (!sw.IsDisposed) Ui.Click(sw);
        Check(Ui.ScrollY(page) == scroll, "la page a saute au second clic");
        ResetMonitors();
        Ui.ScrollTo(page, 0);
    }

    static void TestScreensToggleIsolated()
    {
        SettingsPage page = Ui.Show(Ui.P.ScreensPage);
        ResetMonitors();

        // Deuxieme interrupteur visible de la deuxieme carte : « Ecran eteint ».
        List<ToggleSwitch> sws = new List<ToggleSwitch>();
        foreach (ToggleSwitch t in Ui.AllOf<ToggleSwitch>(Cards()[1])) if (t.Visible && t.Parent.Visible) sws.Add(t);
        Check(sws.Count >= 2, "interrupteurs de carte introuvables");
        if (sws.Count < 2) return;
        Reveal(page, sws[1]);
        Ui.Click(sws[1]);
        Check(Ui.S.For(Ui.D.Monitors[1]).Blackout, "l'ecran 2 aurait du s'eteindre");
        Check(!Ui.S.For(Ui.D.Monitors[0]).Blackout && !Ui.S.For(Ui.D.Monitors[2]).Blackout,
            "un autre ecran a ete eteint");
        ResetMonitors();
        Ui.ScrollTo(page, 0);
    }

    static void TestScreensCopyToOthers()
    {
        SettingsPage page = Ui.Show(Ui.P.ScreensPage);
        Ui.S.LinkMonitors = false;
        MonitorSettings a = Ui.S.For(Ui.D.Monitors[0]);
        a.Independent = true;
        a.Own.Brightness = 72;
        a.Own.Kelvin = 4200;
        a.BrightnessOffset = 12;
        Ui.P.RefreshReadouts(); Ui.Pump();

        DarkButton copy = ButtonStarting(Cards()[0], "Copier");
        Check(copy != null, "bouton « Copier sur les autres ecrans » absent de la carte");
        if (copy != null)
        {
            Reveal(page, copy);
            Ui.Click(copy);
            for (int i = 1; i < 3; i++)
            {
                MonitorSettings b = Ui.S.For(Ui.D.Monitors[i]);
                Check(b.Independent && Math.Abs(b.Own.Brightness - 72) < 0.01 && b.Own.Kelvin == 4200
                      && Math.Abs(b.BrightnessOffset - 12) < 0.01,
                      "l'ecran " + (i + 1) + " n'a pas recu les reglages copies");
            }
            // Et les cartes affichent bien la valeur recue, sans attendre.
            foreach (Slider s in Ui.AllOf<Slider>(Cards()[2]))
                if (s.Visible && s.AccessibleLabel == "Luminosite propre")
                    Check(Math.Abs(s.Value - 72) < 0.01, "la carte de l'ecran 3 n'affiche pas la valeur copiee");
        }
        ResetMonitors();
        Ui.ScrollTo(page, 0);
    }

    static void TestScreensSyncAll()
    {
        SettingsPage page = Ui.Show(Ui.P.ScreensPage);
        Ui.ScrollTo(page, 0);
        Ui.S.LinkMonitors = false;
        foreach (MonitorInfo m in Ui.D.Monitors)
        {
            MonitorSettings ms = Ui.S.For(m);
            ms.Independent = true; ms.BrightnessOffset = 30; ms.Own.Brightness = 40;
        }
        Ui.P.RefreshReadouts(); Ui.Pump();

        DarkButton all = ButtonStarting(page, "Synchroniser");
        Check(all != null, "bouton « Synchroniser tous les ecrans » absent");
        if (all != null)
        {
            Reveal(page, all);
            Ui.Click(all);
            Check(Ui.S.LinkMonitors, "les ecrans devraient etre relies apres synchronisation");
            foreach (MonitorInfo m in Ui.D.Monitors)
            {
                MonitorSettings ms = Ui.S.For(m);
                Check(!ms.Independent && Math.Abs(ms.BrightnessOffset) < 0.01,
                    m.Label + " garde un reglage a part apres synchronisation");
                Profile eff = Ui.S.EffectiveFor(m);
                Check(Math.Abs(eff.Brightness - Ui.S.Current.Brightness) < 0.01,
                    m.Label + " n'affiche pas la meme luminosite que le reglage general");
            }
        }
        ResetMonitors();
        Ui.ScrollTo(page, 0);
    }

    /// <summary>
    /// Un ecran regle en « profil independant » gardait ce profil apres qu'on a
    /// coche « Lier tous les ecrans » : le reglage general ne l'atteignait plus, et
    /// rien a l'ecran ne disait pourquoi - l'interrupteur de profil etait masque.
    /// </summary>
    static void TestLinkReallyLinks()
    {
        SettingsPage page = Ui.Show(Ui.P.ScreensPage);
        Ui.ScrollTo(page, 0);
        Ui.S.LinkMonitors = false;
        MonitorSettings ms = Ui.S.For(Ui.D.Monitors[2]);
        ms.Independent = true;
        ms.Own.Brightness = 40;
        Ui.P.RefreshReadouts(); Ui.Pump();

        List<ToggleSwitch> sws = Ui.AllOf<ToggleSwitch>(page);
        Ui.Click(sws[0]);                           // « Lier tous les ecrans »
        Check(Ui.S.LinkMonitors, "l'interrupteur de liaison n'a pas bascule");
        Ui.S.Current.Brightness = 85;
        Profile eff = Ui.S.EffectiveFor(Ui.D.Monitors[2]);
        Check(Math.Abs(eff.Brightness - 85) < 0.01, "l'ecran 3 ignore le reglage general alors que les ecrans sont lies ("
            + eff.Brightness + " %)");
        Ui.S.Current.Brightness = 100;
        ResetMonitors();
    }

    /// <summary>Clique la pastille du mode nomme, dans la vraie bande de modes.</summary>
    static Profile ClickMode(string name)
    {
        SettingsPage page = Ui.Show(Ui.P.Display1);
        Ui.ScrollTo(page, 0);
        ModeStrip strip = Ui.AllOf<ModeStrip>(page)[0];

        List<Profile> modes = new List<Profile>(Profile.BuiltInModes());
        modes.AddRange(Ui.S.CustomProfiles);
        int index = -1;
        for (int i = 0; i < modes.Count; i++) if (modes[i].Name == name) index = i;
        Check(index >= 0, "mode « " + name + " » introuvable");
        if (index < 0) return null;

        // La bande deborde de la fenetre et defile a la molette : on balaie chaque
        // position de defilement jusqu'a tomber sur la pastille visee, plutot que de
        // cliquer a une coordonnee calculee qui pourrait etre hors cadre.
        Ui.S.ActiveModeName = "";
        for (int notch = 0; notch <= modes.Count; notch++)
        {
            for (int x = 4; x < strip.Width; x += 8)
            {
                Ui.Click(strip, new Point(x, 20));
                if (Ui.S.ActiveModeName == name) return modes[index];
            }
            Ui.Wheel(strip, new Point(10, 10), -120);
            Ui.Pump();
        }
        Check(false, "la pastille « " + name + " » n'a pas pu etre cliquee");
        return null;
    }

    /// <summary>
    /// Le defaut qui a motive ce test : un ecran en profil independant ignorait la
    /// page Ecran. Choisir « Soiree » ne changeait RIEN sur lui, sans aucun message,
    /// et il ne bougeait que si l'on tirait ses curseurs propres a la main.
    /// </summary>
    static void TestModeReachesEveryScreen()
    {
        ResetMonitors();
        Ui.S.LinkMonitors = false;
        MonitorSettings ms = Ui.S.For(Ui.D.Monitors[2]);
        ms.Independent = true;
        ms.Own.Brightness = 45.85;
        ms.Own.Kelvin = 2394;
        Ui.P.RefreshReadouts(); Ui.Pump();

        Profile mode = ClickMode("Soiree");
        if (mode == null) { ResetMonitors(); return; }

        Profile eff = Ui.S.EffectiveFor(Ui.D.Monitors[2]);
        Check(Math.Abs(eff.Brightness - mode.Brightness) < 0.01 && eff.Kelvin == mode.Kelvin,
              "le mode n'atteint pas l'ecran en profil independant : il reste a "
              + (int)eff.Brightness + " % / " + eff.Kelvin + " K");

        // Le reglage pris ecran par ecran tient jusqu'au prochain mode : descendre
        // la luminosite generale ne doit pas effacer la temperature propre.
        ms.Own.Kelvin = 2394;
        Ui.S.Current.Brightness = 88;
        Ui.D.Apply();
        eff = Ui.S.EffectiveFor(Ui.D.Monitors[2]);
        Check(eff.Kelvin == 2394, "la temperature reglee sur cet ecran a ete effacee par la luminosite generale");
        Check(Math.Abs(eff.Brightness - 88) < 0.01, "la luminosite generale n'a pas suivi");

        ResetMonitors();
    }

    /// <summary>L'exception explicite : la dalle calibree que rien ne doit toucher.</summary>
    static void TestLockedScreenIgnoresModes()
    {
        ResetMonitors();
        MonitorSettings ms = Ui.S.For(Ui.D.Monitors[1]);
        ms.Locked = true;
        ms.Own.Brightness = 62;
        ms.Own.Kelvin = 5000;
        Ui.P.RefreshReadouts(); Ui.Pump();

        Profile mode = ClickMode("Bougie");
        if (mode == null) { ms.Locked = false; ResetMonitors(); return; }

        Profile eff = Ui.S.EffectiveFor(Ui.D.Monitors[1]);
        Check(Math.Abs(eff.Brightness - 62) < 0.01 && eff.Kelvin == 5000,
              "l'ecran verrouille a suivi le mode : " + (int)eff.Brightness + " % / " + eff.Kelvin + " K");

        Profile other = Ui.S.EffectiveFor(Ui.D.Monitors[0]);
        Check(Math.Abs(other.Brightness - mode.Brightness) < 0.01,
              "les autres ecrans doivent, eux, avoir suivi le mode");

        ms.Locked = false;
        ResetMonitors();
    }

    // ------------------------------------------------------------------ molette

    static void TestWheelScrollsPage()
    {
        SettingsPage page = Ui.Show(Ui.P.Display1);
        Ui.ScrollTo(page, 0);
        Slider s = null;
        foreach (Slider k in Ui.AllOf<Slider>(page)) if (Ui.FullyVisible(k) && k.Enabled) { s = k; break; }
        Check(s != null, "aucun curseur visible");
        if (s == null) return;
        Ui.P.ActiveControl = null;
        Ui.Pump();

        string before = Ui.S.Export();
        double v = s.Value;
        int scroll = Ui.ScrollY(page);
        Ui.Wheel(s, new Point(s.Width / 2, s.Height / 2), -120);
        Ui.Wheel(s, new Point(s.Width / 2, s.Height / 2), -120);
        Check(Math.Abs(s.Value - v) < 1e-9, "la molette a change la valeur d'un curseur simplement survole ("
            + v + " -> " + s.Value + ")");
        Check(Ui.S.Export() == before, "la molette a modifie les reglages");
        if (page.VerticalScroll.Visible)
            Check(Ui.ScrollY(page) > scroll, "la molette sur un curseur n'a pas fait defiler la page");
        Ui.ScrollTo(page, 0);
    }

    static void TestWheelFocusedSlider()
    {
        SettingsPage page = Ui.Show(Ui.P.Display1);
        Ui.ScrollTo(page, 0);
        Slider s = null;
        foreach (Slider k in Ui.AllOf<Slider>(page))
            if (k.Enabled && k.AccessibleLabel == "Contraste") { s = k; break; }
        if (s == null) { Check(false, "curseur de contraste introuvable"); return; }
        Reveal(page, s);
        s.Focus();
        Ui.Pump();
        double v = s.Value;
        Ui.Wheel(s, new Point(s.Width / 2, s.Height / 2), 120);
        Check(s.Value > v, "un curseur actif et survole devrait monter a la molette");
        Ui.Wheel(s, new Point(s.Width / 2, s.Height / 2), -120);
        Check(Math.Abs(s.Value - v) < 1e-6, "un cran vers le bas devrait annuler le cran vers le haut");
        Ui.S.Current.Contrast = 100;
        Ui.P.RefreshReadouts(); Ui.Pump();
        Ui.ScrollTo(page, 0);
    }

    static void TestWheelCombo()
    {
        DarkComboBox box = null;
        foreach (SettingsPage p in Ui.Pages())
        {
            Ui.Show(p); Ui.ScrollTo(p, 0);
            foreach (DarkComboBox b in Ui.AllOf<DarkComboBox>(p))
                if (Ui.FullyVisible(b) && b.Enabled && b.Items.Count > 2) { box = b; break; }
            if (box != null) break;
        }
        Check(box != null, "aucune liste deroulante visible");
        if (box == null) return;

        box.Focus();
        Ui.Pump();
        int idx = box.SelectedIndex;
        string before = Ui.S.Export();
        Ui.Wheel(box, new Point(box.Width / 2, box.Height / 2), -120);
        Ui.Wheel(box, new Point(box.Width / 2, box.Height / 2), -120);
        Check(box.SelectedIndex == idx, "la molette a change le choix d'une liste fermee ("
            + idx + " -> " + box.SelectedIndex + ")");
        Check(Ui.S.Export() == before, "la molette sur une liste fermee a modifie les reglages");
    }

    // ------------------------------------------------------------------ souris

    static void TestCaptureLost()
    {
        SettingsPage page = Ui.Show(Ui.P.Display1);
        Ui.ScrollTo(page, 0);
        Slider s = null;
        foreach (Slider k in Ui.AllOf<Slider>(page))
            if (k.Enabled && k.AccessibleLabel == "Contraste") { s = k; }
        if (s == null) { Check(false, "curseur de contraste introuvable"); return; }
        Reveal(page, s);

        int y = s.Height / 2;
        Ui.Down(s, new Point(Ui.XFor(s, 100), y));
        Ui.Pump();
        double v = s.Value;
        s.Capture = false;      // une fenetre surgit, Alt+Tab... : la capture est perdue
        Ui.Pump();
        Ui.Move(s, new Point(s.Width - 3, y), false);
        Ui.Pump();
        Check(Math.Abs(s.Value - v) < 1e-9, "le curseur suit encore la souris bouton relache ("
            + v + " -> " + s.Value + ")");
        Ui.Up(s, new Point(s.Width - 3, y));
        Ui.S.Current.Contrast = 100;
        Ui.P.RefreshReadouts(); Ui.Pump();
        Ui.ScrollTo(page, 0);
    }

    static void TestDoubleClickToggle()
    {
        SettingsPage page = Ui.Show(Ui.P.ComfortPage);
        Ui.ScrollTo(page, 0);
        ToggleSwitch sw = null;
        foreach (ToggleSwitch t in Ui.AllOf<ToggleSwitch>(page)) if (Ui.FullyVisible(t) && t.Enabled) { sw = t; break; }
        if (sw == null) { Check(false, "aucun interrupteur"); return; }

        bool start = sw.Checked;
        Ui.DoubleClick(sw, new Point(sw.Width / 2, sw.Height / 2));
        Check(sw.Checked == start, "deux clics rapides n'ont bascule l'interrupteur qu'une fois");
    }

    // ------------------------------------------------------------------ mise en page

    static List<int> Offsets(SettingsPage page)
    {
        List<int> list = new List<int>();
        foreach (Control c in page.Controls) list.Add(c.Top - page.AutoScrollPosition.Y);
        return list;
    }

    static void TestRelayoutWhileScrolled()
    {
        SettingsPage page = Ui.Show(Ui.P.VisionPage);
        Ui.ScrollTo(page, 0);
        List<int> reference = Offsets(page);

        Ui.ScrollTo(page, 10000);
        Check(Ui.ScrollY(page) > 0, "la page Vision devrait defiler");
        Size s0 = Ui.P.Size;
        Ui.P.Size = new Size(s0.Width + 60, s0.Height); Ui.Pump();
        Ui.P.Size = s0; Ui.Pump();
        Ui.P.RefreshReadouts(); Ui.Pump();

        List<int> now = Offsets(page);
        int moved = 0;
        for (int i = 0; i < Math.Min(now.Count, reference.Count); i++) if (now[i] != reference[i]) moved++;
        Check(moved == 0, moved + " element(s) decale(s) apres redisposition d'une page defilee");
        Ui.ScrollTo(page, 0);
        Check(page.Controls.Count > 0 && page.Controls[0].Top < 40,
            "le haut de la page est tombe plus bas qu'il ne devrait (" + page.Controls[0].Top + ")");
    }

    static List<Control> NavItems()
    {
        SideNav nav = Ui.AllOf<SideNav>(Ui.P)[0];
        List<Control> items = new List<Control>();
        foreach (Control c in nav.Controls)
            if (!(c is Label) && !(c is PictureBox)) items.Add(c);
        items.Sort(delegate(Control a, Control b) { return a.Top.CompareTo(b.Top); });
        return items;
    }

    static void TestNavFits()
    {
        SideNav nav = Ui.AllOf<SideNav>(Ui.P)[0];
        List<Control> items = NavItems();
        Check(items.Count == Ui.Pages().Count, "un onglet par page attendu");
        foreach (Control it in items)
        {
            Check(it.Bottom <= nav.ClientSize.Height, "l'onglet « " + it.Text + " » deborde sous la colonne ("
                + it.Bottom + " > " + nav.ClientSize.Height + ")");
            Check(it.Height >= Theme.MinTarget, "l'onglet « " + it.Text + " » est trop petit pour etre clique");
        }
        List<SettingsPage> pages = Ui.Pages();
        for (int i = 0; i < items.Count && i < pages.Count; i++)
        {
            Ui.Click(items[i]);
            Check(pages[i].Visible, "cliquer « " + items[i].Text + " » n'a pas ouvert sa page");
        }
    }

    static void TestNavShortcuts()
    {
        List<SettingsPage> pages = Ui.Pages();
        Keys[] digits = { Keys.D1, Keys.D2, Keys.D3, Keys.D4, Keys.D5, Keys.D6, Keys.D7, Keys.D8, Keys.D9, Keys.D0 };
        System.Reflection.MethodInfo pk = typeof(ControlPanel).GetMethod("ProcessCmdKey",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        for (int i = 0; i < pages.Count && i < digits.Length; i++)
        {
            Message m = Message.Create(Ui.P.Handle, Ui.WM_KEYDOWN, (IntPtr)(int)digits[i], IntPtr.Zero);
            pk.Invoke(Ui.P, new object[] { m, Keys.Control | digits[i] });
            Ui.Pump();
            Check(pages[i].Visible, "Ctrl + " + ((i + 1) % 10) + " n'ouvre pas « " + pages[i].Title + " »");
        }
    }

    // ------------------------------------------------------------------ daltonisme

    static void TestColorBlindPage()
    {
        SettingsPage page = Ui.PageTitled("Daltonisme");
        Check(page != null, "onglet « Daltonisme » absent de la colonne");
        if (page == null) return;

        // Le rang est desormais calcule par la fenetre elle-meme, et non ecrit a la
        // main : inserer un onglet avant celui-ci faisait ouvrir la page voisine.
        Check(Ui.Pages().IndexOf(page) == Ui.P.ColorBlindPageIndex,
            "le menu de la zone de notification n'ouvre pas l'onglet Daltonisme");
        Check(Ui.Pages().IndexOf(Ui.PageTitled("Vision")) == Ui.P.VisionPageIndex,
            "le raccourci de la page Vision n'ouvre pas la bonne page");

        Ui.Show(page);
        Ui.ScrollTo(page, 0);
        List<DarkComboBox> boxes = Ui.AllOf<DarkComboBox>(page);
        Check(boxes.Count >= 1, "choix du type de daltonisme absent");
        if (boxes.Count == 0) return;

        ColorFilter[] expected = { ColorFilter.None, ColorFilter.Protanopia, ColorFilter.Deuteranopia, ColorFilter.Tritanopia };
        for (int i = 0; i < expected.Length; i++)
        {
            boxes[0].SelectedIndex = i;
            Ui.Pump();
            Check(Ui.S.Current.Filter == expected[i], "choix " + i + " : filtre " + Ui.S.Current.Filter
                + " au lieu de " + expected[i]);
        }

        boxes[0].SelectedIndex = 2;
        Ui.Pump();

        // L'interrupteur principal coupe et retablit la correction choisie.
        List<ToggleSwitch> sws = Ui.AllOf<ToggleSwitch>(page);
        Check(sws.Count >= 1, "interrupteur « Correction active » absent");
        if (sws.Count >= 1)
        {
            Ui.ScrollTo(page, 0);
            Check(sws[0].Checked, "l'interrupteur devrait etre allume quand un filtre est choisi");
            Ui.Click(sws[0]);
            Check(Ui.S.Current.Filter == ColorFilter.None, "couper la correction devrait retirer le filtre");
            Ui.Click(sws[0]);
            Check(Ui.S.Current.Filter == ColorFilter.Deuteranopia, "rallumer devrait retrouver le dernier filtre");
        }

        // Le curseur de gravite pilote bien le profil.
        Slider sev = null;
        foreach (Slider s in Ui.AllOf<Slider>(page)) if (s.AccessibleLabel == "Gravite") sev = s;
        Check(sev != null && sev.Enabled, "curseur de gravite absent ou inactif");
        if (sev != null && sev.Enabled)
        {
            Reveal(page, sev);
            Ui.Click(sev, new Point(Ui.XFor(sev, 40), sev.Height / 2));
            Check(Math.Abs(Ui.S.Current.VisionSeverity - 40) < 3, "la gravite ne suit pas le curseur ("
                + Ui.S.Current.VisionSeverity + ")");
        }

        // Et les tuiles de choix rapide posent le bon filtre en un clic.
        DarkButton tile = ButtonStarting(page, "Rouge");
        Check(tile != null, "choix rapide « Rouge » absent");
        if (tile != null)
        {
            Reveal(page, tile);
            Ui.Click(tile);
            Check(Ui.S.Current.Filter == ColorFilter.Protanopia, "la tuile « Rouge » devrait poser la protanopie");
        }

        Ui.S.Current.Filter = ColorFilter.None;
        Ui.S.Current.VisionSeverity = 100;
        Ui.P.RefreshReadouts(); Ui.Pump();
        Ui.ScrollTo(page, 0);
    }

    // ------------------------------------------------------------------ toutes pages

    static void TestSyncIsPure()
    {
        foreach (SettingsPage p in Ui.Pages())
        {
            Ui.Show(p);
            string before = Ui.S.Export();
            for (int i = 0; i < 3; i++) { p.Sync(); Ui.P.RefreshReadouts(); }
            Ui.Pump();
            Check(Ui.S.Export() == before, "rafraichir la page « " + p.Title + " » a modifie des reglages");
        }
    }

    /// <summary>
    /// Balayage systematique : chaque interrupteur actif, sur chaque page, doit
    /// basculer au clic - et un second clic doit le ramener a son etat.
    /// </summary>
    static void TestEveryToggleResponds()
    {
        foreach (SettingsPage p in Ui.Pages())
        {
            if (p == Ui.P.AdvancedPage || p == Ui.P.HotkeysPage) continue;  // reglages systeme
            Ui.Show(p);
            Ui.ScrollTo(p, 0);
            foreach (ToggleSwitch sw in Ui.AllOf<ToggleSwitch>(p))
            {
                if (!sw.Enabled || !sw.Visible || sw.IsDisposed) continue;
                Reveal(p, sw);
                if (!Ui.FullyVisible(sw)) continue;
                bool b = sw.Checked;
                Ui.Click(sw);
                if (sw.IsDisposed) { Check(false, p.Title + " : interrupteur detruit par son propre clic"); continue; }
                Check(sw.Checked != b, p.Title + " : l'interrupteur « " + sw.AccessibleLabel + " » ne bascule pas");
                Ui.Click(sw);
                Check(sw.Checked == b, p.Title + " : l'interrupteur « " + sw.AccessibleLabel + " » ne revient pas");
            }
            Ui.ScrollTo(p, 0);
        }
        ResetMonitors();
    }
    // ------------------------------------------------------------------ test guide

    /// <summary>
    /// Fait passer le test a un observateur SIMULE dont on connait la vision : il
    /// repond comme le ferait cette personne - il ne lit pas les planches qui lui
    /// sont invisibles, et ne distingue les paires que lorsque l'ecart depasse ce
    /// que sa vision percoit.
    /// </summary>
    static void RunExamAs(VisionExamDialog dlg, ColorFilter vision, double severity)
    {
        dlg.Begin();

        int guard = 0;
        while (dlg.CurrentStep == VisionExamDialog.Step.Plates && guard++ < 40)
        {
            VisionPlate plate = dlg.CurrentPlate;
            if (plate == null) break;
            float[] sim = ColorMatrixEffect.BuildMatrix(100, vision, severity, 100, FilterMode.Simulation);
            bool readable = Vision.DeltaE(ColorMatrixEffect.Transform(sim, plate.Figure),
                                          ColorMatrixEffect.Transform(sim, plate.Background))
                            >= VisionExam.JustNoticeable;
            dlg.AnswerPlate(readable ? plate.Digit : -1);
        }

        guard = 0;
        while (dlg.CurrentStep == VisionExamDialog.Step.Pairs && guard++ < 60)
        {
            Color[] pair = VisionExam.PairAt(dlg.Staircase.Axis, dlg.Staircase.Separation);
            bool sees = VisionExam.PerceivedDelta(vision, severity, pair[0], pair[1]) >= VisionExam.JustNoticeable;
            dlg.AnswerPair(sees);
        }
    }

    static bool RedGreen(ColorFilter f)
    {
        return f == ColorFilter.Protanopia || f == ColorFilter.Deuteranopia;
    }

    static void TestGuidedExam()
    {
        ColorFilter[] visions = { ColorFilter.Protanopia, ColorFilter.Deuteranopia, ColorFilter.Tritanopia };
        foreach (ColorFilter vision in visions)
        foreach (double severity in new double[] { 100, 65, 45 })
        {
            Ui.S.Current.Filter = ColorFilter.None;
            using (VisionExamDialog dlg = new VisionExamDialog(Ui.S, Ui.D, 4242))
            {
                RunExamAs(dlg, vision, severity);
                Check(dlg.CurrentStep == VisionExamDialog.Step.Result,
                    Vision.PlainName(vision) + " : le test ne va pas jusqu'au resultat");
                // Distinguer une protanomalie d'une deuteranomalie LEGERE demande un
                // anomaloscope : leurs axes de confusion sont trop voisins. Le test
                // doit donc nommer la bonne famille - rouge-vert ou bleu-jaune - et
                // le bon type des que la deficience est marquee.
                bool exact = dlg.FoundFilter == vision;
                bool family = RedGreen(vision) && RedGreen(dlg.FoundFilter);
                Check(exact || (severity < 60 && family), "deficience trouvee : " + Vision.PlainName(dlg.FoundFilter)
                    + " au lieu de " + Vision.PlainName(vision) + " (gravite reelle " + severity
                    + " %, trouvee " + dlg.FoundSeverity + " %, confiance " + dlg.Confidence + ")");
                Check(Math.Abs(dlg.FoundSeverity - severity) <= 15, "gravite trouvee " + dlg.FoundSeverity
                    + " % pour " + severity + " % reels");
                Check(dlg.Confidence > 0, "confiance nulle malgre un depistage net");

                dlg.Apply();
                Check(Ui.S.Current.Filter == dlg.FoundFilter
                      && Math.Abs(Ui.S.Current.VisionSeverity - dlg.FoundSeverity) < 0.01,
                    "le resultat n'a pas ete applique aux reglages");
                Check(Ui.S.LastExamSummary.Length > 0, "le resultat du test n'est pas memorise");
            }
        }

        // Une vision normale lit tout : le test ne doit rien diagnostiquer.
        using (VisionExamDialog dlg = new VisionExamDialog(Ui.S, Ui.D, 99))
        {
            RunExamAs(dlg, ColorFilter.Deuteranopia, 0);
            Check(dlg.FoundFilter == ColorFilter.None, "une vision normale ne doit rien faire diagnostiquer (trouve "
                + Vision.PlainName(dlg.FoundFilter) + ", gravite " + dlg.FoundSeverity + " %)");
        }

        Ui.S.Current.Filter = ColorFilter.None;
        Ui.S.Current.VisionSeverity = 100;
        Ui.S.LastExamSummary = "";
        Ui.P.RefreshReadouts(); Ui.Pump();
    }

    /// <summary>
    /// Le test retire la correction pendant sa duree - sinon il mesurerait l'ecran
    /// corrige et non l'oeil. Il doit donc la rendre en sortant, y compris quand on
    /// ferme la fenetre en plein milieu.
    /// </summary>
    static void TestExamRestoresScreen()
    {
        Check(!Ui.D.Suspended, "les effets devraient etre actifs avant le test");

        VisionExamDialog dlg = new VisionExamDialog(Ui.S, Ui.D, 7);
        Check(Ui.D.Suspended, "les effets devraient etre suspendus pendant le test");
        dlg.AnswerPlate(-1);              // on abandonne en plein test
        dlg.Close();
        dlg.Dispose();
        Ui.Pump();
        Check(!Ui.D.Suspended, "l'ecran n'a pas ete rendu apres un test interrompu");

        // Et lorsque les effets etaient DEJA suspendus, le test ne doit pas les rallumer.
        Ui.D.Suspend("pause de l'utilisateur");
        VisionExamDialog dlg2 = new VisionExamDialog(Ui.S, Ui.D, 7);
        dlg2.Close();
        dlg2.Dispose();
        Ui.Pump();
        Check(Ui.D.Suspended, "une pause en cours ne doit pas etre levee par le test");
        Ui.D.Resume();
    }

    // ------------------------------------------------------------------ reglages enregistres

    static void TestPresets()
    {
        SettingsPage page = Ui.Show(Ui.PageTitled("Daltonisme"));
        Ui.S.VisionPresets.Clear();
        Ui.S.Current.Filter = ColorFilter.Tritanopia;
        Ui.S.Current.VisionSeverity = 44;
        Ui.S.Current.FilterStrength = 130;
        Ui.P.RefreshReadouts(); Ui.Pump();

        PageColorBlind cb = (PageColorBlind)page;
        cb.SavePreset("Bureau");
        Check(Ui.S.VisionPresets.Count == 1, "le reglage n'a pas ete enregistre");

        bool listed = false;
        foreach (DarkComboBox b in Ui.AllOf<DarkComboBox>(page))
            foreach (object item in b.Items) if (item.ToString() == "Bureau") listed = true;
        Check(listed, "le reglage enregistre n'apparait pas dans la liste");

        // On change tout, puis on rappelle le reglage : la correction revient, et elle seule.
        Ui.S.Current.Filter = ColorFilter.Protanopia;
        Ui.S.Current.VisionSeverity = 100;
        Ui.S.Current.Brightness = 62;
        Ui.P.RefreshReadouts(); Ui.Pump();

        DarkButton apply = ButtonStarting(page, "Appliquer");
        Check(apply != null, "bouton Appliquer absent");
        if (apply != null)
        {
            Reveal(page, apply);
            Ui.Click(apply);
            Check(Ui.S.Current.Filter == ColorFilter.Tritanopia
                  && Math.Abs(Ui.S.Current.VisionSeverity - 44) < 0.01
                  && Math.Abs(Ui.S.Current.FilterStrength - 130) < 0.01,
                  "le reglage rappele n'a pas ete applique");
            Check(Math.Abs(Ui.S.Current.Brightness - 62) < 0.01,
                  "rappeler un reglage de vision a change la luminosite");
        }

        Settings reread = Settings.FromText(Ui.S.Export());
        Check(reread.VisionPresets.Count == 1 && reread.VisionPresets[0].Name == "Bureau",
              "le reglage enregistre ne survit pas au fichier de configuration");

        Ui.S.VisionPresets.Clear();
        Ui.S.Current.Filter = ColorFilter.None;
        Ui.S.Current.VisionSeverity = 100;
        Ui.S.Current.FilterStrength = 100;
        Ui.S.Current.Brightness = 100;
        Ui.P.RefreshReadouts(); Ui.Pump();
        Ui.ScrollTo(page, 0);
    }

    // ------------------------------------------------------------------ demarrage

    static void TestStartupToggle()
    {
        SettingsPage page = Ui.Show(Ui.PageTitled("Daltonisme"));
        Ui.ScrollTo(page, 0);

        ToggleSwitch startup = null;
        foreach (ToggleSwitch sw in Ui.AllOf<ToggleSwitch>(page))
            if (sw.AccessibleLabel.StartsWith("Lancer OpusScreen")) startup = sw;
        Check(startup != null, "interrupteur de demarrage absent de l'onglet Daltonisme");
        if (startup == null) return;

        bool before = Ui.S.StartWithWindows;
        Reveal(page, startup);
        Ui.Click(startup);
        Check(Ui.S.StartWithWindows != before, "l'interrupteur de demarrage ne change rien");

        // Et l'onglet Avance dit la meme chose : un seul reglage, deux endroits.
        Ui.Show(Ui.P.AdvancedPage);
        ToggleSwitch other = null;
        foreach (ToggleSwitch sw in Ui.AllOf<ToggleSwitch>(Ui.P.AdvancedPage))
            if (sw.AccessibleLabel.StartsWith("Lancer au demarrage")) other = sw;
        Check(other != null && other.Checked == Ui.S.StartWithWindows,
            "les deux interrupteurs de demarrage ne disent pas la meme chose");

        Ui.Show(page);
        Reveal(page, startup);
        Ui.Click(startup);
        Check(Ui.S.StartWithWindows == before, "l'interrupteur ne revient pas a son etat");
        Ui.ScrollTo(page, 0);
    }

}
