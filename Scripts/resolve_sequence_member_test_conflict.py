#!/usr/bin/env python3
"""Resolve SequenceSyntheticMemberLinkTests merge conflicts by keeping both sides."""
import re
import sys
from pathlib import Path

CONFLICT = re.compile(
    r"<<<<<<< HEAD\n(.*?)=======\n(.*?)>>>>>>> origin/master\n",
    re.DOTALL,
)


def resolve(path: Path) -> bool:
    text = path.read_text()
    new = CONFLICT.sub(lambda m: m.group(1) + m.group(2), text)
    if new == text:
        return False
    path.write_text(new)
    return True


if __name__ == "__main__":
    target = Path(sys.argv[1] if len(sys.argv) > 1 else
        "Tests/CompilerCoreTests/Sema/SequenceSyntheticMemberLinkTests.swift")
    if resolve(target):
        print(f"resolved conflicts in {target}")
    else:
        print(f"no conflicts in {target}")
        sys.exit(1)
