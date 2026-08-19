using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace OpusScreen
{
    /// <summary>
    /// Volume de sortie de Windows, general et par application.
    ///
    /// CE QUE CETTE CLASSE NE FAIT PAS, ET NE PEUT PAS FAIRE : amplifier au-dela de
    /// 100 %. Le peripherique de sortie declare sa plage en decibels par
    /// IAudioEndpointVolume::GetVolumeRange, et son maximum vaut 0 dB sur toute carte
    /// son ordinaire - autrement dit le 100 % de Windows EST le plafond. Demander
    /// davantage ne renvoie pas une valeur ecretee : l'appel echoue.
    ///
    /// C'est exactement la limite que le voile de PangoBright rencontre sur la
    /// luminosite, et pour la meme raison de fond : un attenuateur retire du signal,
    /// il n'en ajoute pas. La luminosite a pu depasser 100 % parce qu'un AUTRE etage
    /// existait - la table de couleurs de la carte graphique, qui multiplie. Le son
    /// n'a pas d'equivalent accessible depuis une application ordinaire : amplifier
    /// demanderait de s'inserer dans le flux audio, donc un pilote a installer, ce que
    /// cette application refuse par principe.
    ///
    /// Ce qui reste faisable, et qui n'est pas rien : ramener au maximum tout ce qui
    /// se trouve en dessous. Les applications memorisent leur propre volume dans le
    /// mixeur de Windows, un reglage que peu de gens savent ou trouver - une video
    /// faible vient souvent de la, et non du volume general.
    /// </summary>
    public static class SystemVolume
    {
        // ---------------------------------------------------------------- COM

        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
        private class MMDeviceEnumerator { }

        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IMMDeviceEnumerator
        {
            int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
            int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        }

        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IMMDevice
        {
            int Activate(ref Guid iid, int clsCtx, IntPtr p,
                         [MarshalAs(UnmanagedType.IUnknown)] out object iface);
            int OpenPropertyStore(int access, out IntPtr store);
            int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
            int GetState(out int state);
        }

        [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAudioEndpointVolume
        {
            int RegisterControlChangeNotify(IntPtr n);
            int UnregisterControlChangeNotify(IntPtr n);
            int GetChannelCount(out int count);
            int SetMasterVolumeLevel(float db, ref Guid ctx);
            int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
            int GetMasterVolumeLevel(out float db);
            int GetMasterVolumeLevelScalar(out float level);
            int SetChannelVolumeLevel(int ch, float db, ref Guid ctx);
            int SetChannelVolumeLevelScalar(int ch, float level, ref Guid ctx);
            int GetChannelVolumeLevel(int ch, out float db);
            int GetChannelVolumeLevelScalar(int ch, out float level);
            int SetMute(bool mute, ref Guid ctx);
            int GetMute(out bool mute);
            int GetVolumeStepInfo(out int step, out int count);
            int VolumeStepUp(ref Guid ctx);
            int VolumeStepDown(ref Guid ctx);
            int QueryHardwareSupport(out int mask);
            int GetVolumeRange(out float minDb, out float maxDb, out float incDb);
        }

        [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAudioSessionManager2
        {
            int GetAudioSessionControl(IntPtr id, int flags, out IntPtr ctl);
            int GetSimpleAudioVolume(IntPtr id, int flags, out IntPtr vol);
            int GetSessionEnumerator(out IAudioSessionEnumerator e);
        }

        [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAudioSessionEnumerator
        {
            int GetCount(out int count);
            int GetSession(int index, out IAudioSessionControl2 session);
        }

        [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAudioSessionControl2
        {
            int GetState(out int state);
            int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string n);
            int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string n, ref Guid c);
            int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string p);
            int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string p, ref Guid c);
            int GetGroupingParam(out Guid g);
            int SetGroupingParam(ref Guid g, ref Guid c);
            int RegisterAudioSessionNotification(IntPtr n);
            int UnregisterAudioSessionNotification(IntPtr n);
            int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
            int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
            int GetProcessId(out int pid);
            int IsSystemSoundsSession();
            int SetDuckingPreference(bool opt);
        }

        [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface ISimpleAudioVolume
        {
            int SetMasterVolume(float level, ref Guid ctx);
            int GetMasterVolume(out float level);
            int SetMute(bool mute, ref Guid ctx);
            int GetMute(out bool mute);
        }

        private const int Render = 0, Console_ = 0, ClsCtxAll = 23;
        private const int StateActive = 1;

        // ---------------------------------------------------------------- etat

        private static bool _probed, _available;

        /// <summary>Faux quand la machine n'a pas de sortie audio utilisable.</summary>
        public static bool Available
        {
            get { if (!_probed) Probe(); return _available; }
        }

        /// <summary>Nom du peripherique de sortie, pour que l'interface dise de quoi elle parle.</summary>
        public static string DeviceName = "";

        /// <summary>
        /// Plafond declare par le materiel, en decibels. Vaut 0 sur toute carte son
        /// ordinaire : c'est le chiffre qui prouve qu'il n'y a pas de reserve.
        /// </summary>
        public static double CeilingDb;

        private static void Probe()
        {
            _probed = true;
            try
            {
                IAudioEndpointVolume vol = OpenEndpoint();
                if (vol == null) return;

                float min, max, inc;
                vol.GetVolumeRange(out min, out max, out inc);
                CeilingDb = max;
                _available = true;
                Marshal.ReleaseComObject(vol);
            }
            catch { _available = false; }
        }

        private static IMMDevice DefaultDevice()
        {
            IMMDeviceEnumerator en = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            IMMDevice dev;
            if (en.GetDefaultAudioEndpoint(Render, Console_, out dev) != 0) return null;
            return dev;
        }

        private static IAudioEndpointVolume OpenEndpoint()
        {
            IMMDevice dev = DefaultDevice();
            if (dev == null) return null;
            Guid iid = typeof(IAudioEndpointVolume).GUID;
            object o;
            if (dev.Activate(ref iid, ClsCtxAll, IntPtr.Zero, out o) != 0) return null;
            return (IAudioEndpointVolume)o;
        }

        // ---------------------------------------------------------------- volume general

        /// <summary>Volume general, de 0 a 100. Retourne -1 si l'audio est indisponible.</summary>
        public static double GetMaster()
        {
            try
            {
                IAudioEndpointVolume vol = OpenEndpoint();
                if (vol == null) return -1;
                float lvl;
                vol.GetMasterVolumeLevelScalar(out lvl);
                Marshal.ReleaseComObject(vol);
                return lvl * 100.0;
            }
            catch { return -1; }
        }

        /// <summary>
        /// Regle le volume general, de 0 a 100.
        ///
        /// La valeur est bornee a 100 AVANT l'appel, et ce n'est pas une precaution
        /// de style : passer 1,5 a SetMasterVolumeLevelScalar ne donne pas 100 %, cela
        /// leve une exception. Mesure sur le materiel de test - plage -65,25 a 0,00 dB.
        /// </summary>
        public static bool SetMaster(double percent)
        {
            if (percent < 0) percent = 0;
            if (percent > 100) percent = 100;
            try
            {
                IAudioEndpointVolume vol = OpenEndpoint();
                if (vol == null) return false;
                Guid ctx = Guid.Empty;
                bool ok = vol.SetMasterVolumeLevelScalar((float)(percent / 100.0), ref ctx) == 0;
                if (ok) vol.SetMute(false, ref ctx);
                Marshal.ReleaseComObject(vol);
                return ok;
            }
            catch { return false; }
        }

        // ---------------------------------------------------------------- par application

        /// <summary>Une application qui joue du son, telle que la voit le mixeur de Windows.</summary>
        public class AppSession
        {
            public string Name = "";
            public int ProcessId;
            public double Percent;
            public bool Muted;
            public bool Playing;

            /// <summary>Points de volume qu'il reste a recuperer sur cette application.</summary>
            public double Headroom { get { return Muted ? 100 : Math.Max(0, 100 - Percent); } }
        }

        /// <summary>Etat du mixeur, une entree par application. Liste vide si indisponible.</summary>
        public static List<AppSession> Sessions()
        {
            List<AppSession> list = new List<AppSession>();
            try
            {
                IAudioSessionEnumerator e = OpenSessions();
                if (e == null) return list;

                int count;
                e.GetCount(out count);
                for (int i = 0; i < count; i++)
                {
                    IAudioSessionControl2 s;
                    if (e.GetSession(i, out s) != 0) continue;

                    AppSession a = new AppSession();
                    int state; s.GetState(out state);
                    a.Playing = state == StateActive;
                    s.GetProcessId(out a.ProcessId);
                    a.Name = DescribeProcess(s, a.ProcessId);

                    ISimpleAudioVolume v = s as ISimpleAudioVolume;
                    if (v != null)
                    {
                        float lvl; v.GetMasterVolume(out lvl);
                        a.Percent = lvl * 100.0;
                        v.GetMute(out a.Muted);
                    }
                    list.Add(a);
                }
            }
            catch { }
            return list;
        }

        private static IAudioSessionEnumerator OpenSessions()
        {
            IMMDevice dev = DefaultDevice();
            if (dev == null) return null;
            Guid iid = typeof(IAudioSessionManager2).GUID;
            object o;
            if (dev.Activate(ref iid, ClsCtxAll, IntPtr.Zero, out o) != 0) return null;
            IAudioSessionEnumerator e;
            ((IAudioSessionManager2)o).GetSessionEnumerator(out e);
            return e;
        }

        private static string DescribeProcess(IAudioSessionControl2 s, int pid)
        {
            try { if (s.IsSystemSoundsSession() == 0) return "Sons systeme"; }
            catch { }
            try
            {
                Process p = Process.GetProcessById(pid);
                string title = p.MainWindowTitle;
                return title.Length > 0 && title.Length < 48 ? title : p.ProcessName;
            }
            catch { return "Processus " + pid; }
        }

        // ---------------------------------------------------------------- remise au maximum

        /// <summary>Ce qui a reellement change lors d'une remise au maximum.</summary>
        public class RaiseResult
        {
            public bool MasterRaised;
            public double MasterBefore, MasterAfter;
            public int AppsRaised;
            public int AppsUnmuted;
            public List<string> Changed = new List<string>();

            /// <summary>Vrai si rien n'a bouge : tout etait deja au maximum.</summary>
            public bool NothingToDo
            {
                get { return !MasterRaised && AppsRaised == 0 && AppsUnmuted == 0; }
            }
        }

        /// <summary>
        /// Remet au maximum le volume general ET celui de chaque application.
        ///
        /// Ce n'est pas une amplification : c'est la recuperation de ce qui a ete
        /// perdu en chemin. Une application memorise son propre volume dans le mixeur
        /// de Windows et le retrouve au lancement suivant ; un curseur baisse une fois
        /// par megarde reste baisse pour toujours, et le mixeur est un panneau que peu
        /// de gens savent ou trouver. C'est de la, bien plus souvent que du volume
        /// general, que vient un son trop faible.
        /// </summary>
        public static RaiseResult RaiseEverything()
        {
            RaiseResult r = new RaiseResult();
            r.MasterBefore = GetMaster();

            if (r.MasterBefore >= 0 && r.MasterBefore < 99.5)
            {
                r.MasterRaised = SetMaster(100);
            }
            r.MasterAfter = GetMaster();

            try
            {
                IAudioSessionEnumerator e = OpenSessions();
                if (e == null) return r;

                int count;
                e.GetCount(out count);
                for (int i = 0; i < count; i++)
                {
                    IAudioSessionControl2 s;
                    if (e.GetSession(i, out s) != 0) continue;

                    // Les sessions expirees appartiennent a des applications fermees :
                    // les remonter ne sert a rien et ferait un compte-rendu trompeur.
                    int state; s.GetState(out state);
                    if (state == 2) continue;

                    ISimpleAudioVolume v = s as ISimpleAudioVolume;
                    if (v == null) continue;

                    Guid ctx = Guid.Empty;
                    float lvl; v.GetMasterVolume(out lvl);
                    bool muted; v.GetMute(out muted);

                    int pid; s.GetProcessId(out pid);
                    string who = DescribeProcess(s, pid);

                    if (muted)
                    {
                        v.SetMute(false, ref ctx);
                        r.AppsUnmuted++;
                        r.Changed.Add(who + " : reactivee");
                    }
                    if (lvl < 0.995f)
                    {
                        v.SetMasterVolume(1.0f, ref ctx);
                        r.AppsRaised++;
                        r.Changed.Add(string.Format("{0} : {1:0} % -> 100 %", who, lvl * 100));
                    }
                }
            }
            catch { }
            return r;
        }
    }
}
