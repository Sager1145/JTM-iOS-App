# Through Workbench inspection design

The user requests an automatically generated complete inspection plan, repairs driven by its findings, and a logo for the detector. Extend the existing Swift/Catalyst app first. Keep inspection inside the app and its Foundation core, rather than recreating retired standalone verification pipelines.

The plan covers 1996-12-31 through the selected end date. It inventories all imported through-service records, every declared temporal boundary and its preceding day, physical and source prerequisites, and the evidence still needed to establish national completeness. It groups repeated findings by record and defect class, retaining affected dates and a concrete next action. Structural errors, review warnings and missing evidence remain separate. No fabricated onset, connector, operator or endpoint may fill an unknown.

Checks cover schema and duplicate identities; strict Gregorian half-open windows; ordered variant indices and overlap/gaps; HTTP(S) source attribution; physical line/station/reverse identities; raw compact-v1 seams and endpoints; dated adjacency and connector records; onset-only and unresolved-period evidence; historical geometry/identity availability; official service-inventory reconciliation; Swift/Web consumers and native presentation. The last external layers remain explicitly unresolved until supported by actual evidence.

Generate the plan after loading the document. Preserve the report while browsing individual dates; refresh it manually for a different end date, and invalidate it after edits/import. All work runs through the existing serial actor. Export a portable JSON report with its date range, checks, findings and recommendations. The dashboard filters findings by category and severity and navigates to the affected record. Avoid claiming a structurally clean result is complete national history.

Fix the detector before interpreting its findings: preserve surveyed coordinates instead of snapping endpoints during inspection, reject malformed continuing seams, distinguish Unknown from Inactive in comparisons, and review any resulting production-data candidate against its owning builder and official source. Reuse existing incremental build caches, meaningful focused core tests and one native Catalyst case; one heavy job at a time.

Create a navy/teal logo combining railway nodes and a magnifying glass, with an amber historical-change node. Install it as the app icon and retain the full-resolution project asset and generation prompt. Existing typography bounds and orientation rules remain enforced.
