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

appearance_state() {
  jq -cn --argjson barHidden "$(appearance_bar_hidden)" \
    '{ barHidden: $barHidden }'
}
