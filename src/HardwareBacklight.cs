using System;
using System.Collections.Generic;
using System.Management;
using System.Threading;

namespace LumaFlux
{
    /// <summary>
    /// Pilote le retroeclairage physique de l'ecran - le seul etage qui produit
    /// reellement plus de photons, contrairement a la gamma et au voile qui ne font
    /// que redistribuer ce que la dalle emet deja.
    ///
    /// Ni PangoBright ni f.lux ne touchent a cette couche. C'est ce qui rend
    /// credible le passage au-dessus de 100 % : on commence par vider la reserve
    /// materielle avant de solliciter le logiciel.
    ///
    ///   - Ecrans externes : DDC/CI par dxva2.dll (le protocole du menu OSD)
    ///   - Portables       : WMI, classe WmiMonitorBrightnessMethods
    ///
    /// Ces appels sont lents (parfois 500 ms) : tout passe par un thread dedie avec
    /// fusion des demandes, pour que le curseur de l'interface reste fluide.
    /// </summary>
    public static class HardwareBacklight
    {
        private static readonly object Sync = new object();
        private static Thread _worker;
        private static int _pendingTarget = -1;
        private static bool _hasPending;
        private static readonly AutoResetEvent Signal = new AutoResetEvent(false);
        private static volatile bool _running;

        private static bool? _laptopSupported;
        private static readonly Dictionary<string, bool> DdcSupport = new Dictionary<string, bool>();

        /// <summary>Etat lisible pour l'interface : "DDC/CI", "portable (WMI)" ou "non disponible".</summary>
        public static string LastCapabilityDescription = "non teste";

        public static void Start()
        {
            if (_worker != null) return;
            _running = true;
            _worker = new Thread(WorkerLoop);
            _worker.IsBackground = true;
            _worker.Name = "LumaFlux-Backlight";
            _worker.Start();
        }

        public static void Stop()
        {
            _running = false;
            Signal.Set();
        }

        /// <summary>
        /// Demande un niveau 0-100. Retour immediat : le travail se fait en arriere-plan
        /// et seule la derniere demande recue est reellement appliquee.
        /// </summary>
        public static void RequestLevel(int percent)
        {
            if (percent < 0) percent = 0;
            if (percent > 100) percent = 100;
            lock (Sync) { _pendingTarget = percent; _hasPending = true; }
            Signal.Set();
        }

        private static void WorkerLoop()
        {
            while (_running)
            {
                Signal.WaitOne(500);
                if (!_running) break;

                int target;
                lock (Sync)
                {
                    if (!_hasPending) continue;
                    target = _pendingTarget;
                    _hasPending = false;
                }

                bool any = false;
                try { any |= SetLaptopBrightness(target); } catch { }
                try { any |= SetExternalBrightness(target); } catch { }

                if (!any) LastCapabilityDescription = "non disponible sur ce materiel";
            }
        }

        // ---------------------------------------------------------------- portables (WMI)

        private static bool SetLaptopBrightness(int percent)
        {
            if (_laptopSupported.HasValue && !_laptopSupported.Value) return false;
            try
            {
                using (ManagementClass cls = new ManagementClass("root\\WMI", "WmiMonitorBrightnessMethods", null))
                using (ManagementObjectCollection instances = cls.GetInstances())
                {
                    bool done = false;
                    foreach (ManagementObject mo in instances)
                    {
                        using (mo)
                        {
                            mo.InvokeMethod("WmiSetBrightness", new object[] { (uint)1, (byte)percent });
                            done = true;
                        }
                    }
                    _laptopSupported = done;
                    if (done) LastCapabilityDescription = "ecran de portable (WMI)";
                    return done;
                }
            }
            catch
            {
                _laptopSupported = false;
                return false;
            }
        }

        // ---------------------------------------------------------------- externes (DDC/CI)

        private static bool SetExternalBrightness(int percent)
        {
            bool any = false;
            foreach (MonitorInfo m in MonitorEnum.All())
            {
                if (m.Handle == IntPtr.Zero) continue;

                bool known;
                if (DdcSupport.TryGetValue(m.StableId, out known) && !known) continue;

                Native.PHYSICAL_MONITOR[] physical = null;
                uint count = 0;
                try
                {
                    if (!Native.GetNumberOfPhysicalMonitorsFromHMONITOR(m.Handle, ref count) || count == 0)
                    {
                        DdcSupport[m.StableId] = false;
                        continue;
                    }

                    physical = new Native.PHYSICAL_MONITOR[count];
                    if (!Native.GetPhysicalMonitorsFromHMONITOR(m.Handle, count, physical))
                    {
                        DdcSupport[m.StableId] = false;
                        continue;
                    }

                    foreach (Native.PHYSICAL_MONITOR pm in physical)
                    {
                        uint min = 0, cur = 0, max = 0;
                        if (!Native.GetMonitorBrightness(pm.hPhysicalMonitor, ref min, ref cur, ref max))
                        {
                            DdcSupport[m.StableId] = false;
                            continue;
                        }

                        // Le moniteur expose sa propre echelle, rarement 0-100.
                        uint value = (uint)Math.Round(min + (max - min) * (percent / 100.0));
                        if (Native.SetMonitorBrightness(pm.hPhysicalMonitor, value))
                        {
                            DdcSupport[m.StableId] = true;
                            LastCapabilityDescription = "ecran externe (DDC/CI)";
                            any = true;
                        }
                        else
                        {
                            DdcSupport[m.StableId] = false;
                        }
                    }
                }
                catch
                {
                    DdcSupport[m.StableId] = false;
                }
                finally
                {
                    if (physical != null)
                    {
                        try { Native.DestroyPhysicalMonitors(count, physical); } catch { }
                    }
                }
            }
            return any;
        }

        /// <summary>
        /// Sonde le materiel une seule fois, sans rien modifier, pour savoir quoi
        /// afficher dans l'interface.
        /// </summary>
        public static string Probe()
        {
            List<string> found = new List<string>();

            try
            {
                using (ManagementClass cls = new ManagementClass("root\\WMI", "WmiMonitorBrightness", null))
                using (ManagementObjectCollection col = cls.GetInstances())
                {
                    foreach (ManagementObject mo in col) { using (mo) { found.Add("portable (WMI)"); break; } }
                }
            }
            catch { }

            try
            {
                foreach (MonitorInfo m in MonitorEnum.All())
                {
                    if (m.Handle == IntPtr.Zero) continue;
                    uint count = 0;
                    if (!Native.GetNumberOfPhysicalMonitorsFromHMONITOR(m.Handle, ref count) || count == 0) continue;

                    Native.PHYSICAL_MONITOR[] physical = new Native.PHYSICAL_MONITOR[count];
                    if (!Native.GetPhysicalMonitorsFromHMONITOR(m.Handle, count, physical)) continue;
                    try
                    {
                        uint mn = 0, cur = 0, mx = 0;
                        if (Native.GetMonitorBrightness(physical[0].hPhysicalMonitor, ref mn, ref cur, ref mx))
                        {
                            found.Add("DDC/CI sur " + m.FriendlyName);
                        }
                    }
                    finally { try { Native.DestroyPhysicalMonitors(count, physical); } catch { } }
                }
            }
            catch { }

            LastCapabilityDescription = found.Count == 0
                ? "non disponible sur ce materiel"
                : string.Join(", ", found.ToArray());
            return LastCapabilityDescription;
        }
    }
}
