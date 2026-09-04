# Source and asset attribution inventory

Reviewed September 4, 2026. This inventory records available evidence; it does not infer ownership or a redistribution license from filenames, commit authors, or embedded authoring-tool metadata.

## Repository source

| Scope | Evidence and status | Distribution treatment |
| --- | --- | --- |
| `src/`, `scenes/`, `data/cards/`, `resources/maps/` | Repository-maintained game code, scenes, card definitions and map resources. Git history records contributions and changes. No project-level license grant is present. | Do not add an open-source license or claim third-party ownership without an owner decision. |
| Code-drawn ships, terrain, icons, effects and synthesized audio | Implementations reside in `src/client/presentation/` and `src/client/audio/`, with shared gameplay definitions. No separate downloaded sprite/font package was found. | Covered by the project's source licensing decision. The default font is an engine component, included in the engine notice inventory. |
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

`asset-provenance.json` inventories all fourteen runtime source assets, with exact path, byte length, SHA-256, first-addition commit and evidence/status. Imported representations derive from those source files and their checked-in `.import` settings; they are not additional independent works.

| Asset group | Repository evidence | Missing record |
| --- | --- | --- |
| `Distorted.ogg`, `Edge.ogg`, `Numb.ogg`, and `Woofer.ogg` from Ovani Sound's **Heavy Electronic** music pack | The project owner confirms these four tracks were legally acquired in Ovani Sound's **Audio Alchemy: Volume 2** collection. Repository filenames use the song titles directly. They were transcoded from WAV sources added in `7d35d78`. | Ovani Sound's current commercial, royalty-free music-pack license permits use integrated into games and does not require attribution. Raw or standalone redistribution is prohibited. Retain the purchase record privately and keep these files out of any public source-asset distribution. See the [Ovani Sound terms](https://ovanisound.com/policies/terms-of-service) and [FAQ](https://ovanisound.com/pages/faq). |
| `Infinity.ogg`, `Mach 10.ogg`, `No Doubt.ogg`, `Pull Up.ogg`, and `Stomped.ogg` from Ovani Sound's **Heavy Electronic** music pack | The project owner confirms these five tracks were legally acquired in Ovani Sound's **Audio Alchemy: Volume 2** collection. Added from `Heavy Electronic … Main.wav` sources and transcoded to Ogg Vorbis on 2026-09-04. | Same commercial, royalty-free Ovani Sound music-pack license as the other music: integrated game use is permitted, credit is appreciated but not required, and raw or standalone redistribution is prohibited. |
| `main_menu.ogg` — **Nightrunner**, from Ovani Sound's **Heavy Electronic** music pack | The project owner confirms legal acquisition through Ovani Sound's **Audio Alchemy: Volume 2** collection. Transcoded from a WAV source added in `7d35d78`; repository records audio loop processing. | Same commercial, royalty-free Ovani Sound music-pack license as the gameplay tracks: integrated game use is permitted, credit is appreciated but not required, and raw or standalone redistribution is prohibited. |
| `win.ogg` — **Electric**, from Ovani Sound's **Electronic** music pack | The project owner confirms legal acquisition through Ovani Sound's **Audio Alchemy: Volume 2** collection. Transcoded from a WAV source added in `7d35d78`; repository records audio loop processing. | Same commercial, royalty-free Ovani Sound music-pack license as the gameplay tracks: integrated game use is permitted, credit is appreciated but not required, and raw or standalone redistribution is prohibited. |
| `mine_detonated.wav` | The project owner attests that the generated synthetic source was downloaded as a public-domain asset and directs that the current production cue be retained. The original page metadata is unavailable. Added in `8490edf`; that change records the later WAV preroll processing. | Accepted for continued project use by owner attestation. No attribution was stated with the public-domain source. |
| `dumpster_fire_labs.png` | The project owner confirms creating the logo with GPT assistance and owning the resulting project artwork. No downloaded stock or third-party elements were used. Added in `7d35d78` as project branding. | Covered by the project's source licensing decision. Retain this creation statement with the asset inventory. |
| `crosshair.svg` | Small geometric SVG added in `822f1c5`; shape data and change are present in Git. | No separate third-party source is declared; retain under the project source licensing decision. |

**All fourteen runtime assets now have a recorded provenance disposition.** Eleven Ovani Sound music files are licensed for embedded game distribution; the logo and crosshair are project assets; the mine cue is retained under the owner's public-domain attestation. The separate project-level source-license decision remains open.

For each unresolved group, record either its original creator and license/source or its original/in-house/generated creation record, including the relevant provider terms when applicable. Record required credit verbatim where supplied. The project owner also needs to choose whether to publish a project license; none is assigned by this audit.

```powershell
python tools/verify-attribution.py
# Optional final acceptance check; fails while provenance is unresolved:
python tools/verify-attribution.py --require-resolved
```

The default check validates coverage and hashes and reports unresolved records. It does not equate inventory completeness with licensing clearance. The stripped dedicated server contains no external audio or branding assets; its engine notices are still included.
