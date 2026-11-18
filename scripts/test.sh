#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_EXECUTABLE="${GODOT_BIN:-$ROOT_DIR/.tools/Godot.app/Contents/MacOS/Godot}"
[[ -x "$GODOT_EXECUTABLE" ]] || GODOT_EXECUTABLE="${GODOT_BIN:-$ROOT_DIR/.tools/godot}"
[[ -x "$GODOT_EXECUTABLE" ]] || GODOT_EXECUTABLE=godot
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR/game" --editor --import --quit
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR/game" --script res://tests/test_simulation.gd
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR/game" --script res://tests/test_extended.gd
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR/game" --script res://tests/test_english.gd
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR/game" --script res://tests/test_portrait.gd
"$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR/game" -- --qa --mobile
