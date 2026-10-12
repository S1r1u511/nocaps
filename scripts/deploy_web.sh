#!/usr/bin/env bash
# Build the game for the web and publish it to Firebase Hosting.
#
#   scripts/deploy_web.sh                          export + deploy LIVE
#   scripts/deploy_web.sh --no-deploy              export only (build/web/)
#   scripts/deploy_web.sh --serve                  export + serve build/web locally
#   scripts/deploy_web.sh --channel <id> [--expires <dur>]
#                                                  export + deploy a preview channel
#
# Env overrides:
#   GODOT              Godot binary (default: $HOME/Downloads/Godot.app/Contents/MacOS/Godot)
#   GODOT_TEMPLATES    export templates root (default: ~/Library/Application Support/Godot/export_templates)
#   FIREBASE_PROJECT   Firebase project (default: nocaps-v1)
#   FIREBASE_SITE      Firebase Hosting site (default: nocaps-v1)
#   PORT               --serve port (default: 8000)
#   KEEP_VERSIONS      versioned builds kept on the site (default: 5)
#
# Channel deploys print the channel URL as a final `PREVIEW_URL=<url>` line so
# scripts/release.sh can capture it.
#
# Site layout (the platform at play.nocaps.fun embeds these; see nocaps-web/docs/EMBED.md):
#   /nocaps/<version>/   this build, immutable (cached forever); the last
#                        KEEP_VERSIONS builds stay online (.build/web-site keeps them)
#   /nocaps/stable/      copy of the current build (no-cache): the platform's embed URL
#   /game/               same copy, for older links and the standalone loader
#   /                    the standalone loader (web/shell.html)
# Copies cost nothing to upload: Firebase Hosting dedupes files by content hash.
#
# build/web/index.html is the static loader (web/shell.html) with the touch lock
# and the 9:19.5 game frame; the Godot build is exported to build/web/game/ and
# runs in a same-origin iframe. web/game_bridge.js is copied in and injected so
# the game reports progress to the loader via postMessage. Thread support is off,
# so no COOP/COEP headers are needed. build/web/firebase.json (generated here,
# never committed) only sets cache headers; backend/firebase.json is untouched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/web"
GAME="$OUT/game"
PRESET="Web"
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
TEMPLATES="${GODOT_TEMPLATES:-$HOME/Library/Application Support/Godot/export_templates}"
FIREBASE_PROJECT="${FIREBASE_PROJECT:-nocaps-v1}"
FIREBASE_SITE="${FIREBASE_SITE:-nocaps-v1}"
PORT="${PORT:-8000}"
KEEP_VERSIONS="${KEEP_VERSIONS:-5}"
SITE_ARCHIVE="$ROOT/.build/web-site"
VERSION="$(sed -n 's/^config\/version="\([^"]*\)".*/\1/p' "$ROOT/project.godot" | head -n1 | sed 's/ .*//')"

DEPLOY=1
SERVE=0
CHANNEL=""
EXPIRES=""

usage() {
	sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--no-deploy) DEPLOY=0 ;;
		--serve) DEPLOY=0; SERVE=1 ;;
		--channel) CHANNEL="${2:-}"; shift ;;
		--channel=*) CHANNEL="${1#*=}" ;;
		--expires) EXPIRES="${2:-}"; shift ;;
		--expires=*) EXPIRES="${1#*=}" ;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			echo "error: unknown argument: $1 (try --help)" >&2
			exit 2
			;;
	esac
	shift
done

if [ ! -x "$GODOT" ]; then
	echo "error: Godot binary not found or not executable: $GODOT" >&2
	echo "       set GODOT=/path/to/Godot and retry." >&2
	exit 1
fi

GODOT_VERSION="$("$GODOT" --version 2>/dev/null | head -n1)"
TEMPLATE_VERSION="$(printf '%s' "$GODOT_VERSION" | awk -F. '{print $1"."$2"."$3"."$4}')"
TEMPLATE_DIR="$TEMPLATES/$TEMPLATE_VERSION"
if [ ! -f "$TEMPLATE_DIR/web_nothreads_release.zip" ]; then
	RELEASE_TAG="${TEMPLATE_VERSION%.*}-stable"
	cat >&2 <<EOF
error: web export templates for Godot $GODOT_VERSION are not installed.
       expected: $TEMPLATE_DIR/web_nothreads_release.zip

       install them once with:
         tmp="\$(mktemp -d)"
         curl -L -o "\$tmp/templates.tpz" \\
           "https://github.com/godotengine/godot/releases/download/$RELEASE_TAG/Godot_v$RELEASE_TAG_export_templates.tpz"
         unzip -o -j "\$tmp/templates.tpz" 'templates/web*.zip' -d "$TEMPLATE_DIR"
         rm -rf "\$tmp"
EOF
	exit 1
fi

if [ "$SERVE" = 0 ] && [ ! -d "$ROOT/.godot" ]; then
	"$GODOT" --headless --path "$ROOT" --import
fi

echo "==> exporting '$PRESET' to build/web/game/"
rm -rf "$OUT"
mkdir -p "$GAME"
"$GODOT" --headless --path "$ROOT" --export-release "$PRESET" "$GAME/index.html"
if [ ! -f "$GAME/index.html" ] || [ ! -f "$GAME/index.wasm" ] || [ ! -f "$GAME/index.pck" ]; then
	echo "error: export did not produce a complete web build in build/web/game/" >&2
	exit 1
fi
cp "$ROOT/web/shell.html" "$OUT/index.html"
cp "$ROOT/assets/fonts/Fredoka.ttf" "$OUT/fredoka.ttf"
cp "$ROOT/assets/backgrounds/background01.png" "$OUT/sunset.png"
cp "$ROOT/web/icon.png" "$OUT/icon.png"
cp "$ROOT/web/apple-touch-icon.png" "$OUT/apple-touch-icon.png"

