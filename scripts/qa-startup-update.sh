#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/build/apfel-chat.app}"
APP_EXEC="$APP_PATH/Contents/MacOS/apfel-chat"
API_PORT="${API_PORT:-11441}"
API_BASE="http://127.0.0.1:${API_PORT}"
SUITE_A="${APFEL_CHAT_DEFAULTS_SUITE_A:-qa-startup-a-$$}"
SUITE_B="${APFEL_CHAT_DEFAULTS_SUITE_B:-qa-startup-b-$$}"
LOG_DIR="$(mktemp -d)"
APP_PID=""

cleanup() {
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    defaults delete "$SUITE_A" >/dev/null 2>&1 || true
    defaults delete "$SUITE_B" >/dev/null 2>&1 || true
    rm -rf "$LOG_DIR"
}
trap cleanup EXIT

fail() {
    print "FAIL: $1" >&2
    exit 1
}

pass() {
    print "PASS: $1"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

http_json() {
    local method="$1"
    local endpoint="$2"
    local body="${3:-}"
    if [[ -n "$body" ]]; then
        curl -fsS -X "$method" -H "Content-Type: application/json" -d "$body" "${API_BASE}${endpoint}"
    else
        curl -fsS -X "$method" "${API_BASE}${endpoint}"
    fi
}

json_eval() {
    local json="$1"
    local expr="$2"
    python3 -c '
import json
import sys

expr = sys.argv[1]
data = json.load(sys.stdin)
value = eval(expr, {"data": data})
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("null")
else:
    print(value)
' "$expr" <<<"$json"
}

wait_for_api() {
    local attempts=0
    until curl -fsS "${API_BASE}/state" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        [[ "$attempts" -lt 80 ]] || fail "Control API did not come up on ${API_BASE}"
        sleep 0.25
    done
}

launch_app() {
    local suite="$1"
    [[ -x "$APP_EXEC" ]] || fail "App executable not found: $APP_EXEC"
    if lsof -i "tcp:${API_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
        fail "Port ${API_PORT} is already in use. Quit any existing apfel-chat --api process first."
    fi
    APFEL_CHAT_DEFAULTS_SUITE="$suite" open -n "$APP_PATH" --args --api
    wait_for_api
    APP_PID="$(pgrep -f "${APP_EXEC} --api" | head -n 1 || true)"
}

stop_app() {
    [[ -n "$APP_PID" ]] || return 0
    if kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    APP_PID=""
    sleep 0.5
}

wait_for_update_state() {
    local expected="$1"
    local attempts=0
    while true; do
        local payload state
        payload="$(http_json GET /update)"
        state="$(json_eval "$payload" 'data.get("state")')"
        [[ "$state" == "$expected" ]] && return 0
        attempts=$((attempts + 1))
        [[ "$attempts" -lt 40 ]] || fail "Timed out waiting for update state '$expected' (last: $state)"
        sleep 0.25
    done
}

has_debug_update_hook() {
    local help
    help="$(http_json GET /)"
    [[ "$(json_eval "$help" 'any("/debug/update-scenario" in item for item in data.get("endpoints", []))')" == "true" ]]
}

require_cmd curl
require_cmd python3
require_cmd lsof

launch_app "$SUITE_A"

startup="$(http_json GET /startup)"
[[ "$(json_eval "$startup" 'data["visible"]')" == "true" ]] || fail "Fresh launch should show startup overlay"
[[ "$(json_eval "$startup" 'data["has_seen"]')" == "false" ]] || fail "Fresh launch should report has_seen=false"
[[ "$(json_eval "$startup" 'data["check_updates_on_launch"]')" == "true" ]] || fail "Launch update toggle should default to true"
pass "fresh launch shows startup overlay with launch checks enabled"

if has_debug_update_hook; then
    http_json POST /debug/update-scenario '{"latest_version":"9.9.9"}' >/dev/null
    http_json POST /startup/dismiss >/dev/null
    wait_for_update_state "update_available"
    update="$(http_json GET /update)"
    [[ "$(json_eval "$update" 'data["latest_version"]')" == "9.9.9" ]] || fail "Debug update scenario should surface fake latest version"
    pass "debug build simulates launch update availability"
else
    http_json POST /startup/dismiss >/dev/null
    pass "release build dismissed startup overlay"
fi

stop_app
launch_app "$SUITE_A"
startup="$(http_json GET /startup)"
[[ "$(json_eval "$startup" 'data["visible"]')" == "false" ]] || fail "Startup overlay should stay hidden after first dismissal"
pass "startup overlay is one-time per defaults suite"
http_json POST /settings '{"show_welcome_on_next_start":true}' >/dev/null
stop_app

launch_app "$SUITE_A"
startup="$(http_json GET /startup)"
[[ "$(json_eval "$startup" 'data["visible"]')" == "true" ]] || fail "One-shot next-start toggle should reopen startup overlay"
[[ "$(json_eval "$startup" 'data["show_welcome_on_next_start"]')" == "true" ]] || fail "One-shot next-start toggle should stay armed until dismissal"
http_json POST /startup/dismiss >/dev/null
stop_app

launch_app "$SUITE_A"
startup="$(http_json GET /startup)"
[[ "$(json_eval "$startup" 'data["visible"]')" == "false" ]] || fail "One-shot next-start toggle should reset after dismissal"
pass "show welcome on next start resets after the next launch and dismissal"
stop_app

launch_app "$SUITE_B"
startup="$(http_json GET /startup)"
[[ "$(json_eval "$startup" 'data["visible"]')" == "true" ]] || fail "Fresh isolated suite should show startup overlay"
http_json POST /settings '{"check_updates_on_launch":false}' >/dev/null
http_json POST /startup/dismiss >/dev/null
stop_app

launch_app "$SUITE_B"
startup="$(http_json GET /startup)"
[[ "$(json_eval "$startup" 'data["visible"]')" == "false" ]] || fail "Second launch should not show startup overlay"
settings="$(http_json GET /settings)"
[[ "$(json_eval "$settings" 'data["check_updates_on_launch"]')" == "false" ]] || fail "Launch update toggle should persist as false"
pass "launch update toggle persists across relaunch"

if has_debug_update_hook; then
    http_json POST /debug/update-scenario '{"error":"offline"}' >/dev/null
    stop_app
    launch_app "$SUITE_B"
    update="$(http_json GET /update)"
    [[ "$(json_eval "$update" 'data["state"]')" == "idle" ]] || fail "Automatic launch check should stay silent when disabled"
    http_json POST /update/check >/dev/null
    update="$(http_json GET /update)"
    [[ "$(json_eval "$update" 'data["state"]')" == "error" ]] || fail "Manual update check should surface the simulated offline error"
    pass "debug build distinguishes silent launch checks from manual checks"
fi

print ""
print "QA startup/update smoke test completed for:"
print "  APP_PATH=${APP_PATH}"
print "  API_PORT=${API_PORT}"
