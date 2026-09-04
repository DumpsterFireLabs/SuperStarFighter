# Graphical language and UI/UX review — 4 September 2026

## Implementation follow-up — 4 September 2026

All seven findings below have been addressed in the working tree. The original
review remains below as the record of the issues and their initial evidence;
its source line numbers and verification limitations describe the pre-fix state.

| Finding | Delivered change |
| --- | --- |
| 1. Card detail access | Shared scrollable inspection modal; `I` / controller `Y`, visible draft Inspect action, and build-chip activation. Blocks gameplay input, restores card focus, and closes with the momentary scoreboard. Pointer tooltips use the same preview. |
| 2. Hosting visibility | Host & Join stays outside the scrolling form; focused fields scroll into view. Lab stack actions also remain visible. |
| 3. Modal dismissal | Escape and mapped Back close the topmost lobby modal before general pause handling and restore opener focus. |
| 4. Training language | Shared theme, quiet panels, readable heading sizes, padded semantic actions, themed lists/checkboxes, Build/Targets/Stats tabs, and wrapping tutorial actions. |
| 5. Event text | Complete `left` and `defeated` verbs reserve space at the final text size; long player names yield space. Local events use a marker and quiet edge emphasis. |
| 6. Action semantics | Eject uses danger styling; Fresh Rematch is the sole primary results action and receives initial host focus. Focus adds an outline without replacing semantic or rarity fills. |
| 7. Draft hierarchy | Short effect summaries, two key before/after changes retaining a headline drawback, additional-detail counts, compact state text, stable rarity footers, and intact number/unit groups. |

The [design-language contract](DESIGN_LANGUAGE.md) and [manual](MANUAL.md) now
describe these behaviors. Card catalog ordering also uses an explicit lexical
comparison so the lab's card list remains alphabetical.

Validation:

- Full automated suite: **5,860 assertions passed, 0 failed**.
- Strict presentation gate: **passed all six resolutions**, from 1280×720 to
  5120×1440. [Post-fix captures and logs](../.tools/presentation-verification/)
  remain local ignored evidence. One initial ultrawide run failed to open card
  inspection; an isolated rerun and then the complete gate passed. Capture
  failures now include focus and immediate-open diagnostics.
- New interaction/layout checks use viewport keyboard/controller events for
  inspection, modal dismissal, focus restoration, and hosting visibility. All
  **136 cards at 20 stacks** were checked for decision-content/footer overlap.
- Presentation detail captures now open through actual keyboard input rather
  than manually constructing a tooltip.
- Post-fix visual spot checks cover hosting, draft/confirmation/details, results,
  scoreboard details, and the lab/tutorial at 150% scale. Physical controller
  hardware and live multiplayer usability remain outside this automated pass.

## Original review

**Verdict: a coherent visual foundation, with important gaps in interaction consistency and component adoption.** Keep the navy cockpit surfaces, restrained neon, recognizable ship silhouettes, and shared card identity. The next pass should complete the existing design system rather than introduce a new aesthetic.

This reviews the current working tree, including its existing uncommitted changes. It does not change production code. Recommendations below distinguish reproduced behavior from visual judgment.

## Scope and evidence

- Read the design-language contract, theme, menu/lobby/settings controllers, draft and standings components, training UI, HUD, accessibility adapter, and presentation tests.
- Generated **402 screenshots: 67 states at each of six resolutions** — 1280×720, 1920×1080, 2560×1080, 2880×1920, 3440×1440, and 5120×1440. Manually inspected 24 representative screenshots spanning all six resolutions. Generating the remaining images is not equivalent to manually reviewing them.
- Used an isolated Godot input probe to check Escape versus cancel, focus visibility in the host form, and card-detail activation.
- Captures and probe are in [the local evidence folder](../.tools/graphical-review-2026-09-04/). The folder is ignored by Git; preserve it separately if sharing this report. [Probe output](../.tools/graphical-review-2026-09-04/probe.out.log).
- All six capture sequences reported `PRESENTATION_CAPTURE_OK`. The strict `verify-presentation.ps1` gate **did not pass**: it stopped at 720p on log-write and Windows certificate-store errors. Separate runs with a writable log path completed the other resolutions with exit 0, retaining the certificate-store error. No script errors were reported in these capture runs. The full unit suite was not run for this review.

## Prioritized findings

### 1. Card details are inaccessible through focus or activation — high priority

**Reproduced behavior.** The same card has a detailed pointer tooltip but no corresponding inspection action for keyboard/controller users. This is especially consequential in the draft: full descriptions are hidden and some cards show “+1 IN DETAILS,” so the inaccessible surface contains information needed to choose an upgrade.

`CardHoverButton` creates its preview only through `_make_custom_tooltip`. A rendered probe focused the component, waited 1.5 seconds, and sent accept press/release: the preview count remained zero. The component had no focus-entered or pressed handler. Production standings chips likewise have no inspection handler; draft activation selects the card for confirmation.

