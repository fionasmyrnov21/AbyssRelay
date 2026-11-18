#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=4.5.1
mkdir -p "$ROOT_DIR/.tools" "$ROOT_DIR/downloads"
case "$(uname -s)" in
  Darwin) ASSET="Godot_v${VERSION}-stable_macos.universal.zip" ;;
  Linux)
    case "$(uname -m)" in
      aarch64|arm64) GODOT_ARCH=arm64 ;;
      x86_64) GODOT_ARCH=x86_64 ;;
      *) printf '%s\n' 'Unsupported Linux architecture'; exit 1 ;;
    esac
    ASSET="Godot_v${VERSION}-stable_linux.${GODOT_ARCH}.zip"
    ;;
  *) printf '%s\n' 'Install Godot 4.5.1 and set GODOT_BIN to its executable.'; exit 1 ;;
esac
curl --fail --location --retry 2 "https://github.com/godotengine/godot/releases/download/${VERSION}-stable/$ASSET" -o "$ROOT_DIR/downloads/$ASSET"
unzip -q -o "$ROOT_DIR/downloads/$ASSET" -d "$ROOT_DIR/.tools"
if [[ "$(uname -s)" == Darwin ]]; then
  GODOT_EXECUTABLE="$ROOT_DIR/.tools/Godot.app/Contents/MacOS/Godot"
else
  mv "$ROOT_DIR/.tools/Godot_v${VERSION}-stable_linux.${GODOT_ARCH}" "$ROOT_DIR/.tools/godot"
  GODOT_EXECUTABLE="$ROOT_DIR/.tools/godot"
fi
"$GODOT_EXECUTABLE" --headless --version
printf 'Godot ready: %s\n' "$GODOT_EXECUTABLE"
