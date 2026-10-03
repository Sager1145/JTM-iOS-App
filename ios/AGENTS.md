# Permanent product constraints

These are explicit user requirements. Fix layouts and implementations within
these boundaries; do not remove or weaken them to make a later audit pass.

- Every app surface, including Debug test surfaces, clamps Dynamic Type to
  `AppTypographyPolicy.supportedSizes` (`.xSmall ... .xLarge`). Keep the
  typography regression gate enabled in `verify.sh` and CI. UIKit font
  measurements must respect the same bounds.
- iPhone supports portrait only. Keep rotation-lock regression coverage.
  iPad retains its own orientation support.
- North America is retired. Do not package, load, migrate, or provide
  compatibility for US/CA railway data. The repository archive under
  `backups/north-america/` is offline evidence and is never an app input.
- Train routing uses physical railway topology. Proximity, equal names,
  passenger-transfer groups, coordinate coincidence, and through-service
  display relationships do not establish physical connections. Cross-track
  connections require reviewed physical evidence and real surveyed endpoints.
  Preserve through-service display independently of route solvability.
- Apple basemap dimming must cover the full viewport above the basemap and
  below railway drawing. Do not reintroduce per-tile dimming or an additional
  dimming animation during route highlighting.