**Change:** expose the existing preview through an explicit Inspect action and a visible input hint. Support focus-based preview where it does not obscure neighboring choices. Keep inspection separate from selecting and confirming. Provide predictable close behavior and return focus to the originating card.

**Accept when:** mouse, keyboard, and controller can read the same full description and effective stat changes in draft, standings, and results. Exercise real input rather than directly constructing the tooltip.

Sources: [card_hover_button.gd](../src/client/ui/card_hover_button.gd), lines 58 and 112; [standings_screen_controller.gd](../src/client/ui/standings_screen_controller.gd), lines 419–437; [presentation_system_tests.gd](../tests/unit/presentation_system_tests.gd), lines 814 and 847. Current tests establish focusability, not actual detail access.

### 2. Host & Join is hidden, even when it receives focus — high priority

**Visual and reproduced behavior.** Opening Host Game exposes the preset and first fields, while the required password and **Host & Join** action sit below the scroll boundary. Combat Lab remains a prominent visible action outside the tab. The hosting task therefore lacks a visible next step.

The host scroll container has `follow_focus=false`. The probe focused Host & Join and confirmed that its rectangle remained below the visible scroll area, with `scroll_vertical=0`. Users can reach an invisible control without seeing where focus went.

**Change:** put Host & Join in a persistent footer outside the scrolling fields; make the fields scroll to focused controls. Reduce the opening explanation or put advanced networking details behind a disclosure. Keep a visible indication that additional fields exist.

**Accept when:** the host action remains visible at 720p and every focused field scrolls fully into view. Check the LAN list and lab editor for the same scrolling behavior.

Source: [connection_controller.gd](../src/client/ui/connection_controller.gd), lines 254–288.

![Host form: the main action is below the scroll boundary](../.tools/graphical-review-2026-09-04/1280x720_host_menu.png)

### 3. Escape does not close lobby dialogs like controller Back — medium priority

**Reproduced behavior.** In Match Setup and Customize Your Ship, Escape leaves the dialog open; a `ui_cancel` event closes it. Escape matches both `pause_overlay` and `ui_cancel`, but the pause branch runs first and consumes it. In the lobby, its pause-toggle call returns without closing anything.

**Change:** centralize topmost-surface dismissal. Resolve modal cancel before general pause handling, using the same close path for Escape and controller Back. Preserve the existing focus restoration in the modal controllers.

**Accept when:** Escape and mapped Back close the same topmost dialog and restore its opener, including when settings, option popups, or input capture are involved.

Source: [client_main.gd](../src/client/client_main.gd), lines 464–500 and 971–973. The input probe reproduced both dialogs separately.

### 4. Training and Combat Lab use a different component language — medium priority

**Visual finding, supported by source.** The main menu and settings use rounded, padded controls, semantic borders, and prominent focus treatment. Combat Lab uses small, flat engine-default buttons, gray selection rows, a different navy surface, and tightly packed text. The tutorial adds a square panel with near-contiguous text buttons. Moving from Learn to Play into training feels like entering a development utility.

The lab title, instructions, card description, and stat summary also converge on nearly the same text size after the accessibility minimum is applied. At 150% HUD scale, much of the editor becomes a long scroll before stack actions and target controls are reached.

**Change:** apply the shared interface theme at the training HUD root and introduce semantic variants for its actions. Extend the theme to cover ItemList and CheckBox as needed. Use distinct heading, body, and metadata roles; group Build, Targets, and Measurements. Keep Enter Range and frequently used stack controls easy to reach.

**Accept when:** training buttons have the same padding, focus treatment, and action roles as menu buttons; the full editor remains navigable at 100% and 150% scale without obscured focus.

Sources: [lab_panel.gd](../src/client/sandbox/lab_panel.gd), lines 23–86 and 179–185; [combat_tutorial.gd](../src/client/sandbox/combat_tutorial.gd), lines 29–63; [offline_sandbox.gd](../src/client/sandbox/offline_sandbox.gd), lines 348–372.

![Combat Lab uses flat controls and nearly uniform text hierarchy](../.tools/graphical-review-2026-09-04/1280x720_build_lab.png)

### 5. Routine feed messages are truncated — medium priority

**Visual finding.** The kill feed displays “DISCONN…”, “ENVIRONM…”, and “ELIMINAT…” with ordinary fixture content. These are event meanings, not unusually long player names. The same truncation persists with enlarged HUD text; scaling up the whole component does not give its text more logical space.

The feed divides a fixed 420-unit row into minimum columns of 133, 118, and 133 units. Labels authored at size 15 are subsequently raised to the 21-unit accessibility floor, while the column allocation stays fixed.

**Change:** size the event column from the final typography, use shorter complete verbs such as “left” and “defeated,” or adopt a two-line event layout. Let player names truncate only after preserving the event's meaning. Retain a distinct local-player marker without borrowing the full interactive focus appearance.

**Accept when:** default elimination, environment, and disconnect messages remain complete at 720p, at both HUD scales, with short and maximum-length names.

