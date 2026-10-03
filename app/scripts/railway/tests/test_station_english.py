"""Identity and provenance regressions for the all-region English catalog."""
import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "build-station-english.py"
spec = importlib.util.spec_from_file_location("all_station_english", SCRIPT)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def package(*lines):
    return {"version": "test", "lines": list(lines)}


def line(key, name="同名", en="Package Label"):
    return {"id": key, "operator": "Test Railway", "stations": [["test-group", name, 1, 2, en, 3]]}


class StationEnglishTests(unittest.TestCase):
    def test_official_package_marker_is_not_verification(self):
        result = builder.build_region("hk", package(line("first")), {"byCode": {}})
        row = result["byCode"]["test-group"]
        self.assertEqual(row["status"], "package_unverified")
        self.assertTrue(row["translationMayBeWrong"])

    def test_line_identity_wins_and_group_retains_both_labels(self):
        readings = {"byCode": {"test-group": {"en": "Wrong group label"},
            "first:test-group": {"en": "First Platform"},
            "second:test-group": {"en": "Second Platform"}}}
        result = builder.build_region("tw", package(line("first"), line("second")), readings)
        row = result["byCode"]["test-group"]
        self.assertEqual(row["enVariants"], ["First Platform", "Second Platform"])
        self.assertEqual(row["status"], "identity_review")
        self.assertEqual([m["en"] for m in row["memberships"]], ["First Platform", "Second Platform"])

    def test_name_only_fallback_cannot_verify_same_named_station(self):
        result = builder.build_region("tw", package(line("first", en="")),
            {"byName": {"同名": {"en": "Different City"}}})
        row = result["byCode"]["test-group"]
        self.assertIsNone(row["en"])
        self.assertEqual(row["status"], "missing")

    def test_reviewed_identity_rejects_stale_name(self):
        override = {"test-group": {"name": "別站", "en": "Other", "source": "https://operator.example/station/1"}}
        with self.assertRaisesRegex(ValueError, "stale official identity"):
            builder.build_region("mo", package(line("first")), {}, overrides=override)

    def test_bilingual_override_keeps_evidence(self):
        evidence = {"name": "同名", "en": "Official Station", "source": "https://operator.example/station/1",
                    "identityEvidence": [{"stationId": "1", "name": "同名", "en": "Official Station"}]}
        row = builder.build_region("mo", package(line("first")), {},
            overrides={"test-group": evidence})["byCode"]["test-group"]
        self.assertEqual(row["status"], "official_verified")
        self.assertFalse(row["translationMayBeWrong"])
        self.assertEqual(row["identityEvidence"], evidence["identityEvidence"])

    def test_shared_group_does_not_verify_another_operator(self):
        first = line("jr", name="伊勢市")
        first["operator"] = "東海旅客鉄道"
        second = line("kintetsu", name="伊勢市")
        second["operator"] = "近畿日本鉄道"
        jp = {"byCode": {"test-group": {"ja": "伊勢市", "en": "Iseshi",
            "source": "https://global.jr-central.co.jp/en/info/station/", "status": "official_verified",
            "identityEvidence": [{"operator": "東海旅客鉄道", "ja": "伊勢市", "en": "Iseshi",
                "source": "https://global.jr-central.co.jp/en/info/station/"}]}}}
        row = builder.build_region("jp", package(first, second), {}, jp)["byCode"]["test-group"]
        self.assertEqual([m["status"] for m in row["memberships"]],
            ["official_verified", "official_spelling_candidate"])
        self.assertTrue(row["translationMayBeWrong"])

    def test_independently_verified_transfer_names_are_not_an_error(self):
        evidence = {}
        for key, english in [("first", "First Official"), ("second", "Second Official")]:
            evidence[f"{key}:test-group"] = {"country": "tw", "lineId": key,
                "stationCode": "test-group", "operator": "Test Railway", "name": "同名",
                "en": english, "source": "https://operator.example/station/1",
                "identityEvidence": [{"officialStationId": key, "en": english}]}
        row = builder.build_region("tw", package(line("first"), line("second")), {},
            member_overrides=evidence)["byCode"]["test-group"]
        self.assertEqual(row["status"], "multiple_official_names")
        self.assertFalse(row["translationMayBeWrong"])
        self.assertEqual(row["enVariants"], ["First Official", "Second Official"])

    def test_member_evidence_rejects_another_operator_or_missing_proof(self):
        row = {"country": "tw", "lineId": "first", "stationCode": "test-group",
            "operator": "Other Railway", "name": "同名", "en": "Official",
            "source": "https://operator.example/station/1", "identityEvidence": [{"id": "1"}]}
        with self.assertRaisesRegex(ValueError, "stale verified line identity"):
            builder.build_region("tw", package(line("first")), {}, member_overrides={"first:test-group": row})
        row["operator"] = "Test Railway"
        row["identityEvidence"] = []
        with self.assertRaisesRegex(ValueError, "missing verified line evidence"):
            builder.build_region("tw", package(line("first")), {}, member_overrides={"first:test-group": row})

    def test_seven_regions_and_exact_membership_coverage(self):
        catalog, report = builder.build()
        self.assertEqual(tuple(catalog["byCountry"]), builder.REGIONS)
        for region, country in catalog["byCountry"].items():
            original = builder.read(builder.APP / f"public/rail/{region}-2025.json")
            expected = {(l["id"], i, s[0], s[1]) for l in original["lines"] for i, s in enumerate(l["stations"])}
            actual = {(m["lineId"], m["seq"], code, m["name"]) for code, row in country["byCode"].items() for m in row["memberships"]}
            self.assertEqual(actual, expected)
            self.assertEqual(report["regions"][region]["stations"], len(country["byCode"]))
            for row in country["byCode"].values():
                self.assertEqual(row["translationMayBeWrong"], row["status"] not in builder.VERIFIED_STATUSES)
            self.assertEqual(report["regions"][region]["officialVerifiedMemberships"],
                sum(m["status"] == "official_verified" for row in country["byCode"].values() for m in row["memberships"]))
        unresolved_memberships = {(row["country"].lower(), row["lineId"], row["seq"])
            for row in report["unresolvedMemberships"]}
        expected_unresolved = {(region, m["lineId"], m["seq"]) for region, country in catalog["byCountry"].items()
            for row in country["byCode"].values() for m in row["memberships"] if m["translationMayBeWrong"]}
        self.assertEqual(unresolved_memberships, expected_unresolved)
        self.assertEqual(report["allStationsOfficialVerified"], not report["unresolved"])


if __name__ == "__main__":
    unittest.main()
