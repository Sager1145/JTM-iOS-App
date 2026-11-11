"""Tests for ios/tools/build-shinkansen-patterns.py.

SAMPLE DATA ONLY: the rail package, through record, base records and source file
here are synthetic (stations 甲..辛, numbers 90xx). They say nothing about real
trains. The real bundled file is also run, to prove the validator passes on it
today and the generator leaves it byte-for-byte alone with no source files.
"""
import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent
ROOT = TOOLS.parent.parent


def load():
    spec = importlib.util.spec_from_file_location("build_shinkansen_patterns", TOOLS / "build-shinkansen-patterns.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


B = load()
NAMES = "甲乙丙丁戊己庚辛"


def ref(i):
    return {"name": NAMES[i - 1], "sourceCode": f"S0{i}"}


def station(i, code=None):
    return [code or f"S0{i}", NAMES[i - 1], 0.0, 0.0, "x", 1]


PACKAGE = {"lines": [
    {"id": "east", "name": "サンプル東新幹線", "kind": "shinkansen", "stations": [station(i) for i in range(1, 6)]},
    {"id": "west", "name": "サンプル西新幹線", "kind": "shinkansen", "stations": [station(i) for i in range(5, 9)]},
    # A conventional line with same-name stations (different identities).
    {"id": "conv", "name": "サンプル在来線", "kind": "conventional",
     "stations": [station(1, "C01"), station(2, "C02")]},
]}
THROUGH = {"patterns": [{"id": "t", "legs": [
    {"lineID": "east", "fromStationCode": "S01", "toStationCode": "S05"},
    {"lineID": "west", "fromStationCode": "S05", "toStationCode": "S08"}]}]}


def base_records():
    common = {"company": "SAMPLE", "label": "甲〜辛", "origin": "甲", "destination": "辛", "via": [],
              "lines": ["サンプル東新幹線", "サンプル西新幹線"], "validFrom": "2030-01-01", "validUntil": None}
    return [
        {"patternId": "sample-x-all", "serviceId": "sample-x", "name": "サンプル", **common,
         "stops": [ref(i) for i in (1, 3, 6, 8)], "optionalStops": [ref(i) for i in (2, 4, 5, 7)]},
        {"patternId": "sample-all-all", "serviceId": "sample-all", "name": "サンプル各停", **common,
         "allStations": True, "stops": [ref(i) for i in range(1, 9)], "optionalStops": []},
    ]


SAMPLE_SOURCE = json.loads((HERE / "fixtures" / "shinkansen-sample.source.json").read_text(encoding="utf-8"))


class Case:
    """A temp dir holding package, through, bundled records and source files."""

    def __init__(self, test, records=None, sources=None, package=None):
        self.dir = Path(tempfile.mkdtemp(prefix="shinkansen-test-"))
        test.addCleanup(lambda: __import__("shutil").rmtree(self.dir, ignore_errors=True))
        self.patterns = self.dir / "patterns.json"
        self.package = self.dir / "package.json"
        self.through = self.dir / "through.json"
        self.sources = self.dir / "sources"
        self.sources.mkdir()
        self.patterns.write_text(B.serialize(records if records is not None else base_records()), encoding="utf-8")
        self.package.write_text(json.dumps(package or PACKAGE, ensure_ascii=False), encoding="utf-8")
        self.through.write_text(json.dumps(THROUGH, ensure_ascii=False), encoding="utf-8")
        for index, source in enumerate(sources if sources is not None else []):
            (self.sources / f"{index:02d}.json").write_text(json.dumps(source, ensure_ascii=False), encoding="utf-8")

    def analyse(self, check=True):
        return B.analyse(self.patterns, self.package, self.through, self.sources, check)

    def rules(self, check=True):
        findings = self.analyse(check)[0]
        return {r for r, _, _ in findings.errors}, findings


def mutated_source(fn):
    source = copy.deepcopy(SAMPLE_SOURCE)
    fn(source)
    return source


def pattern(source, pid):
    return next(p for p in source["services"][0]["patterns"] if p["id"] == pid)


class RealBundledFile(unittest.TestCase):
    def test_validator_passes_on_real_file_and_generator_changes_nothing(self):
        raw = B.PATTERNS.read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory() as tmp:
            empty = Path(tmp)
            findings, _, new_text, original = B.analyse(B.PATTERNS, B.PACKAGE, B.THROUGH, empty, True)
        self.assertEqual(findings.errors, [], findings.errors)
        self.assertEqual(new_text, raw, "generator must not change a file with no sources")
        self.assertEqual(findings.checked, 34, "every Shinkansen base record is resolved to a corridor")
        # Today's real data also passes the strict base-data rules.
        self.assertEqual(findings.base, [], findings.base)


class GeneratorOutput(unittest.TestCase):
    def test_sample_builds_the_variants_block(self):
        case = Case(self, sources=[SAMPLE_SOURCE])
        findings, generated, text, raw = case.analyse(check=False)
        self.assertEqual(findings.errors, [])
        base = generated[0]
        block = base["variants"]
        self.assertEqual(block["schema"], 1)
        self.assertEqual(block["order"], [f"S0{i}" for i in range(1, 9)])
        (revision,) = block["revisions"]
        self.assertEqual(revision["status"], "unverified")
        self.assertIn("SAMPLE publisher", revision["citation"])
        patterns = {p["id"]: p for p in revision["patterns"]}
        self.assertEqual(patterns["a"]["calls"], ["S04"])
        self.assertNotIn("from", patterns["a"])
        self.assertNotIn("to", patterns["a"])
        self.assertEqual(patterns["b"]["to"], "S06")
        self.assertEqual(patterns["b"]["calls"], ["S02"])
        # The range is stored as explicit numbers, not as shorthand.
        self.assertEqual(patterns["a"]["trains"][0]["numbers"], [9001, 9003, 9004, 9005])
        self.assertEqual(patterns["c"]["trains"][0]["runs"], "weekdays")
        self.assertNotIn("variants", generated[1])
        self.assertEqual(rules_of(findings), set())

    def test_deterministic_and_check_passes_after_write(self):
        case = Case(self, sources=[SAMPLE_SOURCE])
        out = __import__("io").StringIO()
        self.assertEqual(B.run(case.patterns, case.package, case.through, case.sources, False, False, out), 0)
        written = case.patterns.read_text(encoding="utf-8")
        again = case.analyse(check=False)[2]
        self.assertEqual(written, again, "same inputs, same bytes")
        rules, findings = case.rules(check=True)
        self.assertEqual(rules, set(), findings.errors)

    def test_hand_edited_or_stale_variants_fail_check(self):
        case = Case(self, sources=[SAMPLE_SOURCE])
        B.run(case.patterns, case.package, case.through, case.sources, False, False, __import__("io").StringIO())
        records = json.loads(case.patterns.read_text(encoding="utf-8"))
        records[0]["variants"]["revisions"][0]["patterns"][0]["trains"][0]["numbers"].append(9099)
        case.patterns.write_text(B.serialize(records), encoding="utf-8")
        self.assertIn("bundledOutOfDate", case.rules()[0])
        # Variants with no source files at all are refused too.
        orphan = Case(self, records=records)
        self.assertIn("variantsWithoutSource", orphan.rules()[0])

    def test_two_revisions_are_both_kept_in_date_order(self):
        later = mutated_source(lambda s: s.update(revision="2031-03-01", validFrom="2031-03-01", validUntil=None))
        case = Case(self, sources=[later, SAMPLE_SOURCE])
        generated = case.analyse(check=False)[1]
        self.assertEqual([r["revision"] for r in generated[0]["variants"]["revisions"]], ["2030-03-01", "2031-03-01"])
        self.assertEqual(case.rules(check=False)[0], set())


def rules_of(findings):
    return {r for r, _, _ in findings.errors}


class SourceRulesRefused(unittest.TestCase):
    def refused(self, expected, fn=None, source=None, records=None, extra=None):
        src = source if source is not None else mutated_source(fn or (lambda s: None))
        case = Case(self, records=records, sources=[src] + (extra or []))
        rules, findings = case.rules(check=False)
        self.assertIn(expected, rules, findings.errors)
        return rules

    def test_stop_not_on_corridor(self):
        self.refused("stopNotInCorridor", lambda s: pattern(s, "a")["stops"].__setitem__(1, "壬"))

    def test_same_name_conventional_station_is_not_the_shinkansen_station(self):
        # 甲 exists on the conventional line as C01; only the Shinkansen row's S01 is in the corridor,
        # so a bundled stop carrying C01 is flagged by the base-data rule.
        records = base_records()
        records[0]["stops"][0] = {"name": "甲", "sourceCode": "C01"}
        case = Case(self, records=records)
        findings = case.analyse()[0]
        self.assertTrue(any(r == "stopNotOnShinkansenLine" for r, _, _ in findings.base), findings.base)
        self.assertEqual(findings.errors, [])  # guard mode: not failing yet
        out = __import__("io").StringIO()
        self.assertEqual(B.run(case.patterns, case.package, case.through, case.sources, True, False, out), 0)
        self.assertEqual(B.run(case.patterns, case.package, case.through, case.sources, True, True, out), 1)

    def test_order_must_be_monotonic(self):
        self.refused("stopsNotMonotonic", lambda s: pattern(s, "a")["stops"].reverse())

    def test_always_served_stop_may_not_be_left_out(self):
        self.refused("alwaysServedOmitted", lambda s: pattern(s, "a")["stops"].remove("丙"))

    def test_call_must_be_an_optional_stop_of_the_record(self):
        records = base_records()
        records[0]["optionalStops"] = [ref(i) for i in (2, 4, 7)]  # 戊 no longer optional
        self.refused("callNotOptional", lambda s: None, records=records,
                     source=mutated_source(lambda s: None))

    def test_citation_status_and_verified_requirements(self):
        self.refused("missingCitation", lambda s: s["source"].pop("publisher"))
        self.refused("missingStatus", lambda s: s.update(status="probably"))
        self.refused("verifiedWithoutOfficialSource", lambda s: s.update(status="verified", verifiedBy="B"))
        def official(s):
            s["status"] = "verified"
            s["source"]["type"] = "operator_timetable"
        self.refused("verifiedWithoutSecondReader", official)
        def full(s):
            official(s)
            s["verifiedBy"] = "second reader"
        case = Case(self, sources=[mutated_source(full)])
        self.assertEqual(case.rules(check=False)[0], set())

    def test_dates(self):
        self.refused("invalidDate", lambda s: s.update(validFrom="2030-02-30"))
        self.refused("invalidDate", lambda s: s.update(validUntil="2030-01-01"))
        self.refused("invalidDate", lambda s: s.update(checkedOn="soon"))

    def test_revisions_must_not_overlap(self):
        overlapping = mutated_source(lambda s: s.update(revision="2030-09-01", validFrom="2030-09-01", validUntil=None))
        # Same numbers in overlapping revisions are also a number conflict.
        rules = self.refused("revisionOverlap", source=SAMPLE_SOURCE, extra=[overlapping])
        self.assertIn("numberInTwoPatterns", rules)

    def test_open_ended_revision_must_be_last(self):
        first = mutated_source(lambda s: s.update(validUntil=None))
        second = mutated_source(lambda s: s.update(revision="2031-03-01", validFrom="2031-03-01", validUntil=None))
        self.refused("openEndedRevisionNotLast", source=first, extra=[second])

    def test_number_forms(self):
        self.refused("badNumber", lambda s: pattern(s, "a")["trains"][0].update(numbers=["9005-9003"]))
        self.refused("badNumber", lambda s: pattern(s, "a")["trains"][0].update(numbers=["odd"]))
        self.refused("badNumber", lambda s: pattern(s, "a")["trains"][0].update(numbers=["9001-99999"]))
        self.refused("duplicateNumber", lambda s: pattern(s, "a")["trains"][0].update(numbers=[9001, "9001-9002"]))
        self.refused("nonPositiveNumber", lambda s: pattern(s, "a")["trains"][0].update(numbers=[0]))
        self.refused("emptyNumbers", lambda s: pattern(s, "a")["trains"][0].update(numbers=[]))
        self.refused("badDirection", lambda s: pattern(s, "a")["trains"][0].update(direction="north"))
        self.refused("badRuns", lambda s: pattern(s, "a")["trains"][0].update(runs="sometimes"))

    def test_same_number_in_two_patterns_on_overlapping_days(self):
        self.refused("numberInTwoPatterns", lambda s: pattern(s, "b")["trains"][0].update(numbers=[9001]))
        # Daily and weekday trains overlap on weekdays.
        self.refused("numberInTwoPatterns", lambda s: pattern(s, "d")["trains"][0].update(runs="daily"))

    def test_same_number_on_provably_different_days_is_allowed(self):
        # 9021 weekdays vs holidays is already in the sample and passes.
        case = Case(self, sources=[SAMPLE_SOURCE])
        self.assertEqual(case.rules(check=False)[0], set())
        # Disjoint seasonal windows, and different revisions, are allowed too.
        def seasonal(s):
            pattern(s, "a")["trains"][0].update(validFrom="2030-03-01", validUntil="2030-09-01")
            pattern(s, "b")["trains"][0].update(numbers=[9001], validFrom="2030-09-01", validUntil="2030-10-01")
        case = Case(self, sources=[mutated_source(seasonal)])
        self.assertEqual(case.rules(check=False)[0], set())
        later = mutated_source(lambda s: s.update(revision="2031-03-01", validFrom="2031-03-01", validUntil=None))
        case = Case(self, sources=[SAMPLE_SOURCE, later])
        self.assertEqual(case.rules(check=False)[0], set())

    def test_group_window_must_lie_inside_the_revision(self):
        def too_early(s):
            pattern(s, "a")["trains"][0].update(validFrom="2029-01-01")
        self.refused("groupOutsideRevision", too_early)
        self.refused("groupOutsideRevision", lambda s: pattern(s, "a")["trains"][0].update(validUntil="2032-01-01"))

    def test_pattern_ids_unique_and_base_record_known(self):
        self.refused("duplicatePatternID", lambda s: pattern(s, "b").update(id="a"))
        self.refused("unknownBaseRecord", lambda s: s["services"][0].update(pattern="no-such-record"))

    def test_parity_convention_is_a_warning_never_an_error(self):
        # 9004 is a down train (even): breaks the convention, must stay a warning and still pass.
        case = Case(self, sources=[SAMPLE_SOURCE])
        findings = case.analyse(check=False)[0]
        self.assertEqual(findings.errors, [])
        self.assertTrue(any(r == "parityConvention" for r, _, _ in findings.warnings))
        out = __import__("io").StringIO()
        self.assertEqual(B.run(case.patterns, case.package, case.through, case.sources, False, True, out), 0)
        self.assertEqual(B.run(case.patterns, case.package, case.through, case.sources, True, True, out), 0)

    def test_coupled_partner_must_exist(self):
        def couple(service):
            return lambda s: pattern(s, "a").update(coupled={"service": service, "from": "S01", "to": "S03"})
        self.refused("coupledPartnerMissing", couple("sample-nowhere"))
        case = Case(self, sources=[mutated_source(couple("sample-all"))])
        findings = case.analyse(check=False)[0]
        self.assertEqual(findings.errors, [])
        self.assertTrue(any(r == "coupledNotReciprocal" for r, _, _ in findings.warnings))

    def test_all_stations_rules(self):
        records = base_records()
        records[1]["stops"].pop(4)
        case = Case(self, records=records)
        self.assertIn("allStationsIncomplete", case.rules()[0])
        records = base_records()
        records[1]["optionalStops"] = [ref(1)]
        self.assertIn("allStationsWithOptionalStops", Case(self, records=records).rules()[0])
        records = base_records()
        records[1]["allStations"] = "yes"
        self.assertIn("allStationsNotBoolean", Case(self, records=records).rules()[0])

    def test_order_must_match_stops_and_corridor(self):
        case = Case(self, sources=[SAMPLE_SOURCE])
        B.run(case.patterns, case.package, case.through, case.sources, False, False, __import__("io").StringIO())
        records = json.loads(case.patterns.read_text(encoding="utf-8"))
        records[0]["variants"]["order"] = ["S01", "S03", "S02", "S04", "S05", "S06", "S07", "S08"]
        orphan = Case(self, records=records)
        self.assertIn("orderMismatch", orphan.rules()[0])
        records[0]["variants"]["order"] = ["S01"]
        self.assertIn("orderMismatch", Case(self, records=records).rules()[0])

    def test_unresolvable_corridor_is_an_error_for_variant_records(self):
        records = base_records()
        records[0]["lines"] = ["サンプル幻新幹線"]
        case = Case(self, records=records, sources=[SAMPLE_SOURCE])
        self.assertIn("corridorUnresolved", case.rules(check=False)[0])

    def test_no_sources_changes_nothing(self):
        case = Case(self)
        findings, _, text, raw = case.analyse(check=False)
        self.assertEqual((findings.errors, text), ([], raw))


if __name__ == "__main__":
    unittest.main()
