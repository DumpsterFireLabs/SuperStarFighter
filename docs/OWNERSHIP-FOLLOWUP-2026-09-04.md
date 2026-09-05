# Client ownership follow-up — 2026-09-04

The draft controller now receives explicit network, audio, catalog, theme and canvas dependencies. It requests card inspection and presentation refresh through signals. Its context callback supplies only the local build and draft-bye status, with the root normalizing integer/string peer keys and copying the build dictionary. It no longer keeps the client root or reads the full match payload.

Removed 25 draft/settings field aliases and 14 forwarding methods from `client_main.gd`. Production callers, unit tests and presentation captures now address the owning controller directly. The root still handles cross-screen coordination, accessibility propagation and settings return/focus behavior; those callbacks contain real orchestration and remain there.

This is a bounded follow-up to the controller extraction. Settings and standings still retain root dependencies; this change does not claim that every client screen is independent.

Validation: the ownership changes passed 6,322 assertions, including draft confirmation, expired/rejected offers, keyboard access, accessibility propagation, settings focus and presentation integration. The combined follow-up suite also passed after the presentation additions. No gameplay balance or wire-protocol changes.
