# Native Apple Maps rail screenshots

Screenshots **the installed macOS Apple Maps app** using `com.apple.Maps`, its transit view, Accessibility, and macOS window capture. No web map, browser, MapKit replacement, API key, or screenshot upload is used.

The supplied reference has a 250 m scale across approximately 87 image pixels (2.87 m/pixel). `probe` opens Toronto, enables the native scale bar, and adjusts fractional zoom until OCR measures within 7% of that resolution. Each subsequent image is checked again. The initial probe measured **2.85 m/pixel at zoom 16.28**. The updated probe also matches at least three visible station icons to known coordinates, measures the native camera offset, then verifies the corrected center within 20 pixels. A full capture refuses older calibration without that verification. Scale is physical image resolution, not just a matching label or a fixed zoom everywhere.

## Run

From Terminal:

```bash
cd /Users/sager/Documents/GitHub/JTM-iOS-App
/usr/bin/caffeinate -di ./tools/apple-maps-rail/run.sh all
```

Or run the stages individually:

```bash
./tools/apple-maps-rail/run.sh fetch
./tools/apple-maps-rail/run.sh probe
./tools/apple-maps-rail/run.sh plan
./tools/apple-maps-rail/run.sh audit
/usr/bin/caffeinate -di ./tools/apple-maps-rail/run.sh capture
```

Or double-click `Capture All.command` in this folder. It resumes the route fetch, creates verified calibration if needed, rebuilds and audits the plan, then resumes capture. Completed tile identities are retained when their coordinates and calibration are unchanged. The first launch creates a local Python environment and installs Pillow and NumPy. Requires macOS, Python 3.9+, and Xcode command-line tools (`xcrun swiftc`). macOS must already allow the invoking terminal to use Accessibility and Screen Recording. If access is missing, the script stops with the relevant setting; it does not grant permissions itself.

Keep Maps in dark appearance, metric units, 2D, with the sidebar/search cards hidden. The probe prepares the sidebar, scale and north orientation in English or Traditional/Simplified Chinese. On other UI languages, set these using the View menu yourself. Leave the Maps window at its calibrated size. The launcher keeps the display awake; a manually locked session pauses capture until you unlock it yourself. Captures use the Maps window ID, including on a secondary monitor. Avoid interacting with Maps while capture runs. Stop with Ctrl-C; rerun **capture** to resume. No need to repeat probe or plan when resuming.

Output defaults to `outputs/apple-maps-rail/`:

- `rail/` — images classified as showing rail.
- `no_rail/` — images classified as not showing rail.
- `metadata/` — per-image recovery records for interrupted journal writes.
- `manifest.jsonl` — coordinates, scale checks, classifier reasons, confidence score, review flag and image hash.
- `pending/` — captures that failed validation, never silently placed into `no_rail`.
- `status.json`, `failures.jsonl` — resumable progress, lock pauses, and tile errors.
- `workflow-status.json` — current stage of the `all` command, including waiting for manual unlock.
- `network-cache/` — full OpenStreetMap route relations used only to plan coverage, with source/license records.
- `coverage-audit.json` — per-metro area coverage, whole-line coverage, unresolved inventory gaps, and calibration evidence.
- `calibration.json`, `plan.json`, `probe-toronto.png` — calibration and coverage evidence.

Runtime data and screenshots stay local and are ignored by Git.

## Capture less, or change coverage

```bash
./tools/apple-maps-rail/run.sh cities
./tools/apple-maps-rail/run.sh plan --cities new_york,toronto
./tools/apple-maps-rail/run.sh capture --limit 20
# Rerun the same capture command to take the next 20 unsaved tiles.
```

The catalog groups satellite cities into 60 urban/commuter rail metros in the US and Canada (including San Juan). It includes subway, light rail, streetcar, automated rail, and commuter/regional services such as LIRR, Metro-North, NJ Transit, GO, exo and Rail Runner. City eligibility excludes Amtrak/VIA-only and bus-only places. Images within eligible metros may still show Amtrak/VIA tracks; the script does not erase them from Apple Maps.

The default `metros` plan scans each metro’s own union of catalog and sourced network envelopes, then adds full eligible rail corridors beyond those envelopes. `network-extents.json` records distinct system/terminal envelopes for metros where the original boxes were inadequate; the fetcher queries all 60 metros and retains whole route geometry, including portions outside the search boxes. The planner also reconstructs split geometry and assigns isolated outer branches to their operator’s metro. Tile overlap is calculated using the smallest accepted scale, so the 7% zoom tolerance cannot create gaps. The faster optional `corridors` plan follows eligible line geometry from the repository and downloaded supplements. It follows whole matched commuter lines beyond city boundaries, so LIRR's outer reaches are retained. It excludes Amtrak, VIA and intercity/high-speed route categories as capture targets. Metra's Heritage Corridor and public heritage streetcars remain eligible. In corridor-only mode, where a metro has no matching geometry, its catalog boxes are scanned instead. Default metro mode scans all the boxes regardless of inventory matches.

For a faster inventory-only run, or an area-only scan:

```bash
./tools/apple-maps-rail/run.sh plan --mode corridors
./tools/apple-maps-rail/run.sh plan --mode areas
```

