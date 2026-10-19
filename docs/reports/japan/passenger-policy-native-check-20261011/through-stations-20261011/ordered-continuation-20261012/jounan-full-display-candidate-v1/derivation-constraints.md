# Jounan full-display derivation constraints

- Candidate only; production source, station IDs, kilometres, physical records, and serialized topology remain unchanged.
- Interval 0 is derived in two parts: Honmachi 1-chome to the three-arm west junction `J`, then the exact reverse of the shared west-arm polyline.
- Interval 1 is derived in two parts: that same shared west-arm polyline from Nishihoribata to `J`, then the visible south-to-east curve to Minamihoribata. The shared arm has at least three points and is byte-identical under reversal.
- `J` is a rail vertex, never a station representative. Nishihoribata and Honmachi 1-chome retain separate own-frame representatives.
- Minamihoribata uses the west-arm frame for Jounan; Hanazono's south-arm frame remains separate.
- Minamimachi has no defensible drawn platform frame in the supplied raw. Its Apple station POI lies on the continuous own black rail and is recorded as an explicit cartographic warning.
- No station representative is borrowed from another rail line; no physical registry or route serialization is changed.
