# Controller acceptance

Realmz Rebuilt provides a controller-owned route through startup, workspaces, text entry, exploration, combat, and persistence without using a virtual mouse. Keyboard and mouse remain available in the same session. The implementation targets Godot's recognized desktop gamepads on Windows, Linux, and macOS, with automatic Xbox, PlayStation, and Switch-style prompt families plus an explicit override.

## Implemented contract

- `ApplicationInputRouter` gives each controller event one active owner: capture or text editing, modal, radial, playback, targeting, focused workspace, or exploration.
- Controller input is normalized through named actions, dead zones, hysteresis, repeats, active-device tracking, disconnect suspension, and neutral-input acknowledgement. Application focus loss creates a controller suspension only when a pad has deliberately claimed ownership; keyboard/mouse-only play cannot block party Auto behind a controller acknowledgement. A neutral active-pad suspension accepts a consumed controller button, keyboard press, or pointer press as its explicit acknowledgement.
- Every application workspace uses explicit focus navigation, active-root containment, semantic record restoration with next-then-previous fallback, nested-scroll retention, focus inspection, and readable disabled reasons. Deferred refreshes do not steal focus from a newer menu or modal owner.
- View/Create/Minus opens the top menu. Its controller owner traverses the existing headings and entries and invokes the existing route, command, or system operation before restoring workspace focus.
- Action and workspace radials use stable owner-supplied commands, fixed eight-direction slices, visible separators, original cropped command art where it exists, declared monochrome fallback symbols, a gold selected slice and pointer, at most eight entries per page, tap-and-confirm execution, and explicit cancellation. The primary workspace page includes Items, Spells, Maps/Notes, Characters, Money, Preferences, Save & Load, and Explore. In exploration, X opens the action radial and `Move To` previews a route; D-pad/left-stick selects a destination, A commits travel, and B cancels. The five top-menu headings are Game, Adventure, Party, Settings, and Help; Save & Load remains a distinct workspace route. Adventure's checkable `Move To` menu preference enables persistent left-click route-selection mode; right-click directly requests legal movement, and neither the preference nor route state is a controller command path.
- The modal QWERTY editor preserves draft, caret, validation, multiline, accent, Done, and Cancel semantics. Done returns text to the original field without submitting the surrounding operation.
- The embedded Godot file dialog replaces the native scenario picker and remains inside the same focus owner.
- Exploration uses the existing movement scheduler and interaction boundaries. Combat uses rules-supplied movement previews, explicit commits, target cycling, ordered multi-target and summon-space selection, area centers, rotation, and inspection.
- Persistent party Auto retains one generation-tracked pending host continuation across playback and temporary blockers, yields after every activation, resumes after explicit controller acknowledgement, and waits for the matching committed revision to be presented and drawn before revalidating actor, request, session, revision, and Auto state. Failed revisions report once and do not retry automatically.
- Controls are configurable as a draft with conflict handling, live input feedback, required-navigation validation, and persistent Apply, Discard, and Restore Defaults actions. Preferences use five categories—Display, Audio & Pacing, Accessibility, Controls, and Diagnostics—with Save & Load as a separate route/mode. Presentation settings schema 19 adds default-off Immediate Single-Target Actions and click-to-move preferences; missing click-to-move values load as false. Immediate targeting preserves preview/confirm by default and changes only eligible pointer-selected single-combatant targeting. Older settings and custom bindings remain preserved.
- Preferences and Maps/Notes expose visible category rails. Shoulders switch their declared sections directly instead of walking each control. Controller hints float over the upper stage at 75-percent opacity for three seconds without changing shell geometry and are not restarted by movement, repeats, confirmation, or stick noise.
- Runtime Testing admits bounded button and axis events only in isolated fixtures and reports focus identity. Live adventures continue to reject mutation.
- The top menu uses a controller-owned dropdown inside the application viewport rather than a native popup. Entry movement clamps at its ends, held heading movement cannot wrap repeatedly, disabled reasons stay visible, South dispatches once, and pointer takeover closes the controller presentation cleanly.
- The Pen-designed quick-access panel uses eight stable directional slate tiles, native command imagery where available, a bounded central selection record, and a fixed page/Back footer. Canonical and compact layouts accommodate 150-percent text. Full disabled reasons stay in a scrolling detail well; right-stick scrolling and shoulder paging retain their existing semantics.

This scope intentionally excludes virtual mouse emulation, vibration, and platform on-screen keyboard integration.

## Automated evidence

The table below retains the original controller baseline. The current combat/navigation/menu/hotkey checkpoint and its newer aggregate results are recorded in [Combat, navigation, and controls acceptance](combat-navigation-controls-acceptance.md).

