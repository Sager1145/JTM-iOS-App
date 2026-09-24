#!/usr/bin/env python3
"""Generates docs/train-service-database-checklist.md from the bundled
train-service catalog (names + stop patterns), plus the optional test
reports emitted by TrainServiceCatalogChecklistTests
(TRAIN_CATALOG_CHECK_REPORT) and TrainServicePatternRouteTests
(TRAIN_PATTERN_ROUTE_REPORT).

Python 3 stdlib only. See ios/tools/train-service-checklist.py --help.
"""
import argparse
import json
import os
import sys
from collections import Counter, OrderedDict

NOT_RUN = "未运行"
MARK_OK = "✅"
MARK_PARTIAL = "⚠️"
MARK_MISSING = "❌"


def load_json(path):
    if path is None:
        return None
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def repo_root_relative(tools_dir):
    # ios/tools -> repo root is two levels up.
    return os.path.abspath(os.path.join(tools_dir, "..", ".."))


def completeness_mark(level):
    if level == "complete":
        return MARK_OK
    if level == "partial":
        return MARK_PARTIAL
    return MARK_MISSING


def format_completeness(pattern):
    completeness = pattern.get("completeness") or {}
    stops = completeness.get("stops", "missing")
    lines = completeness.get("lines", "missing")
    validity = completeness.get("validity", "missing")
    return "停站{} 线路{} 日期{}".format(
        completeness_mark(stops), completeness_mark(lines), completeness_mark(validity))


def completeness_is_full(pattern):
    completeness = pattern.get("completeness") or {}
    return all(
        completeness.get(field) == "complete" for field in ("stops", "lines", "validity"))


def format_validity(pattern):
    valid_from = pattern.get("validFrom")
    valid_until = pattern.get("validUntil")
    if not valid_from and not valid_until:
        return "—"
    left = valid_from or "?"
    right = "<" + valid_until if valid_until else "?"
    return "{}〜{}".format(left, right)


def format_route_result(pattern_id, route_report):
    if route_report is None:
        return NOT_RUN
    entry = route_report.get(pattern_id)
    if entry is None:
        return NOT_RUN
    legs = entry.get("legs", 0)
    failed = entry.get("failed", []) or []
    unsolvable = entry.get("unsolvable", 0) or 0
    if failed:
        return "{} {} failed".format(MARK_MISSING, len(failed))
    if unsolvable:
        return "⏸ {} unsolvable-historical".format(unsolvable)
    return "{} {}/{}".format(MARK_OK, legs, legs)


def format_recognition(service_id, catalog_report):
    if catalog_report is None:
        return NOT_RUN
    entry = catalog_report.get(service_id)
    if entry is None:
        return NOT_RUN
    failed = entry.get("failed", []) or []
    return MARK_OK if not failed else MARK_MISSING


def logo_mark(logo_path, repo_root):
    if not logo_path:
        return MARK_OK  # No dedicated logo is a valid, checked-in fallback.
    full_path = os.path.join(repo_root, "app", "public") + logo_path
    exists = os.path.exists(full_path)
    filename = os.path.basename(logo_path)
    return "{} ({})".format(MARK_OK if exists else MARK_MISSING, filename)