Sources: [kill_feed.gd](../src/client/ui/kill_feed.gd), lines 98–161; [accessible_interface.gd](../src/client/presentation/accessible_interface.gd), lines 4–15. See [scaled combat capture](../.tools/graphical-review-2026-09-04/1280x720_combat_accessibility.png).

### 6. Action emphasis and color semantics conflict — medium priority

**Visual finding, supported by explicit theme assignments.** Several screens depart from the documented “one clear next action” rule:

- Lobby **Eject** controls use the default cyan button treatment; **Disconnect** uses danger red. Both remove someone from the session, but only one advertises its consequence.
- Results assigns `PrimaryButton` to both Fresh Rematch and Play 5 More Rounds, while initial focus goes to Exit to Lobby. The strongest immediate visual cue therefore points to a third action.
- The yellow focus fill resembles legendary card fills, winner rows, and locally relevant kill-feed entries. Selection, rarity, success, and attention are not always distinguishable at a glance.

**Change:** give Eject the danger variant. Choose one recommended results action, style alternatives as secondary/quiet, and align initial focus with the intended flow. Keep focus as a distinct outline or pointer; preserve rarity in a badge/edge and celebration in an explicitly labeled treatment. A shared hue can remain, provided shape and role are unambiguous.

**Accept when:** each decision group has one clear primary action, destructive actions share a visual role, and selected cards remain recognizable alongside legendary cards without relying only on yellow.

Sources: [connection_controller.gd](../src/client/ui/connection_controller.gd), lines 1170–1175; [standings_screen_controller.gd](../src/client/ui/standings_screen_controller.gd), lines 201–223 and 555; [design_tokens.gd](../src/client/ui/design_tokens.gd), lines 118–129; [draft_screen_controller.gd](../src/client/ui/draft_screen_controller.gd), lines 335–356.

![Results offers competing action emphasis](../.tools/graphical-review-2026-09-04/1280x720_results.png)

### 7. Draft cards need a stronger reading hierarchy — medium priority

**Visual judgment.** Five tall colored columns give the card set impact, but common metadata competes with the actual decision. “YOUR BUILD AFTER PICK” repeats across every card, names and values wrap frequently, and “px/s” can split across lines. Short cards retain large empty bodies while the player still has to read dense stat fragments near the top. Increasing screen resolution preserves these logical-width problems.

**Change:** retain five comparable choices, but put the shared comparison heading above the row. Give each card a clear name, short effect summary, aligned before/after values, and a compact rarity/stack footer. Keep number–unit pairs together. Use the accessible details surface from finding 1 for complete explanations and less important modifiers. Reduce full-card color fill so meaningful differences have more visual weight.

**Accept when:** a player can identify effect, benefit, drawback, and selection state by scanning consistent locations at 720p. Validate with actual first-time players before treating scan speed as solved.

Sources: [card_hover_button.gd](../src/client/ui/card_hover_button.gd), lines 44–106; [draft_screen_controller.gd](../src/client/ui/draft_screen_controller.gd), lines 125–185. See [draft capture](../.tools/graphical-review-2026-09-04/1280x720_draft.png) and [taller-display capture](../.tools/graphical-review-2026-09-04/2880x1920_draft.png).

## Design-system follow-through

After the interaction fixes, add named typography, spacing, control-height, and quiet-panel tokens alongside the existing palette and radii. A useful starting hierarchy is the project's existing 21-unit body floor, 24-unit section titles, 34-unit screen titles, and larger display headings. Validate the hierarchy visually rather than shrinking text to fit.

Use one label for each destination: **Combat Lab** rather than alternating Combat Lab, Build Laboratory, and Offline Combat Lab; **Learn to Play** for the entry point and lesson references. Standardize command capitalization and Back/Close/Cancel semantics. Keep compact combat labels intentionally separate from full menu labels.

Avoid making every boundary neon. Static content can use quiet dividers and surfaces; interaction, immediate combat state, and selected decisions should receive the strongest accents. Preserve the existing team shapes, rarity labels, health/shield distinctions, and stable centered menus. Those are useful foundations.

## Verification gaps to close

The capture harness validates output presence, size, and rendering completion, not readable text, reachable focus, or correct hierarchy. Its tooltip captures manually create and position the preview, bypassing the user interaction that currently fails. Add targeted interaction checks for findings 1–3, and text-fit checks for fixed event labels.

The captured error state also shows a stale lobby overlapping the connection form. Do **not** treat that image alone as proof of a shipping connection-error defect: the capture fixture sets a synthetic local peer ID while leaving the network role unset, and modal cleanup can restore that synthetic lobby. Recreate rejection with realistic session teardown before using the error screenshot as acceptance evidence.

The review did not verify physical controller hardware, native window bars, every possible card/build combination, live multiplayer usability, animation comfort, or formal accessibility conformance. Larger screenshots viewed downscaled are useful for layout comparison, not physical text-legibility certification.

Recommended order: fix detail access, hosting focus/visibility, and modal cancel; then unify training components and fix event text; then refine action semantics, card hierarchy, and shared tokens. Repeat the six-resolution capture pass and a short pointer/keyboard/controller walkthrough after those changes.
