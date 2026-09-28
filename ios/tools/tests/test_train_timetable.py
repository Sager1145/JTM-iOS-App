import json
from pathlib import Path
import shutil
import sqlite3
import sys
import tempfile
import unittest


TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parents[1]
sys.path.insert(0, str(TOOLS))

import train_timetable as timetable


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(timetable.canonical_json(row) + "\n" for row in rows), encoding="utf-8")


class TrainTimetablePipelineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.canonical = Path(self.temporary.name)
        shutil.copy(ROOT / "app/data/train-service-history/schema.sql", self.canonical / "schema.sql")
        manifest = json.loads((ROOT / "app/data/train-service-history/manifest.json").read_text(encoding="utf-8"))
        manifest.update({
            "as_of_date": "2026-01-04", "first_scope_date": "2026-01-01",
            "expected_coverage_scopes": [{"operator_scope": "test-scope", "valid_from": "2026-01-01", "valid_until": "2026-01-05"}],
        })
        (self.canonical / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        package = json.loads((ROOT / "app/public/rail/jp-2025.json").read_text(encoding="utf-8"))
        station_rows = []
        seen = set()
        for line in package["lines"]:
            for station in line.get("stations", []):
                if station[0] not in seen:
                    station_rows.append(station)
                    seen.add(station[0])
                if len(station_rows) == 3: break
            if len(station_rows) == 3: break
        self.station_a, self.station_b, self.station_c = station_rows
        self._seed()

    def tearDown(self):
        self.temporary.cleanup()

    def _seed(self):
        source = {"source_id": "source.test", "publisher": "Test Publisher", "title": "Test timetable", "source_type": "fixture", "url_or_locator": "fixture:test", "accessed_at": "2026-01-01", "license_status": "test_only", "redistribution_status": "test_only", "automated_extraction_allowed": False}
        write_jsonl(self.canonical / "sources/source-registry-test.jsonl", [source])
        write_jsonl(self.canonical / "normalized/operators-test.jsonl", [{"operator_id": "operator.test", "legal_name": "Operator Legal", "display_name": "Operator", "operator_type": "jr", "valid_from": "1987-04-01"}])
        write_jsonl(self.canonical / "normalized/services-test.jsonl", [{"service_id": "service.test", "canonical_name": "テスト", "service_class": "limited_express", "historical_generation": 1, "first_verified_date": "2026-01-01", "last_verified_date": "2026-01-03", "jr_scope": "jr"}])
        write_jsonl(self.canonical / "normalized/service-name-periods-test.jsonl", [{"service_id": "service.test", "name": "テスト", "language": "ja", "valid_from": "2026-01-01", "valid_until": "2026-01-04", "name_type": "official", "source_id": "source.test"}])
        write_jsonl(self.canonical / "normalized/timetable-versions-test.jsonl", [{"timetable_version_id": "version.test", "operator_scope": "test-scope", "effective_from": "2026-01-01", "effective_until": "2026-01-04", "edition_name": "fixture", "revision_type": "regular", "completeness": "partial", "source_ids": ["source.test"]}])
        write_jsonl(self.canonical / "normalized/calendars/test.jsonl", [{"calendar_id": "calendar.test", "monday": 1, "tuesday": 1, "wednesday": 1, "thursday": 1, "friday": 1, "saturday": 1, "sunday": 1, "valid_from": "2026-01-01", "valid_until": "2026-01-04", "holiday_policy": "none"}])
        write_jsonl(self.canonical / "normalized/calendar-exceptions/test.jsonl", [{"calendar_id": "calendar.test", "service_date": "2026-01-02", "exception_type": "remove", "reason": "fixture removal", "source_id": "source.test"}])
        write_jsonl(self.canonical / "normalized/station-identities-test.jsonl", [
            {"station_id": "station.a", "name_snapshot": self.station_a[1], "reference_kind": "current_n02", "current_source_code": self.station_a[0]},
            {"station_id": "station.b", "name_snapshot": self.station_b[1], "reference_kind": "current_n02", "current_source_code": self.station_b[0]},
        ])
        write_jsonl(self.canonical / "normalized/trips/test/seeds.jsonl", [{"trip_id": "trip.test", "timetable_version_id": "version.test", "service_id": "service.test", "calendar_id": "calendar.test", "train_number": "1001M", "public_number": "1", "origin_station_id": "station.a", "destination_station_id": "station.b", "direction": "down", "service_class": "limited_express"}])
        write_jsonl(self.canonical / "normalized/stop-times/test/seeds.jsonl", [
            {"trip_id": "trip.test", "stop_sequence": 0, "station_id": "station.a", "departure_time": "23:55", "call_type": "origin", "time_accuracy": "minute", "source_id": "source.test"},
            {"trip_id": "trip.test", "stop_sequence": 1, "station_id": "station.b", "arrival_time": "00:15", "day_offset": 1, "call_type": "destination", "time_accuracy": "minute", "source_id": "source.test"},
        ])
        write_jsonl(self.canonical / "normalized/trip-stop-time-overrides/test/seeds.jsonl", [{"trip_id": "trip.test", "service_date": "2026-01-01", "stop_sequence": 1, "arrival_override": "00:20", "source_id": "source.test"}])
        write_jsonl(self.canonical / "normalized/trip-operator-segments/test/seeds.jsonl", [{"trip_id": "trip.test", "from_sequence": 0, "to_sequence": 1, "operator_id": "operator.test"}])
        write_jsonl(self.canonical / "normalized/trip-lines/test/seeds.jsonl", [{"trip_id": "trip.test", "sequence": 0, "from_station_id": "station.a", "to_station_id": "station.b", "line_name": "Test Line", "operator_id": "operator.test", "source_id": "source.test", "confidence": "high"}])
        write_jsonl(self.canonical / "normalized/fact-completeness-test.jsonl", [
            {"entity_type": "trip", "entity_id": "trip.test", "dimension": "stops", "status": "verified", "confidence": "high"},
            {"entity_type": "trip", "entity_id": "trip.test", "dimension": "route_lines", "status": "partial", "confidence": "high"},
        ])
        write_jsonl(self.canonical / "normalized/fact-sources-test.jsonl", [
            {"entity_type": "trip", "entity_id": "trip.test", "field_name": "identity", "source_id": "source.test", "page_or_locator": "fixture", "confidence": "high", "verification_status": "verified"},
            {"entity_type": "trip", "entity_id": "trip.test", "field_name": "stops", "source_id": "source.test", "page_or_locator": "fixture", "confidence": "high", "verification_status": "verified"},
            {"entity_type": "trip", "entity_id": "trip.test", "field_name": "route_lines", "source_id": "source.test", "page_or_locator": "fixture", "confidence": "high", "verification_status": "verified"},
        ])

    def load(self):
        manifest = timetable.load_manifest(self.canonical)
        data, origins = timetable.load_dataset(self.canonical, manifest)
        return manifest, data, origins

    def test_service_day_materialization_preserves_after_midnight_time(self):
        _, data, origins = self.load()
        self.assertEqual([], timetable.validate_dataset(data, origins, timetable.load_manifest(self.canonical)))
        occurrence = timetable.materialize(data, "2026-01-01")[0]
        self.assertEqual("trip.test@2026-01-01", occurrence["occurrence_key"])
        self.assertEqual(23 * 3600 + 55 * 60, occurrence["stop_times"][0]["departure_seconds"])
        self.assertEqual(24 * 3600 + 20 * 60, occurrence["stop_times"][1]["arrival_seconds"])
        self.assertEqual("00:20", occurrence["stop_times"][1]["arrival_time"])
        self.assertEqual(1, occurrence["stop_times"][1]["arrival_day_offset"])
        self.assertEqual([], timetable.materialize(data, "2026-01-02"))

    def test_builder_is_byte_reproducible_and_creates_runtime_indexes(self):
        first = self.canonical / "first.sqlite"
        second = self.canonical / "second.sqlite"
        timetable.build_database(self.canonical, first)
        timetable.build_database(self.canonical, second)
        self.assertEqual(timetable.file_sha256(first), timetable.file_sha256(second))
        connection = sqlite3.connect(first)
        try:
            metadata = dict(connection.execute("SELECT key,value FROM metadata"))
            indexes = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='index'")}
            line_columns = {row[1] for row in connection.execute("PRAGMA table_info(trip_line_segments)")}
            stop_columns = {row[1] for row in connection.execute("PRAGMA table_info(stop_times)")}
            override_columns = {row[1] for row in connection.execute("PRAGMA table_info(trip_stop_time_overrides)")}
            seconds = connection.execute("SELECT departure_seconds FROM stop_times WHERE trip_id='trip.test' AND stop_sequence=0").fetchone()[0]
            override_offset = connection.execute("SELECT arrival_day_offset_override FROM trip_stop_time_overrides WHERE trip_id='trip.test'").fetchone()[0]
        finally:
            connection.close()
        self.assertEqual("Asia/Tokyo", metadata["timezone"])
        self.assertIn("idx_calendar_exceptions_date", indexes)
        self.assertIn("idx_stop_times_trip_sequence", indexes)
        self.assertIn("idx_line_segments_current_identity", indexes)
        self.assertIn("idx_line_segments_history_identity", indexes)
        self.assertTrue({"reference_kind", "current_n02_line_id", "rail_history_id"} <= line_columns)
        self.assertTrue({"arrival_day_offset", "departure_day_offset"} <= stop_columns)
        self.assertTrue({"arrival_day_offset_override", "departure_day_offset_override"} <= override_columns)
        self.assertEqual(86100, seconds)
        self.assertEqual(1, override_offset)

    def test_unknown_station_and_backwards_time_are_rejected(self):
        manifest, data, origins = self.load()
        data["station_identities"][0]["current_source_code"] = "invented"
        data["stop_times"][1]["arrival_time"] = "22:00"
        data["stop_times"][1]["day_offset"] = 0
        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertTrue(any("not in jp-2025" in error for error in errors))
        self.assertTrue(any("move backwards" in error for error in errors))

    def test_unverified_historical_holiday_rule_is_rejected(self):
        manifest, data, origins = self.load()
        data["calendars"][0]["holiday_policy"] = "treat_as_sunday"
        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertTrue(any("holiday calendar 2026 is not verified" in error for error in errors))

    def test_empty_verified_coverage_is_rejected(self):
        manifest, data, origins = self.load()
        data["coverage_declarations"].append({"coverage_id": "coverage.test", "operator_scope": "test-scope", "year": 2026, "dimension": "inventory", "status": "verified", "record_count": 0, "source_id": "source.test"})
        origins[("coverage_declarations", 0)] = "fixture:coverage"
        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertTrue(any("empty coverage cannot be verified" in error for error in errors))

    def test_verified_completeness_requires_field_level_source(self):
        manifest, data, origins = self.load()
        data["fact_sources"] = [row for row in data["fact_sources"] if row["field_name"] != "stops"]
        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertTrue(any("matching verified fact_source" in error for error in errors))

    def test_station_and_operator_must_cover_trip_operation_interval(self):
        manifest, data, origins = self.load()
        data["station_identities"][0]["valid_from"] = "2026-01-02"
        data["operators"][0]["valid_from"] = "2027-01-01"
        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertTrue(any("station station.a begins after" in error for error in errors))
        self.assertTrue(any("operator operator.test is not valid" in error for error in errors))
        self.assertTrue(any("line endpoint station station.a begins after" in error for error in errors))
        self.assertTrue(any("line operator operator.test is not valid" in error for error in errors))

    def test_total_service_time_is_bounded_below_72_hours(self):
        self.assertEqual(25 * 3600, timetable.service_seconds("01:00", 1, "fixture"))
        self.assertEqual(25 * 3600 + 3 * 60, timetable.service_seconds("25:03", 0, "fixture"))
        with self.assertRaises(timetable.DatasetError):
            timetable.service_seconds("25:03", 1, "fixture")
        with self.assertRaises(timetable.DatasetError):
            timetable.service_seconds("01:00", 3, "fixture")

    def test_arrival_and_departure_offsets_can_cross_midnight_at_one_stop(self):
        manifest, data, origins = self.load()
        data["station_identities"].append({
            "station_id": "station.c",
            "name_snapshot": self.station_c[1],
            "reference_kind": "current_n02",
            "current_source_code": self.station_c[0],
        })
        origins[("station_identities", 2)] = "fixture:station-c"
        data["stop_times"][0]["departure_time"] = "23:30"
        middle = data["stop_times"][1]
        middle.update({
            "arrival_time": "23:42",
            "departure_time": "00:30",
            "arrival_day_offset": 0,
            "departure_day_offset": 1,
            "call_type": "passenger_stop",
        })
        middle.pop("day_offset", None)
        data["stop_times"].append({
            "trip_id": "trip.test",
            "stop_sequence": 2,
            "station_id": "station.c",
            "arrival_time": "00:50",
            "arrival_day_offset": 1,
            "call_type": "destination",
            "time_accuracy": "minute",
            "source_id": "source.test",
        })
        origins[("stop_times", 2)] = "fixture:station-c-stop"
        data["trips"][0]["destination_station_id"] = "station.c"
        data["trip_operator_segments"][0]["to_sequence"] = 2
        data["trip_stop_time_overrides"] = []

        self.assertEqual([], timetable.validate_dataset(data, origins, manifest))
        stops = timetable.materialize(data, "2026-01-01")[0]["stop_times"]
        self.assertEqual(23 * 3600 + 42 * 60, stops[1]["arrival_seconds"])
        self.assertEqual(24 * 3600 + 30 * 60, stops[1]["departure_seconds"])
        self.assertEqual(24 * 3600 + 50 * 60, stops[2]["arrival_seconds"])

    def test_side_offset_requires_its_corresponding_clock(self):
        manifest, data, origins = self.load()
        data["stop_times"][0]["arrival_day_offset"] = 0
        data["trip_stop_time_overrides"][0]["departure_day_offset_override"] = 1
        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertTrue(any("arrival_day_offset requires arrival_time" in error for error in errors))
        self.assertTrue(any("departure_day_offset_override requires departure_override" in error for error in errors))

    def test_overlapping_duplicate_published_occurrence_is_rejected(self):
        manifest, data, origins = self.load()
        duplicate = dict(data["trips"][0], trip_id="trip.duplicate", train_number="1002M")
        data["trips"].append(duplicate)
        origins[("trips", 1)] = "fixture:duplicate-trip"
        for stop in list(data["stop_times"]):
            copy = dict(stop, trip_id="trip.duplicate")
            data["stop_times"].append(copy)
            origins[("stop_times", len(data["stop_times"]) - 1)] = "fixture:duplicate-stop"
        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertTrue(any("ambiguous duplicate" in error for error in errors))

    def test_number_and_operator_segments_must_be_bounded_and_cover_trip(self):
        manifest, data, origins = self.load()
        data["trip_operator_segments"][0]["from_sequence"] = 99
        data["trip_operator_segments"][0]["to_sequence"] = 100
        data["trip_number_segments"].append({"trip_id": "trip.test", "from_sequence": 99, "to_sequence": 100, "train_number": "1001M"})
        origins[("trip_number_segments", 0)] = "fixture:number-range"
        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertTrue(any("trip_operator_segments boundaries must reference" in error for error in errors))
        self.assertTrue(any("trip_operator_segments must cover" in error for error in errors))
        self.assertTrue(any("trip_number_segments boundaries must reference" in error for error in errors))
        self.assertTrue(any("trip_number_segments must cover" in error for error in errors))

    def test_invalid_calendar_exception_date_reports_without_crashing(self):
        manifest, data, origins = self.load()
        data["calendar_exceptions"][0]["service_date"] = "2026-99-99"
        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertTrue(any("invalid Gregorian date" in error for error in errors))

    def test_coverage_defaults_to_missing_and_never_complete_on_sparse_data(self):
        database, _, _ = timetable.build_database(self.canonical)
        report = timetable.coverage_report(self.canonical, database)
        self.assertFalse(report["coverageComplete"])
        self.assertGreater(report["missingCoverageCells"], 0)
        self.assertEqual(2, report["dailyOccurrencesRepresented"])

    def test_projection_keeps_legacy_fallback_and_marks_calendar_loss(self):
        legacy = self.canonical / "legacy.json"
        legacy.write_text(json.dumps([{"patternId": "legacy-test", "serviceId": "service.test", "name": "テスト", "company": "legacy", "label": "legacy", "origin": "A", "destination": "B", "stops": [], "optionalStops": [], "via": [], "lines": [], "validFrom": None, "validUntil": None, "completeness": {"stops": "missing", "lines": "missing", "validity": "missing"}, "confidence": "low", "source": "legacy"}]), encoding="utf-8")
        output = self.canonical / "projection.json"
        audit = self.canonical / "projection-audit.json"
        timetable.build_projection(self.canonical, legacy, output, audit)
        patterns = json.loads(output.read_text(encoding="utf-8"))
        canonical = next(row for row in patterns if row["_derivation"]["status"] == "canonical_trip_projection")
        fallback = next(row for row in patterns if row["_derivation"]["status"] == "legacy_unverified_fallback")
        self.assertEqual("Operator Legal", canonical["company"])
        self.assertEqual("partial", canonical["completeness"]["validity"])
        self.assertEqual("legacy-test", fallback["patternId"])
        self.assertFalse(json.loads(audit.read_text(encoding="utf-8"))["safeToReplaceBundledLegacyCatalog"])

    def test_history_alignment_uses_actual_days_and_exclusive_service_end(self):
        manifest, data, _ = self.load()
        data["station_identities"][0].update({
            "reference_kind": "historical_overlay",
            "rail_history_id": "history.station.a",
        })
        rail_history = {
            "revision": "fixture.1",
            "sections": [],
            "stations": [{
                "type": "Feature",
                "properties": {
                    "history_id": "history.station.a",
                    # This authoritative interval wins over legacy valid_to.
                    "service_validity": [None, "2026-01-02"],
                    "valid_to": "2027-01-01",
                },
                "geometry": None,
            }],
        }
        report = timetable.audit_history_alignment(data, manifest, rail_history)
        finding = next(row for row in report["findings"] if row["kind"] == "station")
        # The fixture operates Jan 1 and Jan 3; Jan 2 is explicitly removed.
        self.assertEqual(2, finding["occurrenceCount"])
        self.assertEqual(1, finding["alignedOccurrenceCount"])
        self.assertEqual(1, finding["invalidOccurrenceCount"])
        self.assertEqual(["2026-01-03"], finding["sampleInvalidServiceDates"])
        self.assertEqual("error", finding["status"])
        self.assertEqual("service_validity", finding["validitySource"])

    def test_history_alignment_keeps_cross_midnight_stop_on_original_service_day(self):
        manifest, data, _ = self.load()
        data["timetable_versions"][0]["effective_until"] = "2026-01-02"
        data["calendars"][0]["valid_until"] = "2026-01-02"
        data["station_identities"][1].update({
            "reference_kind": "historical_overlay",
            "rail_history_id": "history.station.b",
        })
        rail_history = {
            "revision": "fixture.1",
            "sections": [],
            "stations": [{
                "type": "Feature",
                "properties": {
                    "history_id": "history.station.b",
                    "service_validity": ["2026-01-01", "2026-01-02"],
                },
                "geometry": None,
            }],
        }
        report = timetable.audit_history_alignment(data, manifest, rail_history)
        finding = next(row for row in report["findings"] if row["kind"] == "station")
        self.assertEqual("aligned", finding["status"])
        self.assertEqual(1, finding["alignedOccurrenceCount"])
        self.assertIn("day_offset does not change", report["serviceDateSemantics"])

    def test_line_name_candidate_never_proves_history_alignment(self):
        manifest, data, _ = self.load()
        rail_history = {
            "revision": "fixture.1",
            "stations": [],
            "sections": [{
                "type": "Feature",
                "properties": {
                    "history_id": "history.line.candidate",
                    "N02_003": "Test Line",
                    "N02_004": "Operator",
                    "service_validity": ["2026-01-01", "2026-01-04"],
                },
                "geometry": None,
            }],
        }
        report = timetable.audit_history_alignment(data, manifest, rail_history)
        finding = next(row for row in report["findings"] if row["kind"] == "route")
        self.assertEqual("unverified", finding["status"])
        self.assertEqual("missing_explicit_route_identity", finding["reason"])
        self.assertEqual(["history.line.candidate"], finding["candidateHistoryIds"])
        self.assertFalse(report["complete"])

    def test_history_interval_legacy_key_presence_blocks_infrastructure_fallback(self):
        infrastructure = ["2010-01-01", "2011-01-01"]
        for legacy in (
            {"valid_from": None},
            {"valid_from": "", "valid_to": ""},
        ):
            with self.subTest(legacy=legacy):
                properties = dict(legacy, infrastructure_validity=infrastructure)
                start, end, source = timetable.rail_history_service_interval(properties)
                self.assertIsNone(start)
                self.assertIsNone(end)
                self.assertEqual("valid_from/valid_to", source)

    def test_verified_route_claim_requires_direct_dated_history_attestation(self):
        manifest, data, origins = self.load()
        segment = data["trip_line_segments"][0]
        segment.update({
            "reference_kind": "historical_overlay",
            "rail_history_id": "history.line.test",
        })
        route_completeness = next(
            row for row in data["fact_completeness"] if row["dimension"] == "route_lines")
        route_completeness["status"] = "verified"
        # Jan 1 and Jan 3 are the two actual occurrences. The gap on Jan 2 is
        # removed by the calendar exception, so two disjoint history periods
        # can still attest every real service day.
        rail_history = {
            "revision": "fixture.1",
            "stations": [],
            "sections": [
                {"properties": {
                    "history_id": "history.line.test",
                    "N02_003": "Test Line",
                    "N02_004": "Operator",
                    "service_validity": ["2026-01-01", "2026-01-02"],
                }},
                {"properties": {
                    "history_id": "history.line.test",
                    "N02_003": "Test Line",
                    "N02_004": "Operator",
                    "service_validity": ["2026-01-03", "2026-01-04"],
                }},
            ],
        }
        errors = timetable.validate_dataset(
            data, origins, manifest, rail_history=rail_history, current_package={"lines": []})
        self.assertFalse(any("route_lines verified requires" in error for error in errors), errors)
        verdict = timetable.route_attestations(
            data, manifest, rail_history=rail_history, current_package={"lines": []})["trip.test"]
        self.assertEqual("aligned", verdict["status"])
        self.assertTrue(verdict["canPublishRouteLines"])

        rail_history["sections"].pop()
        errors = timetable.validate_dataset(
            data, origins, manifest, rail_history=rail_history, current_package={"lines": []})
        self.assertTrue(any("route_lines verified requires" in error for error in errors))
        verdict = timetable.route_attestations(
            data, manifest, rail_history=rail_history, current_package={"lines": []})["trip.test"]
        self.assertEqual("error", verdict["status"])
        self.assertEqual(1, verdict["segments"][0]["invalidOccurrenceCount"])

    def test_current_n02_identity_without_snapshot_interval_stays_unverified(self):
        manifest, data, origins = self.load()
        segment = data["trip_line_segments"][0]
        segment.update({
            "reference_kind": "current_n02",
            "current_n02_line_id": "jp-test-line",
        })
        next(row for row in data["fact_completeness"]
             if row["dimension"] == "route_lines")["status"] = "verified"
        current_package = {"lines": [{
            "id": "jp-test-line",
            "name": "Test Line",
            "operator": "Operator",
            "stations": [self.station_a, self.station_b],
        }]}
        verdict = timetable.route_attestations(
            data, manifest, rail_history={"sections": [], "stations": []},
            current_package=current_package)["trip.test"]
        self.assertEqual("unverified", verdict["status"])
        self.assertEqual(
            "current_n02_snapshot_has_no_validity_interval",
            verdict["segments"][0]["reason"])
        self.assertTrue(verdict["segments"][0]["identityVerified"])
        errors = timetable.validate_dataset(
            data, origins, manifest, rail_history={"sections": [], "stations": []},
            current_package=current_package)
        self.assertTrue(any("route_lines verified requires" in error for error in errors))

    def test_partial_route_can_be_a_continuous_prefix_but_verified_must_cover_destination(self):
        manifest, data, origins = self.load()
        data["station_identities"].append({
            "station_id": "station.c",
            "name_snapshot": self.station_c[1],
            "reference_kind": "current_n02",
            "current_source_code": self.station_c[0],
        })
        origins[("station_identities", 2)] = "fixture:station-c"
        data["stop_times"][1]["call_type"] = "passenger_stop"
        data["stop_times"].append({
            "trip_id": "trip.test",
            "stop_sequence": 2,
            "station_id": "station.c",
            "arrival_time": "00:30",
            "day_offset": 1,
            "call_type": "destination",
            "time_accuracy": "minute",
            "source_id": "source.test",
        })
        origins[("stop_times", 2)] = "fixture:stop-c"
        data["trips"][0]["destination_station_id"] = "station.c"

        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertFalse(any("last segment does not end" in error for error in errors), errors)
        route_completeness = next(
            row for row in data["fact_completeness"] if row["dimension"] == "route_lines")
        route_completeness["status"] = "verified"
        errors = timetable.validate_dataset(data, origins, manifest)
        self.assertTrue(any("last segment does not end at trip destination" in error for error in errors))

    def test_explicit_route_identity_must_exist_even_for_partial_research(self):
        manifest, data, origins = self.load()
        segment = data["trip_line_segments"][0]
        segment.update({
            "reference_kind": "historical_overlay",
            "rail_history_id": "history.missing",
        })
        errors = timetable.validate_dataset(
            data, origins, manifest, rail_history={"sections": [], "stations": []},
            current_package={"lines": []})
        self.assertTrue(any("rail_history_section_not_found" in error for error in errors))

        segment.pop("rail_history_id")
        segment.update({
            "reference_kind": "current_n02",
            "current_n02_line_id": "current.missing",
        })
        errors = timetable.validate_dataset(
            data, origins, manifest, rail_history={"sections": [], "stations": []},
            current_package={"lines": []})
        self.assertTrue(any("current_n02_line_not_found" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
