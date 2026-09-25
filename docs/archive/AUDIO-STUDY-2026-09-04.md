# Audio startup, residency, and crowded-combat evidence

Review items R12/R13, September 4, 2026. Baseline: `e88565f`; after: this working tree. The final wrapper also checked `08fffb9`, whose audio director source is identical to `e88565f`. R13 is complete as a measured implementation decision. R12 has technical mixing changes and repeatable recordings, but human listening acceptance remains open. No card balance or gameplay timing changed.

## Resource and process measurements

The 132,474,364 bytes of source WAV files are already imported with Godot compression. Seven current referenced `.sample` resources total **17,873,300 bytes**. An initial whole-cache total also counted orphan imports; it is not the shipped audio footprint.

Read-only inspection of the existing `builds/beta-10/SuperStarFighter-Beta10.exe` found a **129,139,576-byte executable**, a **20,011,884-byte embedded PCK**, and those same seven audio entries totaling **17,873,300 bytes**. This export predates the current review changes. No fresh release package was produced, and lazy loading does not reduce packaged asset size.

Three paired fresh headless processes per version, with warm filesystem caches, measured the director's construction and initialization. Windows process working set/private bytes were read after initialization; Godot static allocation and retained compressed music buffers were measured separately. These figures are not full rendered-client launch time or GPU memory.

| Median measurement | Before | After |
| --- | ---: | ---: |
| Audio director initialization | 63.038 ms | 45.964 ms |
| Windows working set | 116,834,304 B | 99,827,712 B |
| Windows private bytes | 67,428,352 B | 50,884,608 B |
| Director static allocation increase | 18,212,460 B | 630,272 B |
| Startup retained music data | 17,761,120 B | 0 B |

A preceding single startup sample was 122 ms; it is not used as the paired comparison. The startup fixture begins in the silent context. A real client immediately requests menu music, which retains **1,375,616 bytes**. The tested gameplay track retains **3,787,800 bytes**, victory **1,303,080 bytes**, and silent context zero. Only the current context/track remains resident; menu crossfade players share one resource. Actual on-demand loads run asynchronously. The fixture also exposes synchronous context preparation to measure retained data deterministically.

Decision: retain current imported formats, discover paths without loading every track, request music on demand, and release inactive streams. Avoid another lossy transcode or a speculative streaming-format migration.

## Mixing changes and technical evidence

The fixed effects pool remains 24 voices. At most eight remote weapon voices and six remote effect voices can play concurrently. Local damage/shield feedback and objective cues have higher priority; lower-priority voices can be replaced if needed. Remote sources pan horizontally while retaining some signal in both ears. Distant sounds attenuate, explosions and decorative impacts are quieter, and important cues briefly lower music by up to 7 dB. A final limiter protects output peaks. Generated weapon variants use a bounded 96-entry least-recently-used cache.

Friendly flag pickup or local hill control uses rising notes; enemy pickup or loss of local hill control uses falling notes; flag drops use a neutral level tone. Full state snapshots establish a baseline without replaying events, and match resets clear it. Shield block and hull damage retain distinct duration/frequency shapes.

`audio_verifier.gd` records the actual Godot Master bus using the Dummy audio driver, rather than assembling a synthetic mix outside the engine. `cue_audition.wav` presents seven named cues, then left and right weapon shots. `crowded_mix.wav` combines music, 32 pilot emitters, remote explosions, and scheduled local feedback. The fixture runs against elapsed wall time so recording timing does not depend on headless frame pacing.

The final wrapper completed without script or resource-leak errors. A brief mixer drain before harness exit resolved a recorder shutdown warning; the gate now rejects leaked-instance/resource-in-use errors. The recorded fixture peaked at **18 concurrent voices**, stayed within its budgets, and returned music ducking to zero. Thousands of suppressed remote voices are expected in this deliberately saturated fixture; they show admission limits working, not missing authoritative combat events. The recorded crowded mix reached approximately **−1.00 dBFS** with **zero clipped PCM samples**. Isolated left/right shots have mirrored channel energy, with about a 5:1 RMS ratio favoring the source side. Peak-window spectral analysis differentiates shield block (about 874 Hz centroid) from hull damage (about 162 Hz); these measurements do not establish perceptual recognition or absence of masking.

## Reproduction and local artifacts

