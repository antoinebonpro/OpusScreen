using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("OpusScreen")]
[assembly: AssemblyDescription("Luminosite 5-150 %, temperature de couleur et confort visuel")]
[assembly: AssemblyVersion("2.1.0.0")]
[assembly: AssemblyFileVersion("2.1.0.0")]

namespace OpusScreen
{
    internal static class Program
    {
        private static Mutex _instanceLock;
        private static DisplayController _display;

        [STAThread]
        private static void Main(string[] args)
        {
            if (CommandLine.WantsHelp(args)) { CommandLine.ShowHelp(); return; }

            bool isNew;
            _instanceLock = new Mutex(true, "OpusScreen_SingleInstance_9f2a", out isNew);
            if (!isNew) { HandOver(args); return; }

            // --- conscience du DPI : sans cela, sur un ecran a mise a l'echelle, le
            //     voile serait place en coordonnees logiques et ne couvrirait pas tout ---
            MakeDpiAware();

            // --- filets de securite installes AVANT toute modification de l'affichage ---
            AppDomain.CurrentDomain.UnhandledException += OnFatalError;
            AppDomain.CurrentDomain.ProcessExit += OnProcessExit;
            Application.ThreadException += OnUiError;
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);

            // --- si la session precedente s'est mal terminee, l'ecran est peut-etre
            //     reste sombre : on le remet a neuf avant toute chose ---
            SafetyGuard.RecoverFromCrash();
            SafetyGuard.StartGuardThread();

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            Settings settings = Settings.Load();

            // Le chemin de l'executable a pu changer depuis la derniere session - le
            // renommage de LumaFlux en OpusScreen en est un cas. Reecrire l'entree de
            // demarrage a chaque lancement la garde exacte, et efface au passage celle
            // que portait l'ancien nom.
            settings.ApplyStartupRegistration();

            CommandLine.ApplyTo(settings, args);

            CheckForConflicts(settings);

            _display = new DisplayController(settings);
            _display.HardwareStatus = HardwareBacklight.Probe();
            HardwareBacklight.Start();

            TrayApp app = new TrayApp(settings, _display, args);
            Application.Run(app);
        }

        // ------------------------------------------------------------------ instance unique

        /// <summary>
        /// Une instance tourne deja : ce lancement lui passe la main puis s'efface.
        ///
        /// Une application epinglee a la barre des taches est relancee a chaque clic
        /// sur son icone ; repondre « OpusScreen est deja en cours d'execution » serait
        /// un refus la ou l'utilisateur attend sa fenetre. On transmet donc l'ordre
        /// recu s'il y en a un, et on demande l'ouverture de la fenetre sinon.
        /// </summary>
        private static void HandOver(string[] args)
        {
            if (CommandLine.HasCommand(args)) CommandLine.SendToRunningInstance(args);

            if (CommandLine.HasCommand(args) && !CommandLine.WantsShow(args)) return;

            // Le droit de passer au premier plan se cede, il ne se prend pas : sans
            // cette autorisation donnee par le processus qui part, Windows se
            // contenterait de faire clignoter le bouton de la barre des taches.
            Native.AllowSetForegroundWindow(Native.ASFW_ANY);
            Native.PostMessage(Native.HWND_BROADCAST, Native.WM_OPUSSCREEN_SHOW, IntPtr.Zero, IntPtr.Zero);
        }

        // ------------------------------------------------------------------ conflits

        private static void CheckForConflicts(Settings settings)
        {
            if (settings.IgnoreConflicts) return;

            System.Collections.Generic.List<ConflictDetector.Conflict> conflicts = ConflictDetector.Running();
            if (conflicts.Count == 0) return;

            string names = ConflictDetector.Describe(conflicts);
            string msg =
                names + " " + (conflicts.Count > 1 ? "sont en cours d'execution" : "est en cours d'execution") + ".\n\n"
              + "Windows ne dispose que d'une seule table de couleurs par carte graphique. "
              + "Si ces programmes restent actifs, ils ecraseront en permanence les reglages "
              + "de OpusScreen, et l'ecran clignotera.\n\n"
              + "OpusScreen reprend deja leurs fonctions.\n\n"
              + "Oui      : les fermer maintenant\n"
              + "Non      : les laisser, et me redemander au prochain lancement\n"
              + "Annuler : les laisser, et ne plus jamais me le demander";

            DialogResult r = MessageBox.Show(msg, "Applications concurrentes detectees",
                                             MessageBoxButtons.YesNoCancel, MessageBoxIcon.Warning);

            if (r == DialogResult.Yes)
            {
                ConflictDetector.CloseAll(conflicts);
                foreach (MonitorInfo m in MonitorEnum.All()) GammaEngine.ResetToIdentity(m);
            }
            else if (r == DialogResult.Cancel)
            {
                settings.IgnoreConflicts = true;
                settings.Save();
            }
        }

        // ------------------------------------------------------------------ securite

        /// <summary>
        /// Sur exception fatale, la priorite absolue est de rendre l'ecran lisible :
        /// une LUT modifiee survit a la mort du processus qui l'a posee.
        /// </summary>
        private static void OnFatalError(object sender, UnhandledExceptionEventArgs e)
        {
            SafetyGuard.EmergencyRestore();
        }

        private static void OnProcessExit(object sender, EventArgs e)
        {
            SafetyGuard.EmergencyRestore();
        }

        private static void OnUiError(object sender, ThreadExceptionEventArgs e)
        {
            SafetyGuard.EmergencyRestore();
            MessageBox.Show(
                "OpusScreen a rencontre une erreur et a remis l'ecran a l'etat normal.\n\n"
                + e.Exception.Message,
                "OpusScreen", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        // ------------------------------------------------------------------ DPI

        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr context);

        private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

        private static void MakeDpiAware()
        {
            try
            {
                if (SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) return;
            }
            catch { /* API absente avant Windows 10 1703 */ }

            try { SetProcessDPIAware(); } catch { }
        }
    }
}
