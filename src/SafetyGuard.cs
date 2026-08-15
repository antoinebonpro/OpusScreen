using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace OpusScreen
{
    /// <summary>
    /// Filet de securite contre le scenario "ecran noir dont on ne peut plus sortir".
    ///
    /// Une LUT gamma survit a la mort du processus qui l'a ecrite : si l'application
    /// plante alors que l'ecran est a 5 %, l'ecran RESTE a 5 %. C'est le principal
    /// danger de cette categorie d'outil. Cinq protections independantes :
    ///
    ///   1. Un thread de secours autonome, avec sa propre file de messages, qui reste
    ///      capable de tout remettre a zero meme si l'interface est figee.
    ///      Raccourci de panique : Ctrl + Alt + Maj + R
    ///   2. Un fichier temoin sur disque : s'il est encore la au demarrage, c'est que
    ///      la session precedente s'est mal terminee -> on repart d'un ecran normal.
    ///   3. Restauration sur tous les chemins de sortie, y compris exception non geree,
    ///      fermeture de session Windows et arret du processus.
    ///   4. Bornes dures : jamais en dessous de 5 % effectifs, voile jamais opaque.
    ///   5. Confirmation a rebours sur les reglages sombres (comme le changement de
    ///      resolution de Windows) : sans reponse, on revient tout seul en arriere.
    /// </summary>
    public static class SafetyGuard
    {
        public const int PanicHotkeyId = 0xB0FF;
        private const uint VK_R = 0x52;
        private const int SW_HIDE = 0;

        [StructLayout(LayoutKind.Sequential)]
        private struct MSG
        {
            public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam;
            public uint time; public int ptX; public int ptY;
        }

        [DllImport("user32.dll")]
        private static extern int GetMessage(out MSG msg, IntPtr hwnd, uint min, uint max);

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hwnd, int cmd);

        [DllImport("user32.dll")]
        private static extern bool PostThreadMessage(uint threadId, uint msg, IntPtr wParam, IntPtr lParam);

        private const uint WM_QUIT = 0x0012;

        private static readonly object Sync = new object();
        private static readonly List<IntPtr> OverlayHandles = new List<IntPtr>();
        private static Thread _guardThread;
        private static uint _guardThreadId;
        private static volatile bool _running;

        /// <summary>Appele par le thread de secours quand la panique est declenchee.</summary>
        public static event Action PanicTriggered;

        private static string FlagPath
        {
            get { return Path.Combine(Settings.DataFolder, "active.flag"); }
        }

        // ------------------------------------------------------------- 2. fichier temoin

        /// <summary>
        /// A appeler tout au debut du programme. Si le temoin de la session precedente
        /// est encore la, l'ecran est probablement reste modifie : on le remet a neuf.
        /// </summary>
        public static bool RecoverFromCrash()
        {
            try
            {
                if (!File.Exists(FlagPath)) return false;
                foreach (MonitorInfo m in MonitorEnum.All())
                    GammaEngine.ResetToIdentity(m);
                try { ColorMatrixEffect.Reset(); } catch { }
                ClearDirtyFlag();
                return true;
            }
            catch { return false; }
        }

        public static void MarkDirty()
        {
            try
            {
                Directory.CreateDirectory(Settings.DataFolder);
                File.WriteAllText(FlagPath, DateTime.Now.ToString("o"));
            }
            catch { }
        }

        public static void ClearDirtyFlag()
        {
            try { if (File.Exists(FlagPath)) File.Delete(FlagPath); }
            catch { }
        }

        // ------------------------------------------------------------- 1. thread de secours

        /// <summary>
        /// Demarre un thread dedie qui ecoute le raccourci de panique.
        ///
        /// RegisterHotKey avec un hwnd nul depose WM_HOTKEY directement dans la file du
        /// thread appelant : ce thread n'a donc besoin d'aucune fenetre et ne depend en
        /// rien de l'interface. Si l'interface se fige, la panique repond quand meme.
        /// </summary>
        public static void StartGuardThread()
        {
            if (_guardThread != null) return;
            _running = true;
            _guardThread = new Thread(GuardLoop);
            _guardThread.IsBackground = true;
            _guardThread.Name = "OpusScreen-Safety";
            _guardThread.Priority = ThreadPriority.AboveNormal;
            _guardThread.Start();
        }

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        private static void GuardLoop()
        {
            _guardThreadId = GetCurrentThreadId();

            uint mods = Native.MOD_CONTROL | Native.MOD_ALT | Native.MOD_SHIFT | Native.MOD_NOREPEAT;
            bool registered = Native.RegisterHotKey(IntPtr.Zero, PanicHotkeyId, mods, VK_R);

            if (!registered)
            {
                // Sans MOD_NOREPEAT (Windows anterieurs a 7) on retente une fois.
                mods = Native.MOD_CONTROL | Native.MOD_ALT | Native.MOD_SHIFT;
                registered = Native.RegisterHotKey(IntPtr.Zero, PanicHotkeyId, mods, VK_R);
            }

            MSG msg;
            while (_running && GetMessage(out msg, IntPtr.Zero, 0, 0) > 0)
            {
                if (msg.message == Native.WM_HOTKEY && msg.wParam.ToInt32() == PanicHotkeyId)
                {
                    EmergencyRestore();
                    Action handler = PanicTriggered;
                    if (handler != null)
                    {
                        try { handler(); } catch { }
                    }
                }
            }

            if (registered)
            {
                try { Native.UnregisterHotKey(IntPtr.Zero, PanicHotkeyId); } catch { }
            }
        }

        public static void StopGuardThread()
        {
            _running = false;
            if (_guardThreadId != 0)
            {
                try { PostThreadMessage(_guardThreadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero); } catch { }
            }
        }

        // ------------------------------------------------------------- overlays connus

        public static void RegisterOverlay(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero) return;
            lock (Sync) { if (!OverlayHandles.Contains(hwnd)) OverlayHandles.Add(hwnd); }
        }

        public static void UnregisterOverlay(IntPtr hwnd)
        {
            lock (Sync) { OverlayHandles.Remove(hwnd); }
        }

        // ------------------------------------------------------------- 3. restauration totale

        /// <summary>
        /// Remet tout a l'etat neuf. Concue pour etre appelable depuis n'importe quel
        /// thread, sans allocation lourde ni dependance a l'interface : chaque etape est
        /// isolee dans son propre try, pour qu'un echec n'empeche jamais les suivantes.
        /// </summary>
        public static void EmergencyRestore()
        {
            // a) les voiles d'abord : c'est ce qui masque physiquement l'ecran.
            //    SetLayeredWindowAttributes fonctionne d'un thread a l'autre, donc
            //    ceci marche meme si le thread proprietaire de la fenetre est bloque.
            IntPtr[] handles;
            lock (Sync) { handles = OverlayHandles.ToArray(); }
            foreach (IntPtr h in handles)
            {
                try { Native.SetLayeredWindowAttributes(h, 0, 0, Native.LWA_ALPHA); } catch { }
                try { ShowWindow(h, SW_HIDE); } catch { }
            }

            // b) la matrice de couleur : un filtre inverse ou desature rend l'ecran
            //    tout aussi inutilisable qu'un ecran noir.
            try { ColorMatrixEffect.Reset(); } catch { }

            // c) puis les LUT de chaque ecran.
            try
            {
                foreach (MonitorInfo m in MonitorEnum.All())
                {
                    try { GammaEngine.ResetToIdentity(m); } catch { }
                }
            }
            catch
            {
                // Si meme l'enumeration echoue, on tente au moins l'ecran principal.
                try { GammaEngine.ResetToIdentity(null); } catch { }
            }

            ClearDirtyFlag();
        }

        // ------------------------------------------------------------- 4. bornes dures

        /// <summary>Aucun reglage ne peut sortir de cette plage, quelle qu'en soit l'origine.</summary>
        public static double ClampBrightness(double value)
        {
            if (double.IsNaN(value)) return 100.0;
            if (value < GammaEngine.MinBrightness) return GammaEngine.MinBrightness;
            if (value > GammaEngine.MaxBrightness) return GammaEngine.MaxBrightness;
            return value;
        }

        /// <summary>En dessous de ce seuil on demande confirmation avant de laisser le reglage en place.</summary>
        public const double ConfirmBelow = 20.0;
    }
}
