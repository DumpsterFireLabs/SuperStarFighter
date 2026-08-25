# Audio drop-in contract

Super Star Fighter runs safely without external audio files. When files are absent, music is silent and combat uses synthesized placeholder effects generated at runtime.

Add the future music files at these paths:

- `music/main_menu.mp3` — the singular main-menu/lobby track.
- `music/gameplay/*.mp3` — any number of gameplay tracks, played in filename order and looped as a playlist.

Optional authored SFX can replace the synthesized placeholders without code changes. Put `.wav`, `.ogg`, or `.mp3` files in `sfx/` using these names:

`fire`, `reload`, `shield_on`, `shield_block`, `shield_break`, `damage`, `elimination`, `card_lock`, `countdown`, `overtime`, `round_win`, and `match_win`.

Audio files must be original or properly licensed for the project.
