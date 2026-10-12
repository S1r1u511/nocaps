#!/usr/bin/env bash
# NOCAPS release channels.
#
#   scripts/release.sh <version> preview   # Firebase preview channel + Android Dev APK
#   scripts/release.sh <version> stable    # promote LIVE + release-signed APK + git tag
#
# <version> is the semantic version in application/config/version (e.g. 0.3.0).
# The build stamps the short git hash into that setting ("v0.3.0 · 1a2b3c4",
# restored afterwards) so the Profile footer, the DEV panel, and the web build
# all show the exact commit. Android versionName = <version>; versionCode is the
# release number (0.x -> x) and never decreases.
#
# preview: clean tree -> deploy Firebase Hosting channel "preview" (30d, URL
#          printed) -> export "Android Dev" to
#          .build/releases/nocaps-<version>-dev.apk and "Android Preview" to
#          .build/releases/nocaps-<version>-preview.apk -> adb install -r of the
#          preview APK (the side-by-side "NOCAPS Preview" app) if a phone is
#          attached. Records the preview so stable can require it.
# stable:  clean tree + an existing preview for the same version -> deploy web
#          LIVE -> scripts/build_release.sh -> .build/releases/nocaps-<version>-release.apk
#          (release-signed, SHA-256 checked against the hosted assetlinks.json)
#          -> adb install -r if attached -> git tag v<version>.
#
# Files in .build/releases/ are never overwritten: a version is built once.
# Signing details: docs/16_RELEASE_SIGNING.md. History: docs/RELEASES.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
	sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
}

VERSION="${1:-}"
MODE="${2:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "error: <version> must look like 0.3.0" >&2
	usage >&2
	exit 2
fi
if [ "$MODE" != "preview" ] && [ "$MODE" != "stable" ]; then
	echo "error: <mode> must be 'preview' or 'stable'" >&2
	usage >&2
	exit 2
fi

GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
JAVA_HOME="${NOCAPS_JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
RELEASES="$ROOT/.build/releases"
FIREBASE_PROJECT="${FIREBASE_PROJECT:-nocaps-v1}"
FIREBASE_SITE="${FIREBASE_SITE:-nocaps-v1}"
PREVIEW_CHANNEL="${NOCAPS_PREVIEW_CHANNEL:-preview}"
PREVIEW_EXPIRES="${NOCAPS_PREVIEW_EXPIRES:-30d}"
ASSETLINKS_URL="${NOCAPS_ASSETLINKS_URL:-https://nocaps.fun/.well-known/assetlinks.json}"
TAG="v$VERSION"

DEV_APK="$RELEASES/nocaps-$VERSION-dev.apk"
PREVIEW_APK="$RELEASES/nocaps-$VERSION-preview.apk"
RELEASE_APK="$RELEASES/nocaps-$VERSION-release.apk"
PREVIEW_RECORD="$RELEASES/nocaps-$VERSION-preview.txt"

# --- helpers ----------------------------------------------------------------

need_clean_tree() {
	if ! git diff --quiet || ! git diff --cached --quiet; then
		echo "error: working tree is not clean; commit or stash before a release" >&2
		git status --short >&2
		exit 1
	fi
}

## A version is built once: refuse to clobber any artifact already on disk.
refuse_overwrite() {
	if [ -e "$1" ]; then
		echo "error: refusing to overwrite $1" >&2
		echo "       a version is built once; bump <version> for a new build" >&2
		exit 1
	fi
}

