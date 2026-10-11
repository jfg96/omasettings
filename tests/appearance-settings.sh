#!/bin/bash
# Omarchy's Appearance switches, against stub Omarchy commands in a sandbox.
set -euo pipefail
cd "$(dirname "$0")/.."
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
HOME=$sandbox
source lib/core.sh
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
