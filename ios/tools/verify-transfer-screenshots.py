#!/usr/bin/env python3
"""Run the production macOS Vision OCR and TransferGuide parser on screenshots.

Usage:
  python3 ios/tools/verify-transfer-screenshots.py <RailKit scratch> <image> [<image> ...]

Image order is document order. JSON is written to stdout; build and OCR
progress is written to stderr. The RailKit scratch must already contain a
macOS RailCore build, for example from `swift test --scratch-path <scratch>`.
"""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Run production screenshot OCR and emit the parsed route as JSON."
    )
    result.add_argument("scratch", help="RailKit swift-test scratch directory")
    result.add_argument(
        "images", nargs="+", metavar="IMAGE",
        help="screenshot paths in top-to-bottom document order",
    )
    return result


def railcore_build(scratch: Path, arguments: argparse.ArgumentParser):
    if not scratch.is_dir():
        arguments.error(f"scratch directory does not exist: {scratch}")

    libraries = sorted(scratch.rglob("libRailCore.a"))
    for library in libraries:
        for modules in (library.parent, library.parent / "Modules"):
            if (modules / "RailCore.swiftmodule").exists():
                return modules, [library]

    module_directories = sorted(scratch.rglob("Modules/RailCore.swiftmodule"))
    for module in module_directories:
        modules = module.parent
        objects = sorted((modules.parent / "RailCore.build").glob("*.swift.o"))
        if objects:
            return modules, objects

    arguments.error(
        "RailCore build products are missing; run "
        f"`cd {ROOT / 'ios/RailKit'} && swift test --scratch-path {scratch}` first"
    )


def main() -> int:
    arguments = parser()
    options = arguments.parse_args()
    scratch = Path(options.scratch).expanduser().resolve()
    modules, objects = railcore_build(scratch, arguments)

    image_pairs = []
    for original in options.images:
        path = Path(original).expanduser().resolve()
        if not path.is_file():
            arguments.error(f"image does not exist or is not a regular file: {original}")
        image_pairs.extend((original, str(path)))

    with tempfile.TemporaryDirectory(prefix="jtm-transfer-screenshots-") as temporary:
        folder = Path(temporary)
        executable = folder / "verify-transfer-screenshots"
        sdk = subprocess.check_output(
            ["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True
        ).strip()
        environment = dict(
            os.environ, CLANG_MODULE_CACHE_PATH=str(folder / "ModuleCache")
        )
        compile_command = [
            "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
            "-sdk", sdk, "-module-cache-path", str(folder / "ModuleCache"),
            "-I", str(modules),
            str(ROOT / "ios/RailMap/RailSignpost.swift"),
            str(ROOT / "ios/RailMap/TransferGuideOCR.swift"),
            str(ROOT / "ios/tools/verify-transfer-screenshots.swift"),
            *map(str, objects),
            "-framework", "Vision", "-framework", "ImageIO",
            "-o", str(executable),
        ]
        compiled = subprocess.run(compile_command, env=environment)
        if compiled.returncode:
            return compiled.returncode
        return subprocess.run([str(executable), *image_pairs]).returncode


if __name__ == "__main__":
    sys.exit(main())
