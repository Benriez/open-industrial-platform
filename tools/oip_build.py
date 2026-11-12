#!/usr/bin/env python3
"""A build that does not leave its children behind.

A build that times out must not leave an orphaned `xcodebuild` behind: the
orphan holds the lock of the build directory, and the **next** build waits for
it — for hours, without a word. The rehearsals of the release build the macOS
bundle and the archive of the distribution, and a machine with a stale build
lock measures a build that never finishes.

Every long build of the repository therefore runs in its own **process group**,
and the whole group is stopped when the build is stopped: the parent, the
`xcodebuild`, and every child of it.

Usage (from a tool of the repository):

    import sys
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tools"))
    from oip_build import run
"""
import os
import pathlib
import signal
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))


def run(command, cwd=None, timeout=3600, env=None):
    """A command with its whole process group.

    The group is stopped when the command is stopped, and a timeout raises the
    same exception that `subprocess.run` raises — after the group is gone.
    """
    process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, env=env,
                               start_new_session=True)
    try:
        output, error = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        the_group = os.getpgid(process.pid)
        try:
            os.killpg(the_group, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            output, error = process.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(the_group, signal.SIGKILL)
            except ProcessLookupError:
                pass
            output, error = process.communicate()
        raise
    return {"the_command": command, "the_code": process.returncode,
            "the_output": (output or "").strip(), "the_error": (error or "").strip()}
