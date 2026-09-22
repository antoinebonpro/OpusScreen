# -*- coding: utf-8 -*-
"""
Verifie le site et les affirmations qu'il porte.

Un site de presentation vieillit mal : la version change, un lien casse, une
phrase promet « huit suites de tests » alors qu'il y en a neuf. Ce script
confronte ce qui est ECRIT a ce qui est VRAI - le code source d'un cote, la
publication GitHub de l'autre - et sort en erreur des qu'un ecart apparait.

Usage :
    python tools\\verifie-site.py                        (site publie)
    python tools\\verifie-site.py http://localhost:8000   (avant publication)

Aucune dependance : bibliotheque standard seulement.
"""

import io
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = "https://antoinebonpro.github.io/OpusScreen/"
DEPOT = "antoinebonpro/OpusScreen"

echecs = []
avertissements = []
verifs = 0


def verifie(condition, message, detail=""):
    global verifs
    verifs += 1
    if condition:
        print(u"  ok    %s" % message)
    else:
        print(u"  ECHEC %s%s" % (message, (" - " + detail) if detail else ""))
        echecs.append(message + ((" - " + detail) if detail else ""))


def note(message):
    avertissements.append(message)
    print(u"  note  %s" % message)


def lire(url):
    contexte = ssl.create_default_context()
    requete = urllib.request.Request(url, headers={"User-Agent": "OpusScreen-verif/1.0"})
    reponse = urllib.request.urlopen(requete, timeout=30, context=contexte)
    try:
        return reponse.read().decode("utf-8", "replace")
    finally:
        reponse.close()


def code(url):
    try:
        contexte = ssl.create_default_context()
        requete = urllib.request.Request(url, headers={"User-Agent": "OpusScreen-verif/1.0"})
        reponse = urllib.request.urlopen(requete, timeout=30, context=contexte)
        try:
            return reponse.getcode()
        finally:
            reponse.close()
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


def fichier(chemin):
    with io.open(os.path.join(RACINE, chemin), encoding="utf-8", errors="replace") as f:
        return f.read()


# ---------------------------------------------------------------- le site

def verifie_page(base):
    print(u"\n--- La page")
    html = lire(base if base.endswith("/") else base + "/")

    titre = re.search(r"<title>(.*?)</title>", html, re.S)
    verifie(titre is not None, u"une balise title")
    if titre:
        t = titre.group(1).strip()
        verifie(20 <= len(t) <= 70, u"titre de longueur utile (%d caracteres)" % len(t), t)

    desc = re.search(r'<meta name="description" content="(.*?)"', html, re.S)
    verifie(desc is not None, u"une meta description")
    if desc:
        d = desc.group(1).strip()
        verifie(70 <= len(d) <= 175, u"description de longueur utile (%d caracteres)" % len(d))

    verifie('lang="fr"' in html or 'lang="en"' in html, u"la langue de la page est declaree")
    verifie('rel="canonical"' in html, u"une adresse canonique")
    for balise in ["og:title", "og:description", "og:image", "og:url", "og:type"]:
        verifie(balise in html, u"balise %s" % balise)
    verifie("twitter:card" in html, u"carte Twitter")

    h1 = re.findall(r"<h1[^>]*>", html)
    verifie(len(h1) == 1, u"exactement un titre de niveau 1 (%d trouve(s))" % len(h1))

    images = re.findall(r"<img\s[^>]*>", html)
    sans_alt = [i for i in images if 'alt="' not in i]
    verifie(not sans_alt, u"toutes les images ont un texte de remplacement",
            u"%d sans alt" % len(sans_alt))

    # Donnees structurees : ce qui permet a un moteur de comprendre que c'est un logiciel.
    bloc = re.search(r'<script type="application/ld\+json">(.*?)</script>', html, re.S)
    verifie(bloc is not None, u"des donnees structurees JSON-LD")
    if bloc:
        try:
            donnees = json.loads(bloc.group(1))
            verifie(donnees.get("@type") == "SoftwareApplication",
                    u"les donnees structurees declarent un logiciel")
            prix = donnees.get("offers", {}).get("price")
            verifie(prix in ("0", 0), u"les donnees structurees declarent la gratuite")
        except ValueError as e:
            verifie(False, u"les donnees structurees sont du JSON valide", str(e))

    bas = html.lower()
    verifie("googletagmanager" not in bas and "gtag(" not in bas and "google-analytics" not in bas,
            u"aucun traqueur dans la page, comme elle l'affirme")

    return html


def racine_de(base):
    """Racine du site : « .../OpusScreen/en/ » se rapporte a « .../OpusScreen/ »."""
    base = base if base.endswith("/") else base + "/"
    if base.rstrip("/").endswith("/en"):
        return base.rstrip("/")[: -len("en")]
    return base


def verifie_ressources(base, html):
    print(u"\n--- Les ressources et les liens")
    base = base if base.endswith("/") else base + "/"
    racine = racine_de(base)

    locales = set(re.findall(r'(?:src|href)="(?!https?://|#|mailto:)([^"]+)"', html))
    for chemin in sorted(locales):
        # urljoin, et non une concatenation : la version anglaise remonte d'un
        # dossier (« ../style.css ») pour partager les fichiers de la francaise.
        c = code(urllib.parse.urljoin(base, chemin))
        verifie(c == 200, u"ressource %s" % chemin, u"code %d" % c)

    externes = sorted(set(re.findall(r'href="(https?://[^"]+)"', html)))
    for lien in externes:
        # Un lien vers le site lui-meme se verifie sur la version TESTEE : avant
        # publication, la page anglaise n'existe pas encore a l'adresse publique.
        cible = lien
        if lien.startswith(SITE) and not base.startswith(SITE):
            cible = urllib.parse.urljoin(racine, lien[len(SITE):])
        c = code(cible)
        verifie(c in (200, 301, 302), u"lien %s" % lien, u"code %d" % c)

    for chemin in ("robots.txt", "sitemap.xml"):
        c = code(racine + chemin)
        verifie(c == 200, u"presence de %s" % chemin, u"code %d" % c)


