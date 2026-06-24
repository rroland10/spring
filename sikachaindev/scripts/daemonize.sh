#!/usr/bin/env bash
# Start a command detached from the current shell (macOS-safe; no setsid required).
#
# Usage:
#   PID=$(bash scripts/daemonize.sh /path/to.log /path/to/binary --arg1 --arg2)
set -euo pipefail

LOG="${1:?log file required}"
shift

python3 - "$LOG" "$@" <<'PY'
import subprocess
import sys

log_path, *cmd = sys.argv[1:]
if not cmd:
    sys.exit("daemonize: command required")

with open(log_path, "a", buffering=1) as logf:
    proc = subprocess.Popen(
        cmd,
        stdout=logf,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        close_fds=True,
    )
print(proc.pid)
PY
