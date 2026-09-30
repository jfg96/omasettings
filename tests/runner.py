#!/usr/bin/env python3
"""Finite-operation supervision: IO inheritance, timeout, errors and shutdown."""
from pathlib import Path
import os
import signal
import subprocess
import sys
import tempfile
import time

runner = Path(__file__).resolve().parents[1] / "bin/omasettings-run"


def run(code, timeout=2, maximum=4194304):
    started = time.monotonic()
    result = subprocess.run([sys.executable, str(runner), "--timeout", str(timeout),
        "--max-bytes", str(maximum), "--", sys.executable, "-c", code],
        capture_output=True, timeout=5)
    return result, time.monotonic() - started


def stopped(pid):
    try:
        state = Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()[0]
        return state == "Z"
    except FileNotFoundError:
        return True


result, _ = run("import sys; print('output'); print('rejected', file=sys.stderr); sys.exit(7)")
assert result.returncode == 7 and result.stdout == b"output\n" and result.stderr == b"rejected\n"
print("PASS actual exit code, stdout and stderr preserved")

with tempfile.TemporaryDirectory(prefix="omasettings runner ") as directory:
    pid_file = Path(directory) / "child"
    result, elapsed = run(f'''import subprocess,sys
from pathlib import Path
child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(20)'])
Path({str(pid_file)!r}).write_text(str(child.pid))
print('finished')
''')
    child_pid = int(pid_file.read_text())
    try:
        assert result.returncode == 0 and elapsed < 1 and result.stdout == b"finished\n"
    finally:
        os.kill(child_pid, signal.SIGKILL)
    print("PASS descendant retaining stdio cannot delay a completed operation")

    helper = f'''import subprocess,sys,time
from pathlib import Path
child = subprocess.Popen([sys.executable, '-c', 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(20)'])
Path({str(pid_file)!r}).write_text(str(child.pid))
time.sleep(20)
'''
    result, elapsed = run(helper, timeout=0.25)
    assert result.returncode == 124 and b"timed out" in result.stderr and elapsed < 2
    assert stopped(int(pid_file.read_text()))
    print("PASS timeout kills foreground children before the next operation")

    pid_file.unlink()
    process = subprocess.Popen([sys.executable, str(runner), "--timeout", "10", "--",
        sys.executable, "-c", helper], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    deadline = time.monotonic() + 2
    while not pid_file.exists() and time.monotonic() < deadline:
        time.sleep(0.02)
    assert pid_file.exists()
    process.terminate()
    _, error = process.communicate(timeout=3)
    assert process.returncode == 143 and b"interrupted" in error
    assert stopped(int(pid_file.read_text()))
    print("PASS owner shutdown cancels the helper and its foreground children")

result, _ = run("import sys; sys.stdout.write('x' * 10000)", maximum=64)
assert result.returncode == 125 and len(result.stdout) == 64 and b"output limit" in result.stderr
print("PASS excessive output is bounded and reported as failure")

result, _ = run("import subprocess; subprocess.run(['bash', '-c', '(sleep 20 &) | head -c 4194304'])", timeout=0.25)
assert result.returncode == 124 and b"timed out" in result.stderr
print("PASS inherited pipe inside a helper cannot stall the queue indefinitely")
