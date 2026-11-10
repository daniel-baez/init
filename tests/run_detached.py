#!/usr/bin/env python3
"""Run a command in a new session so /dev/tty cannot be opened.

Stdin is inherited. A test can pipe an answer and prove the script does
not take it from the pipe.
"""

import os
import sys


def main() -> None:
    if len(sys.argv) < 2:
        sys.stderr.write("usage: run_detached.py command [args...]\n")
        sys.exit(2)
    pid = os.fork()
    if pid == 0:
        os.setsid()
        os.execvp(sys.argv[1], sys.argv[1:])
    _, status = os.waitpid(pid, 0)
    sys.exit(os.waitstatus_to_exitcode(status))


if __name__ == "__main__":
    main()