# Let the game report load progress to the loader page via postMessage.
cp "$ROOT/web/game_bridge.js" "$GAME/nocaps-bridge.js"
python3 - "$GAME/index.html" <<'PY'
import sys

path = sys.argv[1]
html = open(path).read()
tag = '<script src="nocaps-bridge.js"></script>'
if tag not in html:
    html = html.replace("</body>", tag + "\n\t</body>", 1)
    open(path, "w").write(html)
PY
# Versioned paths. Live deploys keep older builds via the local archive so links
# to /nocaps/<old>/ keep working; channel (preview) deploys carry only this one.
if [ -z "$VERSION" ]; then
	echo "error: could not read application/config/version from project.godot" >&2
	exit 1
fi
mkdir -p "$OUT/nocaps"
cp -R "$GAME" "$OUT/nocaps/$VERSION"
cp -R "$GAME" "$OUT/nocaps/stable"
if [ -z "$CHANNEL" ] && [ "$DEPLOY" = 1 ]; then
	mkdir -p "$SITE_ARCHIVE/nocaps"
	rm -rf "$SITE_ARCHIVE/nocaps/$VERSION"
	cp -R "$GAME" "$SITE_ARCHIVE/nocaps/$VERSION"
	# keep the newest KEEP_VERSIONS builds (by modification time)
	ls -1t "$SITE_ARCHIVE/nocaps" | tail -n +"$((KEEP_VERSIONS + 1))" | while read -r old; do
		rm -rf "$SITE_ARCHIVE/nocaps/$old"
	done
	for kept in "$SITE_ARCHIVE"/nocaps/*; do
		name="$(basename "$kept")"
		[ -d "$OUT/nocaps/$name" ] || cp -R "$kept" "$OUT/nocaps/$name"
	done
fi
printf '{"game":"nocaps","version":"%s","stable":"/nocaps/stable/","versions":[%s]}\n' "$VERSION" \
	"$(ls -1 "$OUT/nocaps" | grep -v '^stable$' | sed 's/.*/"&"/' | paste -sd, -)" > "$OUT/nocaps/manifest.json"
echo "    nocaps $VERSION -> /nocaps/$VERSION/, /nocaps/stable/, /game/"
echo "    $(du -sh "$OUT" | cut -f1) in $(find "$OUT" -type f | wc -l | tr -d ' ') files"

if [ "$SERVE" = 1 ]; then
	echo "==> serving build/web/ on http://127.0.0.1:$PORT/ (Ctrl-C to stop)"
	exec python3 - "$OUT" "$PORT" <<'PY'
import functools, http.server, mimetypes, socketserver, sys

root, port = sys.argv[1], int(sys.argv[2])
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/octet-stream", ".pck")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


with Server(("127.0.0.1", port), functools.partial(Handler, directory=root)) as httpd:
    print(f"    serving {root}")
    httpd.serve_forever()
PY
fi

if [ "$DEPLOY" = 0 ]; then
	echo "==> done (export only)"
	exit 0
fi

cat > "$OUT/firebase.json" <<JSON
{
	"hosting": {
		"site": "$FIREBASE_SITE",
		"public": ".",
		"ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
		"headers": [
			{
				"source": "**",
				"headers": [
					{ "key": "Cache-Control", "value": "no-cache" },
					{ "key": "X-Content-Type-Options", "value": "nosniff" }
				]
			},
			{
				"regex": "^/nocaps/[0-9]+\\\\.[0-9]+\\\\.[0-9]+[^/]*/.*",
				"headers": [
					{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
				]
			},
			{
				"source": "/nocaps/manifest.json",
				"headers": [
					{ "key": "Access-Control-Allow-Origin", "value": "*" }
				]
			}
		]
	}
}
JSON

if command -v firebase >/dev/null 2>&1; then
	FIREBASE=(firebase)
else
	echo "==> firebase CLI not on PATH; using npx firebase-tools"
	FIREBASE=(npx --yes firebase-tools)
fi

if [ -n "$CHANNEL" ]; then
	CHANNEL_ARGS=(hosting:channel:deploy "$CHANNEL" --project "$FIREBASE_PROJECT")
	if [ -n "$EXPIRES" ]; then
		CHANNEL_ARGS+=(--expires "$EXPIRES")
	fi
	echo "==> deploying channel '$CHANNEL' (project $FIREBASE_PROJECT)"
	CHANNEL_LOG="$("${FIREBASE[@]}" "${CHANNEL_ARGS[@]}" --config "$OUT/firebase.json" 2>&1)"
	printf '%s\n' "$CHANNEL_LOG"
	PREVIEW_URL="$(printf '%s\n' "$CHANNEL_LOG" | grep -Eo 'https://[A-Za-z0-9._-]+--[A-Za-z0-9._-]+\.web\.app' | tail -1)"
	if [ -z "$PREVIEW_URL" ]; then
		echo "error: could not parse the preview channel URL from the deploy output" >&2
		exit 1
	fi
	echo "PREVIEW_URL=$PREVIEW_URL"
	exit 0
fi

echo "==> deploying to Firebase Hosting site '$FIREBASE_SITE' (project $FIREBASE_PROJECT)"
"${FIREBASE[@]}" deploy --only hosting --config "$OUT/firebase.json" --project "$FIREBASE_PROJECT"

echo "==> published: https://$FIREBASE_SITE.web.app"
echo "    connect play.nocaps.fun once in the Firebase console:"
echo "    Hosting > $FIREBASE_SITE > Add custom domain"
