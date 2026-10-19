# Native through-station capture baseline

Existing manual Inspector instances only, version 0.1/build 2/v5. No build, data, geometry or review verdict changed. At capture start running bundled jp-2025.json matched current package source. Default alone remained in full capture; latest native observation 8,361/92,218, zero failures (see ../default-capture-progress.ax.txt).

All central and approach overlay/basemap pairs were recaptured with camera setup/native observation separated from the screenshot call. Both PNG and AX records retain line, station, mode and camera context. Some Apple scale-bar labels do not agree with the reported z18 framing even after repeated native observations; do not infer a pixel distance from that label alone. UI z18 and recorded camera are reported, not a measured geographic alignment verdict.

The single-line Inspector preview does not prove production cross-company family composition. Company identity, passenger service, physical platform group and camera proximity remain separate. No nearest black surface track was adopted as underground geometry.

- asakusa-central-z18-overlay: {"lat":35.71022,"lon":139.81241}; overlay/basemap reported camera equal: True.
- hanzomon-central-z18-overlay: {"lat":35.71026,"lon":139.81335}; overlay/basemap reported camera equal: True.
- keisei-approach-view4-z18-overlay: {"lat":35.711015,"lon":139.813661}; overlay/basemap reported camera equal: True.
- keisei-central-z18-overlay: {"lat":35.71022,"lon":139.81241}; overlay/basemap reported camera equal: True.
- tobu-approach-view3-z18-overlay: {"lat":35.712342,"lon":139.815087}; overlay/basemap reported camera equal: True.
- tobu-central-z18-overlay: {"lat":35.71026,"lon":139.81335}; overlay/basemap reported camera equal: True.

Tobu/Hanzomon central is the existing display endpoint [139.81335,35.71026], rather than a newly verified station-middle placement. Keisei/Asakusa central is [139.81241,35.71022]. The additional tobu-hanzomon-station-extent-z17-basemap frame covers the elongated blue/purple underground station area southward. Surface Tobu black railway strokes are visible to the north/west, but the true underground platform boundaries/track path were not clearly identifiable from these captures: keep central alignment pending. Do not snap the underground pair to those surface tracks. Final Hakone manual window remains Oshiage, Tobu/Hanzomon station-area z17 pure basemap.
