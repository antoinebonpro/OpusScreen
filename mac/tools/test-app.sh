#!/bin/bash
#
# Test de bout en bout : la VRAIE application, pilotée depuis un terminal.
#
# Les suites Swift vérifient le calcul et les étages pris un par un. Il reste un
# chemin qu'aucune d'elles n'emprunte : le paquet construit, lancé comme
# l'utilisateur le lancera, recevant des ordres comme il en recevra, et rendant
# l'écran quand on le lui demande.
#
# Ce script assombrit et réchauffe réellement l'écran pendant quelques secondes.
# Il sauvegarde la configuration existante et la remet en partant.
#
set -uo pipefail
# L'application est toujours lancee dans un SOUS-SHELL — « ( ... & ) » — et non
# directement en arriere-plan. Sinon bash garde la tache pour sienne et annonce
# lui-meme chaque mort (« Terminated: 15 », « Killed: 9 ») au milieu du compte
# rendu. Ces morts sont voulues : c'est le test qui les provoque. « set +m » ne
# suffit pas dans un script ; ne pas posseder la tache, si.
set +m
cd "$(dirname "$0")/.."

# Chemin ABSOLU : le binaire est lance par ce chemin et cherche par ce chemin.
# Lancer en relatif et chercher en absolu ne trouve rien, et le script croirait
# que l'application ne demarre pas.
APP="$PWD/OpusScreen.app"
BIN="$APP/Contents/MacOS/OpusScreen"
GAMMA="$(swift build --show-bin-path)/OpusScreenTests"
CONFIG="$HOME/Library/Application Support/OpusScreen"
BACKUP="$(mktemp -d)/OpusScreen-config"

PASS=0
FAIL=0
FAILURES=()

ok()   { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
ko()   { FAIL=$((FAIL+1)); FAILURES+=("$1"); printf '  \033[31m✗\033[0m %s\n' "$1"; }

# Le point blanc du canal demandé, sur le premier écran.
white() {  # $1 = 2 (rouge) | 3 (vert) | 4 (bleu)
    "$GAMMA" --gamma | head -1 | awk -v c="$1" '{print $c}'
}

# Vrai si $1 < $2, en flottant.
below() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'; }
above() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }

cleanup() {
  # Les messages de bash sur les processus tues n'ont rien a faire dans le
  # compte rendu : ces morts sont voulues.
  {
    pkill -f "$BIN" 2>/dev/null
    sleep 1

    # L'écran est rendu quoi qu'il arrive : ce script ne doit jamais laisser
    # derrière lui le problème que l'application est censée prévenir. Sans
    # instance en cours, cette copie applique le réglage elle-même.
    ( "$BIN" --reset >/dev/null 2>&1 & )
    sleep 2
    pkill -f "$BIN" 2>/dev/null
    sleep 2   # laisser le processus finir d'écrire avant d'effacer derrière lui

    # Et la configuration de l'utilisateur est remise telle qu'elle était, y
    # compris son absence : un test ne laisse rien derrière lui.
    rm -rf "$CONFIG"
    if [ -d "$BACKUP" ]; then
        mkdir -p "$(dirname "$CONFIG")"
        cp -R "$BACKUP" "$CONFIG"
    fi
  } 2>/dev/null
}
trap cleanup EXIT

echo
echo "OpusScreen - test de bout en bout"
echo

# ---------------------------------------------------------------- préparation

if [ ! -x "$BIN" ]; then
    echo "Le paquet n'existe pas. Lancez ./build.sh d'abord."
    exit 1
fi

[ -d "$CONFIG" ] && cp -R "$CONFIG" "$BACKUP"
rm -rf "$CONFIG"
pkill -f "$BIN" 2>/dev/null
sleep 1

BEFORE=$(white 2)
echo "  point blanc au départ : $BEFORE"
echo

# ---------------------------------------------------------------- 1. l'aide

if "$BIN" --help 2>/dev/null | grep -q "pilotage en ligne de commande"; then
    ok "--help répond sans rien lancer"
else
    ko "--help ne répond pas"
fi

if pgrep -f "$BIN" > /dev/null; then
    ko "--help a laissé un processus derrière lui"
else
    ok "--help ne laisse aucun processus"
fi

# ---------------------------------------------------------------- 2. démarrage

( "$BIN" --minimized > /tmp/opusscreen-e2e.log 2>&1 & )
sleep 4

if pgrep -f "$BIN" > /dev/null; then
    ok "l'application démarre et tient"
else
    ko "l'application ne démarre pas"
    cat /tmp/opusscreen-e2e.log
    exit 1
fi

if [ -f "$CONFIG/settings.ini" ]; then
    ok "la configuration est écrite au bon endroit"
else
    # Elle n'est écrite qu'au premier réglage : ce n'est pas un échec ici.
    echo "  · configuration pas encore écrite (normal avant tout réglage)"
fi

INSTANCES=$(pgrep -f "$BIN" | wc -l | tr -d " ")
if [ "$INSTANCES" -eq 1 ]; then
    ok "une seule instance"
else
    ko "$INSTANCES instances en même temps"
fi

# ---------------------------------------------------------------- 3. un ordre

"$BIN" --brightness 40 --temp 2500 > /dev/null 2>&1
sleep 3

AFTER_R=$(white 2)
AFTER_B=$(white 4)

if below "$AFTER_R" 0.60; then
    ok "l'écran a été assombri sur ordre  (blanc : $BEFORE → $AFTER_R)"
else
    ko "l'écran n'a pas été assombri  (blanc : $AFTER_R)"
fi

if below "$AFTER_B" "$AFTER_R"; then
    ok "l'écran a été réchauffé  (bleu $AFTER_B < rouge $AFTER_R)"