def build_markdown(args, branding, patterns, route_report, catalog_report, repo_root):
    lines = []
    lines.append("# 特急数据库检查清单")
    lines.append("")
    lines.append(
        "每一项都由自动化测试逐条执行，不跳过任何条目。勾选含义：")
    lines.append("")
    lines.append(
        "- 列车名数据库：**辨识** = 每个别名都解析到本条目且被归为特急"
        "（来自 TrainServiceCatalogChecklistTests 报告）；"
        "**Logo** = 非空 logoPath 的文件已打包（无专属 logo 的条目按规则退回公司 logo／默认图标）。")
    lines.append(
        "- 停靠站模式：**资料完整度** = 停站/线路/生效日期三项的记录完整度"
        "（{ok} complete ⚠️ partial ❌ missing）；"
        "**站序/求解** = 每个相邻站区间是否被真实路线求解器求出，"
        "`unsolvableLegs` 中登记的历史区间会被跳过并单独计入 ⏸"
        "（来自 TrainServicePatternRouteTests 报告）。".format(ok=MARK_OK))
    lines.append("")

    # Section 1
    lines.append("## 一、列车名数据库（{} 条）".format(len(branding)))
    lines.append("")
    lines.append("| # | id | 名称 | 辨识 | Logo |")
    lines.append("|---|---|---|---|---|")
    for i, service in enumerate(branding, start=1):
        names = service.get("names") or []
        display_name = names[0] if names else service.get("id", "")
        recognition = format_recognition(service.get("id"), catalog_report)
        logo = logo_mark(service.get("logoPath"), repo_root)
        lines.append("| {} | `{}` | {} | {} | {} |".format(
            i, service.get("id"), display_name, recognition, logo))
    lines.append("")

    # Section 2
    lines.append("## 二、停靠站模式（{} 条）".format(len(patterns)))
    lines.append("")
    lines.append(
        "| # | patternId | 列车名 | 运行方案 | 公司 | 生效日期 | 经由线路 | "
        "停站数 | 资料完整度 | 站序/求解 | 可信度 |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|")
    gap_patterns = []
    for i, pattern in enumerate(patterns, start=1):
        pattern_id = pattern.get("patternId", "")
        name = pattern.get("name", "")
        label = pattern.get("label", "")
        company = pattern.get("company", "")
        validity = format_validity(pattern)
        via_lines = pattern.get("lines") or []
        via = "・".join(via_lines) if via_lines else "—"
        stop_count = len(pattern.get("stops") or [])
        completeness_str = format_completeness(pattern)
        route_result = format_route_result(pattern_id, route_report)
        confidence = pattern.get("confidence") or "—"
        lines.append("| {} | `{}` | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
            i, pattern_id, name, label, company, validity, via, stop_count,
            completeness_str, route_result, confidence))

        has_gap = (
            completeness_is_full(pattern) is False
            or MARK_MISSING in route_result
            or "unsolvable" in route_result)
        if has_gap:
            gap_patterns.append((pattern_id, name, completeness_str, route_result))
    lines.append("")

    # Section 3: summary
    lines.append("## 三、汇总")
    lines.append("")

    def counter_for(field):
        counts = Counter()
        for pattern in patterns:
            completeness = pattern.get("completeness") or {}
            counts[completeness.get(field, "missing")] += 1
        return counts

    lines.append("### 资料完整度分布")
    lines.append("")
    lines.append("| 字段 | complete | partial | missing |")
    lines.append("|---|---|---|---|")
    for field, label in (("stops", "停站"), ("lines", "线路"), ("validity", "生效日期")):
        counts = counter_for(field)
        lines.append("| {} | {} | {} | {} |".format(
            label, counts.get("complete", 0), counts.get("partial", 0), counts.get("missing", 0)))
    lines.append("")

    confidence_counts = Counter(pattern.get("confidence") or "unknown" for pattern in patterns)
    lines.append("### 可信度分布")
    lines.append("")
    lines.append("| 可信度 | 数量 |")
    lines.append("|---|---|")
    for level in ("high", "medium", "low", "unknown"):
        if confidence_counts.get(level):
            lines.append("| {} | {} |".format(level, confidence_counts[level]))
    lines.append("")

    from datetime import date
    today = date.today().isoformat()
    known = [p for p in patterns if (p.get("completeness") or {}).get("validity") != "missing"]
    current_count = sum(1 for p in known if
                        (not p.get("validFrom") or p["validFrom"] <= today) and
                        (not p.get("validUntil") or today < p["validUntil"]))
    discontinued_count = len(known) - current_count
    lines.append("### 记录的有效期（截至 {}）".format(today))
    lines.append("")
    lines.append("| 状态 | 数量 |")
    lines.append("|---|---|")
    lines.append("| 记录覆盖今日 | {} |".format(current_count))
    lines.append("| 记录不覆盖今日 | {} |".format(discontinued_count))
    lines.append("| 有效期资料缺失 | {} |".format(len(patterns) - len(known)))
    lines.append("")

    lines.append("### 存在缺口的条目（资料不完整或求解失败/含历史不可解区间）")
    lines.append("")
    if gap_patterns:
        lines.append("| patternId | 列车名 | 资料完整度 | 站序/求解 |")
        lines.append("|---|---|---|---|")
        for pattern_id, name, completeness_str, route_result in gap_patterns:
            lines.append("| `{}` | {} | {} | {} |".format(
                pattern_id, name, completeness_str, route_result))
    else:
        lines.append("（无）")
    lines.append("")

    pattern_service_ids = {pattern.get("serviceId") for pattern in patterns}
    no_pattern_services = [
        service for service in branding if service.get("id") not in pattern_service_ids
    ]
    lines.append("### 品牌无模式（有列车名但无停靠站模式）")
    lines.append("")
    if no_pattern_services:
        lines.append("| id | 名称 |")
        lines.append("|---|---|")
        for service in no_pattern_services:
            names = service.get("names") or []
            display_name = names[0] if names else service.get("id", "")
            lines.append("| `{}` | {} |".format(service.get("id"), display_name))
    else:
        lines.append("（无）")
    lines.append("")

    return "\n".join(lines) + "\n"


def main():
    tools_dir = os.path.dirname(os.path.abspath(__file__))
    default_repo_root = repo_root_relative(tools_dir)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--patterns",
        default=os.path.join(
            default_repo_root,
            "ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json"))
    parser.add_argument(
        "--branding",
        default=os.path.join(
            default_repo_root,
            "ios/RailKit/Sources/RailCore/Resources/train-service-branding.json"))
    parser.add_argument("--route-report", default=None)
    parser.add_argument("--catalog-report", default=None)
    parser.add_argument(
        "--out",
        default=os.path.join(default_repo_root, "docs/train-service-database-checklist.md"))
    args = parser.parse_args()

    branding = load_json(args.branding)
    if branding is None:
        print("error: could not load branding catalog at {}".format(args.branding),
              file=sys.stderr)
        sys.exit(1)
    patterns = load_json(args.patterns)
    if patterns is None:
        print("error: could not load pattern catalog at {}".format(args.patterns),
              file=sys.stderr)
        sys.exit(1)

    route_report = load_json(args.route_report) if args.route_report else None
    catalog_report = load_json(args.catalog_report) if args.catalog_report else None

    repo_root = repo_root_relative(tools_dir)
    markdown = build_markdown(
        args, branding, patterns, route_report, catalog_report, repo_root)

    out_dir = os.path.dirname(os.path.abspath(args.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(markdown)
    print("wrote {}".format(args.out))


if __name__ == "__main__":
    main()
