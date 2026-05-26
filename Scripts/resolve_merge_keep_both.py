#!/usr/bin/env python3
"""Resolve origin/master merge conflicts by keeping both HEAD and master hunks."""
import re
import sys
from pathlib import Path

CONFLICT = re.compile(
    r"<<<<<<< HEAD\n(.*?)=======\n(.*?)>>>>>>> origin/master\n",
    re.DOTALL,
)
SKIP_DIRS = {".git", ".build", ".claude"}


def resolve_file(path: Path) -> bool:
    text = path.read_text()
    new = CONFLICT.sub(lambda m: m.group(1) + m.group(2), text)
    if new == text:
        return False
    path.write_text(new)
    return True


def resolve_tree(root: Path) -> list[Path]:
    fixed: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file() or any(part in SKIP_DIRS for part in path.parts):
            continue
        try:
            text = path.read_text()
        except (UnicodeDecodeError, OSError):
            continue
        if "<<<<<<< HEAD" not in text:
            continue
        if resolve_file(path):
            fixed.append(path)
    return fixed


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    fixed = resolve_tree(root)
    if not fixed:
        print("no conflicts found")
        sys.exit(1)
    for path in fixed:
        print(f"resolved {path}")
