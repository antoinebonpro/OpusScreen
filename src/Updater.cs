using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;

namespace OpusScreen
{
    /// <summary>Ce que GitHub dit de la derniere version publiee.</summary>
    public class UpdateInfo
    {
        public Version Version;
        public string Tag = "";
        public string Title = "";
        public string DownloadUrl = "";
        public long Size;
        /// <summary>Empreinte SHA-256 en hexadecimal, vide si GitHub n'en donne pas.</summary>
        public string Sha256 = "";
        public string PageUrl = "";

        public string ShortVersion
        {
            get { return Version == null ? "?" : Version.Major + "." + Version.Minor + "." + Math.Max(0, Version.Build); }
        }
    }

    /// <summary>
    /// Mise a jour : savoir qu'une version plus recente existe, la telecharger, la
    /// verifier et prendre sa place.
    ///
    /// C'est la seule connexion que fait OpusScreen. Elle demande a GitHub le numero
    /// de la derniere version publiee - une requete anonyme, sans identifiant, sans
    /// rien sur la machine ni sur l'utilisateur - et peut se couper dans l'onglet
    /// Avance. Rien ne s'installe sans que l'utilisateur l'ait accepte : une
    /// application qui touche a l'ecran ne redemarre pas au milieu d'un travail.
    /// </summary>
    public static class Updater
    {
        public const string ApiUrl = "https://api.github.com/repos/antoinebonpro/OpusScreen/releases/latest";
        public const string ReleasesPage = "https://github.com/antoinebonpro/OpusScreen/releases/latest";
        private const string AssetName = "OpusScreen.exe";

        /// <summary>Demande de verification venue de l'interface (bouton « Verifier maintenant »).</summary>
        public static event EventHandler CheckRequested;

        public static void RequestCheck()
        {
            EventHandler h = CheckRequested;
            if (h != null) h(null, EventArgs.Empty);
        }

        /// <summary>Etat lisible de la derniere verification, affiche dans l'onglet Avance.</summary>
        public static string LastStatus = "";

        // ------------------------------------------------------------------ lecture de la reponse

        /// <summary>
        /// Extrait la version et le fichier a telecharger de la reponse de GitHub.
        /// Null si la reponse ne decrit pas une publication utilisable : sans
        /// executable joint, il n'y a rien a installer.
        /// </summary>
        public static UpdateInfo Parse(string json)
        {
            Dictionary<string, object> root = MiniJson.Parse(json) as Dictionary<string, object>;
            if (root == null) return null;

            if (AsBool(root, "draft") || AsBool(root, "prerelease")) return null;

            UpdateInfo info = new UpdateInfo();
            info.Tag = AsString(root, "tag_name");
            info.Title = AsString(root, "name");
            info.PageUrl = AsString(root, "html_url");
            info.Version = ParseVersion(info.Tag);
            if (info.Version == null) return null;

            List<object> assets = Get(root, "assets") as List<object>;
            if (assets == null) return null;
            foreach (object o in assets)
            {
                Dictionary<string, object> a = o as Dictionary<string, object>;
                if (a == null) continue;
                if (!string.Equals(AsString(a, "name"), AssetName, StringComparison.OrdinalIgnoreCase)) continue;

                info.DownloadUrl = AsString(a, "browser_download_url");
                object size = Get(a, "size");
                if (size is double) info.Size = (long)(double)size;
                string digest = AsString(a, "digest");
                if (digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase))
                    info.Sha256 = digest.Substring(7).ToLowerInvariant();
                break;
            }

            if (!info.DownloadUrl.StartsWith("https://github.com/", StringComparison.OrdinalIgnoreCase))
                return null;
            return info;
        }

        /// <summary>« v3.4.0 », « 3.4 » ou « 3.4.0 » -> 3.4.0.0. Null si ce n'est pas une version.</summary>
        public static Version ParseVersion(string tag)
        {
            if (string.IsNullOrEmpty(tag)) return null;
            string t = tag.Trim().TrimStart('v', 'V');
            string[] parts = t.Split('.');
            if (parts.Length < 2 || parts.Length > 4) return null;
            int[] n = new int[4];
            for (int i = 0; i < parts.Length; i++)
                if (!int.TryParse(parts[i], NumberStyles.None, CultureInfo.InvariantCulture, out n[i])) return null;
            return new Version(n[0], n[1], n[2], n[3]);
        }

        /// <summary>Compare sur trois chiffres : le quatrieme n'est jamais publie.</summary>
        public static bool IsNewer(Version candidate, Version current)
        {
            if (candidate == null || current == null) return false;
            return Normalize(candidate) > Normalize(current);
        }

        private static Version Normalize(Version v)
        {
            return new Version(v.Major, v.Minor, Math.Max(0, v.Build));
        }

