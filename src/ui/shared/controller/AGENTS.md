# Reusable controller overlays

## Purpose

Own reusable scene-authored controller overlays, including the radial command chooser and modal QWERTY text editor.

## Ownership

- `controller_radial_overlay.tscn` owns the authored responsive ring, compact center selection label, title and page indicator above the ring, scrollable full unavailable reason below it, backdrop, and persistent exit/page legend.
- `controller_radial_overlay.gd` owns presentation-only fixed eight-direction sectors, paging, selected-slice pointer, original-art rendering, input, and signal emission.
- `controller_radial_entry.gd` owns the typed command label, icon or declared fallback symbol, and availability data supplied by feature presenters.
- `controller_qwerty_editor.tscn` owns the authored modal text-entry layout.
- `controller_qwerty_editor.gd` owns draft text, caret, keyboard pages, and completion/cancellation signals.

## Local Contracts

- Entries remain ordered caller data and are displayed in pages of at most eight stable directional slots; returning the stick to neutral retains the selection.
- The component never interprets command IDs, executes on button release, or imports gameplay/session state.
- Raw joypad events remain owned by the central controller input owner; this component accepts explicit direction/confirm/cancel/page calls and keeps only a keyboard fallback.
- Disabled entries remain selectable for explanation but never emit `command_selected`.
- Confirm, cancel, page, and unavailable-reason scrolling methods are explicit public presentation operations.
- `ControllerQwertyEditor` accepts only `LineEdit` or `TextEdit` targets, keeps edits draft-local until Done, and never submits an outer form.
- Raw joypad events remain owned by the central controller input owner for both overlays.

## Work Guidance

- Keep geometry authored in the scene and visual tuning in exported properties.
- Preserve the 1280x720 canonical composition and the compact 800x600 composition.

## Verification

- Run Godot headless project import/script validation after changes.

## Child DOX Index

- None.
