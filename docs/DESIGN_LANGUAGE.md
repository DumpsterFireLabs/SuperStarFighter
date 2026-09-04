# Super Star Fighter Design Language

Super Star Fighter uses a tactical cockpit language: quiet navy surfaces carry
information, while neon is reserved for identity, interaction, and state. The
interface should feel energetic without making every control compete for
attention.

The canonical implementation is `res://src/client/ui/design_tokens.gd`. New
screens should use those semantic tokens and theme variations before adding a
local override.

## Principles

1. **One clear next action.** Each surface should have one visually primary
   action. Secondary, quiet, and destructive actions must not compete with it.
2. **Meaning before decoration.** Cyan means interactive or navigational,
   magenta supports secondary actions and headings, green means success or
   readiness, amber means focus or warning, and red means danger.
3. **Rarity is domain data.** Card rarity colours belong to cards, drops, and
   build chips. They do not define generic button or navigation states.
4. **State is never colour-only.** Pair colour with copy, a symbol, position,
   or shape: `READY ✓`, `SELECTED ✓`, disabled text, or a labeled status.
5. **Progressive disclosure.** Keep the immediate decision readable, then
   expose exact stats through the shared card preview or a dedicated modal.

## Semantic palette

Use the named constants in `DesignTokens`; do not duplicate their hex values.

| Role | Intended use |
| --- | --- |
| `BACKGROUND` | Full-screen void and modal scrim base |
| `SURFACE` | Primary panels |
| `SURFACE_RAISED` | Inputs and elevated content |
| `SURFACE_MUTED` | Recessed tracks and low-emphasis groups |
| `TEXT_PRIMARY` | Headings, values, and important labels |
| `TEXT_SECONDARY` | Supporting copy |
| `TEXT_MUTED` | Metadata and tertiary hints |
| `TEXT_DISABLED` | Unavailable controls and inactive states |
| `INTERACTIVE` | Default controls and navigation |
| `FOCUS` | Keyboard/controller focus and current decision |
| `SUCCESS` | Ready, confirmed, healthy, or positive state |
| `WARNING` | Time pressure and recoverable caution |
| `DANGER` | Destructive or disconnect actions |

Health, shield, team, and card-rarity colours are separate domain roles. They
may appear beside semantic UI colours, but should not replace them.

## Action hierarchy

Apply a `theme_type_variation` to every meaningful action:

| Variation | Use |
| --- | --- |
| `PrimaryButton` | The recommended next step on the current surface |
| `SecondaryButton` | Useful alternate or configuration flow |
| `QuietButton` | Back, cancel, refresh, and low-emphasis utilities |
| `DangerButton` | Quit, eject, disconnect, and irreversible actions |
| `SettingToggle` | Neutral on/off preferences |
| `SuccessToggle` | Readiness or positive commitment |

Do not place multiple primary actions in the same decision group. Prefer
specific labels such as `EXIT TO LOBBY` or `APPLY APPEARANCE` over vague labels
such as `OK`.

## Focus and input

- Every operable control must be reachable by keyboard and controller.
- The first sensible action receives focus whenever a surface opens.
- Focus uses the shared amber outline with restrained glow and no fill, preserving
  the action's semantic accent. Hover follows that accent.
- Rarity cards keep their rarity fill and border while focus adds an amber
  outer decision cue.
- Compact build chips remain focusable so their detailed previews are not a
  mouse-only feature.
- Focus a card and press `I` or controller `Y` to inspect it. Activating a build
  chip also opens details. Draft activation remains a separate pick/confirm flow.
- Escape or the mapped cancel action closes the topmost modal and restores
  focus to the control that opened it.

## Modal surfaces

A modal is a temporary decision layer, not a neighboring panel. It must:

1. Show a dimming input blocker beneath the modal.
2. Hide or inert the underlying interactive panel.
3. Focus the modal's first meaningful control.
4. Provide an explicit completion or cancel action.
5. Restore the previous surface and focus when closed.

The match-options, ship-colour, and shared card-inspection flows follow this
contract. Card inspection blocks gameplay input; closing it restores card focus.
Releasing the momentary scoreboard also closes any inspection opened from it.

## Information hierarchy

Use the following scan order for decision cards:

