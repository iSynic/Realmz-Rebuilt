# Architecture

Realmz Remake 2.0 is a deterministic Realmz engine hosted by Godot, not a Godot-shaped RPG framework. Providence compiles canonical authoring projects into immutable packages. The runtime validates a package, constructs typed Realmz content, and gives one `GameSession` complete ownership of mutable playthrough state.

```mermaid
flowchart LR
    Providence["Providence canonical project"] --> Compiler["Providence 2.0 compiler"]
    Compiler --> Package["Immutable .realmz2 package"]
    Package --> Loader["Validated package loader"]
    Loader --> Session["Deterministic GameSession"]
    Intent["Typed player intent"] --> Session
    Session --> Step["Events + interaction + revision"]
    Step --> Godot["Godot presentation"]
    Godot --> Response["Typed interaction response"]
    Response --> Session
    VM["Scenario VM"] <--> API["Session RealmzRuntimeApi"]
    API <--> Session
    Session --> Save["Whole-session snapshot"]
    Castle["Pinned Castle oracle"] --> Tests["Differential fixtures"]
    Tests --> Session
```

## Layer ownership

`src/core` owns direct Realmz models, fixed Classic rules, topology, clock, RNG, and the session aggregate. It is pure typed GDScript: no Nodes, scenes, autoloads, time, files, audio, OS calls, or Godot RNG.

`src/scenario` owns the serializable VM and Scenario Action language. It asks a session-owned `RealmzRuntimeApi` for domain operations. The VM cannot discover Godot or call arbitrary scripts.

`src/infrastructure` owns untrusted package/save bytes, schema and hash validation, typed construction, persistence, migrations, and installed-content discovery.

`src/app` constructs dependencies and translates host operations. It may replace a session only after a complete restore has validated.

The host materializes one detached `GameView` for a committed session revision and shares it across input gating and presenters. A map view contains the party-local 25×25 render projection, complete visited coordinates for the minimap, and cardinal movement results from topology; it does not rebuild all 8,100 cells of a Classic map for every key event.

`src/presentation` reads `GameView` and ordered domain events, renders disposable caches, and sends typed intents/responses. Animation never controls simulation timing.

## Session boundary

The public session protocol is:

- `start(content, seed) -> SessionStep`
- `restore(content, save_envelope) -> SessionStep`
- `submit_intent(player_intent) -> SessionStep`
- `respond(interaction_response) -> SessionStep`
- `view() -> GameView`
- `snapshot() -> SaveEnvelope`

Mutations are synchronous. A step contains committed ordered events, an optional serializable interaction request, a view revision, and an explicit completed/waiting/failed state. Presentation waits for animations on its own; the session waits only for genuine player or operating-system input.

## Fixed rules and direct model

The engine models Realmz concepts—party, characters, maps, APs/XAPs, Simple/Complex/Thief/Timed Encounters, battles, shops, treasures, spells, items, monsters, races, and castes—rather than translating them into generic RPG resources. Mutable state directly represents conditions, equipment and charges, pooled/banked wealth, allies, encounter attempts, shops, combatants, and program replacement. `RealmzRules` is always present and has no provider registry or compatibility selector. Its character, condition/time, inventory/economy, combat, magic, and monster modules are fixed collaborators, not swappable providers. A narrow named legacy quirk exists only when authored content demonstrably needs it.

## Topology

`MapTopology` and `WorldState` overlays are authoritative. Providence normalizes land cells, packed dungeon fields, Layout adjacency, and placed AP post-action destinations into cells with explicit directional edges/features, random regions, transitions, and validated map coordinates. Movement, LOS, deterministic pathfinding, searches, triggers, random encounters, AP destination rechecks, battle-terrain derivation, minimaps, 2D views, and the optional dungeon 3D view ask that same query surface. TileMaps, collisions, AStar graphs, textures, and meshes are presentation caches and cannot answer simulation questions. See `docs/topology-evidence.md` for the Castle evidence boundary and Phase 2 proofs.

