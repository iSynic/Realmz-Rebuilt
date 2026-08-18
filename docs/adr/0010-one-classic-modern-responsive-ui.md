# ADR 0010: Use one Classic-wide responsive UI system

## Status

Accepted and implemented.

## Context

Classic Realmz is recognizable from composition and pacing, not from stone color alone: map or picture dominance, a six-character roster, a bottom narrative area, context-specific bitmap commands, and compact menus. The superseded dashboard shell used title/route bars, card grids, and a persistent Chronicle column, so it did not reproduce that hierarchy. Realmz 2 still needs responsive desktop layouts, accessible text/focus, and strict detached-view boundaries without maintaining separate Classic and modern skins.

The earlier Remake contains tracked bitmap controls and useful wide-layout evidence, but its host architecture is not a runtime contract. File names alone do not prove Classic provenance or semantic purpose.

## Decision

Use one scene-based Classic-wide presentation system. `ClassicApplicationShell` owns the menu strip, stage boundary, right roster, bottom textbox/status region, and contextual command deck. The canonical/default composition is 1280x720. `UiLayoutProfile` also provides one optional 800x600 Classic 4:3 composition with a square gameplay viewport; intermediate and larger sizes may reflow or scale but are not separately designed targets. Interface density and text scale remain independent. `UiRouteCatalog` owns one scene per route, and named input actions isolate screens from physical bindings.

Import only catalogued bitmap controls from Remake commit `86cf2bf391ef0c43ba31c1633ddd63b7e67e3d61`. Record exact paths, hashes, dimensions, semantic scene-use evidence, and integer scaling rules. Keep original pixels intact and draw interaction states externally. Generated app chrome uses one selected SpriteCook charcoal surface plus deterministic matching frame derivations. Package content media remains separate and resolves by exact type and ID.

Use Alegreya for narrative/headings and Alegreya Sans for dense UI text, bundled under OFL with pinned hashes. Presentation consumes player-knowable detached facts and explicit action availability. Missing facts produce disabled controls or neutral fallbacks, never guesses. Typed interactions retain exact request identity and payload.

## Consequences

- The first-screen silhouette reads as Realmz without a permanent logo.
- Original bitmap lettering does not scale continuously; scalable menus, tooltips, focus rings, and surrounding text provide accessibility.
- The canonical 16:9 composition gets deliberate screen-by-screen design; the optional 4:3 composition prioritizes the square gameplay stage and reachability through compact reflow or scrolling.
- Services and Battle are contextual rather than global tabs.
- Bestiary, Allies, tactical movement, and other unsupported facts remain explicitly unavailable.
- Large text and UI settings reflow and scroll; map/package art remains integer sampled.
- The asset import and slate derivation tools become reproducible build inputs, while rejected visual candidates and dirty reference files remain outside the repository.