Run from the repository root with Godot bootstrapped:

```powershell
./tools/verify-audio.ps1 -Samples 3 -BaselineRevision e88565f
python ./tools/analyze-audio.py reports/audio-verification --package builds/beta-10/SuperStarFighter-Beta10.exe
```

The first tool records process measurements and audition WAVs under ignored `reports/audio-verification/`; `-SkipRecording` limits it to memory measurements. The analyzer uses Python's standard library and records PCM levels, channel direction, source/import footprint, and optional existing-package contents in `analysis.json`. The memory probe is Windows-specific; native cross-platform acceptance remains in R27.

Original paired measurement evidence is retained locally as `reports/review-2026-09-03/audio-os-before-[1..3].log` and `audio-os-after-[1..3].log`. `audio-baseline.json` and `audio-final/memory.json` retain the earlier resource measurements. Current reproducible clips and analysis live under `reports/audio-verification/`.

## Listening acceptance still required

Listen to the cue sequence and crowded mix on headphones and ordinary speakers at a comfortable fixed volume. Confirm shield block, shield break, and hull damage can be identified without looking; left/right direction agrees with the shot; objective gain/loss/drop can be distinguished during music and gunfire; and ducking recovers without distracting pumping. Repeat during human multiplayer play, including a high-action build and a late spectator. Record device, settings, observations, and any confusing cue before tuning further.

The initial automated review did not include a listening session. Subsequent player feedback is recorded below; R12 remains open for the unconfirmed checks, coordinated with the broader R24 player-readability checks. These short local measurements also do not replace R25 representative-hardware performance acceptance.

## Player feedback during batch eight

The user listened to the supplied clips and reported: “I can hear the other sounds over the clutter/crowded mix relatively easily.” This is positive human evidence that important sounds remain audible in the crowded fixture. The listening device, individual shield/hull cue identification, and left/right localization were not specified. R12 therefore retains those narrower acceptance checks; no further mix tuning was inferred from this feedback.

## Headset acceptance follow-up

Using a **Logitech G733 headset**, the user confirmed shield block, shield break and hull damage are distinct and that no audition sound is confusing, harsh or quiet. Both directional shots initially appeared bilateral. A channel-isolation diagnostic then exposed that Windows mono audio had been enabled. After identifying that system setting, Codex's embedded audio playback still appeared mono: even a diagnostic whose first right channel and second left channel contain exactly zero samples sounded bilateral. The initial localization result is therefore invalid rather than a demonstrated game-mix failure. A provisional stronger game pan was reverted. Retry the original recording in an external stereo player with Windows mono disabled; ordinary-speaker and crowded objective-cue checks remain afterward.

The external headset retry passed with Windows mono disabled and Logitech G Surround Sound turned off: left/right channels split correctly and the final weapon shots localized in the intended order. This validates the original game pan on the G733 in stereo mode. Logitech surround processing prevented reliable localization in this test; players encountering bilateral cues should check operating-system mono and headset virtualization before changing the game mix. Headset cue identity, quality and direction are accepted. Crowded objective-cue identification and an ordinary-speaker pass remain.

Preparing the crowded objective acceptance exposed a fixture omission: its loop stopped after six of the seven scheduled cues, so the objective neutral/drop sound was never recorded in the crowded mix. The loop now follows the cue list length and includes gain, loss and neutral/drop before recording ends. This changes only the verification fixture, not runtime playback.

On the updated G733 stereo-mode crowded mix, the user reported: “Thats crazy and chaotic. I love it. Sounds great.” This is positive acceptance of the deliberately saturated mix's character and sound quality. Explicit recognition of each gain/loss/neutral objective meaning is requested separately before closing that criterion.

The user subsequently confirmed all three crowded objective meanings were distinguishable: rising gain, falling loss and short level neutral/drop. The Logitech G733 stereo-mode pass is therefore complete for combat-cue identity, left/right localization, crowded objective recognition, loudness and subjective mix quality. An ordinary-speaker pass remains before R12 can close.

The user does not currently have another speaker and asked to proceed with R12 **conditionally complete**. Acceptance therefore applies to the Logitech G733 with Windows mono and G Surround disabled. Ordinary-speaker playback remains a deferred condition, to be folded into later human/native-hardware acceptance rather than blocking the current review walkthrough.
