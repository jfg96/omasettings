# Changelog — build local

Fixes on top of upstream `io.github.twiking.omasettings` in this personal
build. Not a maintained fork, not a release line: it is upstream 1.3.0 with
the problems below fixed, for this machine.

Base: upstream `v1.3.0` (`72cfe16`). Tagged `v1.3.0-local`.

Everything here is a fix or a port of a fix. No feature work, no upstream
PR merged wholesale: each one was read, ported by hand against the current
code, and tested on its own. `lib/state.sh`, `lib/core.sh`, `bin/omasettings`
and `manifest.json` (bar/entry-point metadata) are untouched, so the shell
API, the state document and the search index are the ones upstream ships.

## Mutation / reconciliation hardening — 2026-09-27

- Hyprland live writes preserve diagnostics and fail before changing the store
  or generated configuration. Readback verifies acceptance, including boolean
  no-ops and float clamping. Returning to an original value follows the same
  validation path; unavailable boolean options cannot masquerade as `false`.
- Each queued mutation carries its ID, arguments, affected slices, exit code,
  exit status, error and reconciliation outcome. `Process.exited` determines
  success; stderr is cleared before every command. Empty stderr gets a useful
  fallback, and identical failures remain distinct mutation results.
- One scheduler excludes full/scoped reads from writes in both directions.
  A burst drains its writes before one unioned scoped read. Unknown scopes use
  a full reconciliation. The optional full settle remains once per burst,
  and `slicesSuffice()` still avoids it where valid. State producers remain
  parallel inside the shell reader.
- Switch, number, factor, percentage, minutes and bar spacer controls reconcile
  by generation and mutation ID, even when their authoritative value has not
  changed. An older read cannot acknowledge a request queued during that read.
  Native toggle busy state and keyboard/slider guards allow one outstanding
  operation per row while other rows remain usable.
- A failed or malformed reconciliation does not advance the generation. It
  releases only the affected rows to their last known state, reports the read
  failure, and requests a delayed full refresh. Live overlays are invalidated
  for slices returned by the authoritative reader.

Regression checks (isolated helpers; no real desktop settings changed):

- `bash tests/backend-mutations.sh`: 12 cases for Lua and legacy live failures,
  failures without diagnostics, success, no-op, failed return to the original
  value, float clamp and missing boolean readback. Failed writes leave the store
  and generated config unchanged.
- `node tests/mutation-protocol.cjs`: production scheduler functions exercise
  ordered bursts, unioned scopes, read/write exclusion, requests during reads,
  mutation watermarks, repeated identical failures, fresh stderr, invalid JSON,
  explicit failed-read outcomes, and full reconciliation for unknown scopes.
- `python3 tests/qml-mutations.py`: real Quickshell processes and production QML
  rows exercise immediate optimistic values, per-row repeat guards, success,
  unchanged-value no-op, exit codes/stderr, slider rejection/clamping, and a
  request arriving during a read. Uses installed native Omarchy controls in
  offscreen mode; platform/window deprecation warnings are expected there.
- `qmllint -I /usr/share/omarchy/shell -I /usr/lib/qt6/qml` over all QML:
  no diagnostics. `bash -n`, `git diff --check`, and `omarchy plugin validate .`
  pass. Physical mouse interaction with the installed window is not automated.

## Fixes

