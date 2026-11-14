#!/usr/bin/python3
"""Format modified, staged, and untracked Swift files after Codex edits."""

import os
from pathlib import Path
import subprocess
import sys


def main():
    # Drain the hook payload; tool arguments aren't executed or parsed as paths.
    sys.stdin.buffer.read()
    root = Path(__file__).resolve().parents[2]
    try:
        changed = subprocess.check_output(
            ["git", "diff", "--name-only", "--diff-filter=ACMR", "-z", "HEAD", "--", "*.swift"],
            cwd=root,
        )
        untracked = subprocess.check_output(
            ["git", "ls-files", "--others", "--exclude-standard", "-z", "--", "*.swift"],
            cwd=root,
        )
        candidates = sorted(set((changed + untracked).split(b"\0")) - {b""})
        files = [root / os.fsdecode(name) for name in candidates]
        files = [str(path) for path in files if path.is_file() and not path.is_symlink()]
        if files:
            subprocess.run(
                [
                    "xcrun", "swift-format", "format", "--in-place",
                    "--configuration", str(root / ".swift-format"), *files,
                ],
                cwd=root,
                stdout=sys.stderr,
                check=True,
            )
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"Swift formatting failed: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
