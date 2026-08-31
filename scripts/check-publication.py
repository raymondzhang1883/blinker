#!/usr/bin/env python3
"""Check tracked publication files without executing the processor or assembler."""
import argparse
from pathlib import Path
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--identity-file", type=Path,
                    help="optional private text file with one identifier per line")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).split(b"\0")
patterns = {
    "email address": re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    "home directory": re.compile(rb"/(?:Users|home)/[^\s/]+"),
    "academic address": re.compile(rb"\b[a-zA-Z0-9.-]+\.edu\b"),
    "credential": re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----)"),
}
identifiers = []
if args.identity_file:
    try:
        identifiers = [line.strip().lower() for line in args.identity_file.read_bytes().splitlines()
                       if line.strip()]
    except OSError:
        sys.exit("Cannot read private identity file; path and contents withheld.")
    if not identifiers:
        sys.exit("Private identity file contains no identifiers.")

problems = []
count = 0
for raw in tracked:
    if not raw:
        continue
    relative = Path(raw.decode())
    path = root / relative
    count += 1
    forbidden = {".private", ".DS_Store", ".env", ".git"}
    if any(part in forbidden or part.startswith(".env.") for part in relative.parts):
        problems.append((str(relative), "forbidden publication path"))
        continue
    if path.is_symlink() or not path.is_file():
        problems.append((str(relative), "symlink or missing/non-regular file"))
        continue
    data = path.read_bytes()
    for category, pattern in patterns.items():
        if pattern.search(data):
            problems.append((str(relative), category))
    if any(token in data.lower() for token in identifiers):
        problems.append((str(relative), "private identifier"))

if not count:
    sys.exit("No tracked files; stage the intended publication files first.")
for path, category in problems:
    print(f"BLOCKED: {path}: {category} (value redacted)", file=sys.stderr)
if problems:
    sys.exit(1)
print(f"Publication scan: {count} tracked files; no configured privacy patterns found.")
if not identifiers:
    print("No private identity list supplied; only generic checks were applied.")