# ---------------------------------------------------------------- les affirmations

def verifie_affirmations(html):
    print(u"\n--- Ce que la page affirme, confronte au code")

    moteur = fichier("src/GammaEngine.cs")
    mini = re.search(r"MinBrightness\s*=\s*([\d.]+)", moteur)
    maxi = re.search(r"MaxBrightness\s*=\s*([\d.]+)", moteur)
    verifie(mini is not None and maxi is not None, u"les bornes de luminosite existent dans le code")
    if mini and maxi:
        verifie(float(mini.group(1)) == 5 and float(maxi.group(1)) == 150,
                u"le code borne la luminosite a 5-150 %",
                u"%s a %s" % (mini.group(1), maxi.group(1)))
        verifie(u"5 %" in html and u"150 %" in html,
                u"la page annonce cette meme plage")

    temp = fichier("src/ColorTemp.cs")
    verifie("MinKelvin = 1200" in temp and "MaxKelvin = 6500" in temp,
            u"la plage de temperature du code est bien 1200-6500 K")
    verifie(u"1200 K" in html and u"6500 K" in html,
            u"la page annonce cette meme plage de temperature")

    script = fichier("tests/run-tests.cmd")
    total = re.search(r"Tests executes : !RAN! / (\d+)", script)
    verifie(total is not None, u"le script de tests annonce un total")
    if total:
        n = int(total.group(1))
        # Les deux langues disent le meme nombre, avec leurs mots.
        mots = {8: [u"uit suites", u"ight suites"], 9: [u"euf suites", u"ine suites"],
                10: [u"ix suites", u"en suites"]}
        attendus = mots.get(n, []) + [u"%d suites" % n]
        verifie(any(m in html for m in attendus),
                u"le nombre de suites annonce sur la page correspond au script (%d)" % n)

    panneau = fichier("src/ControlPanel.cs")
    # Les APPELS seulement : la declaration de la methode s'ecrit « void AddPage( ».
    pages = len(re.findall(r"(?<!void )AddPage\(", panneau))
    verifie(pages == 10, u"l'application a bien dix pages", u"%d trouvees" % pages)
    verifie(any(m in html for m in (u"Dix pages", u"dix pages", u"Ten pages", u"ten pages")),
            u"la page annonce le bon nombre de pages")

    cites = set(re.findall(r"\b([A-Z][a-zA-Z]+Test)\b", html))
    for nom in sorted(cites):
        existe = os.path.exists(os.path.join(RACINE, "tests", nom + ".cs"))
        verifie(existe, u"le test cite %s existe dans le depot" % nom)

    verifie("AGPL" in html, u"la licence est annoncee sur la page")
    verifie("AFFERO" in fichier("LICENSE").upper(), u"le depot porte bien l'AGPL")


def verifie_publication(html):
    print(u"\n--- La derniere version publiee")
    try:
        donnees = json.loads(lire("https://api.github.com/repos/%s/releases/latest" % DEPOT))
    except Exception as e:
        note(u"API GitHub injoignable (%s) : verification de version ignoree" % e)
        return

    tag = donnees.get("tag_name", "")
    version = tag.lstrip("v")
    verifie(bool(version), u"une version est publiee", tag)

    court = ".".join(version.split(".")[:2])
    verifie(court in html, u"la version affichee correspond a la publication (%s)" % court)

    exe = [a for a in donnees.get("assets", []) if a.get("name", "").lower().endswith(".exe")]
    verifie(len(exe) == 1, u"la publication contient l'executable")
    if exe:
        taille = exe[0].get("size", 0)
        verifie(taille > 100000, u"l'executable a une taille plausible (%d octets)" % taille)

    c = code("https://github.com/%s/releases/latest/download/OpusScreen.exe" % DEPOT)
    verifie(c == 200, u"le bouton de telechargement resout vers un fichier", u"code %d" % c)


# ---------------------------------------------------------------- bilan

def main():
    base = sys.argv[1] if len(sys.argv) > 1 else SITE
    print(u"Verification de %s" % base)

    try:
        html = verifie_page(base)
        verifie_ressources(base, html)
        verifie_affirmations(html)
        if base.startswith("https://antoinebonpro"):
            verifie_publication(html)
    except Exception as e:
        print(u"\nInterrompu : %s" % e)
        echecs.append(u"exception : %s" % e)

    print(u"\n============================================================")
    print(u"  Verifications : %d" % verifs)
    print(u"  Echecs        : %d" % len(echecs))
    if avertissements:
        print(u"  Notes         : %d" % len(avertissements))
    if echecs:
        print(u"  RESULTAT : ECHEC")
        for e in echecs:
            print(u"    - %s" % e)
        return 1
    print(u"  RESULTAT : tout concorde")
    return 0


if __name__ == "__main__":
    sys.exit(main())
