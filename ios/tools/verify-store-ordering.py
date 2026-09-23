#!/usr/bin/env python3
"""Compile and run isolated native persistence checks.

Usage: DEVELOPER_DIR=... python3 ios/tools/verify-store-ordering.py <SwiftPM scratch>

The supplied scratch must contain libRailCore.a from a RailKit build. Generated
sources, module caches, executables, and the fake Application Support directory
all stay below that scratch path.
"""

from pathlib import Path
import os
import subprocess
import sys
import tempfile


root = Path(__file__).resolve().parents[2]
scratch = Path(sys.argv[1]).resolve()
harnesses = root / "ios/tools/persistence-harness"

libraries = sorted(scratch.rglob("libRailCore.a"))
if not libraries:
    raise SystemExit("Build RailKit in the supplied scratch directory first.")
rail_core = libraries[0]
products = rail_core.parent

sdk = subprocess.check_output(
    ["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True
).strip()
module_cache = scratch / "persistence-module-cache"
module_cache.mkdir(parents=True, exist_ok=True)


def compile_and_run(name: str, sources: list[Path], arguments: list[str] = [], env=None):
    executable = generated / name
    command = [
        "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
        "-sdk", sdk, "-module-cache-path", str(module_cache),
        "-I", str(products), *(str(source) for source in sources),
        str(rail_core), "-o", str(executable),
    ]
    subprocess.run(command, check=True)
    subprocess.run([str(executable), *arguments], check=True, env=env)


with tempfile.TemporaryDirectory(prefix="persistence-harness-", dir=scratch) as temporary:
    generated = Path(temporary)
    ride_library = (root / "ios/RailMap/RideLibrary.swift").read_text()
    merged_store = (root / "ios/RailMap/MergedStore.swift").read_text()

    # Compile the production RideLibrary definition unchanged. Its real
    # filesystem actor is replaced by a deterministic collaborator that can
    # suspend and fail writes on command.
    queue_source = ride_library.split("actor RideStorage {", 1)[0]
    queue_source += merged_store.split("    /// Every train with its region", 1)[0] + "}\n"
    queue_production = generated / "QueueProduction.swift"
    queue_production.write_text(queue_source)
    compile_and_run(
        "queue-checks",
        [queue_production, harnesses / "QueueChecks.swift"],
        [str(root)],
    )

    # Compile the complete production RideLibrary, RideStorage, and
    # MergedStore. CFFIXED_USER_HOME moves Foundation's user-domain Application
    # Support into a fresh home so these checks cannot touch real journeys.
    disk_production = generated / "DiskProduction.swift"
    disk_production.write_text(ride_library + "\n" + merged_store)
    fake_home = generated / "home"
    fake_home.mkdir()
    disk_environment = os.environ.copy()
    disk_environment["CFFIXED_USER_HOME"] = str(fake_home)
    compile_and_run(
        "disk-checks",
        [disk_production, harnesses / "DiskChecks.swift"],
        [str(fake_home)],
        disk_environment,
    )

    # Compile the production mutation methods and JourneyEditing edge, with
    # display/import-only sections omitted. Generated test seams seed the
    # working set and import lock; the mutations and persistence decisions are
    # copied verbatim from production.
    itinerary = (root / "ios/RailMap/ItineraryStore.swift").read_text()
    itinerary = itinerary.replace("import RailPresentation\n", "")
    itinerary_prefix = itinerary.split("    /// One import's per-journey position", 1)[0]
    mutate = itinerary.split("    private func mutate(", 1)[1]
    mutate = "    private func mutate(" + mutate.split("    /// The reader's own rides", 1)[0]
    test_seams = r'''
    private(set) var isImporting = false

    init(testStore: TrainStore?) {
        store = testStore
    }

    func setImportingForTest(_ value: Bool) {
        isImporting = value
    }

    private func publishWorkingSet(_ next: TrainStore) {
        store = next
    }

    private func regroup(_ store: TrainStore, reassertingSelection: Bool = false) {}
}
'''
    editor_production = generated / "EditorProduction.swift"
    content_view = (root / "ios/RailMap/ContentView.swift").read_text()
    save_edit_start = "            onSaveEdit: { edited, originalID in\n"
    save_edit_end = "            },\n            onSaveDetail:"
    if content_view.count(save_edit_start) != 1 or content_view.count(save_edit_end) != 1:
        raise SystemExit("ContentView onSaveEdit closure boundary changed; update the harness slice.")
    save_edit_body = content_view.split(save_edit_start, 1)[1].split(save_edit_end, 1)[0]
    content_view_helper = """
@MainActor
func runContentViewSaveEdit(
    editing: JourneyEditing,
    sheet: inout String?,
    edited: Train,
    originalID: String
) {
""" + save_edit_body + "\n}\n"
    editor_production.write_text(
        itinerary_prefix + mutate + test_seams
        + (root / "ios/RailMap/JourneyEditing.swift").read_text()
        + content_view_helper
    )
    compile_and_run(
        "editor-checks",
        [editor_production, harnesses / "EditorChecks.swift"],
    )
