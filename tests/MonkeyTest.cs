using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using OpusScreen;

/// <summary>
/// Testeur « singe » : clique, glisse, tourne la molette et tape au hasard dans la
/// vraie fenetre de reglages, et verifie apres CHAQUE geste une liste d'invariants.
///
/// Les tests classiques verifient ce qu'on a pense a verifier ; le singe trouve ce
/// a quoi personne n'a pense - un double-clic pendant un rafraichissement, une
/// molette sur une carte d'ecran en plein glisser, une fenetre reduite au minimum.
///
/// Deux modes :
///   messages (defaut) - les gestes sont envoyes directement aux controles. Rapide,
///                       reproductible (graine), n'emprunte pas la souris : c'est
///                       celui que lance run-tests.cmd.
///   reel              - les gestes passent par SendInput, donc par la vraie souris
///                       et le vrai clavier de Windows : survol, capture, routage de
///                       la molette sous le pointeur. La souris est empruntee le
///                       temps du test ; bouger la souris ou appuyer sur Echap
///                       l'interrompt aussitot.
///
/// Tout tourne en mode a blanc, avec trois ecrans fictifs : ni la gamma, ni le son,
/// ni la configuration de la machine ne sont touches. Les pages Avance et Raccourcis
/// sont ecartees (registre, raccourcis globaux), ainsi que les boutons qui ouvrent
/// d'autres applications. Une sentinelle ferme toute boite de dialogue qui s'ouvre.
///
/// Usage : MonkeyTest.exe [messages|reel] [nombre de gestes] [graine]
/// </summary>
class MonkeyTest
{
    // ------------------------------------------------------------------ Win32

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern IntPtr GetFocus();
    [DllImport("user32.dll")] static extern bool GetCursorPos(out Point p);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point p);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
    delegate bool EnumProc(IntPtr h, IntPtr l);

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx, dy, mouseData, dwFlags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public short wVk, wScan; public int dwFlags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)]
    struct INPUT
    {
        [FieldOffset(0)] public int type;
        [FieldOffset(8)] public MOUSEINPUT mi;     // 8 : alignement en 64 bits
        [FieldOffset(8)] public KEYBDINPUT ki;
    }

    const int WM_CLOSE = 0x0010, WM_COMMAND = 0x0111;
    const int MOVE = 0x0001, LEFTDOWN = 0x0002, LEFTUP = 0x0004, WHEEL = 0x0800,
              ABSOLUTE = 0x8000, VIRTUALDESK = 0x4000, KEYUP = 0x0002;

    // ------------------------------------------------------------------ etat

    static Random rnd;
    static int actionsDone;
    static readonly List<string> recent = new List<string>();
    static readonly Dictionary<string, List<string>> violations = new Dictionary<string, List<string>>();
    static readonly List<string> dialogs = new List<string>();
    static readonly Dictionary<SettingsPage, int> topRef = new Dictionary<SettingsPage, int>();
    static volatile bool stop;
    static IntPtr mainHandle;
    static string abortReason = "";
    static Point lastInjected;

    [STAThread]
    static void Main(string[] args)
    {
        bool realMode = args.Length > 0 && args[0].StartsWith("re", StringComparison.OrdinalIgnoreCase);
        int count = args.Length > 1 ? int.Parse(args[1]) : (realMode ? 400 : 3000);
        int seed = args.Length > 2 ? int.Parse(args[2]) : Environment.TickCount;
        rnd = new Random(seed);

        Console.WriteLine("Singe : mode " + (realMode ? "REEL (souris empruntee - bougez-la ou Echap pour arreter)" : "messages")
                        + ", " + count + " gestes, graine " + seed);

        Ui.Setup(3);
        Ui.P.TopMost = realMode;
        mainHandle = Ui.P.Handle;

        // Reference de mise en page : le haut de chaque page, non defilee.
        foreach (SettingsPage p in Ui.Pages())
        {
            Ui.Show(p);
            Ui.ScrollTo(p, 0);
            if (p.Controls.Count > 0) topRef[p] = p.Controls[0].Top;
        }
        Ui.Show(Ui.Pages()[0]);

        Thread sentinel = new Thread(Sentinel);
        sentinel.IsBackground = true;
        sentinel.Start();

        DateTime t0 = DateTime.Now;
        if (realMode) RunReal(count);
        else RunMessages(count);
        stop = true;

        Report(seed, DateTime.Now - t0);
        Ui.Teardown();
        Environment.Exit(violations.Count == 0 && abortReason.Length == 0 ? 0 : 1);
    }

    // ------------------------------------------------------------------ sentinelle

    /// <summary>
    /// Ferme toute fenetre de ce processus autre que la fenetre de reglages : boite
    /// de message, confirmation, choix de couleur. Sans elle, le premier dialogue
    /// modal bloquerait le singe pour toujours.
    /// </summary>
    static void Sentinel()
    {
        uint me = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
        while (!stop)
        {
            Thread.Sleep(150);
            EnumWindows(delegate(IntPtr h, IntPtr l)
            {
                uint pid;
                GetWindowThreadProcessId(h, out pid);
                if (pid != me || h == mainHandle || !IsWindowVisible(h)) return true;
                StringBuilder cls = new StringBuilder(64), title = new StringBuilder(128);
                GetClassName(h, cls, 64);
                GetWindowText(h, title, 128);
                string c = cls.ToString();

                // Fenetres internes (liste deroulante ouverte, bulle, fenetre sans titre
                // de WinForms) : ce ne sont pas des dialogues.
                bool dialog = c == "#32770" || title.Length > 0;
                if (!dialog || c == "ComboLBox" || c.StartsWith("tooltips")) return true;

                lock (dialogs) dialogs.Add("« " + title + " » (" + c + ")");
                PostMessage(h, WM_COMMAND, (IntPtr)2, IntPtr.Zero);   // Annuler
                PostMessage(h, WM_COMMAND, (IntPtr)7, IntPtr.Zero);   // Non
                PostMessage(h, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
                return true;
            }, IntPtr.Zero);
        }
    }

    // ------------------------------------------------------------------ cibles

    static bool Excluded(Control c)
    {
        for (Control p = c; p != null; p = p.Parent)
            if (p == Ui.P.AdvancedPage || p == Ui.P.HotkeysPage) return true;

        DarkButton b = c as DarkButton;
        if (b != null)
        {
            string t = b.Text;
            // Liens vers les parametres de Windows, dialogues de fichier ou de couleur.
            if (t.EndsWith("...") || t.StartsWith("Couleur de l'anneau") || t.StartsWith("Enregistrer")) return true;
        }
        return false;
    }

    static bool Shown(Control c)
    {
        if (c.IsDisposed || !c.IsHandleCreated) return false;
        for (Control p = c; p != null; p = p.Parent) if (!p.Visible) return false;
        return true;
    }

    /// <summary>Partie du controle reellement visible a l'ecran (page, fenetre).</summary>
    static Rectangle VisibleRect(Control c)
    {
        Rectangle r = c.RectangleToScreen(c.ClientRectangle);
        for (Control p = c.Parent; p != null; p = p.Parent)
            r.Intersect(p.RectangleToScreen(p.ClientRectangle));
        return r;
    }

    static List<Control> Targets(bool leavesOnly)
    {
        List<Control> list = new List<Control>();
        foreach (Control c in Ui.All(Ui.P))
        {
            if (!c.Enabled || !Shown(c) || Excluded(c)) continue;
            if (leavesOnly && c.Controls.Count > 0 && !(c is DarkComboBox)) continue;
            Rectangle v = VisibleRect(c);
            if (v.Width < 3 || v.Height < 3) continue;
            list.Add(c);
        }
        return list;
    }

    static Control Pick(List<Control> list) { return list.Count == 0 ? null : list[rnd.Next(list.Count)]; }

    static Point RandomPointIn(Rectangle r) { return new Point(r.X + 1 + rnd.Next(r.Width - 2), r.Y + 1 + rnd.Next(r.Height - 2)); }

    static string Describe(Control c)
    {
        if (c == null) return "(rien)";
        string name = c.GetType().Name;
        string text = c.Text ?? "";
        Slider s = c as Slider;
        if (s != null) text = s.AccessibleLabel;
        ToggleSwitch t = c as ToggleSwitch;
        if (t != null) text = t.AccessibleLabel;
        SettingsPage page = Ui.PageOf(c);
        return name + (text.Length > 0 ? " « " + (text.Length > 40 ? text.Substring(0, 40) : text) + " »" : "")
             + (page != null ? " [" + page.Title + "]" : "");
    }

    static void Log(string what)
    {
        actionsDone++;
        recent.Add("#" + actionsDone + " " + what);
        if (recent.Count > 8) recent.RemoveAt(0);
    }

    // ------------------------------------------------------------------ invariants

    static void Violation(string kind, string detail)
    {
        List<string> l;
        if (!violations.TryGetValue(kind, out l)) { l = new List<string>(); violations[kind] = l; }
        if (l.Count < 3)
            l.Add(detail + "\n        derniers gestes :\n          " + string.Join("\n          ", recent.ToArray()));
        else l.Add("");
    }

    static SettingsPage VisiblePage()
    {
        foreach (SettingsPage p in Ui.Pages()) if (p.Visible) return p;
        return null;
    }

    static int errorsSeen = 0;

    /// <summary>Ce qui doit rester vrai quoi que fasse l'utilisateur.</summary>
    static void CheckInvariants(string before, Control wheelTarget, bool wheelTargetFocused,
                                SettingsPage clickPage, int clickScroll, int clickDisplayH, bool clickWasFullyVisible)
    {
        // 1. Aucune exception dans l'interface.
        while (errorsSeen < Ui.Errors.Count)
            Violation("Exception dans l'interface", Ui.Errors[errorsSeen++]);

        // 2. Une et une seule page affichee.
        int shown = 0;
        foreach (SettingsPage p in Ui.Pages()) if (p.Visible) shown++;
        if (shown != 1) Violation("Nombre de pages affichees", shown + " page(s) visible(s)");

        // 3. Reglages dans leurs bornes, plancher de securite tenu sur chaque ecran.
        Profile c = Ui.S.Current;
        if (c.Brightness < GammaEngine.MinBrightness - 1e-6 || c.Brightness > GammaEngine.MaxBrightness + 1e-6)
            Violation("Reglage hors bornes", "luminosite " + c.Brightness);
        if (c.Kelvin < ColorTemp.MinKelvin || c.Kelvin > ColorTemp.MaxKelvin)
            Violation("Reglage hors bornes", "temperature " + c.Kelvin);
        if (c.VisionSeverity < 0 || c.VisionSeverity > 100) Violation("Reglage hors bornes", "gravite " + c.VisionSeverity);
        if (c.FilterStrength < 0 || c.FilterStrength > 150) Violation("Reglage hors bornes", "intensite " + c.FilterStrength);
        foreach (MonitorInfo m in Ui.D.Monitors)
        {
            MonitorSettings ms = Ui.S.For(m);
            if (ms.BrightnessOffset < -50 - 1e-6 || ms.BrightnessOffset > 50 + 1e-6)
                Violation("Reglage hors bornes", m.Label + " : decalage " + ms.BrightnessOffset);
            if (ms.Own.Brightness < GammaEngine.MinBrightness - 1e-6 || ms.Own.Brightness > GammaEngine.MaxBrightness + 1e-6)
                Violation("Reglage hors bornes", m.Label + " : luminosite propre " + ms.Own.Brightness);
            Profile eff = Ui.S.EffectiveFor(m);
            if (eff.Brightness < GammaEngine.MinBrightness - 1e-6)
                Violation("Plancher de securite franchi", m.Label + " : " + eff.Brightness + " %");
        }

        // 4. La molette sur un controle qui n'avait pas le focus ne change aucun reglage.
        if (wheelTarget != null && !wheelTargetFocused && Ui.S.Export() != before)
            Violation("La molette a modifie un reglage sans que le controle soit choisi", Describe(wheelTarget));

        // 5. Un clic sur un controle entierement visible ne fait pas sauter la page.
        SettingsPage now = VisiblePage();
        if (clickPage != null && clickWasFullyVisible && now == clickPage
            && Ui.ScrollY(now) != clickScroll && now.DisplayRectangle.Height == clickDisplayH)
            Violation("Saut de defilement apres un clic",
                clickScroll + " -> " + Ui.ScrollY(now) + " sur la page " + now.Title);

        // 6. Le haut du contenu reste a sa place (la page ne « tombe » pas).
        if (now != null && now.Controls.Count > 0 && topRef.ContainsKey(now))
        {
            int top = now.Controls[0].Top - now.AutoScrollPosition.Y;
            if (top != topRef[now])
                Violation("Contenu de page decale (la page « tombe »)",
                    now.Title + " : haut du contenu a " + top + " au lieu de " + topRef[now]);
        }

        // 7. Le controle qui a le focus n'a pas ete detruit sous la souris.
        IntPtr fh = GetFocus();
        Control fc = fh != IntPtr.Zero ? Control.FromHandle(fh) : null;
        if (fc != null && fc.IsDisposed) Violation("Controle actif detruit", Describe(fc));

        // 8. Page Ecrans : exactement une carte par ecran, aucune orpheline.
        List<MonitorCard> cards = Ui.AllOf<MonitorCard>(Ui.P.ScreensPage);
        if (cards.Count != Ui.D.Monitors.Count)
            Violation("Cartes d'ecran incoherentes", cards.Count + " carte(s) pour " + Ui.D.Monitors.Count + " ecran(s)");

        // 9. Ce qui serait ecrit sur le disque se relit a l'identique.
        string exported = Ui.S.Export();
        try
        {
            Settings reread = Settings.FromText(exported);
            if (reread.Export() != exported)
                Violation("Reglages non relus a l'identique", FirstDiff(exported, reread.Export()));
        }
        catch (Exception e) { Violation("Reglages illisibles", e.Message); }
    }

    static string FirstDiff(string a, string b)
    {
        string[] la = a.Split('\n'), lb = b.Split('\n');
        for (int i = 0; i < Math.Min(la.Length, lb.Length); i++)
            if (la[i] != lb[i]) return "ecrit  : " + la[i].Trim() + "\n        relu   : " + lb[i].Trim();
        return "longueurs " + la.Length + " / " + lb.Length;
    }

    // ------------------------------------------------------------------ mode messages

    static void RunMessages(int count)
    {
        Keys[] keys = { Keys.Tab, Keys.Left, Keys.Right, Keys.Up, Keys.Down, Keys.Space, Keys.Enter, Keys.Home, Keys.End };

        for (int i = 0; i < count; i++)
        {
            string before = Ui.S.Export();
            Control wheelTarget = null; bool wheelFocused = false;
            SettingsPage clickPage = null; int clickScroll = 0, clickDisplayH = 0; bool fullyVisible = false;

            int roll = rnd.Next(100);
            try
            {
                if (roll < 34)
                {
                    Control c = Pick(Targets(rnd.Next(5) > 0));
                    if (c == null) continue;
                    Point p = c.PointToClient(RandomPointIn(VisibleRect(c)));
                    clickPage = Ui.PageOf(c);
                    if (clickPage != null) { clickScroll = Ui.ScrollY(clickPage); clickDisplayH = clickPage.DisplayRectangle.Height; }
                    fullyVisible = Ui.FullyVisible(c) && c.GetType().Name != "NavItem";
                    bool dbl = rnd.Next(8) == 0;
                    Log((dbl ? "double-clic " : "clic ") + Describe(c) + " en " + p);
                    if (dbl) Ui.DoubleClick(c, p); else Ui.Click(c, p);
                }
                else if (roll < 50)
                {
                    List<Control> sliders = new List<Control>();
                    foreach (Control c in Targets(true)) if (c is Slider) sliders.Add(c);
                    Slider s = (Slider)Pick(sliders);
                    if (s == null) continue;
                    int y = s.Height / 2;
                    int x = rnd.Next(s.Width);
                    Log("glisser " + Describe(s) + " depuis x=" + x);
                    Ui.Down(s, new Point(x, y));
                    int moves = 1 + rnd.Next(8);
                    for (int k = 0; k < moves; k++)
                    {
                        Ui.Move(s, new Point(rnd.Next(-40, s.Width + 40), y + rnd.Next(-20, 20)), true);
                        if (rnd.Next(4) == 0) Ui.P.RefreshReadouts();   // un rafraichissement tombe en plein geste
                    }
                    if (rnd.Next(6) == 0 && !s.IsDisposed) { s.Capture = false; Log("  capture perdue"); }
                    else Ui.Up(s, new Point(rnd.Next(-40, s.Width + 40), y));
                    Ui.Pump();
                }
                else if (roll < 70)
                {
                    Control c = Pick(Targets(rnd.Next(3) > 0));
                    if (c == null) continue;
                    wheelTarget = c;
                    wheelFocused = c.Focused;
                    Point p = c.PointToClient(RandomPointIn(VisibleRect(c)));
                    int notches = (rnd.Next(2) == 0 ? -1 : 1) * (1 + rnd.Next(3));
                    Log("molette " + notches + " sur " + Describe(c) + (wheelFocused ? " (focus)" : ""));
                    Ui.Wheel(c, p, 120 * notches);
                }
                else if (roll < 80)
                {
                    IntPtr fh = GetFocus();
                    Control f = fh != IntPtr.Zero ? Control.FromHandle(fh) : null;
                    if (f == null || f.IsDisposed || Excluded(f) || !Shown(f)) continue;
                    Keys k = keys[rnd.Next(keys.Length)];
                    Log("touche " + k + " sur " + Describe(f));
                    Ui.Key(f, k);
                }
                else if (roll < 90)
                {
                    List<SettingsPage> pages = Ui.Pages();
                    int idx = rnd.Next(pages.Count);
                    Log("onglet " + pages[idx].Title);
                    Ui.P.SelectPage(idx);
                    Ui.Pump();
                }
                else if (roll < 95)
                {
                    SettingsPage p = VisiblePage();
                    if (p == null) continue;
                    int y = rnd.Next(0, 3000);
                    Log("defilement de la page a " + y);
                    Ui.ScrollTo(p, y);
                }
                else if (roll < 98)
                {
                    Size min = Ui.P.MinimumSize;
                    Size sz = new Size(min.Width + rnd.Next(400), min.Height + rnd.Next(300));
                    Log("taille de fenetre " + sz);
                    Ui.P.Size = sz;
                    Ui.Pump();
                }
                else
                {
                    Log("rafraichissement periodique");
                    Ui.P.RefreshReadouts();
                    Ui.Pump();
                }
            }
            catch (Exception e)
            {
                Violation("Exception pendant un geste", e.GetType().Name + " : " + e.Message + "\n" + e.StackTrace);
            }

            CheckInvariants(before, wheelTarget, wheelFocused, clickPage, clickScroll, clickDisplayH, fullyVisible);
        }
    }

    // ------------------------------------------------------------------ mode reel

    static T OnUi<T>(Func<T> f) { return (T)Ui.P.Invoke(f); }
    static void OnUi(Action a) { Ui.P.Invoke(a); }

    static void Mouse(int flags, Point screen, int data)
    {
        int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77), vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
        INPUT[] input = new INPUT[1];
        input[0].type = 0;
        input[0].mi.dx = (int)Math.Round((screen.X - vx) * 65535.0 / Math.Max(1, vw - 1));
        input[0].mi.dy = (int)Math.Round((screen.Y - vy) * 65535.0 / Math.Max(1, vh - 1));
        input[0].mi.mouseData = data;
        input[0].mi.dwFlags = flags | MOVE | ABSOLUTE | VIRTUALDESK;
        SendInput(1, input, Marshal.SizeOf(typeof(INPUT)));

        // Position relevee apres coup plutot que calculee : la conversion en
        // coordonnees normalisees arrondit, et l'ecart passait pour une reprise en
        // main par l'utilisateur.
        Thread.Sleep(5);
        Point actual;
        lastInjected = GetCursorPos(out actual) ? actual : screen;
    }

    static void Key(Keys k)
    {
        INPUT[] input = new INPUT[2];
        input[0].type = 1; input[0].ki.wVk = (short)k;
        input[1].type = 1; input[1].ki.wVk = (short)k; input[1].ki.dwFlags = KEYUP;
        SendInput(2, input, Marshal.SizeOf(typeof(INPUT)));
    }

    /// <summary>L'utilisateur reprend la main : souris deplacee ou Echap.</summary>
    static bool UserTookOver()
    {
        if ((GetAsyncKeyState(0x1B) & 0x8000) != 0) { abortReason = "Echap"; return true; }
        Point p;
        GetCursorPos(out p);
        if (actionsDone > 0 && (Math.Abs(p.X - lastInjected.X) > 40 || Math.Abs(p.Y - lastInjected.Y) > 40))
        {
            abortReason = "souris deplacee par l'utilisateur (attendue en " + lastInjected + ", trouvee en " + p + ")";
            return true;
        }
        return false;
    }

    static void RunReal(int count)
    {
        Thread worker = new Thread(delegate()
        {
            try { RealLoop(count); }
            catch (Exception e) { abortReason = "erreur du singe : " + e.Message; }
            finally { try { OnUi(delegate { Application.ExitThread(); }); } catch { } }
        });
        worker.IsBackground = true;
        worker.Start();
        Application.Run();
    }

    static void RealLoop(int count)
    {
        Thread.Sleep(500);
        GetCursorPos(out lastInjected);     // reference de depart, avant tout geste
        Keys[] keys = { Keys.Tab, Keys.Left, Keys.Right, Keys.Up, Keys.Down, Keys.Space };

        for (int i = 0; i < count && !stop; i++)
        {
            if (UserTookOver()) return;
            OnUi(delegate
            {
                if (GetForegroundWindow() != Ui.P.Handle) { Ui.P.Activate(); SetForegroundWindow(Ui.P.Handle); }
            });

            string before = OnUi(delegate { return Ui.S.Export(); });
            Control target = null; Rectangle vis = Rectangle.Empty; bool focused = false;
            SettingsPage page = null; int scroll = 0, dispH = 0; bool fully = false;

            int roll = rnd.Next(100);
            bool leaves = rnd.Next(5) > 0;
            OnUi(delegate
            {
                List<Control> list = Targets(leaves);
                if (roll >= 34 && roll < 50) list = list.FindAll(delegate(Control c) { return c is Slider; });
                target = Pick(list);
                if (target != null)
                {
                    vis = VisibleRect(target);
                    focused = target.Focused;
                    page = Ui.PageOf(target);
                    if (page != null) { scroll = Ui.ScrollY(page); dispH = page.DisplayRectangle.Height; }
                    fully = Ui.FullyVisible(target) && target.GetType().Name != "NavItem";
                }
            });
            if (target == null || vis.Width < 3 || vis.Height < 3) continue;

            Point pt = RandomPointIn(vis);

            // Le point doit tomber sur NOTRE fenetre : jamais un clic ailleurs sur le bureau.
            bool ours = OnUi(delegate
            {
                IntPtr under = WindowFromPoint(pt);
                Control uc = under != IntPtr.Zero ? Control.FromChildHandle(under) : null;
                return uc != null && uc.FindForm() == Ui.P;
            });
            if (!ours) continue;

            string desc = OnUi(delegate { return Describe(target); });
            Control wheelTarget = null;

            if (roll < 34)
            {
                bool dbl = rnd.Next(8) == 0;
                OnUi(delegate { Log((dbl ? "double-clic " : "clic ") + desc); });
                Mouse(0, pt, 0); Thread.Sleep(20);
                Mouse(LEFTDOWN, pt, 0); Mouse(LEFTUP, pt, 0);
                if (dbl) { Thread.Sleep(40); Mouse(LEFTDOWN, pt, 0); Mouse(LEFTUP, pt, 0); }
            }
            else if (roll < 50)
            {
                OnUi(delegate { Log("glisser " + desc); });
                Rectangle form = OnUi(delegate { return Ui.P.RectangleToScreen(Ui.P.ClientRectangle); });
                Mouse(0, pt, 0); Thread.Sleep(20);
                Mouse(LEFTDOWN, pt, 0);
                int moves = 1 + rnd.Next(8);
                for (int k = 0; k < moves; k++)
                {
                    Point q = new Point(vis.X + rnd.Next(-40, vis.Width + 40), pt.Y + rnd.Next(-15, 15));
                    q.X = Math.Max(form.Left + 2, Math.Min(form.Right - 2, q.X));
                    q.Y = Math.Max(form.Top + 2, Math.Min(form.Bottom - 2, q.Y));
                    Mouse(0, q, 0);
                    Thread.Sleep(15);
                }
                Mouse(LEFTUP, lastInjected, 0);
            }
            else if (roll < 72)
            {
                int notches = (rnd.Next(2) == 0 ? -1 : 1) * (1 + rnd.Next(3));
                wheelTarget = target;
                OnUi(delegate { Log("molette " + notches + " sur " + desc + (focused ? " (focus)" : "")); });
                Mouse(0, pt, 0); Thread.Sleep(30);
                Mouse(WHEEL, pt, 120 * notches);
            }
            else if (roll < 85)
            {
                bool ok = OnUi(delegate
                {
                    IntPtr fh = GetFocus();
                    Control f = fh != IntPtr.Zero ? Control.FromHandle(fh) : null;
                    return f != null && !f.IsDisposed && !Excluded(f) && Shown(f);
                });
                if (!ok) continue;
                Keys k = keys[rnd.Next(keys.Length)];
                OnUi(delegate { Log("touche " + k); });
                Key(k);
            }
            else
            {
                int idx = rnd.Next(10);
                OnUi(delegate { Log("onglet " + idx); Ui.P.SelectPage(Math.Min(idx, Ui.Pages().Count - 1)); });
            }

            Thread.Sleep(60);

            // La regle « un clic ne fait pas defiler » ne vaut que pour les clics :
            // une molette, elle, doit faire defiler.
            SettingsPage clickPage = roll < 34 ? page : null;
            OnUi(delegate { Ui.Pump(); CheckInvariants(before, wheelTarget, focused, clickPage, scroll, dispH, fully); });
        }
    }

    // ------------------------------------------------------------------ bilan

    static void Report(int seed, TimeSpan took)
    {
        Console.WriteLine();
        Console.WriteLine(actionsDone + " gestes en " + (int)took.TotalSeconds + " s.");
        if (abortReason.Length > 0) Console.WriteLine("Interrompu : " + abortReason);

        lock (dialogs)
        {
            if (dialogs.Count > 0)
            {
                Dictionary<string, int> seen = new Dictionary<string, int>();
                foreach (string d in dialogs) { int n; seen.TryGetValue(d, out n); seen[d] = n + 1; }
                Console.WriteLine("Dialogues ouverts puis fermes par la sentinelle :");
                foreach (KeyValuePair<string, int> kv in seen) Console.WriteLine("  " + kv.Value + " x " + kv.Key);
            }
        }

        if (violations.Count == 0)
        {
            Console.WriteLine(">>> AUCUN DEFAUT TROUVE");
            return;
        }

        Console.WriteLine(">>> " + violations.Count + " TYPE(S) DE DEFAUT - rejouer avec la graine " + seed);
        foreach (KeyValuePair<string, List<string>> kv in violations)
        {
            Console.WriteLine();
            Console.WriteLine("  [" + kv.Value.Count + " x] " + kv.Key);
            foreach (string ex in kv.Value) if (ex.Length > 0) Console.WriteLine("      - " + ex);
        }
    }
}
