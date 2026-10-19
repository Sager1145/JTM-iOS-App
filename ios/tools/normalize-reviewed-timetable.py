#!/usr/bin/env python3
"""Stage one reviewed timetable from a declarative JSON profile.

The profile is data only: dates, sources, the source-pinned candidate
(stops, clocks, seats, and consist), station aliases, and forced N02 codes.
It is loaded with json.loads and never executed. Japan station directory
is read once per invocation. Files are written only with --write.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import reviewed_timetable_staging as staging

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BASE = ROOT / "app/data/train-service-history"
FAMILY = "jr_east_coupled_columns"
WEEKDAYS = (
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
)
PROFILE_KEYS = {
    "family", "suffix", "candidate", "day", "next_day", "source_id", "url",
    "service", "station_name_aliases", "forced_station_codes", "weekdays",
    "pinned", "copy",
}
COPY_KEYS = {
    "edition_prefix", "public_number", "coupling_note", "incomplete_note",
    "identity_note", "partial_stops_note", "partial_times_note", "title",
    "summary", "relations",
}


def load_profile(path):
    """Load a profile and reject anything that is not the declarative schema."""
    profile = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(profile, dict):
        raise ValueError("Profile must be a JSON object")
    unknown = set(profile) - PROFILE_KEYS
    if unknown:
        raise ValueError(f"Profile has unknown keys: {sorted(unknown)}")
    missing = PROFILE_KEYS - set(profile)
    if missing:
        raise ValueError(f"Profile is missing keys: {sorted(missing)}")
    if profile["family"] != FAMILY:
        raise ValueError(f"Unsupported profile family: {profile['family']}")
    if tuple(profile["weekdays"]) != WEEKDAYS:
        raise ValueError("Reviewed weekday set changed")
    copy = profile["copy"]
    if not isinstance(copy, dict) or set(copy) != COPY_KEYS:
        raise ValueError("Profile copy keys changed")
    if not isinstance(copy["relations"], list):
        raise ValueError("Coupling relations must be a list")
    aliases = profile["station_name_aliases"]
    forced = profile["forced_station_codes"]
    if not isinstance(aliases, dict) or not all(
            isinstance(key, str) and isinstance(value, str) for key, value in aliases.items()):
        raise ValueError("Station aliases must be a string map")
    if not isinstance(forced, dict) or not forced:
        raise ValueError("Forced station codes are required")
    for name, codes in forced.items():
        if not isinstance(name, str) or not isinstance(codes, list) or not codes:
            raise ValueError(f"Forced codes for {name} must be a non-empty list")
        if not all(isinstance(code, str) and code for code in codes):
            raise ValueError(f"Forced codes for {name} must be strings")
    pinned = profile["pinned"]
    if not isinstance(pinned, dict):
        raise ValueError("Pinned candidate must be an object")
    if (pinned.get("service_date"), pinned.get("source_id"), pinned.get("source_url")) != (
            profile["day"], profile["source_id"], profile["url"]):
        raise ValueError("Profile date or source does not match the pinned candidate")
    for label in ("suffix", "candidate", "day", "next_day", "source_id", "url", "service"):
        if not isinstance(profile[label], str) or not profile[label]:
            raise ValueError(f"Profile {label} must be a non-empty string")
    return profile


def forced_codes(profile):
    return {name: set(codes) for name, codes in profile["forced_station_codes"].items()}


def stage_profile(profile, *, root, base, write, candidate_path=None):
    """Validate one profile and write its staging files only when requested.

    The Japan station directory is loaded once and reused for station lookup.
    """
    package = staging.load_japan_station_directory(root)
    candidate = Path(candidate_path) if candidate_path is not None else base / profile["candidate"]
    return staging.stage_jr_east_coupled_columns(
        base=base,
        root=root,
        candidate_path=candidate,
        suffix=profile["suffix"],
        day=profile["day"],
        next_day=profile["next_day"],
        source_id=profile["source_id"],
        url=profile["url"],
        service=profile["service"],
        aliases=profile["station_name_aliases"],
        weekdays=tuple(profile["weekdays"]),
        pinned=profile["pinned"],
        copy=profile["copy"],
        forced_codes=forced_codes(profile),
        package=package,
        emit=write,
    )


def main(argv=None):
    parser = argparse.ArgumentParser(description="Stage a reviewed timetable from a JSON profile.")
    parser.add_argument("--profile", required=True, type=Path, help="Declarative JSON profile")
    parser.add_argument("--write", action="store_true", help="Write staging files into the dataset base")
    parser.add_argument("--base", type=Path, default=DEFAULT_BASE, help="Train-service-history base")
    parser.add_argument("--root", type=Path, default=ROOT, help="Repository root holding the station directory")
    args = parser.parse_args(argv)
    try:
        profile = load_profile(args.profile)
        outputs = stage_profile(profile, root=args.root, base=args.base, write=args.write)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    if not args.write:
        print(f"{profile['copy']['summary']} (dry-run, not written)")
        return 0
    return 0 if outputs is not None else 1


if __name__ == "__main__":
    sys.exit(main())
