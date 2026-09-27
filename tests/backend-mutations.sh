#!/bin/bash
# No real Hyprland calls or user config writes.
set -euo pipefail
cd "$(dirname "$0")/.."
source lib/hypr.sh
source lib/store.sh
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
HYPR_DIR=$sandbox
STORE=$sandbox/store.json
MANAGED_LUA=$sandbox/managed.lua
read_file() { cat "$1"; }
write_file() { cat > "$1"; }
render_managed() { cat "$STORE" > "$MANAGED_LUA"; }
die() { echo "$*" >&2; exit 1; }
capture() { "$@"; }
hyprctl() {
  if [[ $1 == -j ]]; then
    cat "$sandbox/live.json"
  elif [[ $mode == fail ]]; then
    echo 'mock Hyprland rejection' >&2
    return 7
  elif [[ $mode == silent-fail ]]; then
    return 8
  elif [[ $mode == success ]]; then
    echo "${accepted_json:-{\"bool\":true}}" > "$sandbox/live.json"
  fi
}
for parser in legacy lua; do
  [[ $parser == legacy ]] || touch "$HYPR_DIR/hyprland.lua"
  for mode in fail silent-fail noop success; do
    echo '{}' > "$STORE"
    echo 'original generated config' > "$MANAGED_LUA"
    echo '{"bool":false}' > "$sandbox/live.json"
    cp "$STORE" "$sandbox/store.before"
    cp "$MANAGED_LUA" "$sandbox/config.before"
    if (hypr_set blur true) 2> "$sandbox/error"; then
      [[ $mode == success ]]
      jq -e '.hypr.blur == true and .hyprOriginal.blur == false' "$STORE" > /dev/null
    else
      [[ $mode != success ]]
      cmp "$STORE" "$sandbox/store.before"
      cmp "$MANAGED_LUA" "$sandbox/config.before"
      [[ -s $sandbox/error ]]
      case $mode in
        fail) grep -q 'mock Hyprland rejection' "$sandbox/error" ;;
        silent-fail) grep -q 'exit 8' "$sandbox/error" ;;
        noop) grep -q 'did not accept' "$sandbox/error" ;;
      esac
    fi
    echo "PASS $parser $mode"
  done
  # Returning to an original value must not bypass live-apply validation.
  echo '{"hypr":{"blur":false},"hyprOriginal":{"blur":true}}' > "$STORE"
  cp "$STORE" "$sandbox/store.before"
  mode=fail
  if (hypr_set blur true) 2> "$sandbox/error"; then exit 1; fi
  cmp "$STORE" "$sandbox/store.before"
  echo "PASS $parser failed return to original"
done

# A clamped float and an unavailable boolean must not become stored success.
echo '{}' > "$STORE"
cp "$STORE" "$sandbox/store.before"
echo '{"float":0.9}' > "$sandbox/live.json"
mode=success
accepted_json='{"float":0.95}'
if (hypr_set active-opacity 0.97) 2> "$sandbox/error"; then exit 1; fi
cmp "$STORE" "$sandbox/store.before"
grep -q 'read back 0.95' "$sandbox/error"
echo 'PASS clamped float is not persisted as requested'
echo '{}' > "$sandbox/live.json"
mode=noop
if (hypr_set blur false) 2> "$sandbox/error"; then exit 1; fi
cmp "$STORE" "$sandbox/store.before"
echo 'PASS absent boolean readback is not accepted as false'
