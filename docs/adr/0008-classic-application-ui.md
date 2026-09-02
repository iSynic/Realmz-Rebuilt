# ADR 0008: Reconstruct the Classic application as scene-based presentation

## Status

Accepted and implemented. ADR 0010 specifies the final responsive visual/scaling system.

## Context

The deterministic kernel and scenario route existed before the application had the shape of Realmz. A procedural shell could prove movement and script execution, but it made the campaign library, party setup, character creation, exploration, services, combat, and mandatory Classic interactions difficult to grow without coupling presentation to gameplay.

Castle is the behavioral and workflow oracle. Existing Remake scenes and assets are donors only; their host dependencies are not runtime contracts.

## Decision

Use a scene-backed `ClassicApplicationShell` with a presentation-owned `ClassicScreenRouter` and `InteractionPresenter`. Presenters consume detached `GameView` read models and emit typed intents or request-matched responses. Presentation selection, focus, menus, scrolling, animation, audio, and gallery state never enter `GameSession`.

The shell preserves Classic information hierarchy and pacing while using responsive containers, keyboard focus, explicit disabled reasons, and accessibility settings. A typed-fixture gallery is the first screen-completeness gate. The old procedural shell was removed after route parity rather than exposed as a second user-facing mode.

## Consequences

- Missing screens become explicit view/intent contract work instead of ad hoc Node mutation.
- Classic textbox and picker pacing can be reproduced without making animation part of simulation.
- Realmz assets can be reused only after provenance review; layout and host scripts are not copied as architecture.
- The first implementation tranche can ship navigable shells before every service and combat mutation is wired.
