# The Builder's Charter

Realmz Rebuilt is being reorganized so that a maintainer can find a rule, open a screen, and follow a player command without first learning the history of the project. The game must remain runnable while the work proceeds. This charter describes the destination and the rules for reaching it.

## The six source areas

| Area | What belongs here | What does not |
|---|---|---|
| `src/app` | Startup, dependency construction, host lifecycle, and input translation | Realmz rules or screen layout |
| `src/game` | Pure definitions, mutable game state, fixed rules, topology, clock, RNG, and detached read models | Nodes, files, audio, or platform services |
| `src/playthrough` | `GameSession`, transactions, continuations, restore coordination, and player workflow orchestration | Presentation or filesystem access |
| `src/scenarios` | Classic instruction execution, Safe Scenario Actions, and the scenario VM | Host UI or package I/O |
| `src/storage` | Package loading, saves, Character Files, settings, validation, and filesystem adapters | Gameplay decisions or screen behavior |
| `src/ui` | Scenes, screens, dialogs, components, rendering, animation, audio, and themes | Mutable game truth or direct storage access |

The intended dependency direction is:

```text
game <- scenarios <- playthrough <- app
game/playthrough/scenarios <- storage <- app
game/playthrough <- ui <- app
```

The six source boundaries are now in place. Any later boundary move includes its scripts, paired `.uid` files, resource paths, tests, verification rules, and DOX contract in one change.

## Names should tell the truth

- Use `Classic` only for behavior, data, media, or evidence that genuinely comes from Castle Realmz.
- A stable route is a `Screen`; a contained surface is a `Panel`; a blocking decision is a `Dialog`; repeated content uses `Row` or `Card`; custom drawing uses `Canvas` or `Renderer`.
- Do not use `Workspace` for ordinary screens.
- A `Definition` is immutable authored data. A `State` is mutable playthrough data. `Rules` are pure calculations. A `Repository` persists records. A `Loader` or `Decoder` converts external input. A `Result` belongs to one named operation.
- Use `Flow` only for a resumable, multi-step operation.
- A script with `class_name` uses the matching snake-case filename. A scene, its primary script, and its root node share the same meaningful base name.
- Rename decisively. Do not leave aliases for internal names. Serialized IDs, package keys, save fields, and the existing user-data directory remain stable.

## Scenes own stable layout

If a maintainer can reasonably move, resize, restyle, or reconnect a control in the Godot editor, that control belongs in a `.tscn` scene. Scripts bind data, respond to input, coordinate behavior, and create genuinely dynamic collections. Repeated rows and cards use small `PackedScene` components rather than ad hoc control trees.

Every route screen will expose the same small lifecycle:

```text
update_view(game_view)
on_enter()
on_exit()
handle_back()
```

Screens emit typed intents and navigation requests. They may retain local display state such as selection or scroll position, but they do not own Realmz state and they do not read storage directly.

Custom map, battlefield, first-person dungeon, animation, and effect drawing may remain script-driven when code is the clearer and faster representation. These are explicit rendering exceptions, not permission to build ordinary forms in code.

Exploration and Combat use one further honest exception: their `*_screen.tscn` files are route tokens because their visible structure already lives in `game_shell.tscn`. The maintainability gate records those two marker scenes separately; it must never be satisfied by adding inert editor-only controls.

## A script should introduce itself

Each production script will gain a short `##` header stating its purpose, owner, inputs, outputs, and boundary. Comments explain an invariant or a source-backed Classic decision. They do not narrate obvious syntax.

Keep one statement per line. The migration ratchets existing compressed statements and runtime-built controls downward; new code may not increase either debt. The final limits are 800 substantive lines per production file and 100 per function.

## The command path

A player command starts in `app`, crosses into `GameSession` as a typed intent or response, changes pure state through `playthrough`, `scenarios`, and `game`, and returns detached events and a view. `ui` renders that result. `storage` is involved only when the host explicitly loads or saves something.

No stage of this overhaul changes `.realmz2`, `.r2save`, `.r2char`, stable IDs, opcode meanings, resource precedence, deterministic RNG, or the public `GameSession` operations. A necessary wire-contract change requires its own decision record and migration plan.

## Order of work

1. Establish this charter and measurable no-regression checks.
2. Move one source boundary at a time, keeping Godot imports and tests green.
3. Build Inventory and Character as the first scene-owned screens and ask a human maintainer to review them in the editor.
4. Convert the remaining route screens and typed interactions.
5. Split large game and playthrough files by feature responsibility.
6. Replace the current architecture guide with the complete Builder's Manual and certify the result.

The migration is complete when a newcomer can locate a character record, fatigue rule, inventory layout, opcode handler, package loader, and save serializer; then follow one command from input to rendered result without private instruction.
