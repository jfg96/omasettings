#!/usr/bin/env python3
"""Run production scheduler and controls in Quickshell with an isolated helper."""
from pathlib import Path
import os, subprocess, tempfile, shutil
repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='omasettings-qml-') as tmp:
    root = Path(tmp)
    shutil.copy2(repo / 'bin/omasettings-run', root / 'omasettings-run')
    # Native widgets and palette, with the same qs import layout as the shell.
    for name in ['Commons', 'Ui']:
        (root / name).symlink_to('/usr/share/omarchy/shell/' + name)
    shutil.copytree(repo / 'ui', root / 'Rows')
    with (root / 'Rows/qmldir').open('a') as directory:
        for file in (root / 'Rows').glob('*.qml'):
            if file.stem != 'Palette': directory.write(f'{file.stem} {file.name}\n')
    source = (repo / 'SettingsWindow.qml').read_text()
    protocol = source[source.index('  // A single scheduler'):source.index('  // ---------------- sections')]
    (root / 'helper').write_text('''#!/bin/bash
if [[ $1 == state ]]; then
  if [[ -f "$(dirname "$0")/fail-read" ]]; then
    rm "$(dirname "$0")/fail-read"
    sleep 20
  fi
  sleep 0.08
  blur=false
  [[ -f "$(dirname "$0")/accepted" ]] && blur=true
  printf '{"hypr":{"blur":%s,"factor":0.95},"hyprChanged":[],"bar":{}}\\n' "$blur"
else
  sleep 0.04
  if [[ $2 == accept ]]; then touch "$(dirname "$0")/accepted"; fi
  if [[ $2 == snap ]]; then echo 'same error' >&2; exit 7; fi
  if [[ $2 == silent ]]; then exit 8; fi
  if [[ $2 == hang ]]; then sleep 20; fi
  if [[ $2 == fail-read ]]; then touch "$(dirname "$0")/fail-read"; fi
fi
''')
    qml = '''import QtQuick
import Quickshell
import Quickshell.Io
import "Rows" as Rows
Item {
 id: root
 property string helperPath: "HELPER"
 property var state: ({hypr:{blur:false}})
 property bool loaded: true
 property string lastError: ""
 property var audioLive: null
 property var powerLive: null
 property var wifiLive: null
 property var bluetoothLive: null
 property bool searching: false
 function registerNavRow(row) {}
 function unregisterNavRow(row) {}
 function rowMatches(a,b,c) { return true }
 function check(ok, message) { if (!ok) { console.error("FAIL " + message); Qt.exit(1) } }
 Rows.SwitchRow { id: toggle; checked: root.state.hypr.blur; onRequested: function(next) { root.run(["set", root.phase === 2 ? "accept" : root.phase === 3 ? "hang" : root.phase === 4 ? "fail-read" : "blur", String(next)]) } }
 Rows.MutationToggle { id: compact; app: root; confirmed: root.state.hypr.blur; onRequested: function(next) { root.run(["set", "blur", String(next)]) } }
 Rows.SwitchRow { id: other; onRequested: function(next) { root.run(["set", "snap", String(next)]) } }
 Rows.NumberRow { id: number; value: 5; onCommitted: function(next) { root.run(["set", "silent", String(next)]) } }
 Rows.FactorRow { id: factor; value: root.state.hypr.factor === undefined ? 0.9 : root.state.hypr.factor; onCommitted: function(next) { root.run(["set", "factor", next]) } }
 Rows.PercentRow { id: percent; value: 0.9; onCommitted: function(next) { root.run(["set", "percent", String(next)]) } }
 Rows.MinutesRow { id: minutes; seconds: 120; onCommitted: function(next) { root.run(["set", "minutes", String(next)]) } }
 property int phase: 0
 property int results: 0
 property bool readFailed: false
 onMutationFinished: function(result) {
   results++
   if (result.args[1] === "snap") check(!result.success && result.exitCode === 7 && result.error === "same error", "stderr belongs to failed mutation")
   if (result.args[1] === "silent") check(!result.success && result.exitCode === 8 && result.error.indexOf("exit 8") >= 0 && result.error.indexOf("same error") < 0, "silent failure has fresh fallback")
   if (result.args[1] === "hang") check(!result.success && result.timedOut && result.error.indexOf("timed out") >= 0, "hung helper becomes an explicit failure")
 }
 onMutationReconciled: function(result) {
   if (result.args[1] === "blur") check(result.accepted === false && result.verificationError.indexOf("did not accept") >= 0, "silent toggle no-op reported")
   if (result.args[1] === "accept") check(result.accepted === true, "successful toggle verified")
   if (result.args[1] === "fail-read") { check(!result.reconciled, "read timeout is not an authoritative result"); readFailed = true }
 }
 Component.onCompleted: Qt.callLater(function() {
   toggle.flip(); toggle.navActivate(); other.flip(); number.commit(9); number.commit(10)
   factor.commit(1); percent.commit(0.97); minutes.commit(3)
   check(toggle.effective && toggle.mutationPending, "immediate optimistic toggle")
   check(nextMutationId === 7, "same-row repeats ignored; other rows enqueue")
   check(number.effective === 9 && factor.effective === 1 && percent.effective === 0.97 && minutes.effective === 3, "optimistic sliders")
 })
 Timer {
   interval: 10; running: true; repeat: true
   onTriggered: {
     root.check(!(applyProc.running && (sliceProc.running || stateProc.running)), "read/write exclusion")
     if (root.phase === 0 && root.reconciliationGeneration === 1) {
       root.check(root.results === 6, "every queued write completed")
       root.check(!toggle.mutationPending && !toggle.effective && !other.mutationPending, "unchanged false reconciles")
       root.check(!number.mutationPending && number.effective === 5 && !factor.mutationPending && factor.effective === 0.95 && !percent.mutationPending && percent.effective === 0.9 && !minutes.mutationPending && minutes.effective === 2, "all slider rejections reconcile")
       root.phase = 1
       root.refresh()
       toggle.flip()
       root.check(toggle.mutationPending, "new request during read")
     } else if (root.phase === 1 && root.reconciliationGeneration === 2) {
       root.check(!toggle.mutationPending && !toggle.effective, "request waits for its own read")
       root.phase = 2
       toggle.flip()
     } else if (root.phase === 2 && root.reconciliationGeneration === 3) {
       root.check(!toggle.mutationPending && toggle.effective && toggle.checked, "successful toggle remains on")
       root.phase = 3
       root.mutationTimeoutMs = 250
       toggle.flip(); compact.flip(); compact.flip()
       root.check(toggle.mutationPending && compact.mutationPending && root.nextMutationId === 11, "compact switch uses shared guard; other rows queue behind hung helper")
     } else if (root.phase === 3 && root.reconciliationGeneration === 4) {
       root.check(!toggle.mutationPending && !compact.mutationPending && toggle.effective && compact.checked, "timed-out write releases all reconciled controls")
       root.phase = 4
       root.readTimeoutMs = 250
       toggle.flip()
     } else if (root.phase === 4 && root.readFailed) {
       root.check(!toggle.mutationPending && !root.readRunning && !root.mutationRunning, "timed-out read releases the row and queue")
       console.log("PASS native QML rows, real processes, exit codes, collectors, burst reconciliation, no-op, busy guards, compact switches, write/read timeouts")
       Qt.quit()
     }
   }
 }
 Timer { interval: 10000; running: true; onTriggered: { console.error("FAIL timeout"); Qt.exit(1) } }
PROTOCOL
}
'''.replace('HELPER', str(root / 'helper')).replace('PROTOCOL', protocol)
    (root / 'shell.qml').write_text(qml)
    result = subprocess.run(['qs', '-p', str(root), '--no-color'], env={**os.environ, 'QT_QPA_PLATFORM':'offscreen'}, text=True, capture_output=True, timeout=15)
    output = result.stdout + result.stderr
    print(output)
    if result.returncode or 'PASS native QML' not in output or 'FAIL' in output:
        raise SystemExit(1)
