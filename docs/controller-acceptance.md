# Controller acceptance

Realmz Rebuilt provides a controller-owned route through startup, workspaces, text entry, exploration, combat, and persistence without using a virtual mouse. Keyboard and mouse remain available in the same session. The implementation targets Godot's recognized desktop gamepads on Windows, Linux, and macOS, with automatic Xbox, PlayStation, and Switch-style prompt families plus an explicit override.

## Implemented contract

- `ApplicationInputRouter` gives each controller event one active owner: capture or text editing, modal, radial, playback, targeting, focused workspace, or exploration.
- Controller input is normalized through named actions, dead zones, hysteresis, repeats, active-device tracking, disconnect suspension, and neutral-input acknowledgement.
- Every application workspace uses explicit focus navigation, active-root containment, semantic record restoration with next-then-previous fallback, nested-scroll retention, focus inspection, and readable disabled reasons. Deferred refreshes do not steal focus from a newer menu or modal owner.
- View/Create/Minus opens the top menu. Its controller owner traverses the existing headings and entries and invokes the existing route, command, or system operation before restoring workspace focus.
- Action and workspace radials use stable owner-supplied commands, fixed eight-direction slices, visible separators, original cropped command art where it exists, declared monochrome fallback symbols, a gold selected slice and pointer, at most eight entries per page, tap-and-confirm execution, and explicit cancellation. The primary workspace page is Items, Spells, Maps/Notes, Characters, Money, Preferences, Save & Load, and Explore.
- The modal QWERTY editor preserves draft, caret, validation, multiline, accent, Done, and Cancel semantics. Done returns text to the original field without submitting the surrounding operation.
- The embedded Godot file dialog replaces the native scenario picker and remains inside the same focus owner.
- Exploration uses the existing movement scheduler and interaction boundaries. Combat uses rules-supplied movement previews, explicit commits, target cycling, ordered multi-target and summon-space selection, area centers, rotation, and inspection.
- Persistent party Auto retains one pending host continuation across playback and temporary blockers, yields after every activation, resumes after explicit controller acknowledgement, rejects stale session revisions, and pauses visibly after a failed activation instead of retrying it.
- Controls are configurable as a draft with conflict handling, live input feedback, required-navigation validation, and persistent Apply and Restore Defaults actions. Presentation settings schema 15 preserves older values and custom bindings; schema 14 receives the Top Menu default only when View/Create/Minus is unused.
- Preferences and Maps/Notes expose visible category rails. Shoulders switch their declared sections directly instead of walking each control. Controller hints float over the upper stage at 75-percent opacity for three seconds without changing shell geometry and are not restarted by movement, repeats, confirmation, or stick noise.
- Runtime Testing admits bounded button and axis events only in isolated fixtures and reports focus identity. Live adventures continue to reject mutation.

This scope intentionally excludes virtual mouse emulation, vibration, and platform on-screen keyboard integration.

## Automated evidence

| Evidence | Result |
| --- | --- |
| Focused controller, Classic shell, System, and exploration workflow | Passed, 1,232 assertions across 4 suites |
| Aggregate repository verification | Passed, 4,325 assertions across 29 suites plus architecture, package alignment, media, icon, export-contract, provenance, workflow-inventory, and gameplay-parity checks |
| Rendered radial gallery | Passed on Windows with Mobile rendering: Actions and Workspaces at 1280 by 720, plus Workspaces at 800 by 600; ring, selected pointer, icons, labels, and unchanged Classic composition inspected |
| Runtime Testing TypeScript build and tests | Passed, 39 tests including the rendered fixture journey; 1 environment-dependent transport test skipped |
| Rendered Windows controller journey | Passed: actual joypad events opened System, navigated focus, quick-saved, and loaded through application owners |
| Controller text journey | Passed: controller-only Journal navigation opened QWERTY, edited a draft, enabled Save Note, then committed separately |
| Rendered combat command discovery | Passed: actual West-button input opened three radial pages beginning with the disabled Weapon command and its reason; all 13 existing commands retain stable order and disabled reasons, Fast Spells follow them, and hidden command-shelf activation uses the existing response owner |
| Navigation latency, 1280 by 720 | 1,000 samples; p50 19 microseconds, p95 35 microseconds, maximum 102 microseconds |
| Navigation latency, 800 by 600 | 1,000 samples; p50 19 microseconds, p95 37 microseconds, maximum 105 microseconds |
| Navigation performance budget | Passed; p95 budget is 2,000 microseconds |
| Startup first frame | Passed in three warmed runs; 157.889 to 181.432 milliseconds, with the splash-only first-frame contract preserved |
| Native export contract | Passed for Windows, Linux, and macOS |
| Native export construction on Windows | Passed: Windows executable/PCK, Linux binary/PCK, and macOS ZIP produced successfully |

The rendered journey also verifies focus observations exposed by the testing bridge. Unit and integration tests cover diagonal quantization, repeats, releases, radial paging, modal isolation, remapping, focus restoration, mixed input, disconnect acknowledgement, exploration boundaries, combat previews, target modes, and unchanged state/RNG for cancelled previews.

## Hands-on acceptance matrix

Export construction and automated input routing do not prove hardware comfort, platform glyph detection, or operating-system reconnection behavior. These checks remain a release-candidate acceptance gate:

| Controller family | Windows | Linux | macOS |
| --- | --- | --- | --- |
| Xbox-style | Not yet tested physically | Not yet tested physically | Not yet tested physically |
| PlayStation-style | Not yet tested physically | Not yet tested physically | Not yet tested physically |
| Switch-style | Not yet tested physically | Not yet tested physically | Not yet tested physically |

For each cell, record device model and connection type, confirm detected labels, complete a controller-only startup-to-save/load journey, exercise QWERTY and every combat target mode, disconnect and reconnect during ordinary input and Auto playback, and note comfort or reachability defects. Linux and macOS binaries must be executed on their native operating systems; cross-platform export creation on Windows is not runtime proof.

Public release remains separate from this implementation and requires the ordinary release preparation and verification workflow.
