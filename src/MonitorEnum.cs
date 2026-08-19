using System;
using System.Collections.Generic;

namespace OpusScreen
{
    /// <summary>
    /// Un ecran physique detecte sur la machine.
    /// PangoBright appelait ca "Monitor N" dans son menu ; f.lux utilisait l'EDID
    /// pour retrouver le meme ecran d'une session a l'autre. On fait les deux.
    /// </summary>
    public class MonitorInfo
    {
        public IntPtr Handle;        // HMONITOR, necessaire pour le DDC/CI
        public string DeviceName;    // "\\.\DISPLAY1", necessaire pour CreateDC
        public string FriendlyName;  // "Dell U2412M" ou a defaut "Ecran 1"
        public string StableId;      // identifiant persistant pour les reglages memorises
        public Native.RECT Bounds;
        public bool IsPrimary;
        public int Index;

        /// <summary>Dalle integree d'un portable : la seule que le reglage WMI atteigne.</summary>
        public bool IsInternal;

        /// <summary>« HDMI », « DisplayPort », « dalle interne »... vide si inconnu.</summary>
        public string Connection = "";

        public string Label
        {
            get
            {
                string suffix = IsPrimary ? " (principal)" : "";
                return string.Format("Ecran {0} - {1}{2}", Index + 1, FriendlyName, suffix);
            }
        }

        /// <summary>Deuxieme ligne des listes : ce qui distingue deux ecrans identiques.</summary>
        public string Detail
        {
            get
            {
                string size = Bounds.Width + " x " + Bounds.Height;
                if (Connection.Length > 0) size += "  -  " + Connection;
                return size;
            }
        }
    }

    /// <summary>Enumere les ecrans. Responsabilite unique : produire la liste.</summary>
    public static class MonitorEnum
    {
        public static List<MonitorInfo> All()
        {
            List<MonitorInfo> found = new List<MonitorInfo>();

            Native.MonitorEnumProc cb = delegate(IntPtr hMon, IntPtr hdc, ref Native.RECT r, IntPtr data)
            {
                Native.MONITORINFOEX mi = new Native.MONITORINFOEX();
                mi.cbSize = System.Runtime.InteropServices.Marshal.SizeOf(typeof(Native.MONITORINFOEX));
                if (Native.GetMonitorInfo(hMon, ref mi))
                {
                    MonitorInfo m = new MonitorInfo();
                    m.Handle = hMon;
                    m.DeviceName = mi.szDevice;
                    m.Bounds = mi.rcMonitor;
                    m.IsPrimary = (mi.dwFlags & Native.MONITORINFOF_PRIMARY) != 0;
                    m.Index = found.Count;
                    found.Add(m);
                }
                return true; // continuer l'enumeration
            };

            Native.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, cb, IntPtr.Zero);

            if (found.Count == 0)
            {
                // Repli defensif : au pire on pilote l'affichage par defaut.
                MonitorInfo m = new MonitorInfo();
                m.Handle = IntPtr.Zero;
                m.DeviceName = null;             // CreateDC(null) -> ecran principal
                m.FriendlyName = "Ecran principal";
                m.StableId = "DISPLAY:default";
                m.IsPrimary = true;
                m.Index = 0;
                found.Add(m);
                return found;
            }

            // Les noms ne sont resolus qu'une fois la liste complete : la levee
            // d'ambiguite entre deux ecrans identiques a besoin de les voir tous.
            Dictionary<string, DisplayConfig.Target> targets = DisplayConfig.Query();
            foreach (MonitorInfo m in found) ResolveNames(m, targets);
            DisambiguateIds(found);

            return found;
        }

