# Settings and standings ownership — 2026-09-04

Settings and standings no longer retain the client root. Settings receives audio, input profiles and the shared theme; standings receives network, audio, catalog, theme, canvas and narrow context/availability callbacks. Navigation, accessibility propagation and card inspection use signals. The root keeps cross-screen coordination and creates the shared theme before configuring its consumers.

Removed 22 standings property aliases, 18 forwarding methods, two unused card-text wrappers and their unused root constants. Production callers, captures and tests now address the owning controller directly.

Standings keeps a detached match/roster observation shared by all rows. Match and lobby events invalidate that observation; unchanged render frames reuse it. This avoids both per-row roster deep copies and copying the match on every frame. Result pending actions and dirty row state remain with the controller. The existing authoritative request checks are unchanged.

Settings applies accessibility through explicitly registered interface trees: connection/match screens, network world, offline sandbox, card inspector, cursor and splash. Weak references allow retired trees to disappear; dynamic controls still receive contrast and minimum text size, and unrelated trees are untouched.

Independent-controller tests cover navigation and accessibility signals, dynamic interface styling/restoration, expired interface scopes, detached nested state, observation reuse, match-team precedence, card inspection, changed leadership and duplicate result actions. Existing production integration tests retain focus, screen construction, draft/results transitions and capture coverage.

This completes the settings/standings dependency cleanup. The connection controller and broader root orchestration remain separate architectural work; this does not claim every screen is independent. No gameplay, protocol, intended layout or persistent user settings changes.

Validation: **7,276 assertions passed**, with no unexpected Godot errors. The Windows certificate-store error is the repository's existing exact allowlisted environment error. The production presentation capture sequence completed successfully at **1280×720 and 5120×1440**, with strict exit/error/completion checks. Settings, contrast settings, results and ultrawide standings were also visually inspected. Export resource allowlists remain current. Selected screenshots and validation markers are retained in `settings-standings-evidence-2026-09-04/`.
