#!/usr/bin/env bash
# Downloads the LATEST yt-dlp, ffmpeg, ffprobe and deno as universal (Apple Silicon + Intel) binaries
# into Jukto/Resources/bin, verifying every download against the publisher's SHA-256.
set -euo pipefail
trap 'echo "✗ Failed at line $LINENO: $BASH_COMMAND" >&2' ERR

DEST="$(cd "$(dirname "$0")/.." && pwd)/Jukto/Resources/bin"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$DEST"

sha_check() { # file expected
  local got; got="$(shasum -a 256 "$1" | awk '{print $1}')"
  [ "$got" = "$2" ] || { echo "✗ Checksum mismatch for $1" >&2; exit 1; }
}

# ---------- yt-dlp (single universal2 binary) — uses GitHub's /latest/download alias, no API quota
echo "→ yt-dlp"
Y="https://github.com/yt-dlp/yt-dlp/releases/latest/download"
echo "  $Y/yt-dlp_macos"
curl -fL --retry 3 "$Y/yt-dlp_macos" -o "$DEST/yt-dlp"
curl -fsSL --retry 3 "$Y/SHA2-256SUMS" -o "$TMP/sums"
EXPECT="$(grep -E '[[:space:]]\*?yt-dlp_macos$' "$TMP/sums" | awk '{print $1}' || true)"
[ -n "$EXPECT" ] || { echo "✗ No checksum for yt-dlp_macos in SHA2-256SUMS" >&2; exit 1; }
sha_check "$DEST/yt-dlp" "$EXPECT"
echo "  yt-dlp verified"

# ---------- ffmpeg / ffprobe — static builds from GitHub (shaka-project), one per CPU, merged with lipo.
# GitHub shows a SHA-256 for every release asset; we read it from the release page and verify against it.
S="https://github.com/shaka-project/static-ffmpeg-binaries"
echo "→ ffmpeg / ffprobe"
STAG="$(curl -fsSL --connect-timeout 20 -o /dev/null -w '%{url_effective}' "$S/releases/latest" | sed 's#.*/tag/##')"
[ -n "$STAG" ] || { echo "✗ Couldn't read the latest ffmpeg release tag" >&2; exit 1; }
echo "  release $STAG"
curl -fsSL --connect-timeout 20 --retry 3 "$S/releases/expanded_assets/$STAG" -o "$TMP/ffassets.html"

digest_for() { # html asset
  ASSET="$2" perl -0777 -ne 'if (/\/\Q$ENV{ASSET}\E"[\s\S]{0,1500}?sha256:([0-9a-f]{64})/) { print $1 }' "$1"
}

fetch_ff() { # name
  local name="$1" arch asset want
  for arch in arm64 x64; do
    asset="$name-osx-$arch"
    want="$(digest_for "$TMP/ffassets.html" "$asset")"
    [ -n "$want" ] || { echo "✗ No published checksum for $asset" >&2; exit 1; }
    echo "  $asset"
    curl -fL --progress-bar --connect-timeout 20 --retry 3 "$S/releases/download/$STAG/$asset" -o "$TMP/$asset"
    sha_check "$TMP/$asset" "$want"
  done
  lipo -create "$TMP/$name-osx-arm64" "$TMP/$name-osx-x64" -output "$DEST/$name"
}
fetch_ff ffmpeg
fetch_ff ffprobe
printf '%s' "$STAG" > "$DEST/../ffmpeg-tag.txt"      # lets the app know which ffmpeg build it ships

# ---------- deno (JavaScript runtime that YouTube downloads need)
echo "→ deno"
for arch in aarch64 x86_64; do
  U="https://github.com/denoland/deno/releases/latest/download/deno-$arch-apple-darwin.zip"
  echo "  $U"
  curl -fL --retry 3 "$U" -o "$TMP/deno-$arch.zip"
  if curl -fsSL "$U.sha256sum" -o "$TMP/deno-$arch.sha" 2>/dev/null; then
    sha_check "$TMP/deno-$arch.zip" "$(awk '{print $1}' "$TMP/deno-$arch.sha")"
  fi
  mkdir -p "$TMP/deno-$arch.d"; unzip -oq "$TMP/deno-$arch.zip" -d "$TMP/deno-$arch.d"
done
lipo -create "$TMP/deno-aarch64.d/deno" "$TMP/deno-x86_64.d/deno" -output "$DEST/deno"

chmod +x "$DEST"/*; xattr -cr "$DEST" || true
echo; echo "✓ Components in $DEST"
for f in yt-dlp ffmpeg ffprobe deno; do printf '  %-8s %s\n' "$f" "$(lipo -archs "$DEST/$f")"; done
