#!/usr/bin/env python3
"""Run a command under a pty and optionally answer one prompt."""

import os
import select
import signal
import sys


def main() -> None:
    answer = os.environ.get("PTY_ANSWER", "").encode()
    needle = os.environ.get("PTY_NEEDLE", "[y/N]").encode()
    cmd = sys.argv[1:]
    if not cmd:
        sys.stderr.write("usage: pty_run.py command [args...]\n")
        sys.exit(2)
    pid, fd = os.forkpty()
    if pid == 0:
        os.execvp(cmd[0], cmd)
    chunks: list[bytes] = []
    sent = False
    while True:
        readable, _, _ = select.select([fd], [], [], 20)
        if not readable:
            break
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        chunks.append(data)
        if answer and not sent and needle in b"".join(chunks):
            os.write(fd, answer)
            sent = True
    try:
        waited, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        waited, status = pid, 0
    if waited == 0:
        os.kill(pid, signal.SIGKILL)
        _, status = os.waitpid(pid, 0)
    sys.stdout.buffer.write(b"".join(chunks))
    sys.exit(os.waitstatus_to_exitcode(status))


if __name__ == "__main__":
    main()
