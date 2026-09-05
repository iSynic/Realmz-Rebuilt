# Journal UI contract

## Purpose

Own the editable Places, acquired Maps, Journal, immediate player-map, and Classic scrolling-text presentation.

## Ownership

- `journal_screen.tscn` owns the route shell and embeds `maps_notes_workspace.tscn`, whose scene-authored tabs contain saved places, the current note editor, acquired maps, the cartographic stage, and the two-page journal.
- `MapsJournalScreenController` binds detached notes, maps, journal entries, zoom, filtering, selection, and Wide/Compact state. It instantiates only exported note, map-menu, and journal-entry rows.
- `PlayerMapPresenter`, `PlayerMapCanvas`, `PlayerMapCartographicStage`, and `PlayerMapParchmentMat` own algorithmic map rendering inside the authored viewport. They consume detached map views and package media without acquiring maps or querying mutable topology.
- `PlayerMapInteraction` presents an immediate typed map request through the same map presenter. `ScrollingTextInteraction` and `ClassicScrollingTextSurface` present both opcode 62 and scrolling acquired maps through one source-backed text/style implementation.

## Local Contracts

- Places may edit only the detached current-location note. Historical map views and authored journal entries remain read-only.
- Acquired-map slots preserve source order and unavailable records. Presentation zoom, selection, dragging, and scrolling never enter simulation or saves.
- Player maps resolve exact PICT, TEXT, and `styl` identities through scenario-before-application media precedence.
- Scrolling text preserves signed text offsets, sorted style starts, Classic font/color/face/size interpretation, native `ppat` 129 tiling, automatic advance, drag steps, and typed acknowledgement behavior.
- Stable panes, headers, actions, empty states, and responsive containers belong in scenes. Only map canvases and request-sized exported row collections are created dynamically.

## Work Guidance

- Start layout changes in `journal_screen.tscn`, `maps_notes_workspace.tscn`, or the relevant interaction/surface scene.
- Keep topology and acquisition decisions in game/playthrough owners; this folder renders only detached public facts.

## Verification

- Run the Classic UI system, scrolling-text/player-map, exploration-session, and Realmz Builder preview suites.
- Run bundled-scenario validation when changing Classic TEXT/`styl` or map-resource handling.

## Child DOX Index

