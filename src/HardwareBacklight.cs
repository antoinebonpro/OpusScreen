using System;
using System.Collections.Generic;
using System.Management;
using System.Threading;

namespace OpusScreen
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
    /// Les demandes sont NOMINATIVES : une consigne vaut pour un ecran designe, pas
    /// pour la machine. La version precedente n'avait qu'un niveau global, ce qui
    /// donnait sur une configuration a deux ecrans un resultat absurde - le dernier
    /// ecran traite imposait sa luminosite materielle a tous les autres, et un
    /// decalage propre a un ecran s'appliquait en fait a son voisin.
    ///
    /// Ces appels sont lents (parfois 500 ms) : tout passe par un thread dedie avec
    /// fusion des demandes, pour que le curseur de l'interface reste fluide.
    /// </summary>
    public static class HardwareBacklight
    {
        private static readonly object Sync = new object();
        private static Thread _worker;
        private static readonly Dictionary<string, int> Pending = new Dictionary<string, int>();
        private static readonly AutoResetEvent Signal = new AutoResetEvent(false);
        private static volatile bool _running;

        private static bool? _wmiSupported;
        private static readonly Dictionary<string, bool> DdcSupport = new Dictionary<string, bool>();
        private static readonly Dictionary<string, string> PerMonitor = new Dictionary<string, string>();

        /// <summary>Etat lisible pour l'interface : "DDC/CI", "portable (WMI)" ou "non disponible".</summary>
        public static string LastCapabilityDescription = "non teste";

        public static void Start()
        {
            if (_worker != null) return;
            _running = true;
            _worker = new Thread(WorkerLoop);
            _worker.IsBackground = true;
            _worker.Name = "OpusScreen-Backlight";
            _worker.Start();
        }

        public static void Stop()
        {
            _running = false;
            Signal.Set();
        }

        /// <summary>
        /// Demande un niveau 0-100 POUR UN ECRAN. Retour immediat : le travail se fait
        /// en arriere-plan et seule la derniere demande recue pour cet ecran est
        /// reellement appliquee.
        /// </summary>
        public static void RequestLevel(MonitorInfo m, int percent)
        {
            if (m == null || string.IsNullOrEmpty(m.StableId)) return;
            if (percent < 0) percent = 0;
            if (percent > 100) percent = 100;
            lock (Sync) { Pending[m.StableId] = percent; }
            Signal.Set();
        }

        /// <summary>Ce que le materiel de cet ecran sait faire. Vide tant qu'il n'a pas ete sollicite.</summary>
        public static string DescribeFor(MonitorInfo m)
        {
            if (m == null) return "";
            lock (Sync)
            {
                string s;
                return PerMonitor.TryGetValue(m.StableId, out s) ? s : "";
            }
        }

        private static void WorkerLoop()
        {
            while (_running)
            {
                Signal.WaitOne(500);
                if (!_running) break;

                Dictionary<string, int> batch;
                lock (Sync)
                {
                    if (Pending.Count == 0) continue;
                    batch = new Dictionary<string, int>(Pending);
                    Pending.Clear();
                }

                List<MonitorInfo> monitors;
                try { monitors = MonitorEnum.All(); }
                catch { continue; }

                bool anySuccess = false;
                foreach (KeyValuePair<string, int> want in batch)
                {
                    MonitorInfo target = null;
                    foreach (MonitorInfo m in monitors)
                        if (m.StableId == want.Key) { target = m; break; }

                    // L'ecran a ete debranche entre la demande et son traitement.
                    if (target == null) continue;

                    anySuccess |= ApplyToOne(target, want.Value);
                }

                if (!anySuccess && batch.Count > 0)
                    LastCapabilityDescription = "non disponible sur ce materiel";
            }
        }

        /// <summary>
        /// Regle un ecran, et un seul.
        ///
        /// L'ordre des tentatives suit ce que l'on sait de l'ecran : la dalle interne
        /// d'un portable passe par WMI, un ecran externe par DDC/CI. Quand la
        /// technologie de sortie n'a pas pu etre lue - pilote muet, session distante -
        /// on essaie le DDC/CI puis, pour l'ecran principal seulement, le WMI :
        /// c'est le cas de figure du portable dont Windows ne declare rien.
        /// </summary>
        private static bool ApplyToOne(MonitorInfo m, int percent)
        {
            if (m.IsInternal)
            {
                bool ok = SetLaptopBrightness(percent);
                Remember(m, ok ? "dalle interne (WMI)" : "aucun reglage materiel");
                return ok;
            }

            if (SetExternalBrightness(m, percent))
            {
                Remember(m, "DDC/CI");
                return true;
            }

            if (m.IsPrimary && SetLaptopBrightness(percent))
            {
                Remember(m, "dalle interne (WMI)");
                return true;
            }

            Remember(m, "aucun reglage materiel");
            return false;
        }

        private static void Remember(MonitorInfo m, string what)
        {
            lock (Sync) { PerMonitor[m.StableId] = what; }
            if (what != "aucun reglage materiel") LastCapabilityDescription = what;
        }

        // ---------------------------------------------------------------- portables (WMI)

        /// <summary>
        /// WMI ne sait piloter que la dalle integree, et il n'y en a qu'une : la
        /// classe ne prend pas d'ecran en parametre. C'est pourquoi le reglage doit
        /// etre reserve a la dalle interne, et surtout pas applique pour le compte
        /// d'un ecran externe.
        /// </summary>
        private static bool SetLaptopBrightness(int percent)
        {
            if (_wmiSupported.HasValue && !_wmiSupported.Value) return false;
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
                    _wmiSupported = done;
                    return done;
                }
            }
            catch
            {
                _wmiSupported = false;
                return false;
            }
        }

        // ---------------------------------------------------------------- externes (DDC/CI)

        private static bool SetExternalBrightness(MonitorInfo m, int percent)
        {
            if (m.Handle == IntPtr.Zero) return false;

            bool known;
            if (DdcSupport.TryGetValue(m.StableId, out known) && !known) return false;

            Native.PHYSICAL_MONITOR[] physical = null;
            uint count = 0;
            try
            {
                if (!Native.GetNumberOfPhysicalMonitorsFromHMONITOR(m.Handle, ref count) || count == 0)
                {
                    DdcSupport[m.StableId] = false;
                    return false;
                }

                physical = new Native.PHYSICAL_MONITOR[count];
                if (!Native.GetPhysicalMonitorsFromHMONITOR(m.Handle, count, physical))
                {
                    DdcSupport[m.StableId] = false;
                    return false;
                }

                bool any = false;
                foreach (Native.PHYSICAL_MONITOR pm in physical)
                {
                    uint min = 0, cur = 0, max = 0;
                    if (!Native.GetMonitorBrightness(pm.hPhysicalMonitor, ref min, ref cur, ref max)) continue;

                    // Le moniteur expose sa propre echelle, rarement 0-100.
                    uint value = (uint)Math.Round(min + (max - min) * (percent / 100.0));
                    if (Native.SetMonitorBrightness(pm.hPhysicalMonitor, value)) any = true;
                }

                DdcSupport[m.StableId] = any;
                return any;
            }
            catch
            {
                DdcSupport[m.StableId] = false;
                return false;
            }
            finally
            {
                if (physical != null)
                {
                    try { Native.DestroyPhysicalMonitors(count, physical); } catch { }
                }
            }
        }

        /// <summary>
        /// Sonde le materiel une seule fois, sans rien modifier, pour savoir quoi
        /// afficher dans l'interface. Le resultat est detaille par ecran : sur une
        /// configuration mixte - portable plus ecran externe - un simple « disponible »
        /// ne dirait pas lequel des deux repond.
        /// </summary>
        public static string Probe()
        {
            List<string> found = new List<string>();
            bool wmi = false;

            try
            {
                using (ManagementClass cls = new ManagementClass("root\\WMI", "WmiMonitorBrightness", null))
                using (ManagementObjectCollection col = cls.GetInstances())
                {
                    foreach (ManagementObject mo in col) { using (mo) { wmi = true; break; } }
                }
            }
            catch { }

            try
            {
                foreach (MonitorInfo m in MonitorEnum.All())
                {
                    if (m.IsInternal)
                    {
                        if (wmi)
                        {
                            Remember(m, "dalle interne (WMI)");
                            found.Add(m.FriendlyName + " : WMI");
                        }
                        else Remember(m, "aucun reglage materiel");
                        continue;
                    }

                    if (m.Handle == IntPtr.Zero) continue;
                    uint count = 0;
                    if (!Native.GetNumberOfPhysicalMonitorsFromHMONITOR(m.Handle, ref count) || count == 0)
                    {
                        Remember(m, "aucun reglage materiel");
                        continue;
                    }

                    Native.PHYSICAL_MONITOR[] physical = new Native.PHYSICAL_MONITOR[count];
                    if (!Native.GetPhysicalMonitorsFromHMONITOR(m.Handle, count, physical)) continue;
                    try
                    {
                        uint mn = 0, cur = 0, mx = 0;
                        if (Native.GetMonitorBrightness(physical[0].hPhysicalMonitor, ref mn, ref cur, ref mx))
                        {
                            DdcSupport[m.StableId] = true;
                            Remember(m, "DDC/CI");
                            found.Add(m.FriendlyName + " : DDC/CI");
                        }
                        else
                        {
                            DdcSupport[m.StableId] = false;
                            Remember(m, wmi && m.IsPrimary ? "dalle interne (WMI)" : "aucun reglage materiel");
                        }
                    }
                    finally { try { Native.DestroyPhysicalMonitors(count, physical); } catch { } }
                }
            }
            catch { }

            if (found.Count == 0 && wmi) found.Add("portable (WMI)");

            LastCapabilityDescription = found.Count == 0
                ? "non disponible sur ce materiel"
                : string.Join(", ", found.ToArray());
            return LastCapabilityDescription;
        }
    }
}
