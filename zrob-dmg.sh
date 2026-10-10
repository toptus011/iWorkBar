#!/bin/bash
# zrob-dmg.sh – kompiluje iWorkBar i tworzy instalator iWorkBar.dmg
# Użycie: w Terminalu wpisz  bash  (ze spacją), przeciągnij ten plik do okna i naciśnij Enter.

set -e
cd "$(dirname "$0")"

APP="iWorkBar"
BUILD="build"
BUNDLE="$BUILD/$APP.app"
STAGE="$BUILD/dmg"
DMG="$APP.dmg"

echo "▶ Sprawdzam narzędzia…"
if ! command -v swiftc >/dev/null 2>&1; then
    echo "Brak kompilatora Swift. Za chwilę otworzy się instalator narzędzi Xcode."
    echo "Po instalacji uruchom ten skrypt ponownie."
    xcode-select --install || true
    exit 1
fi

echo "▶ Kompiluję…"
rm -rf "$BUILD" "$DMG"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

swiftc -O -swift-version 5 \
    -target arm64-apple-macos13.0 \
    -framework Cocoa -framework ServiceManagement -framework ApplicationServices \
    -o "$BUNDLE/Contents/MacOS/$APP" \
    Sources/*.swift

cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/config.default.json "$BUNDLE/Contents/Resources/config.default.json"

echo "▶ Podpisuję (lokalnie, ze stałym identyfikatorem)…"
# Stały wymóg podpisu sprawia, że uprawnienie Dostępności przetrwa kolejne aktualizacje.
if ! codesign --force --sign - --identifier pl.bulka.iworkbar \
        --requirements '=designated => identifier "pl.bulka.iworkbar"' "$BUNDLE" 2>/dev/null; then
    echo "  (podpis ze stałym identyfikatorem niedostępny – używam zwykłego podpisu)"
    codesign --force --sign - --identifier pl.bulka.iworkbar "$BUNDLE"
fi
codesign --verify "$BUNDLE" && echo "  podpis poprawny"

echo "▶ Tworzę instalator .dmg…"
mkdir -p "$STAGE"
cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Aplikacje"
cp README.md "$STAGE/Przeczytaj mnie.md"

hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "✅ Gotowe: $(pwd)/$DMG"
echo "Otwieram instalator – przeciągnij iWorkBar na folder Aplikacje."
open "$DMG"
