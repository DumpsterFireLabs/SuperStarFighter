# Audio drop-in contract

Super Star Fighter runs safely without external audio files. When files are absent, menu/gameplay music is silent, victory music has a generated fallback, and combat uses synthesized placeholder effects generated at runtime.

Add music files at these paths:

- `music/main_menu.ogg` — the singular main-menu/lobby track.
- `music/gameplay/*` — any number of gameplay tracks, played in filename order as a playlist.
- `music/win.ogg` — recommended exact filename for the match-victory track; a generated victory theme is used when absent. `win.wav` and `win.mp3` are also accepted.

Music accepts `.mp3`, `.ogg`, and `.wav`. Discovery uses the final extension, so compound source names such as `main_menu.mp3.wav` also work.

All committed music (`main_menu.ogg` and the `gameplay/` tracks) is project-owned Suno generations with redistribution rights. Only add music the project may publish: `assets/audio/music/` is tracked by Git, and anything placed here also ships in game exports. Earlier licensed Ovani Sound tracks were removed and scrubbed from Git history on 2026-09-24.

Optional authored SFX can replace the synthesized placeholders without code changes. Put `.wav`, `.ogg`, or `.mp3` files in `sfx/` using these names:

`fire`, `beam_fire`, `reload`, `shield_on`, `shield_block`, `shield_break`, `damage`, `elimination`, `card_lock`, `countdown`, `overtime`, `round_win`, `match_win`, `projectile_impact`, `ricochet`, `mine_detonated`, `rebound`, `kinetic_vent`, `breakaway`, `afterburner`, `objective_gain`, `objective_loss`, and `objective_neutral`.

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

Music is discovered by path and loaded asynchronously when its context becomes active; only the current context/track stays resident. Existing imported compression is retained. Remote effects have bounded voice budgets and directional panning; local feedback and objective cues take priority and briefly duck music. Run `tools/verify-audio.ps1` to produce repeatable recordings and memory evidence. Recordings still require listening acceptance.

## Loading and mix verification

Music discovery retains file paths until a context needs its track. Interactive loads run on the resource loader thread; the two menu crossfade players share one buffer, and changing contexts releases inactive music. Bundled music remains Vorbis-compressed, while authored WAV effects retain their configured imports. Generated weapon variants use a 96-entry LRU cache.

The 24-voice effects pool limits remote gunfire to eight concurrent voices and other remote effects to six. Local hull/shield feedback and objective alerts take priority. World effects use restrained stereo panning; critical cues briefly duck music by 7 dB. The master limiter reserves a 1 dB output ceiling.

Run `./tools/verify-audio.ps1 -BaselineRevision 6efe87f` to collect paired process-memory probes and actual Godot mix-bus WAV recordings. Run `python tools/analyze-audio.py reports/audio-verification --package builds/beta-10/SuperStarFighter-Beta10.exe` for sample peak, RMS, stereo and local package measurements. The package argument inspects an existing export; it does not produce a new build. Recorded auditions still require headphone/speaker listening review.
