using System;
using System.Collections.Generic;
using Microsoft.Win32;

namespace LumaFlux
{
    /// <summary>
    /// Detecte les economiseurs d'energie du pilote graphique qui font varier la
    /// luminosite tout seuls.
    ///
    /// Sur les puces Intel (HD, UHD, Iris, Iris Xe), deux mecanismes analysent en
    /// permanence le contenu affiche et ajustent le retroeclairage et le contraste :
    ///
    ///   - DPST (Display Power Saving Technology) : baisse le retroeclairage sur les
    ///     images sombres et compense en poussant les niveaux dans le signal.
    ///   - LACE (Local Adaptive Contrast Enhancement) : retouche le contraste par zones.
    ///
    /// Consequence pour un outil comme celui-ci : la luminosite semble « respirer » en
    /// permanence, et le reglage demande n'est jamais tenu. Le probleme est facile a
    /// attribuer a tort a l'application, car ces mecanismes agissent en aval de la LUT
    /// et n'apparaissent NI dans SetDeviceGammaRamp, NI dans WmiMonitorBrightness.
    ///
    /// Le bit 0x20 de FeatureTestControl desactive le DPST : a 0 il est actif, a 1 il
    /// ne l'est plus.
    /// </summary>
    public static class IntelDpst
    {
        private const string ClassPath =
            @"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}";
        private const string ValueName = "FeatureTestControl";
        private const int DpstDisableBit = 0x20;

        public class Adapter
        {
            public string SubKey;        // "0000", "0001"...
            public string Description;
            public int FeatureTestControl;
            public bool DpstActive;
        }

        /// <summary>Cartes Intel trouvees, avec l'etat de leur economiseur d'ecran.</summary>
        public static List<Adapter> FindIntelAdapters()
        {
            List<Adapter> found = new List<Adapter>();
            try
            {
                using (RegistryKey root = Registry.LocalMachine.OpenSubKey(ClassPath))
                {
                    if (root == null) return found;

                    foreach (string name in root.GetSubKeyNames())
                    {
                        if (name.Length != 4) continue;   // seuls 0000, 0001... sont des cartes
                        using (RegistryKey k = root.OpenSubKey(name))
                        {
                            if (k == null) continue;
                            string desc = k.GetValue("DriverDesc") as string;
                            if (string.IsNullOrEmpty(desc)) continue;
                            if (desc.IndexOf("Intel", StringComparison.OrdinalIgnoreCase) < 0) continue;

                            object raw = k.GetValue(ValueName);
                            if (raw == null) continue;

                            Adapter a = new Adapter();
                            a.SubKey = name;
                            a.Description = desc;
                            a.FeatureTestControl = Convert.ToInt32(raw);
                            a.DpstActive = (a.FeatureTestControl & DpstDisableBit) == 0;
                            found.Add(a);
                        }
                    }
                }
            }
            catch { }
            return found;
        }

        /// <summary>Vrai si au moins une carte Intel laisse son economiseur agir.</summary>
        public static bool IsAnyDpstActive()
        {
            foreach (Adapter a in FindIntelAdapters())
                if (a.DpstActive) return true;
            return false;
        }

        /// <summary>LACE, l'autre mecanisme, visible dans les reglages de l'interface Intel.</summary>
        public static bool IsLaceActive()
        {
            try
            {
                using (RegistryKey k = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Intel\Display\igfxcui\MISC"))
                {
                    if (k == null) return false;
                    object v = k.GetValue("BKPDisplayLACE");
                    return v != null && Convert.ToInt32(v) != 0;
                }
            }
            catch { return false; }
        }

        /// <summary>
        /// Pose le bit qui desactive le DPST sur chaque carte Intel.
        /// Demande les droits administrateur, et un redemarrage pour prendre effet.
        /// Retourne le nombre de cartes modifiees, ou -1 en cas de refus d'acces.
        /// </summary>
        public static int DisableDpst()
        {
            int changed = 0;
            try
            {
                using (RegistryKey root = Registry.LocalMachine.OpenSubKey(ClassPath, true))
                {
                    if (root == null) return -1;

                    foreach (Adapter a in FindIntelAdapters())
                    {
                        if (!a.DpstActive) continue;
                        using (RegistryKey k = root.OpenSubKey(a.SubKey, true))
                        {
                            if (k == null) continue;
                            k.SetValue(ValueName, a.FeatureTestControl | DpstDisableBit, RegistryValueKind.DWord);
                            changed++;
                        }
                    }
                }
                return changed;
            }
            catch (UnauthorizedAccessException) { return -1; }
            catch (System.Security.SecurityException) { return -1; }
            catch { return -1; }
        }

        /// <summary>Remet l'etat d'origine : le DPST redevient actif.</summary>
        public static int EnableDpst()
        {
            int changed = 0;
            try
            {
                using (RegistryKey root = Registry.LocalMachine.OpenSubKey(ClassPath, true))
                {
                    if (root == null) return -1;

                    foreach (Adapter a in FindIntelAdapters())
                    {
                        if (a.DpstActive) continue;
                        using (RegistryKey k = root.OpenSubKey(a.SubKey, true))
                        {
                            if (k == null) continue;
                            k.SetValue(ValueName, a.FeatureTestControl & ~DpstDisableBit, RegistryValueKind.DWord);
                            changed++;
                        }
                    }
                }
                return changed;
            }
            catch { return -1; }
        }

        /// <summary>Resume lisible pour la page de diagnostics.</summary>
        public static string Describe()
        {
            List<Adapter> adapters = FindIntelAdapters();
            if (adapters.Count == 0) return "aucune carte Intel : sans objet";

            List<string> parts = new List<string>();
            foreach (Adapter a in adapters)
                parts.Add(string.Format("{0} : DPST {1} (0x{2:X})",
                    Shorten(a.Description), a.DpstActive ? "ACTIF" : "desactive", a.FeatureTestControl));

            if (IsLaceActive()) parts.Add("LACE actif");
            return string.Join("  |  ", parts.ToArray());
        }

        private static string Shorten(string desc)
        {
            if (string.IsNullOrEmpty(desc)) return "Intel";
            return desc.Replace("Intel(R) ", "").Replace(" Graphics", "");
        }

        /// <summary>Texte d'explication affiche a l'utilisateur.</summary>
        public const string Explanation =
            "Le pilote graphique Intel fait varier la luminosite de lui-meme.\n\n"
          + "Deux mecanismes analysent en permanence l'image affichee et ajustent le "
          + "retroeclairage : DPST (economie d'energie de l'affichage) et LACE "
          + "(contraste adaptatif). C'est ce qui donne l'impression que l'ecran "
          + "« respire » : il s'assombrit sur une page sombre, s'eclaircit sur une page "
          + "claire, sans arret.\n\n"
          + "Ces mecanismes agissent APRES la table de couleurs : aucune application de "
          + "reglage d'ecran ne peut les compenser, et ils sont invisibles aux mesures "
          + "logicielles habituelles.\n\n"
          + "Deux facons de les arreter :\n\n"
          + "1. Intel Graphics Command Center  (recommande, immediat, sans redemarrage)\n"
          + "   Systeme > Alimentation > Economie d'energie de l'affichage : Desactiver\n"
          + "   A faire pour « Sur batterie » ET « Sur secteur ».\n\n"
          + "2. Le bouton ci-dessous ecrit le bit correspondant dans le registre.\n"
          + "   Droits administrateur requis, et redemarrage necessaire.";
    }
}
