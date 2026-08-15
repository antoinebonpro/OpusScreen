using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Text;

namespace OpusScreen
{
    /// <summary>Ce qui pilote la temperature quand l'automatisme est actif.</summary>
    public enum ScheduleMode
    {
        Manual = 0,     // rien d'automatique
        Solar,          // lever et coucher du soleil calcules sur place
        FixedHours      // horaires saisis par l'utilisateur
    }

    /// <summary>Reglages propres a un ecran, retrouves par identifiant materiel.</summary>
    public class MonitorSettings
    {
        public string StableId = "";
        public string FriendlyName = "";
        public bool Enabled = true;          // faux = cet ecran n'est pas touche
        public bool Independent;             // vrai = utilise son propre profil
        public Profile Own = new Profile();
        public double BrightnessOffset;      // decalage applique au profil global, en points
        public bool Blackout;                // ecran eteint (equivalent du BlackOut de Lunar)

        public string Serialize()
        {
            return string.Join("~", new string[] {
                Esc(StableId), Esc(FriendlyName), Enabled ? "1" : "0", Independent ? "1" : "0",
                BrightnessOffset.ToString("0.##", CultureInfo.InvariantCulture),
                Blackout ? "1" : "0", Esc(Own.Serialize())
            });
        }

        public static MonitorSettings Deserialize(string s)
        {
            MonitorSettings m = new MonitorSettings();
            try
            {
                string[] f = s.Split('~');
                if (f.Length > 0) m.StableId = Unesc(f[0]);
                if (f.Length > 1) m.FriendlyName = Unesc(f[1]);
                if (f.Length > 2) m.Enabled = f[2] == "1";
                if (f.Length > 3) m.Independent = f[3] == "1";
                if (f.Length > 4) double.TryParse(f[4], NumberStyles.Float, CultureInfo.InvariantCulture, out m.BrightnessOffset);
                if (f.Length > 5) m.Blackout = f[5] == "1";
                if (f.Length > 6) m.Own = Profile.Deserialize(Unesc(f[6]));
            }
            catch { }
            return m;
        }

        private static string Esc(string s) { return (s ?? "").Replace("~", "%7E").Replace("|", "%7C"); }
        private static string Unesc(string s) { return (s ?? "").Replace("%7E", "~").Replace("%7C", "|"); }
    }

    /// <summary>Un raccourci global reconfigurable.</summary>
    public class HotkeyBinding
    {
        public string Action = "";
        public uint Modifiers;
        public uint Key;
        public bool Enabled = true;

        public HotkeyBinding() { }
        public HotkeyBinding(string action, uint mods, uint key)
        {
            Action = action; Modifiers = mods; Key = key;
        }

        public string Serialize()
        {
            return Action + ">" + Modifiers + ">" + Key + ">" + (Enabled ? "1" : "0");
        }

        public static HotkeyBinding Deserialize(string s)
        {
            HotkeyBinding h = new HotkeyBinding();
            string[] f = s.Split('>');
            try
            {
                if (f.Length > 0) h.Action = f[0];
                if (f.Length > 1) h.Modifiers = uint.Parse(f[1]);
                if (f.Length > 2) h.Key = uint.Parse(f[2]);
                if (f.Length > 3) h.Enabled = f[3] == "1";
            }
            catch { }
            return h;
        }

        public string Describe()
        {
            List<string> parts = new List<string>();
            if ((Modifiers & 0x2) != 0) parts.Add("Ctrl");
            if ((Modifiers & 0x1) != 0) parts.Add("Alt");
            if ((Modifiers & 0x4) != 0) parts.Add("Maj");
            if ((Modifiers & 0x8) != 0) parts.Add("Win");
            parts.Add(KeyName(Key));
            return string.Join(" + ", parts.ToArray());
        }

