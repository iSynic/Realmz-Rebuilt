# Deterministic Realmz core contract

## Purpose

Own the pure Realmz model, fixed Classic rules, topology, game clock, randomness, and complete session state.

## Ownership

- Direct Realmz definitions and mutable playthrough state, including characters, equipment, wealth, conditions, encounters, battles, shops, treasures, spells, monsters, races, and castes.
- `GameSession`, typed intents/events/interactions/views, and snapshot boundaries.
- `RealmzRules`, `RealmzClock`, `RealmzRng`, topology queries, and world overlays.

## Local Contracts

- All classes are pure `RefCounted` or value-like data. They never extend or retain Nodes.
- No scenes, autoloads, filesystem/resource APIs, audio, OS services, wall-clock time, or Godot randomness.
- JSON dictionaries stop at validating infrastructure factories. Domain state is typed and does not expose writable backing dictionaries.
- Classic option-label records are immutable typed content distinct from ordinary messages; runtime choice resolution may query them but never mutate their source table.
- Every gameplay mutation is committed synchronously by `GameSession`.
- `GameSession` owns scenario execution state and is the only object allowed to connect VM operations to domain mutations.
- Session state owns encounter attempts/type flags, equipment escrow, mutable shop stock, combat, and scenario-program replacement. These are save data, never mutations of installed package definitions.
- Combat state owns the active actor's action, retained target, and next authored monster attack row. Character attack capacity remains a signed integer half-unit field on `CharacterState`; save/resume may not recompute or round either boundary.
- Session state owns non-VM interaction continuations as well as VM continuations. Random-rectangle surprise choices serialize with their owning region and resume only through `GameSession.respond`.
- Live age-band changes yield ordered `age_update` requests. Direct clock work may suspend an unstarted post-move continuation beneath the bounded queue; each typed response advances one character before the owning session operation resumes.
- Monster death macros execute before battle resolution. Their combatant identity, VM interaction, and direct-session continuation belong to the save aggregate and resume only through `GameSession.respond`.
- A placed Action Point's Classic header is a post-action map/coordinate destination. `GameSession` applies it only after that AP completes, rechecks the destination cell once, and serializes the recheck depth so save/resume cannot repeat or skip it.
- An ordinary placed Action Point becomes disabled after its complete timeline. Classic opcode 24 Keep Codes preserves it; opcode 25 may disable it explicitly. This world-overlay state is serialized across every interaction and save boundary.
- Every gameplay random draw goes through the session-owned `RealmzRng` and is serializable.
- `RealmzRng` uses the documented QuickDraw 16807/mod-2147483647 state transition and Castle's inclusive scaling; raw scripted values are test-only branch controls.
- Snapshots and restores detach typed state so callers cannot mutate an active session through a prior envelope.
- `MapTopology` plus `WorldState` overlays is the only source for simulation map facts; movement, pathfinding, LOS, search, triggers, and views reuse its explicit cells, edges, and features.
- Land travel accepts all eight adjacent destination cells, follows diagonal Layout neighbors at map corners, and charges the destination tile's ordinary movement cost. Direct movement, detached availability, and land pathfinding use the same destination probe without corner blocking. Dungeon movement and pathfinding remain cardinal and edge-based.
- A topology cell retains immutable presentation metadata for its base tileset/tile and optional special-land overlay asset. These facts pass through detached views but never become an alternate movement, LOS, or trigger model.
- Random rectangles follow Castle's reverse region order, 1-in-10,000 chance scale, three ordered random-door draws, signed one-shot door state, surprise choice, and battle selection through the session RNG.
- A moved-to coordinate selects only its lowest `classic_record_index` placed Action Point. Disabled or failed selected records do not fall through to another same-cell AP; positive sub-100 chances consume one tagged draw, while percentages below one consume none.
- `GameView` and its map/cell views are detached read models for presentation and never expose mutable simulation objects.
- Detached item/spell/monster views carry exact content icon IDs and resource types. Item views retain player-visible item type and icon while revealing identified names, descriptions, definition identity, and values only after simulation marks the instance identified.
- `GameView` reports action availability as `enabled` plus an explicit reason. Presenters cannot infer availability from the existence of a control.
- `MapView` carries a bounded 25×25 party-local cell projection, the complete visited-coordinate set needed by the minimap, and movement availability computed through the same topology query as movement: eight directions on land and four in dungeons. It does not duplicate the full 90×90 map for every presentation revision.
- Classic-visible Realmz behavior is the fixed ruleset. Fidelity corrections require a documented decision and source/oracle tests.
- Campaign display metadata, restriction summaries, race/caste eligibility, and character-creation drafts are detached read models. They may explain a legal choice, but only `GameSession` and fixed Classic rules decide whether a character can enter a party.
- Party setup begins empty and remains session-owned across any number of finalized-character, vault-import, removal, save, and restore boundaries. Exploration intents fail until explicit Begin commits a nonempty party; no placeholder character or view-revision shortcut may stand in for that state.
- Character creation initializes all forty condition slots from the race, then applies only caste condition-level `1` as permanent `-1`; larger caste values remain level-up thresholds. Initial saves use the serialized race/caste bonuses and the `CharacterState` `-99…120` bounds.
- Character creation preserves Castle's complete random sequence: six assigned attribute rolls plus the seventh discarded loop roll, gender adjustment, cumulative race aging rows through the caste minimum age group, final race/caste bounds, three threshold-based special bonuses, stamina, age, and optional spell points. Aging table columns 8 through 14 adjust only saves 0 through 6 during creation.
- `CharacterState` persists exact age days and the independent current age group. Each crossed midnight and each source-backed age-changing spell invokes one Castle age operation: it may apply or erase only one adjacent row, does not reuse creation bounds, floors maximum movement at two, and adjusts only saves 0 through 6. Maximum age reduces battle experience to Castle's truncated two-thirds share; `doesNotDie` remains stored content but has no invented death or exemption behavior.
- A party-target monster attack with Classic special 17 consumes the generic special-potency draw after ordinary damage, tests save slot seven, and on failure applies the attack-row lifespan formula through the same one-transition aging rule. A changed band pauses combat at a session-owned age update before the next actor; the combat continuation, interaction, character mutation, pending weapon condition, Dragon Hide feedback, damage, and RNG boundary all survive save/restore and resume once in source order.
- Monster status specials 1 through 7 and 16 consume generic potency before their source-family save and mutate the exact Classic condition slot. A negative duration is permanent. Party targets add once only when the starting duration is below 30; monster targets stack without that gate. A monster target above 100 runtime magic resistance converts the complete special attack to a miss after potency and before its save. Special and source-sound events precede ordinary damage feedback.
- Monster resource specials 8 and 9 consume the same generic potency draw before their source-family branch. Spell drain tests save six, transfers up to three points per attacker hit die, and permits the attacker balance to exceed its maximum; experience drain tests save five, subtracts twenty times attacker maximum stamina from direct earned experience, and has no monster-target case. Both mutations and above-maximum monster spell energy remain session-owned and saveable.
- Monster charm is battle allegiance, not a generic condition: save zero includes party charm resistance; affected party actors are session-owned automatic combatants, target only the opposite side, remain valid hostile targets for loyal actors, participate in outcome checks, survive mid-battle restore, and return to base allegiance at battle cleanup.
- Monster elemental specials 11 through 15 retain the generic potency draw followed by elemental damage, source-family save, and matching protection. `FD-COMBAT-001` consistently applies protection to committed monster-target damage instead of preserving Castle's cold-through-mental display-only ordering defect.
- Character melee resolves from a validated snapshot of equipped immutable definitions. Armed state comes only from an equipped Classic type-2 item, never from a nonzero damage bonus; conflicting melee slots fail explicitly. `FD-COMBAT-002` makes weapon elemental damage use the defender's save while retaining Castle's immunity, protection, and RNG order. Monster `requiredWeapon` and `magicToHit` are independent attack gates; battle `distance` is placement-only. `FD-COMBAT-003` normalizes specific signed-byte requirements to Divinity Item Numbers and disallows Castle's unarmed family-restriction bypass.
- Ordinary monster melee receives a detached attack context containing the resolved carried weapon, Realmz day, effective defender luck/armor, and party Dragon Hide state. Its bounded fumble-disabled resolver preserves Castle's luck-before-hit and weapon/unarmed damage order, evil-conditional protection, ten-percent floor, typed weapon gates, and Dragon Hide's physical-only reduction plus asynchronous sound 694. `FD-COMBAT-004` floors negative physical damage at zero instead of allowing Castle's subtraction to heal the defender. Reflection and missile replacement remain unavailable until their tactical state is session-owned; Castle's positive `behind` is a withdrawal-attack modifier, not character/monster icon facing.
- Battle state owns a bounded twenty-entry queue of exact fumbled `ItemInstance` values and the active turn's committed-physical-action fact. Character attacks consume the level-scaled fumble draw even while unarmed; cursed weapons and a full queue suppress the fumble without changing the attack result. Armed monsters consume the HD-scaled draw, clear only their active weapon on a fumble, and continue later authored rows unarmed. Body-count selection precedes typed one-item recovery; `FD-COMBAT-005` preserves remaining charges. The fixed runtime currently uses Castle's default enabled behavior; do not add an `allowfumble` toggle without also source-owning its five-percent XP coupling.
- Player-controlled character melee activations normalize any positive prior reserve to one half-unit, clear a negative reserve, add normal attacks plus attack bonus, add Castle's four Speedy half-units, and spend two units plus three movement per attempt. A reserve of at least two retains the active actor. Monster physical activations choose once, retain a living target, and execute each validated authored row in order. Charmed-character cadence, spell/item limits, missile replacement, monster Speedy overflow, and Castle's contradictory zero/one-unit display remain unresolved rather than sharing this bounded rule implicitly.
- Battle state owns each party character's Castle melee/missile toggle. Setup prefers an equipped type-2 weapon, otherwise type 15; switching costs no attacks, movement, turn, or RNG and returning to melee permits hand-to-hand. Equipment projection rejects duplicate type-2/type-10/type-15 slots. Missile mode cannot enter the melee resolver. Fire, monster missiles, proximity-gated melee, placement, range, LOS, and withdrawal attacks remain disabled until exact tactical terrain, positions, and footprints are session-owned.
- Classic random monster-weapon tables have one rules-owned definition shared by construction and package-readiness validation. Every possible generated item ID must exist in immutable package content; combat never treats an unresolved generated weapon as unarmed.
- Monster blindness and petrification use save seven. Blindness writes permanent `-1` before physical damage; petrification writes Castle's target-specific sentinel, sets health to zero, and skips the already-rolled physical damage through the force-kill result.
- Character vault imports arrive as detached validated state plus provenance. The active session clones the state; it never writes back to the vault implicitly.
- Unsuspended held-over allies are consumed into the combat roster as non-traitors. After combat, surviving friendly monsters with nonzero `canSummon` eligibility return only through the typed Classic body-count selection; negative eligibility is mandatory. Monster targeting compares allegiance, so hostile monsters can attack party characters or friendly monsters and friendly monsters target hostiles.

## Work Guidance

- Prefer small domain modules behind a fixed `RealmzRules` facade; do not add registries or profile selectors.
- Keep character, condition/time, inventory/economy, combat, magic, and monster behavior in their owned rule modules. Opcode handlers adapt Classic records to these rules instead of duplicating formulas.
- Preserve 16-bit and 32-bit arithmetic semantics explicitly where Castle behavior depends on them.
- Keep serialized IDs stable strings and use `StringName` only as an internal lookup optimization.

## Verification

- `tools/verify_architecture.ps1` rejects forbidden host dependencies and direct randomness.
- Core behavior requires headless unit tests and, when source-backed, an evidence-labelled oracle fixture.

## Child DOX Index

- No child AGENTS.md files are currently required; subdirectories remain governed here.
