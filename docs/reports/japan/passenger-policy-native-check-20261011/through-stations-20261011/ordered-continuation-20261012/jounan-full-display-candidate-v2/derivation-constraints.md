# Jounan full-display derivation constraints

- Candidate only; production source, station IDs, kilometres, physical records, and serialized topology remain unchanged.
- Interval 0 is derived in two parts: Honmachi 1-chome down the north-south rail to the literal black-glyph junction `J`, then the exact reverse of the curved shared west arm.
- Interval 1 is derived in two parts: the same curved shared west arm from Nishihoribata to `J`, then the smooth same-direction south-to-east curve to Minamihoribata. V1's virtual tangent intersection is excluded because no rail junction exists there.
- `J` is a rail vertex, never a station representative. Nishihoribata and Honmachi 1-chome retain separate own-frame representatives.
- Minamihoribata uses the west-arm frame for Jounan; Hanazono's south-arm frame remains separate.
- Minamimachi has no defensible drawn platform frame in the supplied raw. Its Apple station POI lies on the continuous own black rail and is recorded as an explicit cartographic warning.
- Katsuyamacho uses the first identified platform face chainage normally projected onto the own black rail; no face-gap average is used.
- Kamiichiman's main-line frame remains distinct from the Renraku branch frame sharing station ID 008742. Furu Otemachi's own tram frame remains distinct from its Johoku alias frame. Complete related guard evidence is required before integration.
- Compact source segment arrays are provenance only. Integration parity must use `network.decodeIntervals`, including welded station starts.
- No station representative is borrowed from another rail line; no physical registry or route serialization is changed.
