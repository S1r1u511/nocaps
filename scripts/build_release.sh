#!/usr/bin/env bash
# NOCAPS release build + signature verification (Solana dApp Store target).
#
# Secrets live OUTSIDE the repo in ~/.nocaps/keys/release.env and are read by
# Godot 4 from the GODOT_ANDROID_KEYSTORE_RELEASE_* environment variables, so
# the "Android" export preset carries no secrets. See docs/16_RELEASE_SIGNING.md.
#
# Usage: scripts/build_release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${NOCAPS_RELEASE_ENV:-$HOME/.nocaps/keys/release.env}"
JAVA_HOME="${NOCAPS_JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export JAVA_HOME
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
PRESET="${NOCAPS_ANDROID_PRESET:-Android}"
OUT="$ROOT/.build/nocaps-release.apk"

if [ ! -f "$ENV_FILE" ]; then
	echo "error: release env not found: $ENV_FILE" >&2
	echo "       see docs/16_RELEASE_SIGNING.md" >&2
	exit 1
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

: "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?missing keystore path in $ENV_FILE}"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?missing keystore alias in $ENV_FILE}"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?missing keystore password in $ENV_FILE}"

if [ ! -f "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ]; then
	echo "error: keystore not found: $GODOT_ANDROID_KEYSTORE_RELEASE_PATH" >&2
	exit 1
fi
if [ ! -x "$GODOT" ]; then
	echo "error: Godot binary not found or not executable: $GODOT" >&2
	exit 1
fi

# Expected SHA-256 comes from the release keystore itself.
EXPECTED="$("$JAVA_HOME/bin/keytool" -list -v \
	-keystore "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" \
	-storepass "$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD" \
	-alias "$GODOT_ANDROID_KEYSTORE_RELEASE_USER" 2>/dev/null \
	| awk '/SHA256:/ {print $2; exit}')"
EXPECTED_NORM="$(printf '%s' "$EXPECTED" | tr -d ':' | tr 'A-F' 'a-f')"
if [ -z "$EXPECTED_NORM" ]; then
	echo "error: could not read the SHA-256 from $GODOT_ANDROID_KEYSTORE_RELEASE_PATH" >&2
	exit 1
fi

# Locate apksigner (Android SDK build-tools), newest version by default.
APKSIGNER="${APKSIGNER:-}"
if [ -z "$APKSIGNER" ]; then
	for base in "${ANDROID_HOME:-}/build-tools" "${ANDROID_SDK_ROOT:-}/build-tools" \
			"$HOME/Library/Android/sdk/build-tools" "$HOME/Android/Sdk/build-tools"; do
		[ -d "$base" ] || continue
		version="$(ls -1 "$base" 2>/dev/null | sort -V | tail -1)"
		if [ -n "$version" ] && [ -x "$base/$version/apksigner" ]; then
			APKSIGNER="$base/$version/apksigner"
			break
		fi
	done
fi
if [ -z "$APKSIGNER" ] || [ ! -x "$APKSIGNER" ]; then
	echo "error: apksigner not found; set APKSIGNER to its path" >&2
	exit 1
fi

mkdir -p "$ROOT/.build"
echo "==> exporting '$PRESET' (release) -> $OUT"
"$GODOT" --headless --path "$ROOT" --export-release "$PRESET" "$OUT"

if [ ! -f "$OUT" ]; then
	echo "error: export did not produce $OUT" >&2
	exit 1
fi

echo "==> apksigner verify --print-certs"
CERT_OUT="$("$APKSIGNER" verify --print-certs "$OUT")"
printf '%s\n' "$CERT_OUT" | awk '/certificate SHA-256 digest/'
ACTUAL_NORM="$(printf '%s\n' "$CERT_OUT" \
	| awk '/certificate SHA-256 digest:/ {print $NF; exit}' | tr -d ':' | tr 'A-F' 'a-f')"

if [ "$ACTUAL_NORM" != "$EXPECTED_NORM" ]; then
	echo "error: signature SHA-256 does not match the release keystore" >&2
	echo "  expected: $EXPECTED_NORM" >&2
	echo "  actual:   $ACTUAL_NORM" >&2
	exit 1
fi

echo "OK  release-signed $OUT"
echo "    SHA-256 $EXPECTED"
