#!/usr/bin/env python3
"""Add official English service names without transliterating unsupported names."""
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "app/data/train-service-history"
ACCESSED_AT = "2026-09-29"

SOURCES = [
    {
        "source_id": "jr-hokkaido-limited-express-guide-en",
        "publisher": "Hokkaido Railway Company",
        "title": "Information on Limited Express Trains (All Seats Reserved)",
        "source_type": "official_english_service_guide",
        "url_or_locator": "https://www.jrhokkaido.co.jp/global/english/ticket/usage/usage03.html",
    },
    {
        "source_id": "jr-hokkaido-furano-lavender-guide-en",
        "publisher": "Hokkaido Railway Company",
        "title": "Furano Lavender Express",
        "source_type": "official_english_service_guide",
        "url_or_locator": "https://www.jrhokkaido.co.jp/global/english/train/guide/lavender.html",
    },
    {
        "source_id": "jr-hokkaido-niseko-train-guide-en",
        "publisher": "Hokkaido Railway Company",
        "title": "特急ニセコ号 Niseko express",
        "source_type": "official_bilingual_service_guide",
        "url_or_locator": "https://www.jrhokkaido.co.jp/train/tr036_01.html",
        "notes": "The bilingual train guide prints “Niseko express” (information marked July 2025); JR Hokkaido's 2026 service page confirms the same named train operates in September 2026: https://www.jrhokkaido.co.jp/travel/niseko/index.html",
    },
    {
        "source_id": "jr-east-hitachi-tokiwa-guide-en",
        "publisher": "East Japan Railway Company",
        "title": "HITACHI / TOKIWA (E657 series)",
        "source_type": "official_english_service_guide",
        "url_or_locator": "https://www.jreast.co.jp/en/multi/traininformation/hitachi/",
    },
    {
        "source_id": "jr-east-azusa-guide-en",
        "publisher": "East Japan Railway Company",
        "title": "Azusa, Kaiji and FUJI EXCURSION",
        "source_type": "official_english_service_guide",
        "url_or_locator": "https://www.jreast.co.jp/en/multi/traininformation/azusa_kaiji/index.html",
    },
    {
        "source_id": "jr-central-conventional-limited-express-2026-en",
        "publisher": "Central Japan Railway Company",
        "title": "Conventional Line Limited Express: Hida, Shinano, Nanki",
        "source_type": "official_english_service_guide",
        "url_or_locator": "https://global.jr-central.co.jp/en/nozomi/pdf/zairai_English.pdf",
    },
    {
        "source_id": "jr-shikoku-limited-express-guide-en",
        "publisher": "Shikoku Railway Company",
        "title": "JR Shikoku's Free Wi-Fi Service: supported limited express trains",
        "source_type": "official_english_service_guide",
        "url_or_locator": "https://www.jr-shikoku.co.jp/global/en/service/wifi.html",
    },
    {
        "source_id": "jr-kyushu-ibusuki-guide-en",
        "publisher": "Kyushu Railway Company",
        "title": "IBUSUKI NO TAMATEBAKO",
        "source_type": "official_english_service_guide",
        "url_or_locator": "https://www.jrkyushu.co.jp/english/train/ibutama.html",
    },
    {
        "source_id": "jr-kyushu-yufuin-guide-en",
        "publisher": "Kyushu Railway Company",
        "title": "YUFUIN NO MORI",
        "source_type": "official_english_service_guide",
        "url_or_locator": "https://www.jrkyushu.co.jp/english/train/yufuin_no_mori.html",
    },
    {
        "source_id": "jr-west-west-express-ginga-guide-en",
        "publisher": "West Japan Railway Company",
        "title": "WEST EXPRESS GINGA",
        "source_type": "official_english_service_guide",
        "url_or_locator": "https://www.westjr.co.jp/travel-information/en/train-usage-guide/trains/westexginga/",
    },
]

NAMES = {
    "furano-lavender-express": ("Furano Lavender Express", "jr-hokkaido-furano-lavender-guide-en"),
    "hokuto": ("Hokuto", "jr-hokkaido-limited-express-guide-en"),
    "kamui": ("Kamui", "jr-hokkaido-limited-express-guide-en"),
    "lilac": ("Lilac", "jr-hokkaido-limited-express-guide-en"),
    "niseko": ("Niseko express", "jr-hokkaido-niseko-train-guide-en"),
    "sarobetsu": ("Sarobetsu", "jr-hokkaido-limited-express-guide-en"),
    "azusa": ("Azusa", "jr-east-azusa-guide-en"),
    "hitachi": ("Hitachi", "jr-east-hitachi-tokiwa-guide-en"),
    "tokiwa": ("Tokiwa", "jr-east-hitachi-tokiwa-guide-en"),
    "shinano": ("Shinano", "jr-central-conventional-limited-express-2026-en"),
    "ishizuchi": ("Ishizuchi", "jr-shikoku-limited-express-guide-en"),
    "shiokaze": ("Shiokaze", "jr-shikoku-limited-express-guide-en"),
    "ibusuki-no-tamatebako": ("IBUSUKI NO TAMATEBAKO", "jr-kyushu-ibusuki-guide-en"),
    "yufuin-no-mori": ("YUFUIN NO MORI", "jr-kyushu-yufuin-guide-en"),
    "west-express-ginga": ("WEST EXPRESS GINGA", "jr-west-west-express-ginga-guide-en"),
}


def write_jsonl(path, rows):
    path.write_text("".join(
        json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows
    ))


def main():
    japanese_periods = []
    for path in sorted((BASE / "normalized").glob("service-name-periods*.jsonl")):
        if path.name == "service-name-periods-english.jsonl":
            continue
        japanese_periods.extend(
            json.loads(line) for line in path.read_text().splitlines() if line.strip()
        )

    rows = []
    for period in japanese_periods:
        service_id = period["service_id"]
        if period["language"] != "ja" or service_id not in NAMES:
            continue
        # Current English guides do not establish historical English naming.
        if period["valid_from"] < "2026-01-01":
            continue
        name, source_id = NAMES[service_id]
        rows.append({
            "service_id": service_id,
            "name": name,
            "language": "en",
            "valid_from": period["valid_from"],
            "valid_until": period.get("valid_until"),
            "name_type": "display",
            "source_id": source_id,
        })

    unique = {
        (row["service_id"], row["valid_from"], row.get("valid_until")): row
        for row in rows
    }
    sources = [dict(
        row,
        accessed_at=ACCESSED_AT,
        license_status="no_reuse_grant_identified",
        redistribution_status="factual_metadata_only",
        automated_extraction_allowed=False,
        notes=row.get("notes", "Official English operator page reviewed for the published service name only."),
    ) for row in SOURCES]
    write_jsonl(BASE / "sources/source-registry-english-names.jsonl", sources)
    write_jsonl(BASE / "normalized/service-name-periods-english.jsonl", sorted(
        unique.values(), key=lambda row: (row["service_id"], row["valid_from"])
    ))
    print(f"Normalized {len(unique)} official English service-name periods from {len(sources)} sources")


if __name__ == "__main__":
    main()