The audit tests continuous line segments, including split branches and endpoints, rather than merely counting city names. `ERROR` means uncovered geometry/areas or unverified camera alignment. `INCOMPLETE` means declared geometry is covered but network inventory or extent evidence still needs verification; it must not be reported as proof of every current railway. `PASS` requires those checks to be resolved. The launcher stops on `ERROR`; an `INCOMPLETE` audit permits capturing the declared coverage and retains the limitations in the report.

The boxes and rail inventories are a **coverage baseline, not proof of every current railway in Apple Maps**. The catalog records source URLs and known limitations, including service suspensions and provisional bounds. In corridor-only mode, a partially represented metro does not automatically get an area fallback. Default metro mode scans those city areas too. Add sourced envelopes to `network-extents.json` or supplemental route geometry if a system lies beyond current coverage. A successful Overpass response is not by itself proof that every service branch is mapped. Fetching rejects empty results and partial timeout responses, retries failures, and reports every metro that could not be fetched. A responsive [documented public mirror](https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances) is used when the primary server fails; each cache records the endpoint actually used. These requests send public route-area coordinates, never screenshots. Re-run `fetch`, `plan`, and `audit` after updating network inputs. Tourist-only systems and airport-only shuttles are outside the default scope.

## Sorting accuracy

The sorter is local and heuristic: it looks for thin transit-colored lines and uses available rail-station/route evidence. It is **not a trained semantic vision model**, and its confidence is a heuristic score, not measured accuracy. Bus routes, muted/gray railway lines, very short rail fragments, text and loading artifacts can confuse it. Review `needs_review` records and spot-check both output folders. No claim of perfect rail/no-rail separation is made.

The sorter preserves thin native-resolution strokes and combines separated fragments of the same route color. To apply the current sorter to this capture journal without retaking screenshots:

```bash
./tools/apple-maps-rail/run.sh resort
```

Sort an existing folder of map screenshots (immediate image files only):

```bash
./tools/apple-maps-rail/.venv/bin/python tools/apple-maps-rail/classify.py /absolute/path/to/screenshots
```

This produces the same two folders plus `classification-audit.jsonl`. It never overwrites a same-named image; decoding failures stay in the original folder.

## Merge saved rail screenshots

```bash
./tools/apple-maps-rail/.venv/bin/python -m pip install -r tools/apple-maps-rail/requirements.txt
./tools/apple-maps-rail/.venv/bin/python tools/apple-maps-rail/merge_rail.py
python3 -m http.server 8778 --bind 127.0.0.1 --directory outputs/apple-maps-rail
```

Open `http://127.0.0.1:8778/merged/` for the zoomable mosaic viewer. `merged/full/` contains full-resolution tiled GeoTIFFs, and `merged/previews/` contains PNG previews (up to 6,000 pixels per side). TIFFs use lossless compression and preserve the nominal screenshot scale; geographic resampling is required to align differing measured scales. A TIFF-aware GIS/image viewer is recommended for the largest files. `--skip-tiff` builds just the previews and interactive viewer; `--cities toronto,boston` limits the merge.

Only the latest journal record for each existing image in `rail/` is used. No source image is moved or changed. Map controls are cropped by 100 pixels on each edge, and recorded request coordinates, scale measurements, and native camera offset place the images in Web Mercator. Newer captures cover older overlapping images. Older records without requested coordinates use their recorded tile target as the request. This is approximate geographic registration, not feature-based seamless image alignment. Transparent areas represent missing rail captures, not verified absence of railway. The viewer accesses the unchanged original screenshots when zoomed in; keep the output folder beside `rail/`.

## Verification and custom output

```bash
./tools/apple-maps-rail/.venv/bin/python -m unittest discover -s tools/apple-maps-rail -p 'test_*.py'
./tools/apple-maps-rail/run.sh --out /absolute/path/to/captures probe
./tools/apple-maps-rail/run.sh --out /absolute/path/to/captures plan --cities toronto
./tools/apple-maps-rail/run.sh --out /absolute/path/to/captures capture --limit 3
```

A new display scale/window size requires new calibration and plan. `probe --meters-per-pixel VALUE` overrides the reference resolution. A stale `capture.lock` or `workflow.lock` after a hard kill must be removed only after checking that its recorded PID is no longer running. `all` prevents simultaneous workflows. Background launches record their PID in `full-run.pid` and log to `full-run.log`; `workflow-status.json` and `status.json` distinguish fetching, waiting, validation failures, and completed captures. A complete continental run can take hours; the planner prints tile counts before any batch capture.

Apple's [Map Links reference](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html) documents coordinate, zoom and transit parameters. The actual native app behavior was probed on this Mac. Transit catalog sources are in `cities.json`.

## Recorded probe result

On 2026-09-08 the native app produced Toronto and New York rail captures and a Phoenix residential capture without rail. Sorting put the first two in `rail/` and the last in `no_rail/`. Measured scales were 2.85, 2.87 and 2.87 m/pixel. The three-image smoke batch and its contact sheet are in the local output `smoke/` folder. A later per-metro preflight saved 44 images before the Mac locked. The audit found missing outer branches and a native camera offset. The subsequent live calibration matched 16 station icons and verified the corrected center with residual displacement of 2.37 / -1.63 pixels at 2.87394 m/pixel. Station matching normalizes trailing “Station” and punctuation differences between source data and Maps labels. The complete workflow was launched after these fixes; consult `workflow-status.json` for its current stage. This records the actual test state, not a claim that all networks have been captured.
