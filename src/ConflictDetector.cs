using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace LumaFlux
{
    /// <summary>
    /// Detecte les autres applications qui pilotent la meme LUT gamma.
    ///
    /// Il n'existe qu'une seule table de conversion par carte graphique : deux
    /// programmes qui y ecrivent chacun de leur cote se remplacent mutuellement en
    /// boucle, ce qui donne un ecran qui clignote et des reglages qui "ne tiennent pas".
    /// Comme LumaFlux reprend justement les roles de f.lux et de PangoBright, le cas
    /// est frequent au premier lancement.
    /// </summary>
    public static class ConflictDetector
    {
        /// <summary>Nom de processus (sans .exe) -> nom lisible.</summary>
        private static readonly Dictionary<string, string> Known = BuildKnown();

        private static Dictionary<string, string> BuildKnown()
        {
            Dictionary<string, string> d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            d["flux"] = "f.lux";
            d["PangoBright"] = "PangoBright";
            d["Iris"] = "Iris";
            d["lightbulb"] = "LightBulb";
            d["Twinkle Tray"] = "Twinkle Tray";
            d["dimmer"] = "Dimmer";
            d["ScreenDimmer"] = "Screen Dimmer";
            d["gammy"] = "Gammy";
            d["redshift"] = "Redshift";
            d["clickmonitorddc"] = "ClickMonitorDDC";
            return d;
        }

        public class Conflict
        {
            public string DisplayName;
            public int ProcessId;
            public string ProcessName;
        }

        public static List<Conflict> Running()
        {
            List<Conflict> found = new List<Conflict>();
            try
            {
                foreach (Process p in Process.GetProcesses())
                {
                    using (p)
                    {
                        string friendly;
                        if (!Known.TryGetValue(p.ProcessName, out friendly)) continue;
                        Conflict c = new Conflict();
                        c.DisplayName = friendly;
                        c.ProcessName = p.ProcessName;
                        c.ProcessId = p.Id;
                        found.Add(c);
                    }
                }
            }
            catch { }
            return found;
        }

        /// <summary>
        /// Ferme les processus indiques. Retourne le nombre reellement arretes.
        /// On demande d'abord poliment la fermeture des fenetres ; on ne force qu'ensuite,
        /// pour laisser a l'application concurrente la chance de restaurer sa propre rampe.
        /// </summary>
        public static int CloseAll(List<Conflict> conflicts)
        {
            int closed = 0;
            foreach (Conflict c in conflicts)
            {
                try
                {
                    Process p = Process.GetProcessById(c.ProcessId);
                    using (p)
                    {
                        if (p.CloseMainWindow() && p.WaitForExit(3000)) { closed++; continue; }
                        p.Kill();
                        p.WaitForExit(2000);
                        closed++;
                    }
                }
                catch { /* deja termine, ou droits insuffisants */ }
            }
            return closed;
        }

        public static string Describe(List<Conflict> conflicts)
        {
            if (conflicts.Count == 0) return null;
            List<string> names = new List<string>();
            foreach (Conflict c in conflicts)
                if (!names.Contains(c.DisplayName)) names.Add(c.DisplayName);
            return string.Join(" et ", names.ToArray());
        }
    }
}