Classic land presentation uses the package atlas at its native 32×32 cell size. A Classic negative land value is compiled as the landlook base tile plus an optional content-addressed `cicn` image; presentation draws that image above the base without creating a second terrain model. Normal play does not overlay topology edges, random rectangles, AP markers, or debug grids on that art. Small cardinal cues expose the already-computed topology answer, and keyboard or map click/hold input becomes the same typed movement intent.

## Scenario execution

Classic instructions retain raw/normalized opcode identity, slot, ID, and provenance. Triggers reference ordinary programs whose instructions are either preserved `ClassicAction` records or typed `CallScenarioAction` records. Negative Classic opcodes retain GOSUB intent; CODE 111 returns through the saved Classic frame, CODE 112 discards one, and opcode 39 replaces execution with an XAP program.

Safe Scenario Actions compile in Providence to bounded bytecode. They use separate Safe frames, typed arguments, explicit caller contexts and capabilities, and versioned optional persistent state, but execute inside the same serializable VM. A domain operation goes through the one `RealmzRuntimeApi` owned by `GameSession`; that public boundary delegates to typed character, combat, control-flow, and inventory executors while older domains are extracted incrementally. A genuine player decision yields a serializable request and resumes the exact issuing frame after a matching typed response. Battle-round and monster-death macros use nested serializable frames, with death macros completing before allegiance and outcome resolution; Castle's post-battle body-count choice is another typed continuation and rebuilds the held-over ally list before the issuing frame resumes. Program replacement is a save-owned mapping resolved once when a VM frame starts; it never rewrites package content. Core `realmz.*` operations cannot be overridden, package actions are namespaced, and unknown behavior fails explicitly. GDScript is not a fallback; packages requiring it are rejected until an OS-confined external process implements the same JSON-safe Scenario Action ABI. See `docs/scenario-vm-evidence.md` and `docs/gameplay-domain-evidence.md`.

## Persistence and randomness

One `.r2save` envelope contains all mutable session state, including overlays, clock, equipment escrow, wealth, allies, encounter attempts/type flags, shop stock, combat, scenario-program replacements, VM frames, VM or session-owned pending interaction, post-move/random-region/AP-destination, direct combat-death-macro, or post-battle ally-selection continuation, action state, and RNG state/draw count. Installed package content is referenced by package hash and never copied into the save.

Every gameplay draw uses `RealmzRng`. It owns the QuickDraw `randSeed = randSeed * 16807 mod 2147483647` transition, signed low-word return (mapping `0x8000` to zero), Castle's inclusive `1 + abs(raw) * range / 32768` scaling, draw count, and semantic trace. Presentation has a separate cosmetic RNG. Oracle tests may inject raw scripted values so Castle and the new runtime take identical branches. See `docs/rng-evidence.md` for the evidence boundary.

## Classic application reconstruction

The application layer is now being rebuilt around `ClassicApplicationShell` and `ClassicScreenRouter`, while the session protocol above remains unchanged. The shell owns campaign discovery, setup, vault access, navigation, and the persistent Classic-shaped workspace. A dedicated interaction layer will own textbox, picture, choice, picker, service, and combat overlays; each overlay returns a typed response rather than calling gameplay objects.

The party-setup view is campaign-aware. It presents the authored campaign title/version/author and restriction summary from package v2, places Race on the left, filters Class on the right from typed eligibility relationships, and exposes the five creator stages: Identity, Race & Class, Appearance, Review, and Spells. Appearance identities are package data, and a missing catalog entry is an explicit unavailable choice rather than a guessed path.

Reusable characters are separate from campaign saves. `CharacterVaultRepository` owns immutable `.r2char` revisions and recovery, while `GameSession` validates and clones a selected revision through `IMPORT_VAULT_CHARACTER`. Publishing is explicit and only occurs at a committed boundary. The vault cannot mutate an active session or silently rewrite a character from another campaign.

This tranche intentionally establishes typed shells and gallery surfaces before wiring every service and battle action. The procedural `ClassicShellPresenter` remains only as a route-comparison donor until the new screens cover the same certified paths; no Classic/Remake presentation mode is exposed to players.
