#!/bin/bash
#
# Construit OpusScreen.app.
#
# Aucune dependance a installer, aucun Xcode : les outils en ligne de commande
# d'Apple suffisent. C'est le pendant du build.cmd de la version Windows, qui
# s'appuyait sur le compilateur C# livre avec le systeme.
#
#   ./build.sh            construit OpusScreen.app en mode release
#   ./build.sh debug      construit en mode debug (compilation plus rapide)
#   ./build.sh run        construit puis lance
#
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="release"
RUN="no"
case "${1:-}" in
    debug) CONFIG="debug" ;;
    run)   RUN="yes" ;;
    "")    ;;
    *)     echo "usage: ./build.sh [debug|run]"; exit 1 ;;
esac

APP="OpusScreen.app"
VERSION="1.0.0"
BUNDLE_ID="com.opusscreen.OpusScreen"

echo "==> Compilation ($CONFIG)"
swift build -c "$CONFIG" --product OpusScreenApp

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assemblage du paquet"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/OpusScreenApp" "$APP/Contents/MacOS/OpusScreen"

# Le paquet de ressources produit par SwiftPM contient le logo. Il doit vivre
# dans Resources : c'est la que `Bundle.module` le cherche une fois l'executable
# range dans un paquet d'application.
if [ -d "$BIN_DIR/OpusScreen_OpusScreenKit.bundle" ]; then
    cp -R "$BIN_DIR/OpusScreen_OpusScreenKit.bundle" "$APP/Contents/Resources/"
fi

# ---------------------------------------------------------------- icone
#
# Derivee du logo a la construction plutot que livree toute faite : une icone
# qui vit a cote de son logo finit par diverger de lui.

echo "==> Icone"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
LOGO="Sources/OpusScreen/Resources/logo.png"

if [ -f "$LOGO" ]; then
    # Le logo est plus large que haut : on le recadre au carre, centre, avant de
    # le reduire. Sans ce recadrage, l'icone serait une bande dans un carre vide.
    SQUARE="$(mktemp -d)/square.png"
    HEIGHT=$(sips -g pixelHeight "$LOGO" | awk '/pixelHeight/ {print $2}')
    sips -c "$HEIGHT" "$HEIGHT" "$LOGO" --out "$SQUARE" >/dev/null 2>&1

    for size in 16 32 64 128 256 512; do
        sips -z $size $size "$SQUARE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
        double=$((size * 2))
        sips -z $double $double "$SQUARE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
    done
    # iconutil n'accepte pas les tailles au-dela de 512@2x.
    rm -f "$ICONSET/icon_512x512@2x.png"
    sips -z 1024 1024 "$SQUARE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null 2>&1
    rm -f "$ICONSET/icon_64x64.png" "$ICONSET/icon_64x64@2x.png"

    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
    echo "    (logo absent : paquet sans icone)"
fi

# ---------------------------------------------------------------- Info.plist

echo "==> Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>OpusScreen</string>
    <key>CFBundleDisplayName</key>
    <string>OpusScreen</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>OpusScreen</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>

    <!-- Accessoire de la barre des menus : aucune icone de Dock par defaut.
         Le reglage « montrer dans le Dock » la remet sans redemarrage. -->
    <key>LSUIElement</key>
    <true/>

    <key>NSHumanReadableCopyright</key>
    <string>OpusScreen - GNU AGPL v3</string>

    <!-- Les intitules que macOS montre au moment de demander l'autorisation.
         Ils doivent dire ce que l'application fait, pas reciter le nom de l'API :
         c'est sur cette phrase que la personne decide. -->
    <key>NSScreenCaptureUsageDescription</key>
    <string>OpusScreen lit l'image de l'ecran pour y appliquer la correction du daltonisme, la saturation et la loupe. Rien n'est enregistre et rien ne sort de votre Mac : l'image est transformee et reposee a l'ecran, image par image.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>OpusScreen ouvre les Reglages Systeme a la bonne page lorsque vous le lui demandez.</string>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------- signature
#
# Signature locale. Elle ne remplace pas un certificat de developpeur, mais elle
# donne au paquet une identite stable, sans quoi macOS redemanderait
# l'autorisation d'enregistrement de l'ecran a chaque lancement.

echo "==> Signature locale"
codesign --force --deep --sign - "$APP" 2>/dev/null || \
    echo "    (signature impossible : l'autorisation d'ecran sera redemandee a chaque construction)"

echo
echo "OpusScreen.app est pret."
echo
echo "  open $APP                 lance l'application"
echo "  cp -R $APP /Applications  la range une fois pour toutes"
echo
echo "Au premier lancement, macOS demandera l'autorisation « Enregistrement de"
echo "l'ecran » : elle sert aux filtres de couleur et a la loupe. La luminosite"
echo "et la temperature fonctionnent sans elle."

if [ "$RUN" = "yes" ]; then
    echo
    echo "==> Lancement"
    open "$APP"
fi
