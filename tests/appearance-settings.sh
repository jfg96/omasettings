#!/bin/bash
# Omarchy's Appearance switches, against stub Omarchy commands in a sandbox.
set -euo pipefail
cd "$(dirname "$0")/.."
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
HOME=$sandbox
source lib/core.sh
source lib/shell_config.sh
# Its heredoc read ends at EOF, which is a non-zero status under set -e.
source lib/menu.sh || true
source lib/appearance.sh
die() { echo "$*" >&2; exit 1; }
mkdir -p "$OMARCHY_TOGGLES"

# The stubs do what Omarchy's commands do to their files. They are programs on
# a PATH of their own, since the commands are run under `timeout`, which cannot
# see shell functions — and must never reach the real ones. $sandbox/broken
# makes the next one fail, or exit 0 having done nothing.
export PATH="$sandbox/bin:$PATH" sandbox OMARCHY_TOGGLES
mkdir -p "$sandbox/bin"
stub() {
  { printf '#!/bin/bash\n'
    printf 'case $(cat "$sandbox/broken" 2>/dev/null) in\n'
    printf "  fail) echo 'mock %s failure' >&2; exit 3 ;;\n" "$1"
    printf '  noop) exit 0 ;;\nesac\n'
    cat
  } >"$sandbox/bin/$1"
  chmod +x "$sandbox/bin/$1"
}
broken() { printf '%s' "$1" >"$sandbox/broken"; }

stub omarchy-toggle-bar <<'STUB'
case $1 in on) touch "$OMARCHY_TOGGLES/bar-off" ;; off) rm -f "$OMARCHY_TOGGLES/bar-off" ;; esac
STUB

appearance_set_bar_hidden true
[[ $(appearance_bar_hidden) == true ]]
appearance_set_bar_hidden false
[[ $(appearance_bar_hidden) == false ]]
jq -e '.barHidden == false' <<<"$(appearance_state)" >/dev/null
echo 'PASS bar hidden round trip'

broken fail
if (appearance_set_bar_hidden true) 2>"$sandbox/error"; then exit 1; fi
grep -q 'mock omarchy-toggle-bar failure' "$sandbox/error"
broken noop
if (appearance_set_bar_hidden true) 2>"$sandbox/error"; then exit 1; fi
grep -q 'did not accept' "$sandbox/error"
if (appearance_set_bar_hidden maybe) 2>/dev/null; then exit 1; fi
broken ""
echo 'PASS bar hidden failure, silent no-op and bad value are reported'

# The clock: the bar entry is what the running shell writes, a moment later.
SHELL_JSON=$sandbox/shell.json
export SHELL_JSON
read_file() { cat "$1"; }
echo '{"bar":{"layout":{"center":[{"id":"omarchy.clock"}]}}}' >"$SHELL_JSON"
stub omarchy <<'STUB'
[[ "$1 $2" == "bar set" ]] || exit 9
( sleep 0.3
  if [[ ${6:-} == --json ]]; then json=--argjson; else json=--arg; fi
  jq --arg id "$3" --arg k "$4" $json v "$5" \
    '.bar.layout[][] |= if .id == $id then .[$k] = $v else . end' "$SHELL_JSON" >"$SHELL_JSON.new"
  mv "$SHELL_JSON.new" "$SHELL_JSON" ) &
echo ok
STUB
[[ $(appearance_clock_format) == "dddd HH:mm" ]]
appearance_set_clock_format "HH:mm"
[[ $(appearance_clock_format) == "HH:mm" ]]
echo 'PASS clock format waits for the bar to write it'

broken noop
if (appearance_set_clock_format "h:mm AP") 2>"$sandbox/error"; then exit 1; fi
grep -q 'did not accept' "$sandbox/error"
broken ""
echo '{"bar":{"layout":{"center":[]}}}' >"$SHELL_JSON"
if (appearance_set_clock_format "HH:mm") 2>"$sandbox/error"; then exit 1; fi
grep -q 'not in the bar' "$sandbox/error"
echo 'PASS clock format refuses a silent no-op and a bar without a clock'

echo '{"bar":{"layout":{"right":[{"id":"omarchy.power"}]}}}' >"$SHELL_JSON"
[[ $(appearance_battery_percentage) == false ]]
appearance_set_battery_percentage true
[[ $(appearance_battery_percentage) == true ]]
jq -e '.bar.layout.right[0].showPercentage == true' "$SHELL_JSON" >/dev/null
appearance_set_battery_percentage false
[[ $(appearance_battery_percentage) == false ]]
if (appearance_set_battery_percentage yes) 2>/dev/null; then exit 1; fi
echo 'PASS battery percentage is written as a boolean and read back'

MENU_DEFAULTS=$sandbox/menu.jsonc
MENU_USER=$sandbox/none.jsonc
MENU_ENTRIES_CACHE=""
cat >"$MENU_DEFAULTS" <<'MENU'
{
  // presets
  "trigger.appearance.top-bar.indicators.clock.time-24h": { "label": "14:30", "action": "omarchy-bar set omarchy.clock format \"HH:mm\"" },
  "trigger.appearance.top-bar.indicators.clock.stacked-time": { "label": "14 30", "action": "omarchy-bar set omarchy.clock verticalFormat $'HH\\nmm'" },
}
MENU
jq -e '. == [{"value":"HH:mm","label":"14:30"}]' <<<"$(appearance_clock_formats)" >/dev/null
echo 'PASS clock presets come from the menu, stacked ones left out'

# Corners: the command prints the mode it finds from the toggle files.
stub omarchy-hyprland-corners <<'STUB'
dir=$OMARCHY_TOGGLES/hypr
if (( $# == 0 )); then
  if [[ -f $dir/corners-sharp.lua ]]; then echo sharp
  elif [[ -f $dir/corners-rounded.lua ]]; then echo rounded
  else echo theme; fi
  exit 0
fi
mkdir -p "$dir"; rm -f "$dir"/corners-*.lua
[[ $1 == theme ]] || touch "$dir/corners-$1.lua"
STUB
[[ $(appearance_corners) == theme ]]
appearance_set_corners rounded
[[ $(appearance_corners) == rounded ]]
appearance_set_corners theme
[[ $(appearance_corners) == theme ]]
if (appearance_set_corners square) 2>/dev/null; then exit 1; fi
broken noop
if (appearance_set_corners sharp) 2>"$sandbox/error"; then exit 1; fi
grep -q 'did not accept' "$sandbox/error"
broken ""
echo 'PASS window corners round trip and refusals'

# Reduced effects: Omarchy's switch speaks of animations, so on and off swap.
stub omarchy-toggle-animations <<'STUB'
mkdir -p "$OMARCHY_TOGGLES/hypr"
case $1 in
  off) touch "$OMARCHY_TOGGLES/hypr/no-animations.lua" ;;
  on) rm -f "$OMARCHY_TOGGLES/hypr/no-animations.lua" ;;
esac
STUB
appearance_set_effects_off true
[[ $(appearance_effects_off) == true ]]
appearance_set_effects_off false
[[ $(appearance_effects_off) == false ]]
broken fail
if (appearance_set_effects_off true) 2>"$sandbox/error"; then exit 1; fi
grep -q 'mock omarchy-toggle-animations failure' "$sandbox/error"
broken ""
echo 'PASS reduced effects map onto the animations switch the right way round'
