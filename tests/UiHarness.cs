using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using OpusScreen;

/// <summary>
/// Banc d'essai de l'interface, partage par UiTest et MonkeyTest.
///
/// Monte la VRAIE fenetre de reglages, avec ses vraies pages, mais en mode a blanc :
/// aucune gamma, aucun voile, aucune matrice, aucun son ni fichier de l'utilisateur
/// n'est touche. Trois ecrans fictifs remplacent ceux de la machine - c'est le seul
/// moyen de tester le multi-ecran sur un poste qui n'en a qu'un.
///
/// Les gestes sont envoyes en messages Windows au controle vise (WM_LBUTTONDOWN,
/// WM_MOUSEWHEEL...), et non en appelant OnClick : ils traversent donc le meme chemin
/// que ceux d'un utilisateur - capture de la souris, double-clic, remontee de la
/// molette vers le parent.
/// </summary>
static class Ui
{
    public const int WM_MOUSEMOVE = 0x0200, WM_LBUTTONDOWN = 0x0201, WM_LBUTTONUP = 0x0202,
                     WM_LBUTTONDBLCLK = 0x0203, WM_MOUSEWHEEL = 0x020A,
                     WM_KEYDOWN = 0x0100, WM_KEYUP = 0x0101, MK_LBUTTON = 0x0001;

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);

    public static Settings S;
    public static DisplayController D;
    public static ControlPanel P;
    public static readonly List<string> Errors = new List<string>();

    /// <summary>Ecrans fictifs : deux du meme modele, c'est le cas qui piege.</summary>
    public static List<MonitorInfo> FakeMonitors(int count)
    {
        List<MonitorInfo> list = new List<MonitorInfo>();
        for (int i = 0; i < count; i++)
        {
            MonitorInfo m = new MonitorInfo();
            m.Handle = IntPtr.Zero;
            m.DeviceName = "\\\\.\\FAKE" + (i + 1);
            m.FriendlyName = i == 0 ? "Dalle test" : "Moniteur test";
            m.StableId = "FAKE-" + (i + 1);
            m.Bounds.Left = i * 1920;
            m.Bounds.Right = (i + 1) * 1920;
            m.Bounds.Bottom = 1080;
            m.IsPrimary = i == 0;
            m.Index = i;
            m.Connection = i == 0 ? "dalle interne" : "HDMI";
            list.Add(m);
        }
        return list;
    }

    public static void Setup(int monitors)
    {
        string dir = Path.Combine(Path.GetTempPath(), "OpusScreenUiTest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        Settings.DataFolderOverride = dir;
        DisplayController.DryRun = true;
        SystemVolume.DryRun = true;
        DisplayController.MonitorSource = delegate { return FakeMonitors(monitors); };

        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += delegate(object o, System.Threading.ThreadExceptionEventArgs e)
        {
            Errors.Add(e.Exception.GetType().Name + " : " + e.Exception.Message
                     + "\n" + e.Exception.StackTrace);
        };

        S = new Settings();
        D = new DisplayController(S);

        // Meme enchainement que TrayApp.ApplyAll : appliquer, puis rafraichir la page
        // visible. C'est ce rafraichissement qui detruisait la page Ecrans en plein geste.
        Action push = delegate
        {
            D.Apply();
            if (P != null && P.IsHandleCreated && P.Visible) P.RefreshReadouts();
        };

        P = new ControlPanel(S, D, push);
        P.StartPosition = FormStartPosition.Manual;
        P.Location = new Point(40, 40);
        P.Show();
        Pump();
    }

    public static void Teardown()
    {
        try { P.Hide(); P.Dispose(); } catch { }
        try { Directory.Delete(Settings.DataFolderOverride, true); } catch { }
    }

    public static void Pump()
    {
        for (int i = 0; i < 4; i++) Application.DoEvents();
    }

    // ------------------------------------------------------------------ pages

    public static List<SettingsPage> Pages()
    {
        FieldInfo f = typeof(ControlPanel).GetField("_pages", BindingFlags.NonPublic | BindingFlags.Instance);
        return (List<SettingsPage>)f.GetValue(P);
    }

    public static SettingsPage Show(SettingsPage page)
    {
        P.SelectPage(Pages().IndexOf(page));
        Pump();
        return page;
    }

    public static SettingsPage PageTitled(string title)
    {
        foreach (SettingsPage p in Pages()) if (p.Title == title) return p;
        return null;
    }

    public static int ScrollY(ScrollableControl c) { return -c.AutoScrollPosition.Y; }

    public static void ScrollTo(ScrollableControl c, int y)
    {
        c.AutoScrollPosition = new Point(0, y);
        Pump();
    }

    // ------------------------------------------------------------------ recherche

    public static List<Control> All(Control root)
    {
        List<Control> list = new List<Control>();
        Stack<Control> todo = new Stack<Control>();
        todo.Push(root);
        while (todo.Count > 0)
        {
            Control c = todo.Pop();
            foreach (Control k in c.Controls) { list.Add(k); todo.Push(k); }
        }
        return list;
    }

    public static List<T> AllOf<T>(Control root) where T : Control
    {
        List<T> list = new List<T>();
        foreach (Control c in All(root)) { T t = c as T; if (t != null) list.Add(t); }
        // L'ordre de pile inverse l'ordre des Controls : on le retablit par position.
        list.Sort(delegate(T a, T b)
        {
            int ya = a.PointToScreen(Point.Empty).Y, yb = b.PointToScreen(Point.Empty).Y;
            return ya != yb ? ya.CompareTo(yb) : a.PointToScreen(Point.Empty).X.CompareTo(b.PointToScreen(Point.Empty).X);
        });
        return list;
    }

    /// <summary>Vrai si le controle est affiche en entier dans la zone visible de sa page.</summary>
    public static bool FullyVisible(Control c)
    {
        if (!c.Visible || c.IsDisposed || !c.IsHandleCreated) return false;
        for (Control p = c; p != null; p = p.Parent) if (!p.Visible) return false;
        SettingsPage page = PageOf(c);
        if (page == null) return true;
        Rectangle r = page.RectangleToClient(c.RectangleToScreen(c.ClientRectangle));
        return page.ClientRectangle.Contains(r);
    }

    public static SettingsPage PageOf(Control c)
    {
        for (Control p = c; p != null; p = p.Parent)
        {
            SettingsPage sp = p as SettingsPage;
            if (sp != null) return sp;
        }
        return null;
    }

    // ------------------------------------------------------------------ gestes

    private static IntPtr LP(int x, int y) { return (IntPtr)(((y & 0xFFFF) << 16) | (x & 0xFFFF)); }

    public static void Down(Control c, Point p)
    {
        SendMessage(c.Handle, WM_MOUSEMOVE, IntPtr.Zero, LP(p.X, p.Y));
        SendMessage(c.Handle, WM_LBUTTONDOWN, (IntPtr)MK_LBUTTON, LP(p.X, p.Y));
    }

    public static void Move(Control c, Point p, bool held)
    {
        if (c.IsDisposed) return;
        SendMessage(c.Handle, WM_MOUSEMOVE, (IntPtr)(held ? MK_LBUTTON : 0), LP(p.X, p.Y));
    }

    public static void Up(Control c, Point p)
    {
        if (c.IsDisposed) return;
        SendMessage(c.Handle, WM_LBUTTONUP, IntPtr.Zero, LP(p.X, p.Y));
    }

    public static void Click(Control c, Point p) { Down(c, p); Up(c, p); Pump(); }

    public static void Click(Control c) { Click(c, new Point(c.Width / 2, c.Height / 2)); }

    public static void DoubleClick(Control c, Point p)
    {
        Down(c, p); Up(c, p);
        // Le premier clic peut detruire le controle : c'etait le defaut de la page
        // Ecrans. Le second clic tombe alors dans le vide, comme pour l'utilisateur.
        if (c.IsDisposed) { Pump(); return; }
        SendMessage(c.Handle, WM_LBUTTONDBLCLK, (IntPtr)MK_LBUTTON, LP(p.X, p.Y));
        Up(c, p);
        Pump();
    }

    /// <summary>La molette porte des coordonnees ECRAN, contrairement aux clics.</summary>
    public static void Wheel(Control c, Point client, int delta)
    {
        Point s = c.PointToScreen(client);
        SendMessage(c.Handle, WM_MOUSEWHEEL, (IntPtr)((delta & 0xFFFF) << 16), LP(s.X, s.Y));
        Pump();
    }

    public static void Key(Control c, Keys k)
    {
        SendMessage(c.Handle, WM_KEYDOWN, (IntPtr)(int)k, IntPtr.Zero);
        SendMessage(c.Handle, WM_KEYUP, (IntPtr)(int)k, IntPtr.Zero);
        Pump();
    }

    /// <summary>Abscisse, dans le curseur, qui correspond a une valeur donnee.</summary>
    public static int XFor(Slider s, double v)
    {
        double p = (v - s.Minimum) / (s.Maximum - s.Minimum);
        return 10 + (int)Math.Round(p * (s.Width - 20));
    }
}
