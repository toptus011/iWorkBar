#!/bin/bash
# zbuduj.sh – kompiluje iWorkBar i instaluje w folderze Aplikacje
# Użycie: otwórz Terminal w tym folderze i wpisz:  bash zbuduj.sh

set -e
cd "$(dirname "$0")"

APP="iWorkBar"
BUILD="build"
BUNDLE="$BUILD/$APP.app"

echo "▶ Sprawdzam narzędzia…"
if ! command -v swiftc >/dev/null 2>&1; then
    echo "Brak kompilatora Swift. Za chwilę otworzy się instalator narzędzi Xcode."
    echo "Po instalacji uruchom ten skrypt ponownie."
    xcode-select --install || true
    exit 1
fi

echo "▶ Kompiluję…"
rm -rf "$BUILD"
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

echo "▶ Instaluję…"
pkill -x "$APP" 2>/dev/null || true
sleep 0.5
if [ -w /Applications ]; then
    DEST="/Applications"
else
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi
rm -rf "$DEST/$APP.app"
cp -R "$BUNDLE" "$DEST/"
xattr -cr "$DEST/$APP.app" 2>/dev/null || true

echo "✅ Gotowe: $DEST/$APP.app"
echo
echo "Jeśli to ponowna instalacja, usuń starą pozycję iWorkBar w:"
echo "Ustawienia systemowe → Prywatność i ochrona → Dostępność, a potem dodaj ją na nowo."
open "$DEST/$APP.app"
