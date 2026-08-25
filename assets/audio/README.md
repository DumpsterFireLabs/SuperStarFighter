# Audio drop-in contract

Super Star Fighter runs safely without external audio files. When files are absent, menu/gameplay music is silent, victory music has a generated fallback, and combat uses synthesized placeholder effects generated at runtime.

Add the future music files at these paths:

- `music/main_menu.mp3` — the singular main-menu/lobby track.
- `music/gameplay/*` — any number of gameplay tracks, played in filename order as a playlist.
- `music/win.mp3` — recommended exact filename for the match-victory track; a generated victory theme is used when absent. `win.wav` and `win.ogg` are also accepted.

Music accepts `.mp3`, `.ogg`, and `.wav`. Discovery uses the final extension, so compound source names such as `main_menu.mp3.wav` also work.

Optional authored SFX can replace the synthesized placeholders without code changes. Put `.wav`, `.ogg`, or `.mp3` files in `sfx/` using these names:

`fire`, `beam_fire`, `reload`, `shield_on`, `shield_block`, `shield_break`, `damage`, `elimination`, `card_lock`, `countdown`, `overtime`, `round_win`, and `match_win`.

Audio files must be original or properly licensed for the project.
