# Keikyu Airport V5 builder ownership receipt

Status: **PASS** (read-only structural comparison; no source apply).

- Production compact vs V5 compact changes exactly line index 86, `jp-京浜急行電鉄-空港線`, plus the new `geometrySource.manualOverrides.keikyu-airport-complete-display` record. All other 657 line records and all pre-existing override metadata are structurally exact.
- Removing the two display fields from the candidate Airport record yields the production Airport record exactly. Physical station rows, IDs, kilometre fields, segments, and compressed source geometry are unchanged.
- Display intervals 0–5 contain 53/53/33/40/62/94 points. V5 intervals 0–4 and the reviewed station-alias map equal V2 exactly; only the independently reviewed interval-5 trace changed after V2.
- The six interval GeoJSON files in the candidate root equal the six compact display arrays exactly, including every adjacent shared endpoint.
- Display lanes change exactly the Airport owning part row. All other parts, follows, lanes, family/group windows, hubs and measured-reference structures are exact. The row changes from `0aa80ada1e538b6e713e26376f0864827ea6a88fd68e616872f884933a34694e` to `58c479482961afd683df03a0742d36e6929f2b18febdf9881e7e28ccddd8809f`: one chain, 328 points, 6422.3 m, classification `station-approach/groomed`, and no auxiliary measured rows.
- Builder manifest inputs match the candidate files: package SHA `5d279e0a3a979907f4cc1479a869035ed57c0b081e4a2370db96ef9b3f268018`; lanes SHA `63a39f601f6e63cf068123c0298d3912ecc58a0cbed3112478b1cc862235d7e4`. Its Airport chunk reports 328 vertices, seven stations, one chain; the report has zero dangling JP render-group IDs.
- Existing production Matsumoto, Manyo and Onoda/West records remain covered by the all-other-lines exact comparison; available representative IDs were also spot-checked.

Scope: structural ownership and builder-input correspondence. Pixel/native/Main acceptance remains Root's separate actual-app review.
