# Shinagawa own-pair transverse endpoint repair

Applied through the existing repair-shinagawa-apple-forks-display.mjs. The accepted earlier geometry introduced a7.1399m transverse connector from the retained canonical station anchor to its own-pair reference. Only the first display coordinate is changed to[139.73845609051148,35.628135], with line-specific displayStationCoordinates004095 matching it. Initial control deflection36.5717degrees becomes0; every later control, physical station/segment/ID/km, Tokaido geometry and Osaki branch coordinates remain unchanged.

Same chainage is intentional. This is not a measured whole-platform midpoint. Current official JR map identifies inner1/outer3; cached OSM outerref2 is a legacy label. Roof imagery cannot independently recover all passenger-frame caps. Longitudinal centering remains unresolved; no neighboring Tokaido/Shinkansen/Keihin platform is substituted.

Existing focused file first passed7/8; the new interval-backed row assertion expectedundefined where the production format serializesnull. Corrected the assertion to require a null explicit-coordinate slot; the previously failing upgrade test then passed1/1 in3.4s. Other7results remain applicable with unchanged source/geometry. Tests cover source immutability, exact own alias, native/Web endpoints, Tokaido rulers, Osaki shared coordinates and measured reference rebasing.

Current baseline8/8 and candidate8/8 standard captures completed; parent inspected original0/1 in both. The short initial connector is absent. Separate imagery was deliberately limited to first2/19plannedviews for roof/approach context, not full imagery coverage. Historical15acceptedviews and oldcandidate/native records remain preserved in the authoritative evidence; no oldimages relabelled as newfix.

Main final composition is pending the confirmed-repair batch. Candidate captures and completed AX are in shinagawa-transverse-candidate-native/.


Main batch follow-up: see ../main-repair-batch-20261018.md and main-batch-20261018/. Actual local pixels and bundled owner resources were reviewed; Hikifune same-camera OFF was blank and its reopened OFF camera changed, so that case retains the explicit limitation. No whole-line acceptance.