| Evidence | Result |
| --- | --- |
| Focused controller, Classic shell, and System workflow | Passed, 817 assertions across 3 suites |
| Aggregate repository verification | Passed, 4,385 assertions across 29 suites plus architecture, package alignment, media, icon, export-contract, provenance, workflow-inventory, and gameplay-parity checks |
| Rendered controller gallery | Passed on Windows with Mobile rendering: Actions and Workspaces at 1280 by 720, Workspaces at 800 by 600, and the controller-owned top menu at both sizes; compact center, selected pointer, icons, labels, bounded scrolling, and unchanged Classic composition inspected |
| Runtime Testing TypeScript build and tests | Passed, 39 tests including the rendered fixture journey; 1 environment-dependent transport test skipped |
| Rendered Windows controller journey | Passed: actual joypad events opened System, navigated focus, quick-saved, and loaded through application owners |
| Controller text journey | Passed: controller-only Journal navigation opened QWERTY, edited a draft, enabled Save Note, then committed separately |
| Rendered combat command discovery | Passed: actual West-button input opened three radial pages beginning with the disabled Weapon command and its reason; all 13 existing commands retain stable order and disabled reasons, Fast Spells follow them, and hidden command-shelf activation uses the existing response owner |
| Rendered Half Truth combat continuity | A native isolated host first ran a mixed manual/Auto battle through round 3; its two stops reported the explicit `controller-suspended` blocker after Windows focus loss, and neutral acknowledgement resumed the pending activation. A later foregrounded Battle 182 replay exposed and then eliminated a roster playback exception caused by treating a retained character button as a row container. With all six Auto toggles activated through their actual roster controls, the repaired build continued every available party activation until party defeat in round 2, produced 32 monster moves with no repeated per-activation destinations, and left a clean engine log. This proves the repaired drawn-revision continuation and the concrete lethal checkpoint, while a continuously foregrounded battle that survives for three rounds remains unrecorded. |
| Live Half Truth Battle 70 stall | A user-recreated read-only Debug observation on package `952b9705460e117b7b914e143134c895e04405d686de39e7d58bf2790d52b870` captured David first in round 1 at game revision 1786 with all six Auto toggles enabled, the combat request ready, presentation drawn, no failed revision, and the sole continuation blocker `controller-suspended`. The user confirmed that no controller was connected or paired. This demonstrates the former host defect rather than a David AI/pathfinding failure; focused regression now prevents focus loss from creating that blocker until a pad has claimed ownership. A repaired live replay remains required. |
| Battle-start stage chronology | Focused presentation coverage requires a playback base containing an active battlefield to select Combat immediately, while noncombat routes remain unchanged and terminal battle departure continues to wait for playback. This closes the source-confirmed route deferral that allowed Auto rounds to play behind the exploration map; repaired rendered acceptance remains required. |
| Navigation latency, 1280 by 720 | 1,000 samples; p50 19 microseconds, p95 35 microseconds, maximum 102 microseconds |
| Navigation latency, 800 by 600 | 1,000 samples; p50 19 microseconds, p95 37 microseconds, maximum 105 microseconds |
| Navigation performance budget | Passed; p95 budget is 2,000 microseconds |
| Startup first frame | Passed in three warmed runs; 157.889 to 181.432 milliseconds, with the splash-only first-frame contract preserved |
| Native export contract | Passed for Windows, Linux, and macOS |
| Native export construction on Windows | Passed: Windows executable/PCK, Linux binary/PCK, and macOS ZIP produced successfully |

The rendered journey also verifies focus observations exposed by the testing bridge. Unit and integration tests cover diagonal quantization, repeats, releases, radial paging, modal isolation, remapping, focus restoration, mixed input, disconnect acknowledgement, exploration boundaries, combat previews, target modes, and unchanged state/RNG for cancelled previews.

Current isolated raw-pad fixtures cover all 11 workspaces, Back, exploration and combat Move To, inspection tabs, Fire Weapon and equipped Bull Whip targeting, spellbook and combat inventory entry, controller draft Apply/Discard/Keep Editing, and Music modal focus isolation/restoration. The wheel was inspected at 1280×720 and 800×600 with 150-percent text; all five preference categories and Save & Load have current canonical/compact captures. Pointer-menu opening, heading switching and grace-period dismissal passed. Classic keyboard fixtures additionally cover saved mode selection, route keys, Scroll Case, trade, text-entry protection, spell abort and combat inventory. These are injected-input, visibly isolated runtime checks, not physical-device comfort or ordinary-adventure certification.

## Hands-on acceptance matrix

Export construction and automated input routing do not prove hardware comfort, platform glyph detection, operating-system reconnection behavior, or uninterrupted Auto in a continuously foregrounded native window. These checks remain a release-candidate acceptance gate:

| Controller family | Windows | Linux | macOS |
| --- | --- | --- | --- |
| Xbox-style | Not yet tested physically | Not yet tested physically | Not yet tested physically |
| PlayStation-style | Not yet tested physically | Not yet tested physically | Not yet tested physically |
| Switch-style | Not yet tested physically | Not yet tested physically | Not yet tested physically |

For each cell, record device model and connection type, confirm detected labels, complete a controller-only startup-to-save/load journey, exercise QWERTY and every combat target mode, disconnect and reconnect during ordinary input and Auto playback, and note comfort or reachability defects. Linux and macOS binaries must be executed on their native operating systems; cross-platform export creation on Windows is not runtime proof.

Public release remains separate from this implementation and requires the ordinary release preparation and verification workflow.
