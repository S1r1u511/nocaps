#!/usr/bin/env bash
# NOCAPS menu-screen capture harness (screens-polish pass).
#
# Boots `scenes/main.tscn` with the real renderer at 720x1560, seeds a temp
# `user://`, walks each menu screen, and writes PNGs to
# `.build/reports/screens-polish/<screen>_<suffix>.png`.
#
# Usage:
#   scripts/capture_screens.sh before
#   scripts/capture_screens.sh after home,result
#
# Every run is isolated in a fresh temp HOME/XDG_DATA_HOME so it can never read
# the developer's real save. Requires a GUI session (real renderer).

set -u -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUFFIX="${1:-capture}"
ONLY="${2:-}"

resolve_godot() {
	if [ -n "${GODOT:-}" ]; then
		printf '%s\n' "$GODOT"
		return 0
	fi
	local c
	for c in godot godot4; do
		if command -v "$c" >/dev/null 2>&1; then
			command -v "$c"
			return 0
		fi
	done
	for c in \
		"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
		if [ -x "$c" ]; then
			printf '%s\n' "$c"
			return 0
		fi
	done
	echo "error: Godot not found; set GODOT=/path/to/Godot" >&2
	return 1
}
GODOT_BIN="$(resolve_godot)" || exit 2

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
TDIR="$(mktemp -d "$TMP_BASE/nocaps_capture.XXXXXX")"
trap 'rm -rf "$TDIR"' EXIT
mkdir -p "$TDIR/home" "$TDIR/xdg_data" "$TDIR/xdg_cache" "$TDIR/xdg_config" "$TDIR/tmp"

ARGS=("--suffix=$SUFFIX")
if [ -n "$ONLY" ]; then
	ARGS+=("--only=$ONLY")
fi

HOME="$TDIR/home" \
XDG_DATA_HOME="$TDIR/xdg_data" \
XDG_CACHE_HOME="$TDIR/xdg_cache" \
XDG_CONFIG_HOME="$TDIR/xdg_config" \
TMPDIR="$TDIR/tmp" \
"$GODOT_BIN" --path "$ROOT" --script "res://tools/capture_screens.gd" -- "${ARGS[@]}"
