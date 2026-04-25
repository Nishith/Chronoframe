#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Chronoframe"
BUNDLE_ID="com.nishith.chronoframe"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI_DIR="$ROOT_DIR/ui"
APP_BUNDLE="$UI_DIR/build/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  "$UI_DIR/build.sh"
}

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

first_pid() {
  pgrep -x "$APP_NAME" | awk 'NR == 1 { print; found = 1 } END { exit found ? 0 : 1 }'
}

verify_app() {
  local attempts=10
  while [ "$attempts" -gt 0 ]; do
    if first_pid >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 1
  done

  echo "error: $APP_NAME did not appear in the process list after launch." >&2
  return 1
}

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    ;;
  *)
    usage
    exit 2
    ;;
esac

stop_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    open_app
    verify_app
    lldb -p "$(first_pid)"
    ;;
  --logs|logs)
    open_app
    verify_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    verify_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    verify_app
    echo "$APP_NAME launched successfully from $APP_BUNDLE"
    ;;
esac
