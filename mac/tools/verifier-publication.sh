#!/bin/bash
#
# Verifie ce qui est EN LIGNE, et non ce qui est sur cette machine.
#
# Une publication tient par des valeurs recopiees a plusieurs endroits :
# l'empreinte epinglee dans install.sh, celles annoncees dans les notes de
# version, les liens du site, le numero dans le paquet. Chacune peut se
# desynchroniser sans que rien ne casse visiblement - et ce qui casse alors,
# c'est la confiance : un script qui refuse d'installer, une empreinte qui ne
# correspond pas, un lien vers une version qui n'existe plus.
#
#   tools/verifier-publication.sh
#
set -uo pipefail
cd "$(dirname "$0")/.."

DEPOT="antoinebonpro/OpusScreen"
SITE="https://antoinebonpro.github.io/OpusScreen"
ECHECS=0

ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
ko()  { printf '  \033[31m✗\033[0m %s\n' "$*"; ECHECS=$((ECHECS + 1)); }

echo
echo "OpusScreen macOS — controle de la publication"
echo

VERSION=$(grep -E '^VERSION=' install.sh | cut -d'"' -f2)
EPINGLEE=$(grep -E '^SHA256=' install.sh | cut -d'"' -f2)
echo "  install.sh epingle la version $VERSION"
echo

# --------------------------------------------------------------- la publication

REPONSE="$(mktemp)"
trap 'rm -f "$REPONSE"' EXIT
if ! curl -fsSL "https://api.github.com/repos/$DEPOT/releases/tags/mac-v$VERSION" -o "$REPONSE" 2>/dev/null; then
    ko "la publication mac-v$VERSION n'existe pas"
    echo; echo "$ECHECS probleme(s)"; exit 1
fi
ok "la publication mac-v$VERSION existe"

# Le JSON est lu par `plutil`, present sur tout macOS sans le moindre outil de
# developpement.
#
# La premiere version de ce script decoupait le JSON a coups de `tr` et de
# `grep`. Elle annoncait l'archive ABSENTE alors qu'elle etait bien la : le
# decoupage cassait aussi l'objet imbrique « uploader », et l'empreinte tombait
# hors de portee. Un controle qui crie a tort est pire que pas de controle -
# on apprend a l'ignorer, et le jour ou il a raison, personne ne l'ecoute.
champ() { plutil -extract "$1" raw -o - "$REPONSE" 2>/dev/null; }


PUBLIEE=""
URL_ZIP=""
INDEX=0
while :; do
    NOM=$(champ "assets.$INDEX.name") || break
    [ -n "$NOM" ] || break
    case "$NOM" in
        OpusScreen-mac.zip)
            PUBLIEE=$(champ "assets.$INDEX.digest" | sed 's/^sha256://')
            URL_ZIP=$(champ "assets.$INDEX.browser_download_url")
            ;;
        "OpusScreen-$VERSION.dmg") DMG_PRESENT="oui" ;;
    esac
    INDEX=$((INDEX + 1))
    [ "$INDEX" -gt 20 ] && break
done

if [ -z "$PUBLIEE" ]; then
    ko "OpusScreen-mac.zip absent de la publication"
elif [ "$PUBLIEE" = "$EPINGLEE" ]; then
    ok "l'empreinte epinglee dans install.sh est celle du fichier publie"
else
    ko "empreintes differentes — install.sh refuserait d'installer"
    echo "      epinglee : $EPINGLEE"
    echo "      publiee  : $PUBLIEE"
fi

if [ "${DMG_PRESENT:-non}" = "oui" ]; then
    ok "OpusScreen-$VERSION.dmg est publie"
else
    ko "OpusScreen-$VERSION.dmg absent de la publication"
fi

# --------------------------------------------------------------- Windows intact

# Capture d'abord, filtre ensuite : « curl | grep -q » fait echouer le tuyau
# entier sous `pipefail`, grep fermant le tuyau des la premiere correspondance
# et curl mourant alors d'un SIGPIPE. Le controle disait « non trouve » sur des
# pages qui contenaient pourtant ce qu'il cherchait.
DERNIERE_JSON="$(curl -fsSL "https://api.github.com/repos/$DEPOT/releases/latest" 2>/dev/null)"
DERNIERE=$(printf '%s' "$DERNIERE_JSON" | grep -m1 '"tag_name"' | cut -d'"' -f4)
case "$DERNIERE" in
    mac-*) ko "« derniere version » est $DERNIERE : la version Windows irait la chercher" ;;
    "")    ko "impossible de lire la derniere publication" ;;
    *)     ok "« derniere version » reste $DERNIERE, pour Windows" ;;
esac

# --------------------------------------------------------------- le site

for CHEMIN in "/" "/en/" "/install.sh"; do
    CODE=$(curl -fsSL -o /dev/null -w '%{http_code}' "$SITE$CHEMIN" 2>/dev/null)
    [ "$CODE" = "200" ] && ok "le site sert $CHEMIN" || ko "le site rend $CODE sur $CHEMIN"
done

SCRIPT_DISTANT="$(curl -fsSL "$SITE/install.sh" 2>/dev/null)"
DISTANT=$(printf '%s' "$SCRIPT_DISTANT" | grep -E '^SHA256=' | cut -d'"' -f2)
if [ "$DISTANT" = "$EPINGLEE" ]; then
    ok "le script servi par le site est celui du depot"
else
    ko "le script servi par le site epingle une AUTRE empreinte"
    echo "      depot : $EPINGLEE"
    echo "      site  : ${DISTANT:-absente}"
fi

MANQUANTS=0
for PAGE in "$SITE/" "$SITE/en/"; do
    CORPS="$(curl -fsSL "$PAGE" 2>/dev/null)"
    case "$CORPS" in
        *"OpusScreen-$VERSION.dmg"*) ;;
        *) MANQUANTS=$((MANQUANTS + 1)) ;;
    esac
done
[ "$MANQUANTS" -eq 0 ] && ok "les deux pages pointent la $VERSION" \
                       || ko "$MANQUANTS page(s) pointent une autre version"

# --------------------------------------------------------------- le fichier

if [ -n "$URL_ZIP" ]; then
    RECUE=$(curl -fsSL "$URL_ZIP" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
    [ "$RECUE" = "$EPINGLEE" ] && ok "le fichier telecharge a bien cette empreinte" \
                               || ko "le fichier telecharge rend $RECUE"
fi

echo
if [ "$ECHECS" -eq 0 ]; then
    printf '\033[32mLa publication est coherente.\033[0m\n\n'
else
    printf '\033[31m%s probleme(s).\033[0m\n\n' "$ECHECS"
    exit 1
fi
