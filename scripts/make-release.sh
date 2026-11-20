#!/usr/bin/env bash
# Builds Jukto, signs it (ad-hoc) and packages it. Puts two disk images on your Desktop:
#   Jukto-<ver>-AppleSilicon.dmg   for M-series Macs
#   Jukto-<ver>-Intel.dmg          for Intel Macs
#   Jukto-<ver>.sha256             SHA-256 of the .dmg files (what GitHub shows for each download)
#   Jukto-<ver>-in-app.sha256      SHA-256 of the app INSIDE each .dmg = what Jukto shows when you click its version
#   Jukto-<ver>-release-notes.md   a ready table for the GitHub release description
# Then launches the freshly built app.
#
#   ./scripts/make-release.sh            -> version from project.yml (MARKETING_VERSION)
#   ./scripts/make-release.sh 1.0.1      -> another version
#   UNIVERSAL=1 ./scripts/make-release.sh   -> also a universal .dmg (both CPUs in one, larger)
#   SKIP_FETCH=1 ./scripts/make-release.sh  -> reuse the components already downloaded
#   NO_LAUNCH=1 ./scripts/make-release.sh   -> don't open the app at the end
set -euo pipefail
trap 'echo "✗ Failed at line $LINENO: $BASH_COMMAND" >&2' ERR
cd "$(dirname "$0")/.."
# Default version = MARKETING_VERSION in project.yml (the one place to bump it).
VERSION="${1:-$(sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -1)}"
BUILD_NO="$(date +%Y%m%d%H%M)"

command -v xcodegen >/dev/null || { echo "Install xcodegen first:  brew install xcodegen"; exit 1; }
xcodebuild -version >/dev/null 2>&1 || { echo "Full Xcode is required (App Store)."; exit 1; }

# yt-dlp / ffmpeg / ffprobe / deno are downloaded (and checksum-verified) once and baked into the app.
if [ "${SKIP_FETCH:-0}" != "1" ] || [ ! -x Jukto/Resources/bin/yt-dlp ]; then ./scripts/fetch-binaries.sh; fi

xcodegen generate
rm -rf build
xcodebuild -project Jukto.xcodeproj -scheme Jukto -configuration Release -derivedDataPath build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NO" \
  CODE_SIGN_IDENTITY="-" build | tail -5

APP="build/Build/Products/Release/Jukto.app"
ENT="Jukto/Jukto.entitlements"
[ -d "$APP" ] || { echo "Build failed"; exit 1; }
DESK="$HOME/Desktop"

# Nested tools are signed first and the app last, so the app's seal covers everything.
sign_app() {
  local app="$1" f
  for f in "$app"/Contents/Resources/bin/*; do
    [ -f "$f" ] || continue
    chmod +x "$f"; codesign --force --options runtime --entitlements "$ENT" --sign - "$f"
  done
  codesign --force --options runtime --entitlements "$ENT" --sign - "$app"
  codesign --verify --strict "$app"
}

README="$(mktemp)"
cat > "$README" <<EOS
Jukto $VERSION — made by asan_djantaliev
Works on macOS 14 or newer.

INSTALL
1. Drag Jukto.app into the Applications folder.
2. First launch: macOS says the app is from an unidentified developer.
   Open System Settings → Privacy & Security, scroll down and press "Open Anyway"
   (older macOS: right-click Jukto → Open → Open).
   Or run once in Terminal:  xattr -cr /Applications/Jukto.app

UPDATES
Jukto never updates itself. Click "yt-dlp" in the footer (or Settings → Check for Updates)
when YOU want to refresh yt-dlp and ffmpeg.
EOS

make_dmg() { # app-path output-name
  local stage; stage="$(mktemp -d)"
  cp -R "$1" "$stage/"; ln -s /Applications "$stage/Applications"; cp "$README" "$stage/READ ME.txt"
  rm -f "$DESK/$2.dmg"
  hdiutil create -volname "Jukto $VERSION" -srcfolder "$stage" -ov -format ULMO "$DESK/$2.dmg" >/dev/null   # LZMA: smallest
}

make_thin() { # arch -> prints path of a single-architecture signed copy
  local arch="$1" dir f; dir="$(mktemp -d)"
  ditto "$APP" "$dir/Jukto.app"
  for f in "$dir/Jukto.app/Contents/MacOS/Jukto" "$dir/Jukto.app/Contents/Resources/bin/"*; do
    [ -f "$f" ] || continue
    if [ "$(lipo -archs "$f" | wc -w | tr -d ' ')" -gt 1 ]; then
      lipo -thin "$arch" "$f" -output "$f.thin"; mv "$f.thin" "$f"; chmod +x "$f"
    fi
  done
  sign_app "$dir/Jukto.app" >&2
  echo "$dir/Jukto.app"
}

sign_app "$APP"
echo "CPU architectures: $(lipo -archs "$APP/Contents/MacOS/Jukto")"

# Same recipe as the app's own footer check: main executable + code-signature seal.
app_sha() { cat "$1/Contents/MacOS/Jukto" "$1/Contents/_CodeSignature/CodeResources" | shasum -a 256 | cut -d' ' -f1; }

ARM_APP="$(make_thin arm64)";  make_dmg "$ARM_APP"  "Jukto-$VERSION-AppleSilicon"
X86_APP="$(make_thin x86_64)"; make_dmg "$X86_APP" "Jukto-$VERSION-Intel"
[ "${UNIVERSAL:-0}" = "1" ] && make_dmg "$APP" "Jukto-$VERSION-Universal"

( cd "$DESK" && shasum -a 256 Jukto-"$VERSION"-*.dmg > "Jukto-$VERSION.sha256" )
{
  echo "$(app_sha "$ARM_APP")  Jukto $VERSION AppleSilicon (shown in the app)"
  echo "$(app_sha "$X86_APP")  Jukto $VERSION Intel (shown in the app)"
  [ "${UNIVERSAL:-0}" = "1" ] && echo "$(app_sha "$APP")  Jukto $VERSION Universal (shown in the app)"
} > "$DESK/Jukto-$VERSION-in-app.sha256"
{
  echo "### SHA-256"
  echo
  echo "| Download | SHA-256 of the .dmg (GitHub shows the same) | SHA-256 shown inside Jukto (click the version in the footer) |"
  echo "|---|---|---|"
  echo "| Jukto-$VERSION-AppleSilicon.dmg | \`$(shasum -a 256 "$DESK/Jukto-$VERSION-AppleSilicon.dmg" | cut -d' ' -f1)\` | \`$(app_sha "$ARM_APP")\` |"
  echo "| Jukto-$VERSION-Intel.dmg | \`$(shasum -a 256 "$DESK/Jukto-$VERSION-Intel.dmg" | cut -d' ' -f1)\` | \`$(app_sha "$X86_APP")\` |"
} > "$DESK/Jukto-$VERSION-release-notes.md"
echo "In-app SHA-256 (AppleSilicon): $(app_sha "$ARM_APP")"
echo "In-app SHA-256 (Intel):        $(app_sha "$X86_APP")"
echo; echo "✓ Ready on your Desktop:"; ls -lh "$DESK"/Jukto-"$VERSION"-*.dmg

if [ "${NO_LAUNCH:-0}" != "1" ]; then
  xattr -cr "$APP" 2>/dev/null || true
  open "$APP"
fi
