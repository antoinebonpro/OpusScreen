using System;
using System.Collections.Generic;

namespace LumaFlux
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

        public string Label
        {
            get
            {
                string suffix = IsPrimary ? " (principal)" : "";
                return string.Format("Ecran {0} - {1}{2}", Index + 1, FriendlyName, suffix);
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
                    ResolveNames(m);
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
            }
            return found;
        }

        /// <summary>
        /// Recupere le nom lisible et un identifiant stable via EnumDisplayDevices.
        /// Le DeviceID contient la cle materielle (ex. MONITOR\DELA07E\...), ce qui joue
        /// le meme role que la lecture EDID que fait f.lux via SetupDi*.
        /// </summary>
        private static void ResolveNames(MonitorInfo m)
        {
            m.FriendlyName = "Ecran " + (m.Index + 1);
            m.StableId = m.DeviceName != null ? "DEV:" + m.DeviceName : "DISPLAY:default";

            try
            {
                Native.DISPLAY_DEVICE dd = new Native.DISPLAY_DEVICE();
                dd.cb = System.Runtime.InteropServices.Marshal.SizeOf(typeof(Native.DISPLAY_DEVICE));

                // flag 1 = EDD_GET_DEVICE_INTERFACE_NAME : donne un DeviceID persistant
                if (Native.EnumDisplayDevices(m.DeviceName, 0, ref dd, 1))
                {
                    if (!string.IsNullOrEmpty(dd.DeviceString))
                        m.FriendlyName = dd.DeviceString.Trim();
                    if (!string.IsNullOrEmpty(dd.DeviceID))
                        m.StableId = ExtractHardwareId(dd.DeviceID);
                }
            }
            catch { /* nom par defaut conserve */ }
        }

        /// <summary>
        /// "\\?\DISPLAY#DELA07E#5&12ab#..." -> "DELA07E" : la partie qui reste identique
        /// au fil des rebranchements, contrairement au numero de port.
        /// </summary>
        private static string ExtractHardwareId(string deviceId)
        {
            string[] parts = deviceId.Split('#');
            if (parts.Length >= 2 && parts[1].Length > 0)
                return "HW:" + parts[1];
            return "ID:" + deviceId;
        }
    }
}
