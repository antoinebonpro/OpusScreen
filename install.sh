#!/bin/bash
#
# Installation d'OpusScreen en une commande, sans avertissement.
#
#   curl -fsSL https://antoinebonpro.github.io/OpusScreen/install.sh | bash
#
# CE QUE FAIT CE SCRIPT, ET POURQUOI IL EVITE L'AVERTISSEMENT
#
#   macOS refuse d'ouvrir un logiciel telecharge par un navigateur quand ce
#   logiciel n'est pas NOTARIE - c'est-a-dire envoye a Apple, analyse par elle,
#   et contresigne. La notarisation passe par un compte de developpeur payant.
#   Le message « Apple n'a pas pu confirmer que ce fichier ne contenait pas de
#   logiciel malveillant » ne dit pas qu'Apple a trouve quelque chose : il dit
#   qu'elle n'a rien pu verifier.
#
#   Le blocage repose sur une marque - « com.apple.quarantine » - que les
#   NAVIGATEURS posent sur ce qu'ils telechargent. `curl` ne la pose pas. Un
#   paquet installe par ce script s'ouvre donc normalement.
#
#   Il faut le dire franchement : cela CONTOURNE la verification d'Apple, ce
#   n'est pas la satisfaire. Ce qui la remplace ici est verifiable a l'oeil,
#   dans ce fichier que vous etes en train de lire : l'empreinte SHA-256 du
#   paquet attendu est ecrite ci-dessous, et le script REFUSE d'installer quoi
#   que ce soit qui ne lui corresponde pas, a l'octet pres. La meme empreinte
#   est publiee sur la page de la version. Si les deux concordent, le fichier
#   qui arrive est celui qui a ete publie.
#
#   La seule facon de faire disparaitre l'avertissement pour tout le monde,
#   sans rien contourner, reste la notarisation.
#
set -euo pipefail

VERSION="1.0.1"
# Mises a jour a chaque publication, et verifiees contre GitHub par
# tools/verifier-publication.sh.
ARCHIVE="OpusScreen-mac.zip"
SHA256="c041ff8701e6ced3b942fee9829a27e1f4d00507c3e966efba71a9be647792ae"
URL="https://github.com/antoinebonpro/OpusScreen/releases/download/mac-v$VERSION/$ARCHIVE"

rouge()  { printf '\033[31m%s\033[0m\n' "$*"; }
vert()   { printf '\033[32m%s\033[0m\n' "$*"; }
etape()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

echo
echo "OpusScreen $VERSION — installation"

# ---------------------------------------------------------------- refus utiles

if [ "$(id -u)" -eq 0 ]; then
    rouge "N'installez pas en root : l'application vit dans votre session."
    echo  "Relancez la commande sans sudo."
    exit 1
fi

MAJEURE=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJEURE" -lt 13 ]; then
    rouge "macOS 13 (Ventura) ou plus recent est necessaire — vous avez $(sw_vers -productVersion)."
    exit 1
fi

# ---------------------------------------------------------------- ou installer

CIBLE="/Applications"
if [ ! -w "$CIBLE" ]; then
    CIBLE="$HOME/Applications"
    mkdir -p "$CIBLE"
    echo "  /Applications n'est pas accessible en ecriture — installation dans $CIBLE"
fi

TRAVAIL=$(mktemp -d)
nettoyer() { rm -rf "$TRAVAIL"; }
trap nettoyer EXIT

# ---------------------------------------------------------------- telechargement

etape "1/4  Telechargement"
echo "     $URL"
if ! curl -fSL --progress-bar -o "$TRAVAIL/$ARCHIVE" "$URL"; then
    rouge "Le telechargement a echoue."
    exit 1
fi

# ---------------------------------------------------------------- verification

etape "2/4  Verification"
RECUE=$(shasum -a 256 "$TRAVAIL/$ARCHIVE" | cut -d' ' -f1)
echo "     attendue : $SHA256"
echo "     recue    : $RECUE"
if [ "$RECUE" != "$SHA256" ]; then
    rouge "L'empreinte ne correspond pas. Rien n'a ete installe."
    echo  "Le fichier recu n'est pas celui qui a ete publie : ne l'ouvrez pas."
    exit 1
fi
vert  "     identiques"

# ---------------------------------------------------------------- installation

etape "3/4  Installation dans $CIBLE"

# `ditto` conserve la signature du paquet ; `unzip` ne le fait pas toujours, et
# un paquet dont la signature a saute ne se lance plus.
ditto -x -k "$TRAVAIL/$ARCHIVE" "$TRAVAIL/ouvert"
PAQUET="$TRAVAIL/ouvert/OpusScreen.app"
[ -d "$PAQUET" ] || { rouge "L'archive ne contient pas OpusScreen.app."; exit 1; }

if ! codesign -v --deep --strict "$PAQUET" 2>/dev/null; then
    rouge "La signature du paquet est invalide. Rien n'a ete installe."
    exit 1
fi

ARCHS=$(lipo -archs "$PAQUET/Contents/MacOS/OpusScreen")
echo "     architectures : $ARCHS"
case "$ARCHS" in
    *$(uname -m)*) ;;
    *) rouge "Ce paquet ne contient pas $(uname -m) : il ne demarrerait pas ici."; exit 1 ;;
esac

# Une version deja lancee tient la table de couleurs de l'ecran : la remplacer
# sous ses pieds laisserait un ecran teinte sans personne pour le rendre.
if pgrep -f "OpusScreen.app/Contents/MacOS/OpusScreen" > /dev/null 2>&1; then
    echo "     une version tourne deja — arret propre"
    osascript -e 'quit app "OpusScreen"' 2>/dev/null || true
    sleep 2
    pkill -f "OpusScreen.app/Contents/MacOS/OpusScreen" 2>/dev/null || true
    sleep 1
fi

rm -rf "$CIBLE/OpusScreen.app"
mv "$PAQUET" "$CIBLE/OpusScreen.app"

# Ceinture et bretelles : `curl` ne pose pas de quarantaine, mais rien
# n'empeche ce script d'etre lance sur une archive venue d'ailleurs.
xattr -dr com.apple.quarantine "$CIBLE/OpusScreen.app" 2>/dev/null || true

# ---------------------------------------------------------------- lancement

etape "4/4  Lancement"
open "$CIBLE/OpusScreen.app"
sleep 3
if pgrep -f "OpusScreen.app/Contents/MacOS/OpusScreen" > /dev/null 2>&1; then
    vert "     OpusScreen tourne — son icone est dans la barre des menus, en haut a droite."
else
    rouge "     L'application ne semble pas demarrer. Ouvrez-la depuis $CIBLE."
    exit 1
fi

echo
echo "Installe dans $CIBLE/OpusScreen.app"
echo
echo "  Clic gauche sur l'icone : reglages       Molette : luminosite"
echo "  Clic droit              : menu rapide"
echo
echo "Deux autorisations seront demandees quand elles serviront :"
echo "  · Enregistrement de l'ecran — filtres de couleur, daltonisme, loupe."
echo "    Sans elle, la luminosite et la temperature fonctionnent quand meme."
echo "  · Accessibilite — pour que le raccourci de secours reponde meme si"
echo "    l'interface est bloquee."
echo
echo "Desinstaller :  rm -rf \"$CIBLE/OpusScreen.app\""
echo