        private static object Get(Dictionary<string, object> d, string key)
        {
            object v;
            return d.TryGetValue(key, out v) ? v : null;
        }

        private static string AsString(Dictionary<string, object> d, string key)
        {
            return Get(d, key) as string ?? "";
        }

        private static bool AsBool(Dictionary<string, object> d, string key)
        {
            object v = Get(d, key);
            return v is bool && (bool)v;
        }

        // ------------------------------------------------------------------ reseau

        private static void EnableModernTls()
        {
            // GitHub n'accepte que TLS 1.2. Le .NET Framework 4.0 ne le connait pas par
            // son nom, mais le prend par sa valeur des que le 4.5 ou plus est installe -
            // ce qui est le cas de tout Windows depuis 8, et de tout Windows 7 a jour.
            try
            {
                ServicePointManager.SecurityProtocol =
                    (SecurityProtocolType)3072 | (SecurityProtocolType)768 | SecurityProtocolType.Tls;
            }
            catch (NotSupportedException) { }
        }

        private static WebClient NewClient()
        {
            EnableModernTls();
            WebClient wc = new WebClient();
            // Sans agent declare, l'API de GitHub refuse la requete.
            wc.Headers[HttpRequestHeader.UserAgent] = "OpusScreen/" + Installer.CurrentVersion.ToString(3);
            return wc;
        }

        /// <summary>Interroge GitHub. Leve une exception si le reseau ou la reponse fait defaut.</summary>
        public static UpdateInfo Fetch()
        {
            using (WebClient wc = NewClient())
            {
                wc.Headers[HttpRequestHeader.Accept] = "application/vnd.github+json";
                wc.Encoding = Encoding.UTF8;
                UpdateInfo info = Parse(wc.DownloadString(ApiUrl));
                if (info == null) throw new InvalidDataException("La reponse de GitHub ne decrit aucune version telechargeable.");
                return info;
            }
        }

        /// <summary>
        /// Telecharge la nouvelle version a cote de l'executable en cours, puis la
        /// verifie : taille, empreinte quand GitHub la publie, et numero de version
        /// inscrit dans le fichier. Un fichier qui ne passe pas est efface. Retourne
        /// son chemin.
        /// </summary>
        public static string Download(UpdateInfo info)
        {
            string dir = Path.GetDirectoryName(Taskbar.ExecutablePath);
            string target = Path.Combine(dir, "OpusScreen.new.exe");
            try { if (File.Exists(target)) File.Delete(target); } catch { }

            using (WebClient wc = NewClient())
                wc.DownloadFile(info.DownloadUrl, target);

            string problem = Verify(target, info);
            if (problem != null)
            {
                try { File.Delete(target); } catch { }
                throw new InvalidDataException(problem);
            }
            return target;
        }

        /// <summary>Null si le fichier est bien la version annoncee, sinon la raison du refus.</summary>
        public static string Verify(string file, UpdateInfo info)
        {
            FileInfo fi = new FileInfo(file);
            if (!fi.Exists) return "Le fichier telecharge est introuvable.";
            if (info.Size > 0 && fi.Length != info.Size)
                return "Le fichier telecharge est incomplet (" + fi.Length + " octets au lieu de " + info.Size + ").";

            if (info.Sha256.Length > 0)
            {
                string actual = Sha256Of(file);
                if (!string.Equals(actual, info.Sha256, StringComparison.OrdinalIgnoreCase))
                    return "L'empreinte du fichier telecharge ne correspond pas a celle publiee.";
            }

            FileVersionInfo fvi;
            try { fvi = FileVersionInfo.GetVersionInfo(file); }
            catch { return "Le fichier telecharge n'est pas un executable lisible."; }

            if (!string.Equals(fvi.FileDescription, "OpusScreen", StringComparison.OrdinalIgnoreCase))
                return "Le fichier telecharge n'est pas OpusScreen.";

            Version inside = ParseVersion(fvi.FileVersion);
            if (inside == null || Normalize(inside) != Normalize(info.Version))
                return "Le fichier telecharge porte la version " + fvi.FileVersion
                     + " au lieu de " + info.ShortVersion + ".";
            return null;
        }

