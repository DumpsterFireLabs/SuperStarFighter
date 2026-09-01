# Audio drop-in contract

Super Star Fighter runs safely without external audio files. When files are absent, menu/gameplay music is silent, victory music has a generated fallback, and combat uses synthesized placeholder effects generated at runtime.

Add the future music files at these paths:

- `music/main_menu.mp3` — the singular main-menu/lobby track.
- `music/gameplay/*` — any number of gameplay tracks, played in filename order as a playlist.
- `music/win.mp3` — recommended exact filename for the match-victory track; a generated victory theme is used when absent. `win.wav` and `win.ogg` are also accepted.

Music accepts `.mp3`, `.ogg`, and `.wav`. Discovery uses the final extension, so compound source names such as `main_menu.mp3.wav` also work.

Optional authored SFX can replace the synthesized placeholders without code changes. Put `.wav`, `.ogg`, or `.mp3` files in `sfx/` using these names:

`fire`, `beam_fire`, `reload`, `shield_on`, `shield_block`, `shield_break`, `damage`, `elimination`, `card_lock`, `countdown`, `overtime`, `round_win`, `match_win`, `projectile_impact`, `ricochet`, `mine_detonated`, and `rebound`.

Mine sound-design candidates can use a `mine_detonated_preview_*` prefix without being loaded by the game. Rename the selected candidate to `mine_detonated.wav` to activate it.

Weapon firing uses build-aware procedural sounds by default. The stable legacy `fire` and `beam_fire` files remain generic authored fallbacks, while individual weapon families can be replaced with these stems:

- `weapon_standard`
- `weapon_automatic`
- `weapon_heavy`
- `weapon_rail`
- `weapon_scatter`
- `weapon_beam_pulse`
- `weapon_beam_repeater`
- `weapon_beam_lance`

Add `_01`, `_02`, or `_03` for deterministic shot variants, such as `weapon_heavy_02.wav`. For power-specific replacements, insert `_base`, `_modified`, `_powerful`, or `_extreme` before the variant: `weapon_beam_lance_extreme_03.wav`. Resolution order is power-specific variant, family variant, family stem, legacy generic fire/beam, then the generated build-aware sound.

The procedural and authored paths both play one launch sound per volley. Projectile count, damage, cadence, speed, pierce, ricochet, knockback, beam conversion, weapon-card rarity, and accumulated weapon stacks determine the family and weight of the generated fallback.

Audio files must be original or properly licensed for the project.