## "0.3.0" or a stamped "v0.3.0 · hash" -> "0.3.0".
source_version() {
	local raw
	raw="$(perl -ne 'print "$1\n" if /^config\/version="([^"]+)"/' project.godot)"
	raw="${raw#v}"
	printf '%s' "${raw%% *}"
}

## Release number: 0.3.0 -> 3. Override with NOCAPS_VERSION_CODE.
version_code() {
	local major="${VERSION%%.*}"
	local rest="${VERSION#*.}"
	local minor="${rest%%.*}"
	printf '%s' "$((10#$major * 100 + 10#$minor))"
}

find_tool() {
	local name="$1"; shift
	local path
	for path in "$@"; do
		if [ -x "$path" ]; then
			printf '%s' "$path"
			return 0
		fi
	done
	if command -v "$name" >/dev/null 2>&1; then
		command -v "$name"
		return 0
	fi
	return 1
}

find_apksigner() {
	local base version
	for base in "${ANDROID_HOME:-}/build-tools" "${ANDROID_SDK_ROOT:-}/build-tools" \
		"$HOME/Library/Android/sdk/build-tools" "$HOME/Android/Sdk/build-tools"; do
		[ -d "$base" ] || continue
		version="$(ls -1 "$base" 2>/dev/null | sort -V | tail -1)"
		if [ -n "$version" ] && [ -x "$base/$version/apksigner" ]; then
			printf '%s' "$base/$version/apksigner"
			return 0
		fi
	done
	return 1
}

install_if_connected() {
	local apk="$1"
	local adb
	if ! adb="$(find_tool adb "$HOME/Library/Android/sdk/platform-tools/adb" "$HOME/Android/Sdk/platform-tools/adb")"; then
		echo "==> adb not found; skipping install"
		return 0
	fi
	if [ -z "$("$adb" devices | awk 'NR > 1 && $2 == "device" { print $1 }')" ]; then
		echo "==> no connected phone; skipping adb install"
		return 0
	fi
	echo "==> adb install -r $apk"
	"$adb" install -r "$apk"
}

## The release APK's signing certificate must be listed for com.nocapsfun.game
## in the hosted Digital Asset Links file the wallet uses to verify the app.
verify_assetlinks() {
	local apk="$1"
	local apksigner cert cert_norm json
	if ! apksigner="$(find_apksigner)"; then
		echo "error: apksigner not found; cannot verify assetlinks" >&2
		exit 1
	fi
	cert="$("$apksigner" verify --print-certs "$apk" | awk '/certificate SHA-256 digest:/ { print $NF; exit }')"
	cert_norm="$(printf '%s' "$cert" | tr -d ':' | tr 'A-F' 'a-f')"
	if [ -z "$cert_norm" ]; then
		echo "error: could not read the APK signing certificate" >&2
		exit 1
	fi
	if ! json="$(curl -fsS --max-time 30 "$ASSETLINKS_URL")"; then
		echo "error: could not fetch $ASSETLINKS_URL" >&2
		exit 1
	fi
	if ! printf '%s' "$json" | tr -d ' :\n' | tr 'A-F' 'a-f' | grep -q "$cert_norm"; then
		echo "error: $apk SHA-256 $cert is not listed in $ASSETLINKS_URL" >&2
		exit 1
	fi
	echo "==> assetlinks OK: $cert"
}

# --- version stamping -------------------------------------------------------

if [ "$(source_version)" != "$VERSION" ]; then
	echo "error: project.godot is version $(source_version), requested $VERSION" >&2
	echo "       update application/config/version in project.godot first" >&2
	exit 1
fi

VERSION_CODE="${NOCAPS_VERSION_CODE:-$(version_code)}"
SHORT_HASH="$(git rev-parse --short HEAD)"
LABEL="v$VERSION · $SHORT_HASH"

STAMPED=0
restore_sources() {
	if [ "$STAMPED" = 1 ]; then
		git checkout -- project.godot export_presets.cfg
		STAMPED=0
	fi
}
trap restore_sources EXIT

stamp_version() {
	perl -pi -e "s{^config/version=.*\$}{config/version=\"$LABEL\"}" project.godot
	perl -pi -e "s{^version/name=.*\$}{version/name=\"$VERSION\"}" export_presets.cfg
	perl -pi -e "s{^version/code=.*\$}{version/code=$VERSION_CODE}" export_presets.cfg
	STAMPED=1
	echo "==> $MODE $VERSION  ($LABEL)  commit $SHORT_HASH"
	echo "    application/config/version = \"$LABEL\" (restored after the build)"
}

# --- modes ------------------------------------------------------------------

run_preview() {
	need_clean_tree
	refuse_overwrite "$DEV_APK"
	refuse_overwrite "$PREVIEW_APK"
	mkdir -p "$RELEASES"
	stamp_version

	echo "==> exporting web + deploying Firebase preview channel '$PREVIEW_CHANNEL' ($PREVIEW_EXPIRES)"
	local web_log preview_url
	web_log="$("$ROOT/scripts/deploy_web.sh" --channel "$PREVIEW_CHANNEL" --expires "$PREVIEW_EXPIRES" 2>&1)"
	printf '%s\n' "$web_log"
	preview_url="$(printf '%s\n' "$web_log" | sed -n 's/^PREVIEW_URL=//p' | tail -1)"
	if [ -z "$preview_url" ]; then
		echo "error: preview deploy did not report a URL" >&2
		exit 1
	fi

	echo "==> exporting 'Android Dev' -> $DEV_APK"
	"$GODOT" --headless --path "$ROOT" --export-debug "Android Dev" "$DEV_APK"
	[ -f "$DEV_APK" ] || { echo "error: dev APK missing" >&2; exit 1; }

	echo "==> exporting 'Android Preview' -> $PREVIEW_APK"
	"$GODOT" --headless --path "$ROOT" --export-debug "Android Preview" "$PREVIEW_APK"
	[ -f "$PREVIEW_APK" ] || { echo "error: preview APK missing" >&2; exit 1; }

	install_if_connected "$PREVIEW_APK"

	{
		printf 'version=%s\n' "$VERSION"
		printf 'channel=%s\n' "$PREVIEW_CHANNEL"
		printf 'url=%s\n' "$preview_url"
		printf 'commit=%s\n' "$SHORT_HASH"
		printf 'deployed_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	} > "$PREVIEW_RECORD"

	restore_sources
	echo
	echo "==> preview URL:  $preview_url"
	echo "==> dev APK:      $DEV_APK"
	echo "==> preview APK:  $PREVIEW_APK"
	echo "==> promote with: scripts/release.sh $VERSION stable"
}

run_stable() {
	need_clean_tree
	refuse_overwrite "$RELEASE_APK"
	if [ ! -f "$PREVIEW_RECORD" ]; then
		echo "error: no preview recorded for $VERSION" >&2
		echo "       run: scripts/release.sh $VERSION preview" >&2
		exit 1
	fi
	if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
		echo "error: tag $TAG already exists" >&2
		exit 1
	fi
	stamp_version

	echo "==> deploying web LIVE"
	"$ROOT/scripts/deploy_web.sh"

	echo "==> building release APK"
	"$ROOT/scripts/build_release.sh"
	cp "$ROOT/.build/nocaps-release.apk" "$RELEASE_APK"
	verify_assetlinks "$RELEASE_APK"

	install_if_connected "$RELEASE_APK"

	restore_sources
	git tag "$TAG"
	echo
	echo "==> live:        https://$FIREBASE_SITE.web.app"
	echo "==> release APK: $RELEASE_APK"
	echo "==> tagged:      $TAG -> $SHORT_HASH"
}

case "$MODE" in
	preview) run_preview ;;
	stable) run_stable ;;
esac
