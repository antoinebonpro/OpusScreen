using System;
using System.IO;
using OpusScreen;

/// <summary>
/// Verifie ce qui garantit qu'une seule version tourne, et que c'est la plus recente :
/// la decision prise au lancement, la lecture de la reponse de GitHub, la comparaison
/// des versions et le controle du fichier telecharge.
///
/// Aucun appel reseau et aucune installation : la decision est une fonction pure, et
/// la reponse de GitHub est reproduite ici telle qu'elle arrive.
/// </summary>
class UpdateTest
{
    static int fails = 0;

    static void Check(bool ok, string what)
    {
        Console.WriteLine((ok ? "  OK    " : "  ECHEC ") + what);
        if (!ok) fails++;
    }

    const string Installed = @"C:\Users\u\AppData\Local\Programs\OpusScreen\OpusScreen.exe";
    const string Downloaded = @"C:\Users\u\Downloads\OpusScreen(1).exe";

    // Extrait fidele de https://api.github.com/repos/antoinebonpro/OpusScreen/releases/latest,
    // champs dans le desordre et objet imbrique compris.
    const string Release = @"{
      ""url"": ""https://api.github.com/repos/antoinebonpro/OpusScreen/releases/1"",
      ""html_url"": ""https://github.com/antoinebonpro/OpusScreen/releases/tag/v3.4.0"",
      ""tag_name"": ""v3.4.0"",
      ""name"": ""OpusScreen 3.4 \u2014 toujours \""a jour\"""",
      ""draft"": false,
      ""prerelease"": false,
      ""assets"": [
        { ""name"": ""notes.txt"", ""size"": 12,
          ""browser_download_url"": ""https://github.com/antoinebonpro/OpusScreen/releases/download/v3.4.0/notes.txt"" },
        { ""uploader"": { ""login"": ""antoinebonpro"", ""id"": 1 },
          ""browser_download_url"": ""https://github.com/antoinebonpro/OpusScreen/releases/download/v3.4.0/OpusScreen.exe"",
          ""digest"": ""sha256:ABCDEF0123"",
          ""size"": 720896,
          ""name"": ""OpusScreen.exe"",
          ""download_count"": 2 }
      ],
      ""body"": ""ligne 1\nligne 2\t\u00e9""
    }";

    static int Main()
    {
        Console.WriteLine("--- 1. Decision au lancement ---");

        Version v331 = new Version(3, 3, 1, 0), v340 = new Version(3, 4, 0, 0), v350 = new Version(3, 5, 0, 0);

        Check(Installer.Decide(Installed, Installed, v340, v340) == Installer.LaunchAction.Run,
              "la copie installee demarre normalement");
        Check(Installer.Decide(Installed.ToUpperInvariant(), Installed, v340, v340) == Installer.LaunchAction.Run,
              "le chemin se compare sans tenir compte de la casse");
        Check(Installer.Decide(Downloaded, Installed, v340, null) == Installer.LaunchAction.Install,
              "rien d'installe : la copie telechargee s'installe");
        Check(Installer.Decide(Downloaded, Installed, v350, v340) == Installer.LaunchAction.Install,
              "copie telechargee plus recente : elle remplace l'installee");
        Check(Installer.Decide(Downloaded, Installed, v331, v340) == Installer.LaunchAction.DeferToInstalled,
              "vieille copie oubliee dans Telechargements : elle s'efface devant l'installee");
        Check(Installer.Decide(Downloaded, Installed, v340, v340) == Installer.LaunchAction.DeferToInstalled,
              "meme version : l'instance en cours n'est pas fermee pour rien");

        string folder = Installer.InstallFolder;
        Check(folder.EndsWith(@"\Programs\OpusScreen", StringComparison.OrdinalIgnoreCase)
              && folder.IndexOf("Program Files", StringComparison.OrdinalIgnoreCase) < 0,
              "installation dans le dossier de l'utilisateur, sans droits administrateur");

        Console.WriteLine();
        Console.WriteLine("--- 2. Versions ---");

        Check(Updater.ParseVersion("v3.4.0") == new Version(3, 4, 0, 0), "« v3.4.0 » se lit");
        Check(Updater.ParseVersion("3.4") == new Version(3, 4, 0, 0), "« 3.4 » se lit");
        Check(Updater.ParseVersion("V10.0.2") == new Version(10, 0, 2, 0), "majuscule et deux chiffres");
        Check(Updater.ParseVersion("latest") == null, "une etiquette qui n'est pas une version est refusee");
        Check(Updater.ParseVersion("v3.4.0-beta") == null, "une preversion nommee est refusee");
        Check(Updater.ParseVersion("") == null && Updater.ParseVersion(null) == null, "vide ou absent");

        Check(Updater.IsNewer(v340, v331), "3.4.0 est plus recente que 3.3.1");
        Check(!Updater.IsNewer(v331, v340), "3.3.1 n'est pas plus recente que 3.4.0");
        Check(!Updater.IsNewer(new Version(3, 4, 0), v340), "3.4.0 et 3.4.0.0 sont la meme version");
        Check(Updater.IsNewer(new Version(3, 10, 0), new Version(3, 9, 9)), "3.10 passe apres 3.9 (pas d'ordre alphabetique)");
        Check(!Updater.IsNewer(null, v340), "aucune version annoncee : rien a installer");

        Console.WriteLine();
        Console.WriteLine("--- 3. Reponse de GitHub ---");

        UpdateInfo info = Updater.Parse(Release);
        Check(info != null, "la publication se lit");
        if (info != null)
        {
            Check(info.Version == v340, "version 3.4.0");
            Check(info.ShortVersion == "3.4.0", "version affichee sur trois chiffres");
            Check(info.DownloadUrl.EndsWith("/v3.4.0/OpusScreen.exe"), "c'est l'executable qui est retenu, pas le premier fichier joint");
            Check(info.Size == 720896, "taille annoncee lue");
            Check(info.Sha256 == "abcdef0123", "empreinte lue, prefixe retire, en minuscules");
            Check(info.Title.IndexOf("\u2014") > 0 && info.Title.EndsWith("\"a jour\""), "echappements \\u et \\\" decodes");
        }

        Check(Updater.Parse(Release.Replace("\"draft\": false", "\"draft\": true")) == null, "un brouillon est ignore");
        Check(Updater.Parse(Release.Replace("\"prerelease\": false", "\"prerelease\": true")) == null, "une preversion est ignoree");
        Check(Updater.Parse(Release.Replace("\"OpusScreen.exe\"", "\"Autre.exe\"")) == null, "publication sans executable : rien a installer");
        Check(Updater.Parse(Release.Replace("https://github.com/antoinebonpro/OpusScreen/releases/download/v3.4.0/OpusScreen.exe",
                                            "http://ailleurs.example/OpusScreen.exe")) == null,
              "un telechargement hors de github.com en https est refuse");
        Check(Updater.Parse("{\"message\":\"API rate limit exceeded\"}") == null, "reponse d'erreur de GitHub : aucune version");
        Check(Updater.Parse("<html>proxy</html>") == null, "reponse qui n'est pas du JSON : aucune version");
        Check(Updater.Parse("{\"tag_name\":\"v3.4.0\",") == null, "reponse tronquee : aucune version");
        Check(Updater.Parse(null) == null, "reponse absente : aucune version");

        Console.WriteLine();
        Console.WriteLine("--- 4. Controle du fichier telecharge ---");

        string exe = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, @"..\..\OpusScreen.exe"));
        if (File.Exists(exe))
        {
            Version built = Installer.VersionOf(exe);
            UpdateInfo good = new UpdateInfo();
            good.Version = built;
            good.Size = new FileInfo(exe).Length;
            good.Sha256 = Updater.Sha256Of(exe);

            Check(Updater.Verify(exe, good) == null, "l'executable compile passe le controle");

            UpdateInfo badSize = new UpdateInfo();
            badSize.Version = built; badSize.Size = good.Size + 1;
            Check(Updater.Verify(exe, badSize) != null, "une taille differente est refusee");

            UpdateInfo badHash = new UpdateInfo();
            badHash.Version = built; badHash.Size = good.Size; badHash.Sha256 = new string('0', 64);
            Check(Updater.Verify(exe, badHash) != null, "une empreinte differente est refusee");

            UpdateInfo badVersion = new UpdateInfo();
            badVersion.Version = new Version(99, 0, 0);
            Check(Updater.Verify(exe, badVersion) != null, "un fichier d'une autre version que celle annoncee est refuse");

            UpdateInfo noHash = new UpdateInfo();
            noHash.Version = built; noHash.Size = good.Size;
            Check(Updater.Verify(exe, noHash) == null, "sans empreinte publiee, taille et version suffisent");

            string other = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "notepad.exe");
            UpdateInfo foreign = new UpdateInfo();
            foreign.Version = Installer.VersionOf(other) ?? new Version(1, 0);
            Check(!File.Exists(other) || Updater.Verify(other, foreign) != null, "un executable qui n'est pas OpusScreen est refuse");
        }
        else Console.WriteLine("  (OpusScreen.exe absent : controle du fichier saute)");

        Console.WriteLine();
        Console.WriteLine("--- 5. Reglages ---");

        Settings fresh = new Settings();
        Check(fresh.CheckUpdates, "la verification est active par defaut");

        Settings s = new Settings();
        s.CheckUpdates = false;
        s.LastUpdateCheck = new DateTime(2026, 9, 24, 8, 30, 0, DateTimeKind.Utc);
        Settings back = Settings.FromText(s.Export());
        Check(!back.CheckUpdates, "la desactivation survit a l'enregistrement");
        Check(back.LastUpdateCheck == s.LastUpdateCheck, "la date de derniere verification survit a l'enregistrement");

        Settings old = Settings.FromText("startWithWindows=1\n");
        Check(old.CheckUpdates && old.LastUpdateCheck == DateTime.MinValue,
              "un fichier d'avant la 3.4 recoit la verification active, jamais faite");

        Settings broken = Settings.FromText("lastUpdateCheck=n'importe quoi\n");
        Check(broken.LastUpdateCheck == DateTime.MinValue, "une date illisible ne casse pas le chargement");

        Console.WriteLine();
        Console.WriteLine(fails == 0 ? "UpdateTest : tout passe" : "UpdateTest : " + fails + " echec(s)");
        return fails == 0 ? 0 : 1;
    }
}