        public static string Sha256Of(string file)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream fs = File.OpenRead(file))
            {
                byte[] h = sha.ComputeHash(fs);
                StringBuilder sb = new StringBuilder(h.Length * 2);
                foreach (byte b in h) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        /// <summary>
        /// Met la nouvelle version a la place de l'ancienne et la demarre. L'appelant
        /// doit ensuite sortir : la nouvelle attend sa fin avant de prendre le verrou.
        ///
        /// Windows interdit d'effacer un executable en cours, mais pas de le renommer.
        /// L'ancien devient OpusScreen.old.exe, efface au demarrage suivant ; si la
        /// moindre etape echoue, il reprend son nom et rien n'a change.
        /// </summary>
        public static void Apply(string newExe)
        {
            string current = Taskbar.ExecutablePath;
            string previous = Path.Combine(Path.GetDirectoryName(current), "OpusScreen.old.exe");

            if (File.Exists(previous)) File.Delete(previous);
            File.Move(current, previous);
            try
            {
                File.Move(newExe, current);
            }
            catch
            {
                File.Move(previous, current);
                throw;
            }

            ProcessStartInfo psi = new ProcessStartInfo(current,
                "--wait-pid " + Process.GetCurrentProcess().Id + " --updated");
            psi.UseShellExecute = false;
            psi.WorkingDirectory = Path.GetDirectoryName(current);
            try
            {
                Process.Start(psi);
            }
            catch
            {
                // La nouvelle version ne demarre pas : on remet l'ancienne en place.
                try { File.Delete(current); File.Move(previous, current); } catch { }
                throw;
            }
        }

        public static bool WasJustUpdated(string[] args)
        {
            foreach (string a in args)
                if (string.Equals(a, "--updated", StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }

    /// <summary>
    /// Lecteur JSON minimal : objets, tableaux, chaines, nombres, booleens, null.
    /// Le .NET Framework 4 n'en fournit pas dans les bibliotheques qu'on a le droit de
    /// supposer presentes, et une reponse lue a coups d'expressions regulieres se
    /// tromperait des que GitHub change l'ordre de ses champs.
    /// </summary>
    public static class MiniJson
    {
        public static object Parse(string text)
        {
            if (text == null) return null;
            int i = 0;
            try
            {
                object v = Value(text, ref i);
                Skip(text, ref i);
                return i == text.Length ? v : null;
            }
            catch (FormatException) { return null; }
            catch (IndexOutOfRangeException) { return null; }
            catch (ArgumentOutOfRangeException) { return null; }
        }

        private static void Skip(string s, ref int i)
        {
            while (i < s.Length && char.IsWhiteSpace(s[i])) i++;
        }

        private static object Value(string s, ref int i)
        {
            Skip(s, ref i);
            char c = s[i];
            if (c == '{') return Obj(s, ref i);
            if (c == '[') return Arr(s, ref i);
            if (c == '"') return Str(s, ref i);
            if (Word(s, ref i, "true")) return true;
            if (Word(s, ref i, "false")) return false;
            if (Word(s, ref i, "null")) return null;
            return Num(s, ref i);
        }

        private static bool Word(string s, ref int i, string w)
        {
            if (string.CompareOrdinal(s, i, w, 0, w.Length) != 0) return false;
            i += w.Length;
            return true;
        }

        private static Dictionary<string, object> Obj(string s, ref int i)
        {
            Dictionary<string, object> d = new Dictionary<string, object>();
            i++;
            Skip(s, ref i);
            if (s[i] == '}') { i++; return d; }
            while (true)
            {
                Skip(s, ref i);
                if (s[i] != '"') throw new FormatException();
                string key = Str(s, ref i);
                Skip(s, ref i);
                if (s[i++] != ':') throw new FormatException();
                d[key] = Value(s, ref i);
                Skip(s, ref i);
                char c = s[i++];
                if (c == '}') return d;
                if (c != ',') throw new FormatException();
            }
        }

        private static List<object> Arr(string s, ref int i)
        {
            List<object> l = new List<object>();
            i++;
            Skip(s, ref i);
            if (s[i] == ']') { i++; return l; }
            while (true)
            {
                l.Add(Value(s, ref i));
                Skip(s, ref i);
                char c = s[i++];
                if (c == ']') return l;
                if (c != ',') throw new FormatException();
            }
        }

        private static string Str(string s, ref int i)
        {
            StringBuilder sb = new StringBuilder();
            i++;
            while (true)
            {
                char c = s[i++];
                if (c == '"') return sb.ToString();
                if (c != '\\') { sb.Append(c); continue; }
                char e = s[i++];
                switch (e)
                {
                    case '"': sb.Append('"'); break;
                    case '\\': sb.Append('\\'); break;
                    case '/': sb.Append('/'); break;
                    case 'b': sb.Append('\b'); break;
                    case 'f': sb.Append('\f'); break;
                    case 'n': sb.Append('\n'); break;
                    case 'r': sb.Append('\r'); break;
                    case 't': sb.Append('\t'); break;
                    case 'u':
                        sb.Append((char)int.Parse(s.Substring(i, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture));
                        i += 4;
                        break;
                    default: throw new FormatException();
                }
            }
        }

        private static double Num(string s, ref int i)
        {
            int start = i;
            while (i < s.Length && "+-0123456789.eE".IndexOf(s[i]) >= 0) i++;
            if (i == start) throw new FormatException();
            return double.Parse(s.Substring(start, i - start), NumberStyles.Float, CultureInfo.InvariantCulture);
        }
    }
}
