# Native capture ownership — 2026-10-11

Single native UI/capture owner: native_capture_owner subagent. All launch, pause, quit, selection and screenshot operations used CUA.

Only InspectorModel.swift changed here: CLI batch output wins; otherwise a nonempty absolute JTMInspectorBatchOutput Info.plist value supplies output; otherwise original controller default remains. Explicit output stores reviews.json alongside its evidence and does not automatically load the default history. Default retains its prior reviews.json and evidence directory.

One successful incremental alignment build was used. The first sandbox attempt failed before compilation because existing compiler caches were unwritable; the same command succeeded after automatic escalation approval. No full tests or matrices were run. Clone packaging uses the same built Mach-O UUID E187A5AA-9713-34E4-9F22-DE078340C46B, same AppIcon.icns and Assets.car; bundle IDs, names and output metadata differ. All three are version 0.1, build 2, revision 20261011-instance-isolation-v5. Ad-hoc signing and signature verification succeeded. No renderer or geometry changes were made.

At the user’s logo/version steering, all three Inspector apps were paused/quit then reopened after packaging was unified. Reopened screenshots visibly show the same upper-left InspectorLogo in all three windows. RouteWorkbench was left running.

Reopened evidence:
- parallel-instance-hakone/reopened-unified-hakone-z17.png (+ .ax.txt): jp-小田急箱根-鉄道線#6, 大平台→宮ノ下, detailed viewpoint 1/8, z17.
- parallel-instance-kisuki-keiyo/reopened-unified-kisuki-z17.png (+ .ax.txt): jp-西日本旅客鉄道-木次線#14, 出雲坂根→三井野原, detailed viewpoint 1/20, z17.
- reopened-unified-default-running.png (+ .ax.txt): default unique full-batch running, original output path, beyond 1780/92218, zero failures.
- reopened-unified-app-inventory.json: three distinct running bundle IDs.

Both clones remained manual at 0/92218; default alone resumed the dependency-bound v5 plan from 1773 receipts. Screenshots are limited viewpoint evidence. Full coverage is incomplete and no geographic/pixel alignment PASS is asserted.
