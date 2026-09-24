#!/bin/bash
#
# Fabrique OpusScreen-1.0.0.dmg : l'image disque que l'on telecharge, ouvre, et
# dans laquelle on glisse l'application vers Applications.
#
# Pourquoi une image disque ALORS qu'une archive existe deja :
#
#   Le .zip reste, et il reste necessaire - c'est lui que l'application va
#   chercher quand elle se met a jour toute seule : `ditto` le deballe, et
#   l'echange se fait sans que personne n'ait rien a faire.
#
#   Le .dmg est pour la PREMIERE fois. Une archive telechargee se deballe la ou
#   le navigateur l'a posee, et l'application reste dans Telechargements - d'ou
#   elle fonctionne, mais ou elle se fait effacer par megarde, et ou macOS
#   demande son accord pour le moindre fichier lu. L'image disque montre le
#   geste a faire et l'endroit ou le faire.
#
# Aucun outil tiers, aucun Xcode : hdiutil, osascript et le Finder suffisent.
#
#   tools/make-dmg.sh              construit l'application puis l'image
#   tools/make-dmg.sh --sans-build utilise l'OpusScreen.app deja construit
#
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0.0"
VOLUME="OpusScreen"
APP="OpusScreen.app"
DMG="OpusScreen-$VERSION.dmg"

# La fenetre, en points. Ces trois valeurs sont les memes que celles du script
# qui dessine le fond : elles doivent le rester, sinon les icones ne tombent plus
# sur la fleche.
LARGEUR=640
HAUTEUR=400
AXE=196          # hauteur des deux icones, depuis le HAUT de la fenetre
GAUCHE=160       # centre de l'application
DROITE=480       # centre du raccourci vers Applications
TAILLE_ICONE=112

if [ "${1:-}" != "--sans-build" ]; then
    ./build.sh
fi

[ -d "$APP" ] || { echo "OpusScreen.app absent : lancez ./build.sh"; exit 1; }

echo "==> Fond de la fenetre"
ETAPE="$(mktemp -d)"
mkdir -p "$ETAPE/.background"
swift tools/dmg-fond.swift "$ETAPE/.background/fond.png" 1 > /dev/null
swift tools/dmg-fond.swift "$ETAPE/.background/fond@2x.png" 2 > /dev/null
# Les deux definitions dans un seul fichier : le Finder choisit celle qui
# convient a l'ecran. Sans la version double, le fond est flou sur un Retina -
# c'est-a-dire sur a peu pres tous les Mac vendus depuis 2012.
tiffutil -cathidpicheck "$ETAPE/.background/fond.png" "$ETAPE/.background/fond@2x.png" \
         -out "$ETAPE/.background/fond.tiff" > /dev/null 2>&1
rm "$ETAPE/.background/fond.png" "$ETAPE/.background/fond@2x.png"

echo "==> Contenu"
cp -R "$APP" "$ETAPE/$APP"
ln -s /Applications "$ETAPE/Applications"
# L'icone du disque monte : la meme que celle de l'application.
cp "$APP/Contents/Resources/AppIcon.icns" "$ETAPE/.VolumeIcon.icns"

echo "==> Image inscriptible"
rm -f "$DMG" /tmp/opusscreen-rw.dmg
hdiutil create -srcfolder "$ETAPE" -volname "$VOLUME" -fs HFS+ \
        -format UDRW -ov /tmp/opusscreen-rw.dmg > /dev/null

MONTAGE=$(hdiutil attach /tmp/opusscreen-rw.dmg -readwrite -noverify -nobrowse |
          grep -Eo '/Volumes/.*' | head -1)
[ -n "$MONTAGE" ] || { echo "l'image ne s'est pas montee"; exit 1; }
echo "    montee sur $MONTAGE"

# Le drapeau « cette icone est personnalisee » : sans lui, le fichier
# .VolumeIcon.icns est present mais ignore.
SetFile -a C "$MONTAGE" 2>/dev/null || true

echo "==> Disposition de la fenetre"
#
# Le Finder est pilote par AppleScript, et macOS demande a l'utilisateur
# d'autoriser ce pilotage la premiere fois. Si la question reste sans reponse,
# l'appel ne rend jamais la main. On lui laisse donc un temps, et l'on continue
# sans disposition plutot que de rester bloque : une image sans mise en page
# s'installe tout aussi bien, elle est seulement moins parlante.
#
cat > /tmp/opusscreen-dispo.applescript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {240, 140, $((240 + LARGEUR)), $((140 + HAUTEUR))}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $TAILLE_ICONE
    set text size of opts to 13
    set background picture of opts to file ".background:fond.tiff"
    set position of item "$APP" of container window to {$GAUCHE, $AXE}
    set position of item "Applications" of container window to {$DROITE, $AXE}
    update without registering applications
    close
  end tell
end tell
APPLESCRIPT

osascript /tmp/opusscreen-dispo.applescript > /dev/null 2>&1 &
PILOTE=$!
for _ in $(seq 1 40); do
    kill -0 $PILOTE 2>/dev/null || break
    sleep 1
done
if kill -0 $PILOTE 2>/dev/null; then
    kill -9 $PILOTE 2>/dev/null || true
    echo "    le Finder n'a pas repondu — image sans mise en page"
    DISPOSEE="non"
else
    wait $PILOTE 2>/dev/null && DISPOSEE="oui" || DISPOSEE="non"
    [ "$DISPOSEE" = "oui" ] && echo "    fenetre, icones et fond poses" \
                            || echo "    le Finder a refuse — image sans mise en page"
fi

sync
hdiutil detach "$MONTAGE" -quiet || hdiutil detach "$MONTAGE" -force -quiet

echo "==> Compression"
hdiutil convert /tmp/opusscreen-rw.dmg -format UDZO -imagekey zlib-level=9 \
        -o "$DMG" > /dev/null
rm -f /tmp/opusscreen-rw.dmg
rm -rf "$ETAPE"

# Une image signee, meme localement, n'est pas alteree en chemin sans que cela
# se voie. Ce n'est pas un certificat Apple, et cela ne dispense pas du clic
# droit au premier lancement.
codesign -s - "$DMG" 2>/dev/null || true

echo
echo "$DMG  ($(du -h "$DMG" | cut -f1), mise en page : $DISPOSEE)"
