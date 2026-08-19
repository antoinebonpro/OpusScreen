using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace OpusScreen
{
    /// Pilotage en ligne de commande.
    ///
    /// La transmission a l'instance en cours passe par un petit fichier d'ordres plutot
    /// que par un canal nomme : c'est lisible, cela survit a un plantage, et cela ne
    /// laisse aucun port ni objet systeme derriere soi.
    /// </summary>
    public static class CommandLine
    {
        private static string CommandPath
        {
            get { return Path.Combine(Settings.DataFolder, "command.txt"); }
        }

        private static readonly string[] Commands = {
            "--brightness", "--temp", "--mode", "--reset", "--pause", "--resume",
            "--adaptive", "--blackout", "--break", "--show",
            "--vision", "--severity", "--magnifier", "--beacon", "--colors"
        };

        public static bool HasCommand(string[] args)
        {
            foreach (string a in args)
                foreach (string c in Commands)
                    if (string.Equals(a, c, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        public static bool WantsHelp(string[] args)
        {
            foreach (string a in args)
                if (a == "--help" || a == "-h" || a == "/?") return true;
            return false;
        }

        public static bool StartMinimized(string[] args)
        {
            foreach (string a in args)
                if (string.Equals(a, "--minimized", StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>
        /// Demande explicite de la fenetre. Emise par la liste de raccourcis de la
        /// barre des taches, ou par qui veut ouvrir les reglages sans savoir si
        /// l'application tourne deja.
        /// </summary>
        public static bool WantsShow(string[] args)
        {
            foreach (string a in args)
                if (string.Equals(a, "--show", StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        /// <summary>Depose l'ordre pour l'instance en cours. Faux si aucune ne tourne.</summary>
        public static bool SendToRunningInstance(string[] args)
        {
            bool isNew;
            using (Mutex probe = new Mutex(false, "OpusScreen_SingleInstance_9f2a"))
            {
                try { isNew = probe.WaitOne(0); }
                catch { isNew = false; }
                if (isNew) { probe.ReleaseMutex(); return false; }
            }

            try
            {
                Directory.CreateDirectory(Settings.DataFolder);
                File.WriteAllText(CommandPath, Quote(args));
                return true;
            }
            catch { return false; }
        }

        /// <summary>
        /// Recompose une ligne de commande en reprotegeant les arguments contenant des
        /// espaces. Sans cela, --mode "Nuit profonde" arrive decoupe en deux mots a
        /// l'instance en cours, et aucun mode ne correspond.
        /// </summary>
        private static string Quote(string[] args)
        {
            StringBuilder sb = new StringBuilder();
            foreach (string a in args)
            {
                if (sb.Length > 0) sb.Append(' ');
                if (a.IndexOf(' ') >= 0) sb.Append('"').Append(a).Append('"');
                else sb.Append(a);
            }
            return sb.ToString();
        }

        /// <summary>Lit puis efface l'ordre depose. Chaine vide s'il n'y en a pas.</summary>
        public static string ConsumePending()
        {
            try
            {
                if (!File.Exists(CommandPath)) return "";
                string text = File.ReadAllText(CommandPath);
                File.Delete(CommandPath);
                return text;
            }
            catch { return ""; }
        }

        /// <summary>Applique un ordre aux reglages. Retourne vrai si quelque chose a change.</summary>
        public static bool ApplyTo(Settings s, string[] args)
        {
            bool changed = false;
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i].ToLowerInvariant();
                string next = i + 1 < args.Length ? args[i + 1] : null;

                switch (a)
                {
                    case "--brightness":
                        {
                            double v;
                            if (next != null && double.TryParse(next, System.Globalization.NumberStyles.Float,
                                    System.Globalization.CultureInfo.InvariantCulture, out v))
                            {
                                s.Current.Brightness = SafetyGuard.ClampBrightness(v);
                                changed = true; i++;
                            }
                        }
                        break;

                    case "--temp":
                        {
                            int v;
                            if (next != null && int.TryParse(next, out v))
                            {
                                s.Current.Kelvin = Math.Max(ColorTemp.MinKelvin, Math.Min(ColorTemp.MaxKelvin, v));
                                changed = true; i++;
                            }
                        }
                        break;

                    case "--mode":
                        if (next != null)
                        {
                            // Les noms de mode contiennent des espaces. Si l'utilisateur
                            // a oublie les guillemets, on recolle les mots suivants et on
                            // retient la correspondance la plus longue - « Nuit profonde »
                            // marche donc avec ou sans protection.
                            int consumed;
                            Profile found = MatchMode(s, args, i + 1, out consumed);
                            if (found != null)
                            {
                                s.Current.CopyFrom(found);
                                s.ActiveModeName = found.Name;
                                changed = true;
                                i += consumed;
                            }
                            else i++;
                        }
                        break;

                    case "--reset":
                        s.Current = new Profile();
                        s.ActiveModeName = "Normal";
                        s.Schedule = ScheduleMode.Manual;
                        s.AdaptiveEnabled = false;
                        changed = true;
                        break;

                    case "--adaptive":
                        if (next != null && (next == "on" || next == "off"))
                        { s.AdaptiveEnabled = next == "on"; changed = true; i++; }
                        else { s.AdaptiveEnabled = !s.AdaptiveEnabled; changed = true; }
                        break;

                    // --- accessibilite ---
                    //
                    // Les intitules acceptes sont ceux de la couleur mal percue, pas les
                    // termes cliniques : quelqu'un qui ecrit un script se souvient de
                    // « vert », pas de « deuteranopie ». Les deux marchent.

                    case "--vision":
                        {
                            ColorFilter f;
                            if (next != null && ParseVision(next, out f))
                            {
                                s.Current.Filter = f;
                                changed = true; i++;
                            }
                        }
                        break;

                    case "--severity":
                        {
                            double v;
                            if (next != null && double.TryParse(next, System.Globalization.NumberStyles.Float,
                                    System.Globalization.CultureInfo.InvariantCulture, out v))
                            {
                                s.Current.VisionSeverity = Math.Max(0, Math.Min(100, v));
                                changed = true; i++;
                            }
                        }
                        break;

                    case "--magnifier":
                        {
                            double zoom;
                            if (next != null && double.TryParse(next, System.Globalization.NumberStyles.Float,
                                    System.Globalization.CultureInfo.InvariantCulture, out zoom))
                            {
                                s.MagnifierZoom = Math.Max(ScreenMagnifier.MinZoom,
                                                  Math.Min(ScreenMagnifier.MaxZoom, zoom));
                                s.MagnifierEnabled = zoom > ScreenMagnifier.MinZoom + 0.001;
                                changed = true; i++;
                            }
                            else if (next == "on" || next == "off")
                            { s.MagnifierEnabled = next == "on"; changed = true; i++; }
                            else { s.MagnifierEnabled = !s.MagnifierEnabled; changed = true; }
                        }
                        break;

                    case "--beacon":
                        if (next == "on" || next == "off")
                        { s.BeaconEnabled = next == "on"; changed = true; i++; }
                        else { s.BeaconEnabled = !s.BeaconEnabled; changed = true; }
                        break;

                    case "--colors":
                        if (next == "on" || next == "off")
                        { s.ColorReaderEnabled = next == "on"; changed = true; i++; }
                        else { s.ColorReaderEnabled = !s.ColorReaderEnabled; changed = true; }
                        break;
                }
            }
            return changed;
        }

        /// <summary>
        /// Reconnait une correction de vision, par la couleur mal percue ou par son nom
        /// clinique. Les deux sont acceptes : l'un se retient, l'autre se cherche.
        /// </summary>
        private static bool ParseVision(string word, out ColorFilter f)
        {
            switch (word.ToLowerInvariant())
            {
                case "none": case "aucun": case "aucune": case "off":
                    f = ColorFilter.None; return true;
                case "red": case "rouge": case "protanopie": case "protanopia": case "protan":
                    f = ColorFilter.Protanopia; return true;
                case "green": case "vert": case "deuteranopie": case "deuteranopia": case "deutan":
                    f = ColorFilter.Deuteranopia; return true;
                case "blue": case "bleu": case "tritanopie": case "tritanopia": case "tritan":
                    f = ColorFilter.Tritanopia; return true;
                default:
                    f = ColorFilter.None; return false;
            }
        }

        /// <summary>
        /// Cherche un mode dont le nom correspond aux arguments a partir de start, en
        /// essayant d'abord la plus longue suite de mots. Renvoie le nombre d'arguments
        /// consommes dans consumed.
        /// </summary>
        private static Profile MatchMode(Settings s, string[] args, int start, out int consumed)
        {
            consumed = 1;
            if (start >= args.Length) return null;

            List<Profile> all = new List<Profile>(Profile.BuiltInModes());
            all.AddRange(s.CustomProfiles);

            // Un argument suivant qui commence par -- appartient a la commande d'apres.
            int maxWords = 0;
            for (int k = start; k < args.Length && !args[k].StartsWith("--"); k++) maxWords++;

            for (int words = maxWords; words >= 1; words--)
            {
                string candidate = string.Join(" ", args, start, words);
                foreach (Profile p in all)
                {
                    if (string.Equals(p.Name, candidate, StringComparison.OrdinalIgnoreCase))
                    {
                        consumed = words;
                        return p;
                    }
                }
            }
            return null;
        }

        public static void ShowHelp()
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("OpusScreen - pilotage en ligne de commande");
            sb.AppendLine();
            sb.AppendLine("  OpusScreen.exe --brightness 130     luminosite, de 5 a 150");
            sb.AppendLine("  OpusScreen.exe --temp 3400          temperature en kelvins, 1200 a 6500");
            sb.AppendLine("  OpusScreen.exe --mode \"Lecture\"     applique un mode par son nom");
            sb.AppendLine("  OpusScreen.exe --adaptive on|off    adaptation au contenu affiche");
            sb.AppendLine();
            sb.AppendLine("  Accessibilite :");
            sb.AppendLine("  OpusScreen.exe --vision vert        correction daltonisme :");
            sb.AppendLine("                                      aucune | rouge | vert | bleu");
            sb.AppendLine("  OpusScreen.exe --severity 70        gravite de la deficience, 0 a 100");
            sb.AppendLine("  OpusScreen.exe --magnifier 2.5      loupe plein ecran, 1 a 8 (1 = eteinte)");
            sb.AppendLine("  OpusScreen.exe --beacon on|off      anneau autour du pointeur");
            sb.AppendLine("  OpusScreen.exe --colors on|off      etiquette qui nomme les couleurs");
            sb.AppendLine();
            sb.AppendLine("  OpusScreen.exe --pause              suspend tous les effets");
            sb.AppendLine("  OpusScreen.exe --resume             reprend");
            sb.AppendLine("  OpusScreen.exe --break              declenche une pause pour les yeux");
            sb.AppendLine("  OpusScreen.exe --reset              remet l'ecran a l'etat normal");
            sb.AppendLine("  OpusScreen.exe --show               ouvre la fenetre de reglages");
            sb.AppendLine("  OpusScreen.exe --minimized          demarre sans ouvrir la fenetre");
            sb.AppendLine();
            sb.AppendLine("Si OpusScreen tourne deja, l'ordre lui est transmis et prend effet");
            sb.AppendLine("immediatement. Sinon il s'applique au demarrage.");

            MessageBox.Show(sb.ToString(), "OpusScreen - aide", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }
}
