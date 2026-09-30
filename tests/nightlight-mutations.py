#!/usr/bin/env python3
"""Exercise the real CLI pipeline with isolated shell IPC and daemon startup."""
from pathlib import Path
import json
import os
import signal
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="omasettings-nightlight-") as directory:
    sandbox = Path(directory)
    binaries = sandbox / "bin"
    binaries.mkdir()
    hypr = sandbox / "hypr"
    hypr.mkdir()
    # Legacy renderer with no live compositor; every written file is isolated.
    (hypr / "hyprland.conf").write_text("")
    (binaries / "omarchy-shell").write_text('''#!/bin/bash
echo "$*" >> "$FIXTURE/calls"
case $MODE in
  ipc-fail) echo 'mock IPC rejection' >&2; exit 9 ;;
  unavailable) echo 'Target not found.'; exit 0 ;;
esac
[[ $1 == nightlight ]] || exit 2
case $2 in
  enable) target=4000; answer=enabled ;;
  disable) target=6500; answer=disabled ;;
  *) exit 3 ;;
esac
if [[ $MODE == delayed || $MODE == delayed-start ]]; then
  [[ $MODE == delayed-start ]] && touch "$FIXTURE/starting"
  # The actual shell service detaches daemon stdio from its caller.
  (sleep 0.2; echo "$target" > "$FIXTURE/temperature"; rm -f "$FIXTURE/starting") </dev/null >/dev/null 2>&1 &
fi
echo "$answer"
''')
    (binaries / "omarchy-toggle-nightlight").write_text('''#!/bin/bash
if [[ ${1:-} == --status ]]; then
  if [[ $MODE == missing-temperature || -f $FIXTURE/starting ]]; then
    echo '{"enabled":false,"temperature":null}'
  else
    temp=$(cat "$FIXTURE/temperature")
    enabled=false
    (( temp < 6000 )) && enabled=true
    printf '{"enabled":%s,"temperature":%s}\\n' "$enabled" "$temp"
  fi
  exit 0
fi
echo legacy-toggle >> "$FIXTURE/calls"
# Mimic the daemon retaining the CLI's pipe after the toggle script exits.
sleep 30 &
''')
    for binary in binaries.iterdir():
        binary.chmod(0o755)
    env = {**os.environ, "PATH": f"{binaries}:{os.environ['PATH']}",
           "FIXTURE": str(sandbox), "OMASETTINGS_STORE": str(sandbox / "store.json"),
           "OMASETTINGS_HYPR_DIR": str(hypr)}

    def run(mode, value):
        process = subprocess.Popen(
            ["bash", str(repo / "bin/omasettings"), "set", "nightlight", value],
            env={**env, "MODE": mode}, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=7)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            raise AssertionError("nightlight mutation retained its output pipe")
        return process.returncode, stdout, stderr

    (sandbox / "temperature").write_text("6500\n")
    code, _, error = run("delayed", "true")
    assert code == 0, error
    assert (sandbox / "temperature").read_text().strip() == "4000"
    assert json.loads((sandbox / "store.json").read_text())["written"]["nightlight"] == "false"
    code, _, error = run("delayed", "true")
    assert code == 0, error
    code, _, error = run("delayed", "false")
    assert code == 0, error
    assert (sandbox / "temperature").read_text().strip() == "6500"
    assert "nightlight" not in json.loads((sandbox / "store.json").read_text()).get("written", {})
    assert "legacy-toggle" not in (sandbox / "calls").read_text()
    print("PASS absolute on/off, asynchronous startup, repeat, tracking round trip, pipe closes")

    code, _, error = run("delayed-start", "true")
    assert code == 0, error
    code, _, error = run("delayed", "false")
    assert code == 0, error
    print("PASS unavailable temperature during startup is retried before acceptance")

    before = (sandbox / "store.json").read_bytes()
    for mode, value, message in [
        ("ipc-fail", "true", "mock IPC rejection"),
        ("unavailable", "true", "Target not found."),
        ("noop", "true", "did not accept"),
        ("missing-temperature", "false", "did not accept"),
        ("delayed", "toggle", "not true or false"),
    ]:
        code, _, error = run(mode, value)
        assert code != 0 and message in error, (mode, code, error)
        assert (sandbox / "store.json").read_bytes() == before, mode
        print(f"PASS {mode}: failure reported, store unchanged")
