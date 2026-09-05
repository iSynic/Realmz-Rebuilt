# Places, Maps, and Journal

This folder contains the complete Godot presentation for the Maps / Notes route and the same immediate map and scrolling-text surfaces used by scenario instructions. A maintainer can begin with one of the major scenes and follow its attached script to detached data and typed responses.

## Where to start

- `journal_screen.tscn`: route frame and persistent Back action.
- `maps_notes_workspace.tscn`: Places, Maps, and Journal tabs with their stable editable layout.
- `maps_journal_screen_controller.gd`: selection, note drafts, filtering, zoom, responsive state, and detached-view binding.
- `player_map_presenter.gd`: algorithmic PICT/topology/marker rendering inside the authored cartographic stage.
- `player_map_interaction.tscn`: immediate scenario player-map display.
- `scrolling_text_interaction.tscn`: opcode 62's complete-stage request surface.
- `classic_scrolling_text_surface.tscn`: shared tiled background and styled scrolling-text viewport.

Repeated selector records are the neighboring `location_note_row.tscn`, `player_map_menu_row.tscn`, and `journal_entry_row.tscn` scenes.

## Data flow

```text
GameSession -> detached notes, journal entries, and player maps
            -> MapsJournalScreenController
            -> authored route scene + exported rows + map presenter
            -> typed note intent or interaction acknowledgement
```

The map presenter receives an already detached `PlayerMapView` and media catalog. It does not decide whether a map was acquired, inspect mutable world state, or alter exploration discovery.

## Invariants

- Only the current-location note is editable.
- Authored journal text and acquired-map content retain source identity and order.
- PICT, TEXT, `styl`, and application `ppat` resources resolve through the shared exact-key media chain.
- Immediate maps and Maps/Notes use the same renderer; scrolling acquired maps and opcode 62 use the same scrolling-text surface.
- Automatic scroll position, drag offset, selected tab, filter, and zoom are presentation-only.

## Performance

The route remains mounted while its local state changes. Controllers rebind exported rows rather than rebuilding the workspace, and the map canvas caches decoded media while the selected map identity is unchanged. No route instantiation occurs during exploration movement.

## Tests and preview

Realmz Builder supplies Wide, Compact, empty, long-content, unavailable, and error profiles for the major journal surfaces. Presentation coverage lives in the Classic UI system and Builder preview suites; scenario resource coverage is enforced by the bundled-scenario validator and the aggregate `tools/verify.ps1` gate.
