# Local railway evidence

Raw diagnostic screenshots, native capture sessions, candidate payloads and their receipts live under the external canonical root `/Volumes/JTM Evidence/99 Compatibility/Workspace/JTM-iOS-App/railway-evidence/local/`. The table below uses `local/` as shorthand for that external directory. The checkout's ignored `railway-evidence/local/` retains only uncopied originals during migration; copied evidence is read at its external path. Source code, reusable tests and concise reviewed-result documentation stay in their normal repository locations.

| Directory | Contents |
| --- | --- |
| `local/diagnostics/sessions/` | Default new Rail Diagnostics sessions, including requests, viewpoints, original PNGs and review ledgers. |
| `local/alignment-inspector/BatchEvidence/` | Existing numbered Inspector captures and future default batch evidence. |
| `local/alignment-inspector/reviews.json` | Existing Inspector review records. |
| `local/candidates/` | New scoped display-repair candidate outputs. |
| `local/requests/` | New explicit agent task requests. |
| `local/repair-inputs/` | Local coordinate-bearing repair authority inputs. |
| `local/build-logs/` | Targeted native build receipts. |
| `local/legacy-tmp/`, `local/legacy-visualizations/` | Relocated earlier evidence and associated research/session context. |

## External evidence storage (2026-10-24)

The user has replaced iCloud evidence storage with the external drive **Untitled**, in `JTM Railway Evidence/`. Its APFS container mounts at `/Volumes/JTM Evidence`; this preserves symbolic links that the outer ExFAT drive cannot store. The readable folders group captures, repairs, records, requests, source inputs, build receipts, historical evidence and tools. `00 Inventory/INDEX.md` records original paths, intended external paths and transfer status.

Migration is in progress. Saved-evidence reviews and selected captures continue through the rebuilt external-only Diagnostics app; root coordinates one native job at a time. Copy verification precedes original deletion. Later retrieved regular files use direct verified deletion without creating temporary original-location links. The user's latest instruction also removes original-location compatibility links, so copied evidence exists only on Untitled. All 535,655 such links from completed passes through r22 were removed; their receipts cover 1,424,267 original regular files. Uncopied local iCloud placeholders remain until their contents arrive and copies pass verification.

Use `00 Inventory/INDEX.md` to locate canonical external paths and `00 Inventory/Migration Cutover/` for removal receipts. Historical CSV rows saying `READ_REDIRECTED` are superseded by the link-retirement receipt; their `canonical_storage_path` remains authoritative. Historical embedded paths in immutable requests, views and reports are lookup keys, not live read paths. Keep original image, request and receipt bytes unchanged.

The original main root remains a real directory holding pending originals. No compatibility link at that root is planned. Do not recreate old evidence directories or internal fallbacks. Local iCloud retrieval remains allowed for uncopied files; remote deletion and global cloud queue completion remain unconfirmed. No new evidence may be written into this synced checkout.

## Historical migration records

The 2026-10-20 migration retained compatibility links. That read-path policy was superseded on 2026-10-24 by the user's requirement to leave evidence only on Untitled. The external inventory preserves original-to-canonical mappings. Active source-code and runtime dependencies are outside the evidence cleanup. Historical capture/resume writers remain paused until their effective output paths are external.

Candidate writers accept the mounted external evidence root and retained private scratch paths, validating the resolved destination so a symlink cannot redirect a candidate into production resources. Production apply and source-evidence guards retain their existing checks.
