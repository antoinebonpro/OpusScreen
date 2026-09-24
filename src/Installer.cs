using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace OpusScreen
{
    /// <summary>
    /// Une seule copie sur le disque, une seule en memoire, et c'est la plus recente.
    ///
    /// OpusScreen se telecharge en un seul fichier, qu'on lance la ou le navigateur
    /// l'a pose. Chaque telechargement laissait donc une copie de plus - OpusScreen.exe,
    /// OpusScreen(1).exe... - et l'entree de demarrage de Windows pointait vers l'une
    /// d'elles, pas forcement la derniere. Pire : une nouvelle version lancee pendant
    /// qu'une ancienne tournait se contentait de lui passer la main, et l'utilisateur
    /// retrouvait l'ancienne fenetre en croyant ouvrir la nouvelle.
    ///
    /// L'application se range desormais d'elle-meme dans un dossier fixe, propre a
    /// l'utilisateur et sans droits administrateur. Un lancement depuis ailleurs
    /// compare les versions : plus recent, il remplace la copie installee ; plus
    /// ancien, il s'efface devant elle. Un vieux fichier oublie dans Telechargements
    /// ne peut plus faire revenir une ancienne version.
    /// </summary>
    public static class Installer
    {
        public const string MutexName = "OpusScreen_SingleInstance_9f2a";
        private const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\OpusScreen";
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

        /// <summary>%LOCALAPPDATA%\Programs\OpusScreen - l'emplacement que Windows
        /// reserve aux programmes installes pour un seul utilisateur.</summary>
        public static string InstallFolder
        {
            get
            {
                return Path.Combine(Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Programs"), "OpusScreen");
            }
        }

        public static string InstalledExe
        {
            get { return Path.Combine(InstallFolder, "OpusScreen.exe"); }
        }

        /// <summary>Ancien executable mis de cote pendant une mise a jour.</summary>
        public static string PreviousExe
        {
            get { return Path.Combine(InstallFolder, "OpusScreen.old.exe"); }
        }

        public static Version CurrentVersion
        {
            get { return Assembly.GetExecutingAssembly().GetName().Version; }
        }

        /// <summary>Version inscrite dans un executable, ou null s'il est illisible.</summary>
        public static Version VersionOf(string exe)
        {
            try
            {
                if (!File.Exists(exe)) return null;
                FileVersionInfo fvi = FileVersionInfo.GetVersionInfo(exe);
                if (string.IsNullOrEmpty(fvi.FileVersion)) return null;
                return new Version(fvi.FileVersion);
            }
            catch { return null; }
        }

        // ------------------------------------------------------------------ decision

        public enum LaunchAction
        {
            /// <summary>C'est la copie installee : demarrage normal.</summary>
            Run,
            /// <summary>Copie etrangere plus recente, ou rien d'installe : elle s'installe.</summary>
            Install,
            /// <summary>Copie etrangere pas plus recente : elle ouvre la copie installee.</summary>
            DeferToInstalled
        }

        /// <summary>
        /// Ce que doit faire un lancement, selon d'ou il part et ce qui est deja
        /// installe. Pure : c'est ce qui la rend testable.
        ///
        /// A version egale, la copie installee garde la main : la remplacer par
        /// elle-meme fermerait l'instance en cours pour rien, et l'ecran clignoterait.
        /// </summary>
        public static LaunchAction Decide(string runningExe, string installedExe,
                                          Version running, Version installed)
        {
            if (SamePath(runningExe, installedExe)) return LaunchAction.Run;
            if (installed != null && running != null && installed >= running)
                return LaunchAction.DeferToInstalled;
            return LaunchAction.Install;
        }

        public static bool SamePath(string a, string b)
        {
            try
            {
                return string.Equals(Path.GetFullPath(a).TrimEnd('\\'),
                                     Path.GetFullPath(b).TrimEnd('\\'),
                                     StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

        // ------------------------------------------------------------------ lancement

        /// <summary>
        /// Appelee tout au debut de Main. Vrai si ce processus a passe la main et
        /// doit s'arreter la.
        ///
        /// Aucun echec ici ne doit empecher l'application de marcher : si la copie
        /// est impossible - disque plein, antivirus, dossier verrouille - on demarre
        /// depuis l'endroit ou l'on est, comme avant.
        /// </summary>
        public static bool HandleLaunch(string[] args)
        {
            // Les tests pilotent l'application depuis leur propre dossier.
            if (!string.IsNullOrEmpty(Settings.DataFolderOverride)) return false;

            WaitForPid(args);

            string running = Taskbar.ExecutablePath;
            LaunchAction action = Decide(running, InstalledExe, CurrentVersion, VersionOf(InstalledExe));

            switch (action)
            {
                case LaunchAction.Run:
                    // Une version d'avant la 3.4, lancee a la main depuis Telechargements,
                    // ignore tout de ce qui precede et reinscrit le demarrage vers elle.
                    // Si elle tourne, c'est elle qui recevrait la main : on la remplace.
                    if (OlderInstanceRunning()) CloseRunningInstances(4000);
                    DeleteQuietly(PreviousExe);
                    // Une mise a jour remplace le fichier sans repasser par l'installation :
                    // l'entree d'Applications installees afficherait l'ancienne version.
                    RegisterUninstall();
                    return false;

                case LaunchAction.DeferToInstalled:
                    // Une copie installee plus recente fait foi. Si elle tourne deja, elle
                    // recevra la demande d'ouverture ; sinon on la demarre.
                    return Start(InstalledExe, ForwardArgs(args));

                default:
                    CloseRunningInstances(4000);
                    if (!CopyTo(running, InstalledExe)) return false;
                    RegisterUninstall();
                    return Start(InstalledExe, ForwardArgs(args));
            }
        }

        /// <summary>
        /// Arguments transmis a la copie installee. Sans ordre explicite, on demande
        /// la fenetre : l'utilisateur vient de double-cliquer, il attend quelque chose.
        /// </summary>
        private static string ForwardArgs(string[] args)
        {
            string line = Quote(args);
            if (!CommandLine.HasCommand(args)) line = (line + " --show").Trim();
            return line;
        }

        private static string Quote(string[] args)
        {
            System.Text.StringBuilder sb = new System.Text.StringBuilder();
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i];
                // --wait-pid ne concerne que le processus qui l'a recu.
                if (string.Equals(a, "--wait-pid", StringComparison.OrdinalIgnoreCase)) { i++; continue; }
                if (sb.Length > 0) sb.Append(' ');
                if (a.IndexOf(' ') >= 0) sb.Append('"').Append(a).Append('"');
                else sb.Append(a);
            }
            return sb.ToString();
        }

        /// <summary>
        /// --wait-pid N : attend que le processus N soit sorti. Emis par une mise a
        /// jour, dont l'ancienne instance lance la nouvelle puis se ferme ; sans cette
        /// attente, la nouvelle trouverait le verrou encore pris et lui passerait la main.
        /// </summary>
        private static void WaitForPid(string[] args)
        {
            for (int i = 0; i + 1 < args.Length; i++)
            {
                if (!string.Equals(args[i], "--wait-pid", StringComparison.OrdinalIgnoreCase)) continue;
                int pid;
                if (!int.TryParse(args[i + 1], out pid)) return;
                try
                {
                    using (Process p = Process.GetProcessById(pid)) p.WaitForExit(15000);
                }
                catch { /* deja sorti */ }
                return;
            }
        }

        private static bool Start(string exe, string arguments)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(exe, arguments);
                psi.UseShellExecute = false;
                psi.WorkingDirectory = Path.GetDirectoryName(exe);
                Process.Start(psi);
                return true;
            }
            catch { return false; }
        }

        /// <summary>
        /// Copie par un fichier temporaire puis remplacement : une copie interrompue ne
        /// laisse jamais un executable tronque a la place du bon.
        /// </summary>
        private static bool CopyTo(string source, string target)
        {
            string temp = target + ".tmp";
            for (int attempt = 0; attempt < 10; attempt++)
            {
                try
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    File.Copy(source, temp, true);
                    if (File.Exists(target)) File.Delete(target);
                    File.Move(temp, target);
                    return true;
                }
                catch
                {
                    // L'instance qu'on vient de fermer peut tenir le fichier encore un
                    // instant, le temps que Windows le relache.
                    Thread.Sleep(300);
                }
            }
            DeleteQuietly(temp);
            return false;
        }

        private static void DeleteQuietly(string path)
        {
            try { if (File.Exists(path)) File.Delete(path); } catch { }
        }

        // ------------------------------------------------------------------ instance en cours

        /// <summary>Vrai si une instance d'OpusScreen tient le verrou d'instance unique.</summary>
        public static bool IsAnyInstanceRunning()
        {
            try
            {
                using (Mutex probe = new Mutex(false, MutexName))
                {
                    bool free;
                    try { free = probe.WaitOne(0); }
                    catch (AbandonedMutexException) { free = true; }
                    if (free) probe.ReleaseMutex();
                    return !free;
                }
            }
            catch { return false; }
        }

        /// <summary>
        /// Ferme l'instance en cours, quelle que soit sa version.
        ///
        /// D'abord poliment : WM_OPUSSCREEN_QUIT lui fait remettre l'ecran a l'etat
        /// normal et sortir. Les versions anterieures a la 3.4 ne connaissent pas ce
        /// message ; passe le delai, leur processus est arrete. L'ecran qu'elles
        /// laissent modifie est remis a neuf par la suivante, qui trouve le temoin de
        /// session inachevee et le restaure avant toute chose.
        /// </summary>
        public static void CloseRunningInstances(int politeTimeoutMs)
        {
            if (!IsAnyInstanceRunning()) return;

            try { Native.PostMessage(Native.HWND_BROADCAST, Native.WM_OPUSSCREEN_QUIT, IntPtr.Zero, IntPtr.Zero); }
            catch { }

            DateTime limit = DateTime.Now.AddMilliseconds(politeTimeoutMs);
            while (DateTime.Now < limit)
            {
                if (!IsAnyInstanceRunning()) return;
                Thread.Sleep(150);
            }

            int self = Process.GetCurrentProcess().Id;
            foreach (Process p in Process.GetProcesses())
            {
                try
                {
                    if (p.Id == self) continue;
                    if (!IsOpusScreenProcess(p)) continue;
                    p.Kill();
                    p.WaitForExit(3000);
                }
                catch { }
                finally { p.Dispose(); }
            }
        }

        /// <summary>Vrai si une instance d'une version plus ancienne que celle-ci tourne.</summary>
        public static bool OlderInstanceRunning()
        {
            if (!IsAnyInstanceRunning()) return false;
            int self = Process.GetCurrentProcess().Id;
            foreach (Process p in Process.GetProcesses())
            {
                try
                {
                    if (p.Id == self || !IsOpusScreenProcess(p)) continue;
                    Version v = VersionOf(p.MainModule.FileName);
                    if (v != null && v < CurrentVersion) return true;
                }
                catch { }
                finally { p.Dispose(); }
            }
            return false;
        }

        /// <summary>
        /// Reconnait OpusScreen a la description inscrite dans son executable, et non a
        /// son nom de fichier : un navigateur le renomme volontiers OpusScreen(1).exe.
        /// </summary>
        private static bool IsOpusScreenProcess(Process p)
        {
            string name = p.ProcessName;
            if (name.IndexOf("opus", StringComparison.OrdinalIgnoreCase) < 0
             && name.IndexOf("lumaflux", StringComparison.OrdinalIgnoreCase) < 0) return false;
            try
            {
                string desc = p.MainModule.FileVersionInfo.FileDescription;
                return string.Equals(desc, "OpusScreen", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(desc, "LumaFlux", StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

        // ------------------------------------------------------------------ applications installees

        /// <summary>
        /// Entree de « Applications installees ». Sans elle, rien dans Windows ne dit
        /// qu'OpusScreen est la, ni comment l'enlever proprement.
        /// </summary>
        public static void RegisterUninstall()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(UninstallKey))
                {
                    if (key == null) return;
                    string exe = InstalledExe;
                    Version v = VersionOf(exe) ?? CurrentVersion;
                    key.SetValue("DisplayName", "OpusScreen");
                    key.SetValue("DisplayVersion", v.Major + "." + v.Minor + "." + v.Build);
                    key.SetValue("Publisher", "Opus Belli");
                    key.SetValue("DisplayIcon", exe);
                    key.SetValue("InstallLocation", InstallFolder);
                    key.SetValue("UninstallString", "\"" + exe + "\" --uninstall");
                    key.SetValue("URLInfoAbout", "https://antoinebonpro.github.io/OpusScreen/");
                    key.SetValue("HelpLink", "https://github.com/antoinebonpro/OpusScreen/issues");
                    key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                    key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                    try
                    {
                        key.SetValue("EstimatedSize", (int)(new FileInfo(exe).Length / 1024),
                                     RegistryValueKind.DWord);
                    }
                    catch { }
                }
            }
            catch { }
        }

        public static bool WantsUninstall(string[] args)
        {
            foreach (string a in args)
                if (string.Equals(a, "--uninstall", StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>
        /// Desinstallation complete : ecran remis a l'etat normal, demarrage automatique,
        /// raccourci, entree d'Applications installees et dossier du programme. Les
        /// reglages ne partent que si l'utilisateur le demande.
        /// </summary>
        public static void Uninstall()
        {
            DialogResult go = MessageBox.Show(
                "Desinstaller OpusScreen ?\n\n"
              + "L'ecran sera remis a l'etat normal et l'application retiree de cet ordinateur.",
                "Desinstaller OpusScreen", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (go != DialogResult.Yes) return;

            DialogResult keep = MessageBox.Show(
                "Garder vos reglages ?\n\n"
              + "Oui : ils seront retrouves si vous reinstallez OpusScreen.\n"
              + "Non : ils sont effaces aussi.",
                "Desinstaller OpusScreen", MessageBoxButtons.YesNo, MessageBoxIcon.Question);

            CloseRunningInstances(4000);

            try { foreach (MonitorInfo m in MonitorEnum.All()) GammaEngine.ResetToIdentity(m); } catch { }

            try
            {
                using (RegistryKey run = Registry.CurrentUser.OpenSubKey(RunKey, true))
                    if (run != null && run.GetValue("OpusScreen") != null) run.DeleteValue("OpusScreen", false);
            }
            catch { }

            try { if (File.Exists(Taskbar.ShortcutPath)) File.Delete(Taskbar.ShortcutPath); } catch { }
            Taskbar.ClearJumpList();

            try { Registry.CurrentUser.DeleteSubKeyTree(UninstallKey); } catch { }

            if (keep == DialogResult.No)
            {
                try { if (Directory.Exists(Settings.DataFolder)) Directory.Delete(Settings.DataFolder, true); }
                catch { }
            }

            ScheduleFolderRemoval(InstallFolder);

            MessageBox.Show("OpusScreen a ete desinstalle.", "OpusScreen",
                            MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        /// <summary>
        /// Un executable ne peut pas effacer le dossier d'ou il tourne. On confie la
        /// tache a une invite de commandes cachee, qui attend quelques secondes que ce
        /// processus soit sorti.
        /// </summary>
        private static void ScheduleFolderRemoval(string folder)
        {
            try
            {
                if (!Directory.Exists(folder)) return;
                ProcessStartInfo psi = new ProcessStartInfo("cmd.exe",
                    "/c ping 127.0.0.1 -n 4 >nul & rmdir /s /q \"" + folder + "\"");
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                Process.Start(psi);
            }
            catch { }
        }
    }
}
