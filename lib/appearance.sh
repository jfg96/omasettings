# Part of OmaSettings. Sourced by bin/omasettings; not run on its own.

# ------------------------------------------------------------- appearance
#
# The switches Omarchy keeps under Trigger > Appearance. Each one is a flag or
# a toggle file that Omarchy's own command writes, so this module reads them
# the way that command does and writes them only through it: the menu and this
# window then always agree on what is set.

OMARCHY_TOGGLES="$HOME_DIR/.local/state/omarchy/toggles"

# Runs one of Omarchy's commands and dies with its own words when it fails.
appearance_run() {
  local what=$1 out
  shift
  out=$(capture_err "$@") || die "could not set $what: ${out:-$1 failed}"
}

# The flag records the bar being off, so hidden is the flag being there.
appearance_bar_hidden() {
  [[ -f $OMARCHY_TOGGLES/bar-off ]] && echo true || echo false
}

appearance_set_bar_hidden() {
  local value=$1
  case $value in
    true) appearance_run "the bar" omarchy-toggle-bar on ;;
    false) appearance_run "the bar" omarchy-toggle-bar off ;;
    *) die "'$value' is not true or false" ;;
  esac
  [[ $(appearance_bar_hidden) == "$value" ]] || die "the bar did not accept hidden '$value'"
}

# ------------------------------------------------------- Window Corners
#
# theme, sharp or rounded: a toggle file loaded after every theme. Our managed
# file loads after the toggles, so a rounding set on the Windows page still
# wins over this; the page says so.

appearance_corners() {
  local mode
  mode=$(capture omarchy-hyprland-corners | head -n1)
  printf '%s\n' "${mode:-theme}"
}

appearance_set_corners() {
  local value=$1
  case $value in
    theme | sharp | rounded) ;;
    *) die "expected theme, sharp or rounded" ;;
  esac
  appearance_run "window corners" omarchy-hyprland-corners "$value"
  [[ $(appearance_corners) == "$value" ]] || die "window corners did not accept '$value'"
}

# ----------------------------------------------------------- Animations
#
# Omarchy's switch for machines that draw on the CPU: a Hyprland toggle that
# turns off animations, blur and shadows and makes every window opaque. The
# toggle records the effects being off, so on here means the file is there.

appearance_effects_off() {
  [[ -f $OMARCHY_TOGGLES/hypr/no-animations.lua ]] && echo true || echo false
}

appearance_set_effects_off() {
  local value=$1
  case $value in
    true) appearance_run "animations" omarchy-toggle-animations off ;;
    false) appearance_run "animations" omarchy-toggle-animations on ;;
    *) die "'$value' is not true or false" ;;
  esac
  [[ $(appearance_effects_off) == "$value" ]] || die "animations did not accept '$value'"
}

# ------------------------------------------------------ Workspace Layout
#
# The layout of every workspace without one of its own: dwindle, scrolling, or
# floating, which floats the windows rather than being a layout. A tiled
# choice is written as general.layout before our managed file loads, so a
# Layout set on the Layout page wins over it; the page says so.

appearance_workspace_layout() {
  local mode
  mode=$(capture omarchy-hyprland-workspace-layout-default | head -n1)
  printf '%s\n' "${mode:-dwindle}"
}

appearance_set_workspace_layout() {
  local value=$1
  case $value in
    dwindle | scrolling | floating) ;;
    *) die "expected dwindle, scrolling or floating" ;;
  esac
  appearance_run "the workspace layout" omarchy-hyprland-workspace-layout-default "$value"
  [[ $(appearance_workspace_layout) == "$value" ]] ||
    die "the workspace layout did not accept '$value'"
}

# ------------------------------------------------ Menu Bar > Indicators
#
# The clock and the battery keep these in their own bar entry, so they are
# set through `omarchy bar set`, which has the running bar write the entry,
# and read back out of shell.json.

# The widget's own fallback when its entry names no format.
CLOCK_DEFAULT_FORMAT="dddd HH:mm"

# What the bar entry of a widget says for one of its settings, or nothing.
bar_entry_setting() {
  read_shell_json | jq -r --arg id "$1" --arg key "$2" '
    first(.bar.layout[]?[]? | select(.id == $id) | .[$key] | select(. != null))
    | if type == "string" then . else tojson end' 2>/dev/null
}

appearance_clock_format() {
  local format
  format=$(bar_entry_setting omarchy.clock format)
  printf '%s\n' "${format:-$CLOCK_DEFAULT_FORMAT}"
}

# The presets are the menu's own rows, so the two offer the same list. Each
# row's action ends in the format it sets, quoted. The stacked rows set the
# format a vertical bar uses instead, and are left out by the same match.
appearance_clock_formats() {
  menu_group "trigger.appearance.top-bar.indicators.clock" | jq -c '[.[]
    | (.action | capture("format \"(?<f>.*)\"$").f) as $format
    | select($format != null)
    | { value: $format, label: .label }]' 2>/dev/null || echo '[]'
}

# The bar takes a setting through the running shell, which writes shell.json a
# moment after it answers; wait for the entry to say it.
bar_entry_wait() {
  local id=$1 key=$2 value=$3 attempt
  for attempt in {1..25}; do
    [[ $(bar_entry_setting "$id" "$key") == "$value" ]] && return 0
    sleep 0.1
  done
  return 1
}

appearance_set_clock_format() {
  local value=$1
  [[ -n $value ]] || die "no clock format given"
  [[ -n $(bar_widget_section omarchy.clock) ]] || die "the clock is not in the bar"
  appearance_run "the clock format" omarchy bar set omarchy.clock format "$value"
  bar_entry_wait omarchy.clock format "$value" || die "the clock did not accept format '$value'"
}

# Off until the entry says otherwise, as the widget reads it.
appearance_battery_percentage() {
  [[ $(bar_entry_setting omarchy.power showPercentage) == true ]] && echo true || echo false
}

appearance_set_battery_percentage() {
  local value=$1
  [[ $value == true || $value == false ]] || die "'$value' is not true or false"
  [[ -n $(bar_widget_section omarchy.power) ]] || die "the battery is not in the bar"
  appearance_run "the battery percentage" omarchy bar set omarchy.power showPercentage "$value" --json
  bar_entry_wait omarchy.power showPercentage "$value" ||
    die "the battery did not accept percentage '$value'"
}

appearance_state() {
  jq -cn --argjson barHidden "$(appearance_bar_hidden)" \
    --argjson clockFormats "$(appearance_clock_formats)" \
    --arg corners "$(appearance_corners)" \
    --argjson effectsOff "$(appearance_effects_off)" \
    --arg workspaceLayout "$(appearance_workspace_layout)" \
    '{ barHidden: $barHidden, clockFormats: $clockFormats, corners: $corners,
       effectsOff: $effectsOff, workspaceLayout: $workspaceLayout }'
}
