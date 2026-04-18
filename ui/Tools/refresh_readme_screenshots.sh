#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${UI_DIR}/.." && pwd)"
APP_DIR="${UI_DIR}/build/Chronoframe.app"
APP_BINARY="${APP_DIR}/Contents/MacOS/Chronoframe"
SCREENSHOT_DIR="${REPO_ROOT}/docs/screenshots"
WINDOW_X=120
WINDOW_Y=80
WINDOW_WIDTH=1440
WINDOW_HEIGHT=960

if [ ! -x "$APP_BINARY" ]; then
  echo "error: expected built app binary at $APP_BINARY" >&2
  echo "hint: run ui/build.sh first" >&2
  exit 1
fi

mkdir -p "$SCREENSHOT_DIR"

cleanup_app() {
  pkill -x Chronoframe >/dev/null 2>&1 || true
}

wait_for_window() {
  local attempt
  for attempt in $(seq 1 60); do
    if osascript <<'OSA' >/dev/null 2>&1
tell application "System Events"
  if exists process "Chronoframe" then
    tell process "Chronoframe"
      if (count of windows) > 0 then return true
    end tell
  end if
end tell
OSA
    then
      return 0
    fi
    sleep 0.2
  done

  echo "error: Chronoframe window did not appear in time" >&2
  return 1
}

position_window() {
  osascript <<OSA
tell application "Chronoframe" to activate
tell application "System Events"
  tell process "Chronoframe"
    repeat 40 times
      if (count of windows) > 0 then exit repeat
      delay 0.2
    end repeat
    if (count of windows) > 0 then
      set position of front window to {$WINDOW_X, $WINDOW_Y}
      set size of front window to {$WINDOW_WIDTH, $WINDOW_HEIGHT}
    end if
  end tell
end tell
OSA
}

capture_scenario() {
  local scenario="$1"
  local output_path="$2"
  local log_path="${UI_DIR}/build/screenshot-${scenario}.log"

  cleanup_app
  CHRONOFRAME_UI_TEST_SCENARIO="$scenario" \
  CHRONOFRAME_UI_TEST_DISABLE_NOTIFICATIONS=1 \
  "$APP_BINARY" >"$log_path" 2>&1 &
  local app_pid=$!

  wait_for_window
  position_window

  if [ "$scenario" = "runPreviewReview" ]; then
    sleep 1.5
  else
    sleep 0.8
  fi

  screencapture -x -R"${WINDOW_X},${WINDOW_Y},${WINDOW_WIDTH},${WINDOW_HEIGHT}" "$output_path"

  kill "$app_pid" >/dev/null 2>&1 || true
  wait "$app_pid" >/dev/null 2>&1 || true
}

capture_scenario "setupReady" "${SCREENSHOT_DIR}/ui-setup-overview.png"
capture_scenario "runPreviewReview" "${SCREENSHOT_DIR}/ui-run-preview.png"
cleanup_app

echo "Updated screenshots:"
echo "  ${SCREENSHOT_DIR}/ui-setup-overview.png"
echo "  ${SCREENSHOT_DIR}/ui-run-preview.png"
