#!/usr/bin/env python3
"""Reproduce reviewed evidence from the retained official source snapshots."""
import argparse
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
CHECKERS = (
    "verify-na-station-english.py",
    "verify-tw-station-english.py",
    "verify-tw-afr-transfer-station-english.py",
    "verify-kr-station-english.py",
    "verify-jp-station-english.py",
    "verify-jp-private-station-english.py",
    "verify-jp-east-station-english.py",
    "verify-jp-west-station-english.py",
    "verify-tw-afr-station-english.py",
    "verify-jp-nankai-station-english.py",
    "verify-jp-fukuoka-station-english.py",
    "verify-jp-shikoku-station-english.py",
    "verify-next-official-station-english.py",
    "verify-kr-second-pass-station-english.py",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rebuild", action="store_true", help="regenerate evidence offline before rebuilding the unified catalog")
    args = parser.parse_args()
    for script in CHECKERS:
        subprocess.run([sys.executable, str(HERE / script), *([] if args.rebuild else ["--check"])], check=True)


if __name__ == "__main__":
    main()
