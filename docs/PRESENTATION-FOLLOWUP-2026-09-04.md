# Presentation follow-up — 2026-09-04

Three remaining presentation items are addressed:

1. **Card headlines describe the tactical effect.** Modifier cards within one family can now say “Shorten your reload downtime” or “Fire more shots before reloading,” instead of sharing a generic family description. Shield headlines distinguish capacity, recovery, coverage and block efficiency. Mechanic unlocks retain their existing descriptions; effective values, clamps and tradeoffs still come from the build preview.
2. **The enlarged combat lab has more browsing space.** The Build tab dedicates its available height to the card list, with preset/search controls alongside one another and stack actions fixed below it. The selected card's full description has a separate Card tab with a return action. Search and selection survive tab changes, and cards can be added while inspecting them. Paused-editor status spacing is compacted; live-range status returns when play resumes. Targets and Stats remain accessible, with Clear build in Stats. At 1280×720 and 150% scale the capture shows nine complete card rows plus part of the next row.
3. **Objective labels avoid collisions.** A bounded placement search checks the full icon/caption rectangle against all previously placed objectives and visible HUD, toggle status, spectator, diagnostics and kill-feed entries. Carrier return routes have priority. Shifted arrows continue pointing toward their targets. Existing ship and incoming-projectile markers are unchanged.

Validation: 6,441 assertions passed, including 119 new assertions for tactical text, crowded corners at 720p/1080p/5120×1440, HUD exclusion, return-route priority and actual lab browsing/inspection at enlarged scale. Final production captures completed at 1280×720 and 1920×1080 with strict engine-error checks. The new enlarged details state is part of the capture sequence and standard presentation wrapper's required-image list. Selected 720p captures were inspected for readable text, complete controls and objective/status separation; this is automated/visual acceptance, not a human controller-usability playtest.

Selected evidence:

- [Enlarged card browser](presentation-evidence-2026-09-04/lab-scaled.png)
- [Enlarged card details](presentation-evidence-2026-09-04/lab-details-scaled.png)
- [Draft headlines](presentation-evidence-2026-09-04/draft.png)
- [Flag/base navigation](presentation-evidence-2026-09-04/flag-navigation.png)
- [Carrier return route](presentation-evidence-2026-09-04/flag-return.png)

Local full captures remain in `.tools/presentation-followup-final`; strict capture output is in `.tools/presentation-followup-1280x720.log` and `.tools/presentation-followup-1920x1080.log`. The closing suite output is `.tools/presentation-final-acceptance-tests.log`. No card balance or shield timing changes are included.
