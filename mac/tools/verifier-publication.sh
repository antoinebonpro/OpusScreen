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

JSON=$(curl -fsSL "https://api.github.com/repos/$DEPOT/releases/tags/mac-v$VERSION" 2>/dev/null)
if [ -z "$JSON" ]; then
    ko "la publication mac-v$VERSION n'existe pas"
    echo; echo "$ECHECS probleme(s)"; exit 1
fi
ok "la publication mac-v$VERSION existe"

lire() { printf '%s' "$JSON" | tr ',' '\n' | grep -A0 "$1" | head -1; }

PUBLIEE=$(printf '%s' "$JSON" \
  | tr '{}' '\n\n' | grep -F '"name": "OpusScreen-mac.zip"' -A 30 \
  | grep -o 'sha256:[0-9a-f]\{64\}' | head -1 | cut -d: -f2)

if [ -z "$PUBLIEE" ]; then
    ko "OpusScreen-mac.zip absent de la publication"
elif [ "$PUBLIEE" = "$EPINGLEE" ]; then
    ok "l'empreinte epinglee dans install.sh est celle du fichier publie"
else
    ko "empreintes differentes — install.sh refuserait d'installer"
    echo "      epinglee : $EPINGLEE"
    echo "      publiee  : $PUBLIEE"
fi

if printf '%s' "$JSON" | grep -q "OpusScreen-$VERSION.dmg"; then
    ok "OpusScreen-$VERSION.dmg est publie"
else
    ko "OpusScreen-$VERSION.dmg absent de la publication"
fi

# --------------------------------------------------------------- Windows intact

DERNIERE=$(curl -fsSL "https://api.github.com/repos/$DEPOT/releases/latest" 2>/dev/null \
           | grep -m1 '"tag_name"' | cut -d'"' -f4)
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

DISTANT=$(curl -fsSL "$SITE/install.sh" 2>/dev/null | grep -E '^SHA256=' | cut -d'"' -f2)
if [ "$DISTANT" = "$EPINGLEE" ]; then
    ok "le script servi par le site est celui du depot"
else
    ko "le script servi par le site epingle une AUTRE empreinte"
    echo "      depot : $EPINGLEE"
    echo "      site  : ${DISTANT:-absente}"
fi

MANQUANTS=0
for PAGE in "$SITE/" "$SITE/en/"; do
    curl -fsSL "$PAGE" 2>/dev/null | grep -q "OpusScreen-$VERSION.dmg" || MANQUANTS=$((MANQUANTS + 1))
done
[ "$MANQUANTS" -eq 0 ] && ok "les deux pages pointent la $VERSION" \
                       || ko "$MANQUANTS page(s) pointent une autre version"

# --------------------------------------------------------------- le fichier

ATTENDUE=$(printf '%s' "$JSON" | tr '{}' '\n\n' \
  | grep -F '"name": "OpusScreen-mac.zip"' -A 30 \
  | grep -o '"browser_download_url": "[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "$ATTENDUE" ]; then
    RECUE=$(curl -fsSL "$ATTENDUE" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
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
