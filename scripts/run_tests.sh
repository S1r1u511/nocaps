#!/usr/bin/env bash
# NOCAPS offline smoke-test runner — the merge gate.
#
# Every test runs in an isolated, empty user data dir: a fresh temporary
# HOME / XDG_DATA_HOME with NOCAPS_TEST_ROOT pointing at it, so `user://` can
# never touch the real save, settings, caches, or DEV presets. Tests refuse to
# run without that isolation (see `tests/test_env.gd`).
#
# Usage:
#   scripts/run_tests.sh                    # all offline smoke tests
#   scripts/run_tests.sh run_core_smoke     # one or more named tests
#   scripts/run_tests.sh --emulator         # also run backend_emulator_smoke
#
# Environment:
#   GODOT=/path/to/Godot        Godot binary override
#   NOCAPS_TEST_TIMEOUT=120     Per-test timeout in seconds
#
# Exit code: 0 only when every selected test PASSes.

set -u -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMEOUT_SECS="${NOCAPS_TEST_TIMEOUT:-120}"

TEST_NAMES=(
	app_shell_smoke
	run_core_smoke
	run_feel_smoke
	coins_smoke
	run_e2e_smoke
	safe_zone_smoke
	hud_layout_smoke
	screens_layout_smoke
	progress_smoke
	submission_smoke
	community_smoke
	invite_smoke
	embed_smoke
	player_name_smoke
	wallet_link_smoke
	board_cache_smoke
	touch_input_smoke
	fit_tool_smoke
	moments_smoke
	race_smoke
	quests_smoke
	battle_smoke
	clash_smoke
	run_start_smoke
	first_run_card_smoke
	roster_lazy_smoke
	backend_empty_body_smoke
	server_clock_smoke
	backend_emulator_smoke
)
TEST_MARKERS=(
	APP_SHELL_PASS
	RUN_CORE_PASS
	RUN_FEEL_PASS
	COINS_PASS
	RUN_E2E_PASS
	SAFE_ZONE_PASS
	HUD_LAYOUT_PASS
	SCREENS_LAYOUT_PASS
	PROGRESS_PASS
	SUBMISSION_PASS
	COMMUNITY_PASS
	INVITE_PASS
	EMBED_PASS
	PLAYER_NAME_PASS
	WALLET_LINK_PASS
	BOARD_CACHE_PASS
	TOUCH_PASS
	FIT_TOOL_PASS
	MOMENTS_PASS
	RACE_PASS
	QUESTS_PASS
	BATTLE_PASS
	CLASH_PASS
	RUN_START_PASS
	FIRST_RUN_CARD_PASS
	ROSTER_LAZY_PASS
	BACKEND_EMPTY_BODY_PASS
	SERVER_CLOCK_PASS
	BACKEND_EMULATOR_PASS
)

usage() {
	sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

INCLUDE_EMULATOR=0
PICKED=()
for arg in "$@"; do
	case "$arg" in
		--emulator) INCLUDE_EMULATOR=1 ;;
		-h|--help) usage; exit 0 ;;
		-*) echo "error: unknown option: $arg" >&2; exit 2 ;;
		*) PICKED+=("$arg") ;;
	esac
done

SELECTED=()
if [ "${#PICKED[@]}" -eq 0 ]; then
	for i in "${!TEST_NAMES[@]}"; do
		if [ "${TEST_NAMES[$i]}" = "backend_emulator_smoke" ] && [ "$INCLUDE_EMULATOR" -eq 0 ]; then
			continue
		fi
		SELECTED+=("$i")
	done
else
	for pick in "${PICKED[@]}"; do
		found=0
		for i in "${!TEST_NAMES[@]}"; do
			name="${TEST_NAMES[$i]}"
			if [ "$name" = "$pick" ] || [ "$name" = "${pick}_smoke" ]; then
				SELECTED+=("$i")
				found=1
				break
			fi
		done
		if [ "$found" -eq 0 ]; then
			echo "error: unknown test: $pick" >&2
			exit 2
		fi
	done
fi