else
    ko "l'écran n'a pas été réchauffé  (bleu $AFTER_B, rouge $AFTER_R)"
fi

INSTANCES=$(pgrep -f "$BIN" | wc -l | tr -d " ")
if [ "$INSTANCES" -eq 1 ]; then
    ok "l'ordre a été transmis sans lancer de seconde instance"
else
    ko "$INSTANCES instances après l'ordre"
fi

if [ -f "$CONFIG/active.flag" ]; then
    ok "le témoin de plantage est posé tant qu'un effet est actif"
else
    ko "le témoin de plantage n'a pas été posé"
fi

# ---------------------------------------------------------------- 4. un mode

"$BIN" --mode "Nuit profonde" > /dev/null 2>&1
sleep 3

NIGHT_R=$(white 2)
if below "$NIGHT_R" 0.55; then
    ok "un mode nommé s'applique  (« Nuit profonde », blanc : $NIGHT_R)"
else
    ko "le mode nommé ne s'est pas appliqué  (blanc : $NIGHT_R)"
fi

if grep -q "activeMode=Nuit profonde" "$CONFIG/settings.ini" 2>/dev/null; then
    ok "le mode est mémorisé dans la configuration"
else
    ko "le mode n'a pas été mémorisé"
fi

# ---------------------------------------------------------------- 5. remise à zéro

"$BIN" --reset > /dev/null 2>&1
sleep 3

RESET_R=$(white 2)
if above "$RESET_R" 0.95; then
    ok "--reset rend l'écran  (blanc : $RESET_R)"
else
    ko "--reset n'a pas rendu l'écran  (blanc : $RESET_R)"
fi

if [ ! -f "$CONFIG/active.flag" ]; then
    ok "le témoin de plantage est effacé quand plus rien n'est actif"
else
    ko "le témoin de plantage traîne alors que l'écran est normal"
fi

# ---------------------------------------------------------------- 6. les accessibilités

"$BIN" --vision vert --severity 60 > /dev/null 2>&1
sleep 2
if grep -qE "^current=.*;5;" "$CONFIG/settings.ini" 2>/dev/null; then
    ok "la correction daltonisme est enregistrée par son nom courant"
else
    ko "la correction daltonisme n'a pas été enregistrée"
fi

"$BIN" --vision aucune > /dev/null 2>&1
sleep 2

# ---------------------------------------------------------------- 7. sortie propre

pkill -f "$BIN"
sleep 3

if pgrep -f "$BIN" > /dev/null; then
    ko "l'application ne s'arrête pas"
else
    ok "l'application s'arrête"
fi

FINAL=$(white 2)
if above "$FINAL" 0.95; then
    ok "l'écran est rendu après l'arrêt  (blanc : $FINAL)"
else
    ko "l'écran est resté modifié après l'arrêt  (blanc : $FINAL)"
fi

# ---------------------------------------------------------------- 8. après un plantage
#
# On simule le pire : un effet actif, et le processus tué sans ménagement.
#
# Ce que macOS fait ici mérite d'être constaté plutôt que supposé : il REND la
# table de couleurs quand le processus qui l'a posée meurt. C'est la différence
# la plus importante avec Windows, où la table survit au processus. Le test
# l'affirme donc sur cette machine, au lieu de recopier une croyance.

( "$BIN" --minimized > /dev/null 2>&1 & )
sleep 4
"$BIN" --brightness 30 > /dev/null 2>&1
sleep 3

DURING=$(white 2)
if below "$DURING" 0.5; then
    ok "un effet est bien actif avant le plantage  (blanc : $DURING)"
else
    ko "l'effet n'a pas été appliqué avant le plantage  (blanc : $DURING)"
fi

pkill -9 -f "$BIN"
sleep 2

AFTER_KILL=$(white 2)
if above "$AFTER_KILL" 0.95; then
    ok "macOS rend la table à la mort du processus  (blanc : $AFTER_KILL)"
else
    ko "la table a survécu au processus  (blanc : $AFTER_KILL) — le danger de Windows existe ici"
fi

# Le témoin de plantage, lui, survit : c'est ce qui permet à l'application de
# savoir, au relancement, que la session précédente s'est mal terminée.
if [ -f "$CONFIG/active.flag" ]; then
    ok "le témoin de plantage a survécu au SIGKILL"
else
    ko "le témoin de plantage a disparu : la reprise ne saurait pas qu'il y a eu plantage"
fi

# Au relancement, l'application reprend la main : elle repose ce que
# l'utilisateur avait réglé. Ce n'est pas un écran rendu, c'est un écran
# retrouvé - et c'est bien ce qu'on veut.
( "$BIN" --minimized > /dev/null 2>&1 & )
sleep 5

REGAINED=$(white 2)
if below "$REGAINED" 0.5; then
    ok "au relancement, l'application reprend la main  (blanc : $REGAINED)"
else
    ko "l'application n'a pas repris la main après le plantage  (blanc : $REGAINED)"
fi

"$BIN" --reset > /dev/null 2>&1
sleep 3
CLEARED=$(white 2)
if above "$CLEARED" 0.95; then
    ok "et --reset rend l'écran après une reprise  (blanc : $CLEARED)"
else
    ko "--reset ne rend pas l'écran après une reprise  (blanc : $CLEARED)"
fi

pkill -f "$BIN"
sleep 2

# ---------------------------------------------------------------- verdict

echo
echo "$((PASS + FAIL)) vérifications, $PASS réussies, $FAIL en échec"
if [ "$FAIL" -gt 0 ]; then
    echo
    echo "ÉCHECS :"
    for f in "${FAILURES[@]}"; do echo "  · $f"; done
    echo
    exit 1
fi
echo
echo "L'application fonctionne de bout en bout."
echo