| Commit | What was wrong |
| --- | --- |
| `84c26b7` | Settings mutations were fired as they arrived, so two quick writes could reach the shell out of order and the second could read the first's half-applied state. They are serialized through one queue now. |
| `5fac37d` | A switch derived its next action from confirmed state, so pressing it twice quickly asked for the value it had just asked for. It keeps the pending value as its own, and a switch nobody touched stays settled. |
| `a5b200f` | A per-device row's Changed mark and its Reset wrote the global Hyprland keyword instead of `device:<name>:<option>`, so resetting a mouse row moved every mouse. Upstream issue #7. |
| `e40bfb1` | Natural scrolling and scroll factor were offered once, for a touchpad, and written to whichever device the pointer was. A mouse has `input:natural_scroll` and `input:scroll_factor` of its own; they are now a separate group, with the kind of the device deciding which row writes where. |
| `0b5bfe1` | The same per-device mistake in five keyboard rows. |
| `732b281` | `WifiRow`'s `NavCursor` was a direct child of a `Column`, anchored `fill` — one `Column` anchor warning per visible network, and a wrong cursor. The invalid `searchHidden` on the Network page's `SettingGroup` was a second `ReferenceError` on the same page. Upstream issue #16. |
| `ae84e8b` | A value containing `"`, `\` or a newline was escaped once for the shell and then written into Lua still escaped, so a keybinding with a quote in it produced a file Hyprland would not load. Values are stored raw and quoted once, at the point of writing; `awk -v` (which re-interprets backslashes) was replaced by `ENVIRON` on every path that carries a value into a renderer. Includes a one-time `bindingsSchema` migration for stores written by the old escaping. Port of upstream PR #10. |
| `49c72ce` | No `Text` in the plugin set `textFormat`, so all 47 of them were on QtQuick's `AutoText` and switched to rich text for any string that parses as markup — an SSID or Bluetooth name could make the shell fetch a URL, and any foreign label could borrow the window's formatting. All 47 are `Text.PlainText`. Port of upstream PR #11. |
| `2fee53a` | `plugin-updates.json` kept a failed update verdict forever, so a `cannot fast-forward` banner outlived the fix that caused it, and outlived the plugin itself. Verdicts are now scoped to installed plugins, and a failure is dropped once the count says nothing is waiting. Upstream PR #13 shipped with a guard that returned early when the plugins directory was missing — the one case where the stale cache must not be left alone; that guard is gone and a missing directory writes the empty current cache. Upstream PR #13. |
| `275c5fb` | The launcher entry was written from `manifest.__sourceDir`, a field Omarchy strips from a third-party plugin's manifest, so `omasettings.desktop` was never written and nothing said so. The path comes from `Qt.resolvedUrl(".")` instead, and an install that fails now says why once in the journal. Port of upstream PR #9. |
| `e2e26d7` | Documentation only: records the third qmllint warning this fork's launcher handler raises, and why importing `QtQuick.Processes` to silence it would break the file. |
| `5e2f11c` | The full read that follows a burst of writes was armed on a timer when the first write finished, and the next write started immediately — so a write slower than 400 ms was still running when the timer expired, and the full read landed in the middle of it. One burst, two full reads, one of them against a half-applied change. The debt is now recorded when a write needs it and the timer is armed only once the queue is empty, so a burst always ends in exactly one full read, after the last write. |
| `d25ea54` | `helperPath` stripped `file://` off a `Qt.resolvedUrl` result but left the percent-encoding, so with a space anywhere in `$HOME` every helper the window shells out to — audio watch, power watch, bluetooth and wifi polls, wifi connect, plugin updates — was run at a path that does not exist, silently. Decoded, the same way the launcher path is. |

## How it was checked

- `omarchy plugin validate .` on every commit.
- Qt 6 `qmllint` over the window, service, panel, all pages and all `ui/`
  components: 0 errors, and the warning set is byte-identical to the
  baseline on `v1.3.0` (the one Network-section warning is gone, the one
  launcher warning is new and explained above).
- `bash -n` over every `lib/*.sh` and `bin/omasettings`.
- All 23 pages opened one after another on a restarted shell with an empty
  journal apart from the launcher failure test that was asked for.
- The escaping work ran against a sandbox with every path redirected:
  28 cases, including quotes, `grep \d`, a literal `\n`, a trailing
  backslash, a real newline, multibyte input, a quoted device name, Herdr's
  TOML, Neovim's Lua, a `.conf` left byte-identical, an old store migrated
  once, and `state` never writing. Then a real binding with a quote in it,
  added and removed, leaving `bindings.lua` byte-identical.
- The update cache ran against real local git repositories: 22 cases
  covering the pruning rules, the missing and empty plugins directory,
  `changes` still carrying commit subjects, a second sweep changing
  nothing, and a corrupt or absent cache being replaced rather than
  trusted. Ten of those cases fail against `v1.3.0`.
- Per-device set and reset against the real store and the real managed Lua,
  with `luac -p` and `hyprChanged` checked at each end.
- The launcher cycle: written on restart, gone on `omarchy plugin disable`,
  back on `enable`, `desktop-file-validate` clean, and a deliberately
  missing template reported once as
  `omasettings: no launcher entry: no template at …`.
- Window opens in 58–66 ms warm, so the scoped-refresh work is intact.
- The mutation queue was run through six scenarios with a stand-in process
  of known duration, using the functions as they stand in the file: six
  quick writes, a fast write followed by one slower than the settle window,
  the same the other way round, a write arriving inside the window, a
  command its scoped read covers, and a mix of both. 25 checks, all
  passing. The same six against the previous code fail four — the burst
  containing the slow write reads the state twice, once while a write is in
  flight.
- The path decoding was run on the Qt 6 QML runtime with the URLs a home
  directory holding a space really produces: the old expression yields
  `/home/javi/My%20Stuff/...`, the new one yields `/home/javi/My Stuff/...`,
  an unencoded path is unchanged, a literal `%` in a name survives, and a
  malformed escape falls back to the raw value instead of throwing.

## Not in this build

Reviewed and left out on purpose, per the plan this fork was built to:

- upstream PR #8 (bar-widget-hosted fallback) — only useful with a
  third-party bar container, and it trades against Omarchy's plugin
  permission model.
- upstream PR #5 (display rotation and alignment) — a feature, for a
  multi-display setup.
- upstream PR #14 (card cap on very large displays) — no such display here.
- upstream PR #15 (bar reorder by typing the order) — a feature with a
  large surface, for later if this build is picked up again.
