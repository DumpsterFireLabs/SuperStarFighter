# Source and asset attribution inventory

Reviewed September 4, 2026. This inventory records available evidence; it does not infer ownership or a redistribution license from filenames, commit authors, or embedded authoring-tool metadata.

## Repository source

| Scope | Evidence and status | Distribution treatment |
| --- | --- | --- |
| `src/`, `scenes/`, `data/cards/`, `resources/maps/` | Repository-maintained game code, scenes, card definitions and map resources. Git history records contributions and changes. | Released under the [MIT License](../LICENSE). |
| Code-drawn ships, terrain, icons, effects and synthesized audio | Implementations reside in `src/client/presentation/` and `src/client/audio/`, with shared gameplay definitions. No separate downloaded sprite/font package was found. | MIT, with the project source. The default font is an engine component, included in the engine notice inventory. |
| `tests/`, `tools/`, documentation and reference fixtures | Repository-maintained development material. Python tools use the standard library; PowerShell tools use platform APIs and the bootstrapped engine. | Excluded from game resource exports. No separately vendored application library or active Godot add-on was found. |
| `.tools/`, `.godot/`, reports and builds | Generated/cache/downloaded development state, excluded from Git or runtime source allowlists. Engine binaries are the relevant redistributed dependency. | Do not package the workspace wholesale. Audit the actual exported resource pack. |

## Engine dependency

The project pins official **Godot 4.7.2-stable** in `tools/common.ps1`; bootstrap validates release download SHA-512 checksums. `docs/THIRD_PARTY_NOTICES.txt` retains the Godot MIT notice. `docs/GODOT_COPYRIGHT.txt` contains engine and bundled component copyright/license records generated directly from that installed engine's `Engine.get_copyright_info()`, `get_license_info()` and `get_license_text()` APIs: 102 components and 19 named license texts. This is a conservative engine-source component inventory, which may include components not used by a particular platform template.

Regenerate after an engine upgrade:

```powershell
. ./tools/common.ps1
& (Get-SsfGodotExecutable) --headless --path . --script res://tools/generate-engine-notices.gd
```

Every packaging script includes both notice files. See Godot's [license documentation](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html) and [engine notice APIs](https://docs.godotengine.org/en/stable/classes/class_engine.html#class-engine-method-get-copyright-info) for the upstream source of this procedure.

## Authored asset files

`asset-provenance.json` inventories every runtime source asset, with exact path, byte length, SHA-256, first-addition commit and evidence/status. Imported representations derive from those source files and their checked-in `.import` settings; they are not additional independent works.

| Asset group | Repository evidence | Missing record |
| --- | --- | --- |
| `main_menu.ogg` (**Main Menu Loop**), `win.ogg` (**Galactic Triumph**, victory music) and gameplay tracks `Arcade Clash.ogg`, `Arcade Drive.ogg`, `Neon Battle.ogg`, `Neon Outrun.ogg`, `Power-Up Climax (Remastered).ogg`, `Space Combat.ogg`, and `Zenith Run.ogg`, generated with **Suno** | The project owner generated these tracks with Suno (usesuno.com). `Zenith Run` was left untitled by Suno (`song-snwn144`) and named by the project owner. The Suno MP3s had their metadata removed and were transcoded to Ogg Vorbis on 2026-09-24. They replace the Ovani Sound gameplay and menu tracks, which were removed from the project and scrubbed from Git history on 2026-09-24 together with the Ovani victory track, which `win.ogg` (Galactic Triumph) now replaces. | The project owner confirms these Suno generations carry commercial-use and redistribution rights, so they may be published in the source repository and shipped in builds. No attribution is required. Keep the Suno account/plan record privately. See the [Suno terms](https://suno.com/terms). |
| `mine_detonated.wav` | The project owner attests that the generated synthetic source was downloaded as a public-domain asset and directs that the current production cue be retained. The original page metadata is unavailable. Added in `135d9f9`; that change records the later WAV preroll processing. | Accepted for continued project use by owner attestation. No attribution was stated with the public-domain source. |
| `dumpster_fire_labs.png` | The project owner confirms creating the logo with GPT assistance and owning the resulting project artwork. No downloaded stock or third-party elements were used. Added in `9e3f3cc` as project branding. | All rights reserved; not covered by the MIT License (see [asset licensing](../assets/LICENSE.md)). Retain this creation statement with the asset inventory. |
| `crosshair.svg` | Small geometric SVG added in `822f1c5`; shape data and change are present in Git. | No separate third-party source is declared; MIT, with the project source. |

**Every runtime asset has a recorded provenance disposition.** The nine Suno music tracks are project-owned with redistribution rights; the logo and crosshair are project assets; the mine cue is retained under the owner's public-domain attestation. Source is MIT-licensed; the music and logo are reserved as described in [asset licensing](../assets/LICENSE.md).

For each unresolved group, record either its original creator and license/source or its original/in-house/generated creation record, including the relevant provider terms when applicable. Record required credit verbatim where supplied.

```powershell
python tools/verify-attribution.py
# Optional final acceptance check; fails while provenance is unresolved:
python tools/verify-attribution.py --require-resolved
```

The default check validates coverage and hashes and reports unresolved records. It does not equate inventory completeness with licensing clearance. The stripped dedicated server contains no external audio or branding assets; its engine notices are still included.