        /// <summary>
        /// Nom lisible et identifiant stable. DisplayConfig d'abord, car lui seul
        /// donne le nom grave dans l'ecran et un chemin unique par connecteur ;
        /// EnumDisplayDevices ensuite, pour les systemes ou l'API precedente se tait.
        /// </summary>
        private static void ResolveNames(MonitorInfo m, Dictionary<string, DisplayConfig.Target> targets)
        {
            m.FriendlyName = "Ecran " + (m.Index + 1);
            m.StableId = m.DeviceName != null ? "DEV:" + m.DeviceName : "DISPLAY:default";

            DisplayConfig.Target t = null;
            if (m.DeviceName != null && targets.Count > 0) targets.TryGetValue(m.DeviceName, out t);

            if (t != null)
            {
                if (t.FriendlyName.Length > 0) m.FriendlyName = t.FriendlyName;
                m.IsInternal = t.IsInternal;
                m.Connection = DisplayConfig.ConnectionName(t.OutputTechnology);
                if (t.DevicePath.Length > 0) m.StableId = ExtractHardwareId(t.DevicePath);
            }

            // Complement par l'ancienne voie : elle sert de secours au nom comme a
            // l'identifiant, et reste seule disponible sur certains pilotes.
            try
            {
                Native.DISPLAY_DEVICE dd = new Native.DISPLAY_DEVICE();
                dd.cb = System.Runtime.InteropServices.Marshal.SizeOf(typeof(Native.DISPLAY_DEVICE));

                // flag 1 = EDD_GET_DEVICE_INTERFACE_NAME : donne un DeviceID persistant
                if (Native.EnumDisplayDevices(m.DeviceName, 0, ref dd, 1))
                {
                    if (t == null && !string.IsNullOrEmpty(dd.DeviceString))
                        m.FriendlyName = dd.DeviceString.Trim();
                    if (t == null && !string.IsNullOrEmpty(dd.DeviceID))
                        m.StableId = ExtractHardwareId(dd.DeviceID);
                }
            }
            catch { /* nom par defaut conserve */ }
        }

        /// <summary>
        /// "\\?\DISPLAY#DELA07E#5&12ab&0&UID4353#..." -> "HW:DELA07E" : la partie qui
        /// reste identique au fil des rebranchements, contrairement au numero de port.
        /// </summary>
        private static string ExtractHardwareId(string deviceId)
        {
            string[] parts = deviceId.Split('#');
            if (parts.Length >= 2 && parts[1].Length > 0)
                return "HW:" + parts[1];
            return "ID:" + deviceId;
        }

        /// <summary>
        /// Deux ecrans du meme modele produisent le meme identifiant materiel - et
        /// c'est la configuration a deux ecrans la plus courante qui soit. Sans levee
        /// d'ambiguite, les deux ecrans partagent une seule fiche de reglages : le
        /// voile de l'un se pose sur l'autre, le profil independant du second ecrase
        /// celui du premier, et « eteindre cet ecran » en eteint deux.
        ///
        /// Le suffixe n'est ajoute QUE s'il y a collision. Un ecran seul de son modele
        /// garde donc l'identifiant qu'il avait, et les reglages deja memorises ne
        /// sont pas perdus par la correction elle-meme.
        /// </summary>
        private static void DisambiguateIds(List<MonitorInfo> monitors)
        {
            Dictionary<string, List<MonitorInfo>> groups = new Dictionary<string, List<MonitorInfo>>();
            foreach (MonitorInfo m in monitors)
            {
                List<MonitorInfo> g;
                if (!groups.TryGetValue(m.StableId, out g))
                {
                    g = new List<MonitorInfo>();
                    groups[m.StableId] = g;
                }
                g.Add(m);
            }

            foreach (KeyValuePair<string, List<MonitorInfo>> kv in groups)
            {
                if (kv.Value.Count < 2) continue;

                // Le numero de sortie GDI est le seul discriminant toujours present ;
                // il est stable tant que les ecrans restent sur les memes ports.
                for (int i = 0; i < kv.Value.Count; i++)
                {
                    MonitorInfo m = kv.Value[i];
                    string port = m.DeviceName != null ? m.DeviceName.Replace("\\\\.\\", "") : ("n" + i);
                    m.StableId = kv.Key + "@" + port;
                }
            }
        }
    }
}