1. Input shortcut or choice number
2. Card name
3. Mechanic role and short effect description
4. Up to two effective before/after changes, retaining a headline drawback
5. Count of additional changes available in details
6. Stack change and selection state
7. Rarity and tier chance in a stable footer

The full graphical card preview owns exact per-stack and compounded statistics.
Draft, scoreboard, and results should all use that same preview component.
Keep a visible Inspect action or input hint next to compact card choices.

Stat labels, units, and benefit polarity come from `StatMetadata` and its
`CombatStatDescriptor` entries. Use the shared formatter for nominal modifiers,
effective before/after values, and lab summaries; retain units when values wrap
at narrow widths. Graphical and accessible card details share modifier rows.
Context-dependent changes retain neutral meaning instead of assuming that every
larger number is beneficial.

Combat status follows a similarly stable order:

1. Match state and mode
2. Map, round, and heat
3. Alive count, objective, and overtime timing
4. Hull, shield, and ammunition
5. Low-priority control hints

Prefer explicit labels (`ROUND 2 / HEAT 3`) over compressed notation when the
space is available.

## Layout and responsive behavior

- Center decision panels inside the available safe area.
- Preserve the arena's aspect and reveal additional space on ultrawide displays
  rather than stretching controls horizontally.
- Use scrolling for variable-length rosters, bindings, and standings.
- Scroll containers follow keyboard/controller focus. Keep Host & Join outside
  its scrolling fields, and keep frequent lab stack actions outside the build scroll.
- Keep a readable line length for instructional copy; wrap it instead of
  shrinking type.
- At 1280 × 720, the primary action, close action, and full decision content
  must remain visible without clipping.
- Verify every production surface at 1280 × 720, 1920 × 1080, 2560 × 1080,
  2880 × 1920, 3440 × 1440, and 5120 × 1440.

Combat Lab and Learn to Play use the shared theme, including list selections,
checkboxes, tabs, padded buttons, and quiet panels. Lab content is grouped into
Build, Targets, and Stats; Enter Range is its primary action. Kill-feed event
verbs remain complete while long pilot names may truncate. A local-player marker
adds emphasis without borrowing the amber focus treatment.

## Review checklist

Before merging a new or changed screen, confirm:

- The surface has one obvious primary action.
- Every action uses the correct semantic variation.
- Focus is visible and navigation starts in a sensible place.
- Meaning is not conveyed by colour alone.
- Any modal blocks the underlying screen and restores focus on close.
- Card details work with pointer, keyboard, and controller input.
- Text does not clip at the six presentation-verification resolutions.
- The presentation capture and full test suite pass.

Run:

```powershell
.\tools\run-tests.ps1
.\tools\verify-presentation.ps1
```


## Build geometry, world materials, and readable text

`ShipBuildGeometry` derives up to three restrained modules from actual effective stats: beam, spread, cannon, shield, drive, ordnance, and repair. Modules stay within the existing hull envelope; collision, directional shields, and allegiance shapes retain their meaning. They supplement cosmetic paint rather than redefine teams.

`ArenaStaticLayer` uses station panel seams, cargo ribs, crystal facets, thermal vents, and stone fractures. Numbered material callouts identify landmarks. Material marks sit on actual solid cover with continuous outer collision boundaries; they must not imply traversable holes or new hazards. Static commands remain cached.

`AccessibleInterface` applies a 21 logical-pixel minimum to interface text (about 14 physical pixels at 720p under the current canvas scale). Deliberately hidden native labels under custom card content are exempt. Wrapped card bodies and footers, a centered taller draft panel, and scrollable settings/rosters accommodate the larger text. High contrast strengthens text and surface boundaries without replacing team shapes or card rarity labels. This is an implementation floor, not human readability or formal contrast-conformance acceptance; those checks remain in the review's player-validation work.

## Competitive canvas

Competitive view is a host-selected match rule, separate from the HUD safe area. During these matches keep a fixed 1920×1080 logical world canvas, center the fitted content, and use native bars for wider/taller windows. Keep mouse aim and the gameplay crosshair inside that canvas. Preserve ordinary expanded menus after leaving a match. Presentation captures store the native content framebuffer, which excludes window bars; test the visible world extent as well as image dimensions.
