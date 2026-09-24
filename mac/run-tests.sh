#!/bin/bash
#
# Verification avant diffusion.
#
# Sept suites, plus de cinq mille assertions. Le script refuse d'annoncer un
# succes si une suite n'a rien execute : une suite silencieuse est le pire des
# resultats, parce qu'elle ressemble a un succes.
#
#   ./run-tests.sh          les sept suites de calcul, en mode a blanc
#   ./run-tests.sh live     + la verification REELLE : elle pose une table de
#                             couleurs sur l'ecran, la relit, et la rend.
#                             L'ecran change brievement.
#   ./run-tests.sh app      + le test de bout en bout de la vraie application
#   ./run-tests.sh build    + construction du paquet
#   ./run-tests.sh all      tout
#
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Compilation des suites"
swift build --product OpusScreenTests > /dev/null

BIN="$(swift build --show-bin-path)/OpusScreenTests"

MODE="${1:-}"
ARGS=""
if [ "$MODE" = "live" ] || [ "$MODE" = "all" ]; then
    ARGS="--live"
fi

# Sans --live, les suites tournent en mode a blanc : elles ne touchent ni a la
# table de couleurs, ni au voile, ni au retroeclairage, ni au son de la machine
# qui les execute.
set +e
"$BIN" $ARGS
STATUS=$?
set -e

if [ "$MODE" = "build" ] || [ "$MODE" = "app" ] || [ "$MODE" = "all" ]; then
    echo "==> Construction du paquet"
    ./build.sh > /dev/null
    if [ ! -x "OpusScreen.app/Contents/MacOS/OpusScreen" ]; then
        echo "Le paquet n'a pas ete produit."
        exit 1
    fi
    echo "  ✓ OpusScreen.app construit"
fi

if [ "$MODE" = "app" ] || [ "$MODE" = "all" ]; then
    # Le dernier chemin qu'aucune suite Swift n'emprunte : le paquet construit,
    # lance comme l'utilisateur le lancera, pilote comme il le pilotera.
    set +e
    ./tools/test-app.sh
    APP_STATUS=$?
    set -e
    [ "$APP_STATUS" -ne 0 ] && STATUS=$APP_STATUS
fi

exit $STATUS
