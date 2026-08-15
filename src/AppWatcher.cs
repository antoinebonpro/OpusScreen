using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace LumaFlux
{
    /// <summary>
    /// Surveille l'application au premier plan.
    ///
    /// Deux usages, tous deux reserves aux versions payantes de la concurrence :
    ///
    ///   - Profils par application (Lunar Pro) : Photoshop en couleurs fideles,
    ///     le lecteur video en mode film, le terminal en mode nuit - sans rien toucher.
    ///   - Suspension automatique en jeu ou en video plein ecran, pour ne pas fausser
    ///     les couleurs ni laisser un voile par-dessus une partie.
    /// </summary>
    public class AppWatcher
    {
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern int GetWindowThreadProcessId(IntPtr hwnd, out int pid);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out Native.RECT rect);
        [DllImport("user32.dll")] private static extern IntPtr GetDesktopWindow();
        [DllImport("user32.dll")] private static extern IntPtr GetShellWindow();
        [DllImport("user32.dll")] private static extern int GetClassName(IntPtr hwnd, StringBuilder buf, int max);

        private string _lastProcess = "";
        private bool _lastFullscreen;

        /// <summary>Nom de processus (sans .exe) de l'application active, en minuscules.</summary>
        public string CurrentProcess { get { return _lastProcess; } }

        public bool IsFullscreen { get { return _lastFullscreen; } }

        /// <summary>Emis quand l'application au premier plan change.</summary>
        public event Action<string> ForegroundChanged;

        /// <summary>Emis quand on entre ou sort d'un plein ecran.</summary>
        public event Action<bool> FullscreenChanged;

        /// <summary>A appeler periodiquement, typiquement chaque seconde.</summary>
        public void Poll()
        {
            try
            {
                IntPtr hwnd = GetForegroundWindow();
                if (hwnd == IntPtr.Zero) return;

                string proc = ProcessNameOf(hwnd);
                if (proc != _lastProcess)
                {
                    _lastProcess = proc;
                    Action<string> h = ForegroundChanged;
                    if (h != null) h(proc);
                }

                bool full = IsWindowFullscreen(hwnd);
                if (full != _lastFullscreen)
                {
                    _lastFullscreen = full;
                    Action<bool> h2 = FullscreenChanged;
                    if (h2 != null) h2(full);
                }
            }
            catch { }
        }

        private static string ProcessNameOf(IntPtr hwnd)
        {
            try
            {
                int pid;
                GetWindowThreadProcessId(hwnd, out pid);
                if (pid == 0) return "";
                using (Process p = Process.GetProcessById(pid))
                    return p.ProcessName.ToLowerInvariant();
            }
            catch { return ""; }
        }

        /// <summary>
        /// Une fenetre est consideree plein ecran si elle couvre exactement un ecran
        /// entier. Le bureau et la barre des taches sont exclus : ils remplissent
        /// l'ecran en permanence sans etre des jeux.
        /// </summary>
        private static bool IsWindowFullscreen(IntPtr hwnd)
        {
            try
            {
                if (hwnd == GetDesktopWindow() || hwnd == GetShellWindow()) return false;

                StringBuilder cls = new StringBuilder(256);
                GetClassName(hwnd, cls, cls.Capacity);
                string c = cls.ToString();
                if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd") return false;

                Native.RECT r;
                if (!GetWindowRect(hwnd, out r)) return false;

                foreach (MonitorInfo m in MonitorEnum.All())
                {
                    if (r.Left <= m.Bounds.Left && r.Top <= m.Bounds.Top
                     && r.Right >= m.Bounds.Right && r.Bottom >= m.Bounds.Bottom)
                        return true;
                }
                return false;
            }
            catch { return false; }
        }
    }

    /// <summary>Association « application -> profil », telle que la propose Lunar Pro.</summary>
    public class AppRule
    {
        public string ProcessName = "";   // sans .exe, en minuscules
        public string ProfileName = "";
        public bool Disable;              // vrai = suspendre tout effet pour cette application

        public string Serialize()
        {
            return ProcessName + ">" + ProfileName + ">" + (Disable ? "1" : "0");
        }

        public static AppRule Deserialize(string s)
        {
            AppRule r = new AppRule();
            string[] f = s.Split('>');
            if (f.Length >= 1) r.ProcessName = f[0].Trim().ToLowerInvariant();
            if (f.Length >= 2) r.ProfileName = f[1].Trim();
            if (f.Length >= 3) r.Disable = f[2] == "1";
            return r;
        }

        public string Describe()
        {
            return ProcessName + "  ->  " + (Disable ? "aucun effet" : ProfileName);
        }
    }

    /// <summary>Applications courantes proposees pour creer une regle sans taper le nom.</summary>
    public static class KnownApps
    {
        public class Entry
        {
            public string Process, Label, Suggested;
            public Entry(string p, string l, string s) { Process = p; Label = l; Suggested = s; }
        }

        public static List<Entry> Suggestions()
        {
            List<Entry> l = new List<Entry>();
            l.Add(new Entry("photoshop", "Adobe Photoshop", "Normal"));
            l.Add(new Entry("illustrator", "Adobe Illustrator", "Normal"));
            l.Add(new Entry("afterfx", "After Effects", "Normal"));
            l.Add(new Entry("lightroom", "Lightroom", "Normal"));
            l.Add(new Entry("davinci resolve", "DaVinci Resolve", "Normal"));
            l.Add(new Entry("vlc", "VLC", "Film"));
            l.Add(new Entry("mpc-hc64", "Media Player Classic", "Film"));
            l.Add(new Entry("netflix", "Netflix", "Film"));
            l.Add(new Entry("devenv", "Visual Studio", "Lecture"));
            l.Add(new Entry("code", "Visual Studio Code", "Lecture"));
            l.Add(new Entry("windowsterminal", "Terminal Windows", "Lecture"));
            l.Add(new Entry("acrord32", "Acrobat Reader", "Papier"));
            l.Add(new Entry("winword", "Microsoft Word", "Papier"));
            l.Add(new Entry("steam", "Steam", "Jeu"));
            l.Add(new Entry("teams", "Microsoft Teams", "Visioconference"));
            l.Add(new Entry("zoom", "Zoom", "Visioconference"));
            return l;
        }
    }
}
