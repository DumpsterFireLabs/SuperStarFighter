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
specific labels such as `EXIT TO LOBBY` or `APPLY COLOUR` over vague labels
such as `OK`.

## Focus and input

- Every operable control must be reachable by keyboard and controller.
- The first sensible action receives focus whenever a surface opens.
- Focus uses the shared amber outline and glow. Hover remains cyan or follows
  the action's semantic accent.
- Rarity cards keep their rarity fill and border while focus adds an amber
  outer decision cue.
- Compact build chips remain focusable so their detailed previews are not a
  mouse-only feature.
- Escape or the mapped cancel action closes the topmost modal and restores
  focus to the control that opened it.

## Modal surfaces

A modal is a temporary decision layer, not a neighboring panel. It must:

1. Show a dimming input blocker beneath the modal.
2. Hide or inert the underlying interactive panel.
3. Focus the modal's first meaningful control.
4. Provide an explicit completion or cancel action.
5. Restore the previous surface and focus when closed.

The match-options and ship-colour flows are the reference implementations.

## Information hierarchy

Use the following scan order for decision cards:

1. Input shortcut or choice number
2. Card name
3. Category
4. Effect description
5. Stack change
6. Rarity and tier chance
7. Selection state

The full graphical card preview owns exact per-stack and compounded statistics.
Draft, scoreboard, and results should all use that same preview component.

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
- Keep a readable line length for instructional copy; wrap it instead of
  shrinking type.
- At 1280 × 720, the primary action, close action, and full decision content
  must remain visible without clipping.
- Verify every production surface at 1280 × 720, 1920 × 1080, 2560 × 1080,
  2880 × 1920, 3440 × 1440, and 5120 × 1440.

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
