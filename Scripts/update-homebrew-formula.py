#!/usr/bin/env python3
"""Generate the tap formula from an uploaded release archive (no Git mutations)."""

import argparse
import hashlib
from pathlib import Path
import re


def version_tuple(value):
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", value):
        raise argparse.ArgumentTypeError("expected X.Y.Z without a prefix or leading zeroes")
    return tuple(map(int, value.split(".")))


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", type=version_tuple)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--output", type=Path, default=root / "Formula/xcprojgen.rb")
    args = parser.parse_args()
    version = ".".join(map(str, args.version))
    if args.archive.name != f"xcprojgen-{version}-macos-universal.tar.gz":
        parser.error("archive name must match the release version")
    checksum = hashlib.sha256(args.archive.read_bytes()).hexdigest()
    template = (root / "Formula/xcprojgen.rb.template").read_text()
    formula = template.replace("@VERSION@", version).replace("@SHA256@", checksum)

    if args.output.exists():
        previous = args.output.read_text()
        match = re.search(r'^  version "([^"]+)"$', previous, re.MULTILINE)
        if not match:
            parser.error("cannot determine the existing formula version")
        previous_version = version_tuple(match[1])
        if previous_version > args.version:
            print(f"Keeping newer formula version {match[1]}")
            return
        if previous_version == args.version and f'  sha256 "{checksum}"' not in previous:
            parser.error("refusing to change the checksum of an already released version")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(formula)
    print(f"Prepared {args.output} for {version}")


if __name__ == "__main__":
    main()