        public static string KeyName(uint vk)
        {
            switch (vk)
            {
                case 0x26: return "Fleche haut";
                case 0x28: return "Fleche bas";
                case 0x25: return "Fleche gauche";
                case 0x27: return "Fleche droite";
                case 0x20: return "Espace";
                case 0x2D: return "Inser";
                case 0x2E: return "Suppr";
                case 0x21: return "Page prec.";
                case 0x22: return "Page suiv.";
                case 0x24: return "Origine";
                case 0x23: return "Fin";
                default:
                    if (vk >= 0x30 && vk <= 0x39) return ((char)vk).ToString();
                    if (vk >= 0x41 && vk <= 0x5A) return ((char)vk).ToString();
                    if (vk >= 0x70 && vk <= 0x7B) return "F" + (vk - 0x6F);
                    return "0x" + vk.ToString("X2");
            }
        }
    }

    /// <summary>
    /// Tous les reglages persistants, en texte clef=valeur.
    ///
    /// PangoBright stockait les siens dans HKCU\Software\Pangolin\PangoBright ; un
    /// fichier se lit, se sauvegarde et se supprime plus facilement - et rend l'export
    /// de configuration trivial.
    /// </summary>
    public class Settings
    {
        public static string DataFolder
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "OpusScreen");
            }
        }

        private static string FilePath { get { return Path.Combine(DataFolder, "settings.ini"); } }

        /// <summary>
        /// Dossier utilise avant que l'application ne s'appelle OpusScreen. Sans reprise,
        /// un utilisateur de LumaFlux retrouverait ses reglages remis a zero par un simple
        /// changement de nom.
        /// </summary>
        private static string LegacyDataFolder
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "LumaFlux");
            }
        }

        /// <summary>
        /// Deplace la configuration de l'ancien dossier vers le nouveau, une seule fois :
        /// des que le nouveau fichier de reglages existe, l'ancien n'est plus regarde.
        ///
        /// La condition porte sur le fichier et non sur le dossier : un dossier vide
        /// suffirait sinon a faire passer la reprise pour deja faite.
        /// </summary>
        private static void MigrateLegacyFolder()
        {
            try
            {
                if (File.Exists(FilePath)) return;
                if (!File.Exists(Path.Combine(LegacyDataFolder, "settings.ini"))) return;

                Directory.CreateDirectory(DataFolder);
                foreach (string src in Directory.GetFiles(LegacyDataFolder))
                    File.Copy(src, Path.Combine(DataFolder, Path.GetFileName(src)), true);

                // L'ancien dossier n'est efface que si la copie a tenu : mieux vaut deux
                // exemplaires qu'aucun.
                if (File.Exists(FilePath)) Directory.Delete(LegacyDataFolder, true);
            }
            catch { }
        }

        /// <summary>
        /// Vrai si aucun fichier de reglages n'existait au chargement.
        /// Sert a ouvrir la fenetre au tout premier lancement : demarrer discretement
        /// est le bon comportement ensuite, mais la premiere fois cela donne
        /// l'impression que rien ne s'est passe.
        /// </summary>
        public bool IsFirstRun { get; private set; }

        // ---------------- etat visuel courant ----------------
        public Profile Current = new Profile();
        public string ActiveModeName = "Normal";
        public List<Profile> CustomProfiles = new List<Profile>();

        // ---------------- automatisme horaire ----------------
        public ScheduleMode Schedule = ScheduleMode.Manual;
        public string PresetName = "Couleurs recommandees";
        public double Latitude = 48.8566;
        public double Longitude = 2.3522;
        public double BedtimeHour = 23.0;
        public double WakeHour = 7.0;
        public double FixedDayHour = 8.0;
        public double FixedNightHour = 19.0;
        public int TransitionMinutes = 60;
        /// <summary>Fait aussi varier la luminosite avec l'heure, pas seulement la couleur.</summary>
        public bool ScheduleAffectsBrightness;
        public double DayBrightness = 100;
        public double NightBrightness = 70;

        // ---------------- luminosite adaptative au contenu ----------------
        public bool AdaptiveEnabled;
        public double AdaptiveMin = 40;
        public double AdaptiveMax = 110;
        public double AdaptiveReactivity = 3;
        public int AdaptiveIntervalMs = 1200;

        // ---------------- ecrans ----------------
        public List<MonitorSettings> Monitors = new List<MonitorSettings>();
        public bool LinkMonitors = true;

        // ---------------- regles par application ----------------
        public bool AppRulesEnabled;
        public List<AppRule> AppRules = new List<AppRule>();
        public bool DisableOnFullscreen = true;
        public bool DisableOnBattery;

        // ---------------- pauses oculaires ----------------
        public bool BreaksEnabled;
        public int BreakIntervalMinutes = 20;
        public int BreakDurationSeconds = 20;
        public bool BreakDim;
        public bool BreakSound = true;

        // ---------------- etages autorises ----------------
        public bool UseHardwareBacklight = true;
        public bool UseOverlay = true;
        public bool UseColorMatrix = true;
        public bool SmoothTransitions = true;
        public int TransitionSpeedMs = 400;

        // ---------------- systeme ----------------
        public bool StartWithWindows;
        public bool StartMinimized = true;
        public bool HotkeysEnabled = true;
        public bool TrayWheelControl = true;
        public bool SkipDarkConfirm;
        public bool IgnoreConflicts;
        public bool WarnedAboutClamp;
        public bool ShowTrayPercentage = true;

        /// <summary>
        /// Peuple des l'instanciation, et non au chargement : une remise a zero ou un
        /// import partiel laisserait sinon l'utilisateur sans aucun raccourci.
        /// </summary>
        public List<HotkeyBinding> Hotkeys = DefaultHotkeys();

        /// <summary>Vrai des qu'un raccourci a ete lu depuis un fichier.</summary>
        private bool _hotkeysFromFile;

        // ------------------------------------------------------------------ ecrans

        public MonitorSettings For(MonitorInfo m)
        {
            foreach (MonitorSettings ms in Monitors)
                if (ms.StableId == m.StableId) return ms;

            MonitorSettings created = new MonitorSettings();
            created.StableId = m.StableId;
            created.FriendlyName = m.FriendlyName;
            Monitors.Add(created);
            return created;
        }

        /// <summary>Profil effectif pour un ecran, une fois les reglages propres pris en compte.</summary>
        public Profile EffectiveFor(MonitorInfo m)
        {
            MonitorSettings ms = For(m);
            Profile p = ms.Independent ? ms.Own.Clone() : Current.Clone();
            if (!ms.Independent && Math.Abs(ms.BrightnessOffset) > 0.01)
                p.Brightness = SafetyGuard.ClampBrightness(p.Brightness + ms.BrightnessOffset);
            return p;
        }

        // ------------------------------------------------------------------ raccourcis

        public static List<HotkeyBinding> DefaultHotkeys()
        {
            const uint CTRL = 0x2, ALT = 0x1, SHIFT = 0x4;
            List<HotkeyBinding> l = new List<HotkeyBinding>();
            l.Add(new HotkeyBinding("brightness.up", CTRL | ALT, 0x26));       // fleche haut
            l.Add(new HotkeyBinding("brightness.down", CTRL | ALT, 0x28));     // fleche bas
            l.Add(new HotkeyBinding("temp.warmer", CTRL | ALT, 0x25));         // fleche gauche
            l.Add(new HotkeyBinding("temp.cooler", CTRL | ALT, 0x27));         // fleche droite
            l.Add(new HotkeyBinding("reset", CTRL | ALT | SHIFT, 0x52));       // R
            l.Add(new HotkeyBinding("pause.toggle", CTRL | ALT, 0x50));        // P
            l.Add(new HotkeyBinding("mode.next", CTRL | ALT, 0x4D));           // M
            l.Add(new HotkeyBinding("adaptive.toggle", CTRL | ALT, 0x41));     // A
            l.Add(new HotkeyBinding("break.now", CTRL | ALT, 0x42));           // B
            l.Add(new HotkeyBinding("panel.show", CTRL | ALT, 0x4C));          // L
            return l;
        }

        public static string ActionLabel(string action)
        {
            switch (action)
            {
                case "brightness.up": return "Luminosite +";
                case "brightness.down": return "Luminosite -";
                case "temp.warmer": return "Couleur plus chaude";
                case "temp.cooler": return "Couleur plus froide";
                case "reset": return "Tout reinitialiser (secours)";
                case "pause.toggle": return "Suspendre / reprendre";
                case "mode.next": return "Mode suivant";
                case "adaptive.toggle": return "Adaptatif on / off";
                case "break.now": return "Pause pour les yeux";
                case "panel.show": return "Ouvrir les reglages";
                default: return action;
            }
        }

        // ------------------------------------------------------------------ E/S

        public static Settings Load()
        {
            Settings s = new Settings();
            try
            {
                MigrateLegacyFolder();
                s.IsFirstRun = !File.Exists(FilePath);
                if (File.Exists(FilePath))
                {
                    foreach (string raw in File.ReadAllLines(FilePath))
                    {
                        string line = raw.Trim();
                        if (line.Length == 0 || line.StartsWith("#")) continue;
                        int eq = line.IndexOf('=');
                        if (eq <= 0) continue;
                        s.ApplyPair(line.Substring(0, eq).Trim(), line.Substring(eq + 1).Trim());
                    }
                }
            }
            catch { /* fichier illisible : valeurs par defaut */ }

            if (s.Hotkeys.Count == 0) s.Hotkeys = DefaultHotkeys();
            s.Current.ClampAll();
            return s;
        }

        private void ApplyPair(string key, string val)
        {
            CultureInfo inv = CultureInfo.InvariantCulture;
            switch (key)
            {
                case "current": Current = Profile.Deserialize(val); break;
                case "activeMode": ActiveModeName = val; break;
                case "customProfile": CustomProfiles.Add(Profile.Deserialize(val)); break;

                case "schedule": Schedule = (ScheduleMode)ParseInt(val); break;
                case "preset": PresetName = val; break;
                case "latitude": double.TryParse(val, NumberStyles.Float, inv, out Latitude); break;
                case "longitude": double.TryParse(val, NumberStyles.Float, inv, out Longitude); break;
                case "bedtime": double.TryParse(val, NumberStyles.Float, inv, out BedtimeHour); break;
                case "wake": double.TryParse(val, NumberStyles.Float, inv, out WakeHour); break;
                case "fixedDay": double.TryParse(val, NumberStyles.Float, inv, out FixedDayHour); break;
                case "fixedNight": double.TryParse(val, NumberStyles.Float, inv, out FixedNightHour); break;
                case "transitionMin": TransitionMinutes = ParseInt(val); break;
                case "schedBright": ScheduleAffectsBrightness = val == "1"; break;
                case "dayBright": double.TryParse(val, NumberStyles.Float, inv, out DayBrightness); break;
                case "nightBright": double.TryParse(val, NumberStyles.Float, inv, out NightBrightness); break;

                case "adaptive": AdaptiveEnabled = val == "1"; break;
                case "adaptiveMin": double.TryParse(val, NumberStyles.Float, inv, out AdaptiveMin); break;
                case "adaptiveMax": double.TryParse(val, NumberStyles.Float, inv, out AdaptiveMax); break;
                case "adaptiveReact": double.TryParse(val, NumberStyles.Float, inv, out AdaptiveReactivity); break;
                case "adaptiveInterval": AdaptiveIntervalMs = ParseInt(val); break;

                case "monitor": Monitors.Add(MonitorSettings.Deserialize(val)); break;
                case "linkMonitors": LinkMonitors = val == "1"; break;

                case "appRules": AppRulesEnabled = val == "1"; break;
                case "appRule": AppRules.Add(AppRule.Deserialize(val)); break;
                case "disableFullscreen": DisableOnFullscreen = val == "1"; break;
                case "disableBattery": DisableOnBattery = val == "1"; break;

                case "breaks": BreaksEnabled = val == "1"; break;
                case "breakInterval": BreakIntervalMinutes = ParseInt(val); break;
                case "breakDuration": BreakDurationSeconds = ParseInt(val); break;
                case "breakDim": BreakDim = val == "1"; break;
                case "breakSound": BreakSound = val == "1"; break;

                case "hardwareBacklight": UseHardwareBacklight = val == "1"; break;
                case "useOverlay": UseOverlay = val == "1"; break;
                case "useColorMatrix": UseColorMatrix = val == "1"; break;
                case "smooth": SmoothTransitions = val == "1"; break;
                case "transitionSpeed": TransitionSpeedMs = ParseInt(val); break;

                case "startWithWindows": StartWithWindows = val == "1"; break;
                case "startMinimized": StartMinimized = val == "1"; break;
                case "hotkeysEnabled": HotkeysEnabled = val == "1"; break;
                case "trayWheel": TrayWheelControl = val == "1"; break;
                case "skipDarkConfirm": SkipDarkConfirm = val == "1"; break;
                case "ignoreConflicts": IgnoreConflicts = val == "1"; break;
                case "warnedAboutClamp": WarnedAboutClamp = val == "1"; break;
                case "trayPercent": ShowTrayPercentage = val == "1"; break;
                case "hotkey":
                    // Le premier raccourci lu remplace les valeurs par defaut plutot
                    // que de s'y ajouter, sinon chaque action serait liee deux fois.
                    if (!_hotkeysFromFile) { Hotkeys.Clear(); _hotkeysFromFile = true; }
                    Hotkeys.Add(HotkeyBinding.Deserialize(val));
                    break;
            }
        }

        private static int ParseInt(string v)
        {
            int r;
            int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out r);
            return r;
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(DataFolder);
                File.WriteAllText(FilePath, Export());
            }
            catch { }
        }

        /// <summary>Serialise toute la configuration. Sert aussi a l'export de fichier.</summary>
        public string Export()
        {
            CultureInfo inv = CultureInfo.InvariantCulture;
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("# OpusScreen - configuration");
            sb.AppendLine("# Supprimer ce fichier remet tous les reglages par defaut.");
            sb.AppendLine();
            sb.AppendLine("current=" + Current.Serialize());
            sb.AppendLine("activeMode=" + ActiveModeName);
            foreach (Profile p in CustomProfiles) sb.AppendLine("customProfile=" + p.Serialize());
            sb.AppendLine();
            sb.AppendLine("schedule=" + (int)Schedule);
            sb.AppendLine("preset=" + PresetName);
            sb.AppendLine("latitude=" + Latitude.ToString("0.####", inv));
            sb.AppendLine("longitude=" + Longitude.ToString("0.####", inv));
            sb.AppendLine("bedtime=" + BedtimeHour.ToString("0.##", inv));
            sb.AppendLine("wake=" + WakeHour.ToString("0.##", inv));
            sb.AppendLine("fixedDay=" + FixedDayHour.ToString("0.##", inv));
            sb.AppendLine("fixedNight=" + FixedNightHour.ToString("0.##", inv));
            sb.AppendLine("transitionMin=" + TransitionMinutes);
            sb.AppendLine("schedBright=" + B(ScheduleAffectsBrightness));
            sb.AppendLine("dayBright=" + DayBrightness.ToString("0.##", inv));
            sb.AppendLine("nightBright=" + NightBrightness.ToString("0.##", inv));
            sb.AppendLine();
            sb.AppendLine("adaptive=" + B(AdaptiveEnabled));
            sb.AppendLine("adaptiveMin=" + AdaptiveMin.ToString("0.##", inv));
            sb.AppendLine("adaptiveMax=" + AdaptiveMax.ToString("0.##", inv));
            sb.AppendLine("adaptiveReact=" + AdaptiveReactivity.ToString("0.##", inv));
            sb.AppendLine("adaptiveInterval=" + AdaptiveIntervalMs);
            sb.AppendLine();
            foreach (MonitorSettings m in Monitors) sb.AppendLine("monitor=" + m.Serialize());
            sb.AppendLine("linkMonitors=" + B(LinkMonitors));
            sb.AppendLine();
            sb.AppendLine("appRules=" + B(AppRulesEnabled));
            foreach (AppRule r in AppRules) sb.AppendLine("appRule=" + r.Serialize());
            sb.AppendLine("disableFullscreen=" + B(DisableOnFullscreen));
            sb.AppendLine("disableBattery=" + B(DisableOnBattery));
            sb.AppendLine();
            sb.AppendLine("breaks=" + B(BreaksEnabled));
            sb.AppendLine("breakInterval=" + BreakIntervalMinutes);
            sb.AppendLine("breakDuration=" + BreakDurationSeconds);
            sb.AppendLine("breakDim=" + B(BreakDim));
            sb.AppendLine("breakSound=" + B(BreakSound));
            sb.AppendLine();
            sb.AppendLine("hardwareBacklight=" + B(UseHardwareBacklight));
            sb.AppendLine("useOverlay=" + B(UseOverlay));
            sb.AppendLine("useColorMatrix=" + B(UseColorMatrix));
            sb.AppendLine("smooth=" + B(SmoothTransitions));
            sb.AppendLine("transitionSpeed=" + TransitionSpeedMs);
            sb.AppendLine();
            sb.AppendLine("startWithWindows=" + B(StartWithWindows));
            sb.AppendLine("startMinimized=" + B(StartMinimized));
            sb.AppendLine("hotkeysEnabled=" + B(HotkeysEnabled));
            sb.AppendLine("trayWheel=" + B(TrayWheelControl));
            sb.AppendLine("skipDarkConfirm=" + B(SkipDarkConfirm));
            sb.AppendLine("ignoreConflicts=" + B(IgnoreConflicts));
            sb.AppendLine("warnedAboutClamp=" + B(WarnedAboutClamp));
            sb.AppendLine("trayPercent=" + B(ShowTrayPercentage));
            foreach (HotkeyBinding h in Hotkeys) sb.AppendLine("hotkey=" + h.Serialize());
            return sb.ToString();
        }

        private static string B(bool v) { return v ? "1" : "0"; }

        /// <summary>Recharge depuis un texte exporte. Utilise par l'import de configuration.</summary>
        public static Settings FromText(string text)
        {
            Settings s = new Settings();
            s.Monitors.Clear();
            s.CustomProfiles.Clear();
            s.AppRules.Clear();
            foreach (string raw in text.Replace("\r\n", "\n").Split('\n'))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int eq = line.IndexOf('=');
                if (eq <= 0) continue;
                s.ApplyPair(line.Substring(0, eq).Trim(), line.Substring(eq + 1).Trim());
            }
            if (s.Hotkeys.Count == 0) s.Hotkeys = DefaultHotkeys();
            s.Current.ClampAll();
            return s;
        }

        // ------------------------------------------------------------------ demarrage auto

        public void ApplyStartupRegistration()
        {
            try
            {
                using (Microsoft.Win32.RegistryKey key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    if (key == null) return;

                    // Entree laissee par LumaFlux : elle pointe vers un executable qui
                    // n'existe plus, et Windows signalerait un demarrage en echec.
                    if (key.GetValue("LumaFlux") != null) key.DeleteValue("LumaFlux", false);

                    if (StartWithWindows)
                    {
                        string exe = System.Reflection.Assembly.GetExecutingAssembly().Location;
                        key.SetValue("OpusScreen", "\"" + exe + "\"" + (StartMinimized ? " --minimized" : ""));
                    }
                    else if (key.GetValue("OpusScreen") != null)
                    {
                        key.DeleteValue("OpusScreen", false);
                    }
                }
            }
            catch { }
        }
    }
}