resolve_godot() {
	if [ -n "${GODOT:-}" ]; then
		if [ -x "$GODOT" ]; then
			printf '%s\n' "$GODOT"
			return 0
		fi
		echo "error: GODOT is not executable: $GODOT" >&2
		return 1
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

if [ ! -f "$ROOT/.godot/global_script_class_cache.cfg" ]; then
	echo "importing project (first run)..."
	"$GODOT_BIN" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
fi

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
TMP_ROOT="$(mktemp -d "$TMP_BASE/nocaps_tests.XXXXXX")"
LOGS="$TMP_ROOT/logs"
mkdir -p "$LOGS"

DETAILS=()
FAILED=0

cleanup() {
	if [ "$FAILED" -eq 0 ]; then
		rm -rf "$TMP_ROOT"
	else
		printf '\nfull logs kept at: %s\n' "$LOGS"
	fi
}
trap cleanup EXIT

# Runs one test isolated; writes stdout+stderr to $2 and a timeout marker to $3.
run_isolated() {
	local tdir="$1" log="$2" marker_file="$3" script="$4"
	rm -f "$marker_file"
	mkdir -p "$tdir/home" "$tdir/xdg_data" "$tdir/xdg_cache" "$tdir/xdg_config" "$tdir/tmp"
	HOME="$tdir/home" \
	XDG_DATA_HOME="$tdir/xdg_data" \
	XDG_CACHE_HOME="$tdir/xdg_cache" \
	XDG_CONFIG_HOME="$tdir/xdg_config" \
	TMPDIR="$tdir/tmp" \
	NOCAPS_TEST_ROOT="$tdir" \
	"$GODOT_BIN" --headless --path "$ROOT" --script "$script" >"$log" 2>&1 &
	local pid=$!
	(
		sleep "$TIMEOUT_SECS"
		if kill -0 "$pid" 2>/dev/null; then
			: >"$marker_file"
			kill -TERM "$pid" 2>/dev/null
			sleep 3
			kill -KILL "$pid" 2>/dev/null
		fi
	) &
	local watcher=$!
	wait "$pid" 2>/dev/null
	local rc=$?
	kill "$watcher" 2>/dev/null
	wait "$watcher" 2>/dev/null
	return "$rc"
}

printf '%-26s %-8s %s\n' "TEST" "RESULT" "TIME"
printf '%-26s %-8s %s\n' "--------------------------" "------" "----"

for i in "${SELECTED[@]}"; do
	name="${TEST_NAMES[$i]}"
	marker="${TEST_MARKERS[$i]}"
	tdir="$TMP_ROOT/run/$name"
	log="$LOGS/$name.log"
	timeout_file="$tdir/timed_out"
	start="$(date +%s)"
	run_isolated "$tdir" "$log" "$timeout_file" "res://tests/$name.gd"
	rc=$?
	secs=$(( $(date +%s) - start ))
	if [ -f "$timeout_file" ] && [ "$rc" -ge 128 ]; then
		result="TIMEOUT"
		FAILED=1
	elif [ "$rc" -ne 0 ]; then
		result="FAIL($rc)"
		FAILED=1
	elif ! grep -q "$marker" "$log"; then
		result="FAIL"
		FAILED=1
	elif grep -q "SCRIPT ERROR" "$log"; then
		# Headless --script runs keep going after a failed assert(), so a test can
		# still print its PASS marker; any script error fails the test.
		result="FAIL(err)"
		FAILED=1
	else
		result="PASS"
	fi
	printf '%-26s %-8s %ss\n' "$name" "$result" "$secs"
	if [ "$result" != "PASS" ]; then
		DETAILS+=("$name")
	fi
done

if [ "${#PICKED[@]}" -eq 0 ] && [ "$INCLUDE_EMULATOR" -eq 0 ]; then
	printf '%-26s %-8s %s\n' "backend_emulator_smoke" "SKIP" "(needs emulators; use --emulator)"
fi

for name in "${DETAILS[@]:-}"; do
	[ -n "$name" ] || continue
	printf '\n--- %s (last 30 log lines) ---\n' "$name"
	tail -n 30 "$LOGS/$name.log"
done

if [ "$FAILED" -ne 0 ]; then
	printf '\nRESULT: FAIL\n'
	exit 1
fi
printf '\nRESULT: PASS\n'
exit 0
