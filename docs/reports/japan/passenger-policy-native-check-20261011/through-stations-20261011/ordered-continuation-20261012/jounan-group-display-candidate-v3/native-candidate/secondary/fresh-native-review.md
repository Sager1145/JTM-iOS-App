# Secondary fresh native review — Jounan group display candidate V3

Verdict: **ACCEPT for the fresh Secondary scope described below.** I opened and visually compared every captured basemap, display, and smooth panel. I found no concrete rendering defect in the fresh Jounan or Hanazono evidence.

## Reviewed evidence

- Candidate SHA-256: `e5c87f0e10dfa935f766a39fdd8d2cc87b96bfa521bae4dfbef3c609a100a491`.
- Jounan (`jp-伊予鉄道-城南線`) intervals `#0` through `#10`: 11 complete intervals, 27 viewpoints, 81 panels.
- Hanazono (`jp-伊予鉄道-花園線`) interval `#0`: 1 complete interval, 3 viewpoints, 9 panels.
- Total: 12 complete intervals, 30 viewpoints, 90 panels (30 basemap + 30 display + 30 smooth), with 0 scoped pending captures and 0 failed captures in `fresh-report.json`.
- Jounan viewpoint counts by interval `#0...#10`: `2, 2, 3, 2, 3, 3, 2, 2, 3, 3, 2`.

Capture totals and bounds are inventory evidence only. The verdict above is based on opening all 30 triplets and comparing their pixels.

## Pixel findings

- Jounan `#0` and `#1` retain the rounded west-to-south tram arm and the north/south station-face relationships without a reverse-U display, hook, open seam, or abrupt cap. The legal record's west-arm retracing remains an inventory/topology concern and is not rendered as an operational wrong turn.
- Jounan `#2` follows the literal thin tied-black tram rail in all three views. Its west head reaches the real junction at approximately `[132.76179812, 33.83934635]`; the eastward head and northward City Hall curve stay on the rail rather than the moat curb. The smooth result preserves the bend and does not shortcut across the curb or grounds.
- Jounan `#3` through `#8` remain continuous at their shared interval ends. The Prefectural Office/Katsuyamacho approaches, north-south transition, and shared Kami north-south face show no new kink, cap, flattened curve, or detached station dot.
- Jounan `#9` and `#10` follow the broad Dogo Park approach and terminal arc without the earlier inside/outside drift. Their shared seam is continuous, and the terminal approach has no visible hook or slope break.
- Hanazono `#0` now reaches the literal Minamihoribata junction with its separate north display lead-in. All three views show the previous network gap closed, with no overshoot, false west-arm visit, hook, or cusp. The underlying interval still terminates at its own Minamihoribata station face; the added display lead-in supplies visual network continuity without moving that serialized endpoint.
- The south Matsuyamashi terminal stays on the Hanazono rail/platform approach and ends cleanly at its own terminal face. Display and smooth panels agree closely through the final bend, with no fake terminal hook.

## Limits and warnings

- `fresh-report.json` records a 29.656575778097967 m Hanazono display-to-decoded maximum. That is expected for the separate display lead-in and is not a pixel failure in these captures.
- Apple rail casing, labels, and generalized station graphics limit metre-level cartographic claims. This review accepts visible continuity and own-rail/frame behavior in the supplied frames; it does not certify surveyed track accuracy or operational service patterns.
- Only Jounan and Hanazono were freshly captured here. The four unchanged legal lines in the six-line group are outside this receipt. Reusing their earlier evidence requires the separate source/native input-equality check owned by the root review.
- This is a bounded candidate review, not source application, Main-app acceptance, or a national-completion claim.
