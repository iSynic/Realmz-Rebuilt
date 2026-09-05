# Combat rules

Start with `CombatFlow` when you need to submit a battle command. It is intentionally small: it accepts mutations such as moving, casting, using an item, or completing a battle. Immutable `BattleDefinition`, `BattleMonsterSlotDefinition`, `MonsterDefinition`, and `MonsterAttackDefinition` records sit beside `CombatCatalog`; use `RealmzContent.combat` to resolve them. For a read-only rules question, go directly to the collaborator that owns the answer—`actions`, `reactions`, `magic`, `rounds`, `fields`, `summoning`, `phase`, or `automation`.

All collaborators share one `CombatContext`. The context supplies the pure rule services and public collaborator references; it does not copy battle state or hide a second combat model. The command receives `GameState`, immutable content, and the serialized session RNG, performs one transaction, and returns a `CombatFlowResult` with already-committed domain events. `CombatState` remains the saved aggregate, its roster/turn/status/dropped-item/spell-runtime collaborators own their respective battle facts, and its few aggregate commands synchronize cross-owner initiative and turn-boundary invariants. `CombatStateCodec` preserves the flat save shape, and `CombatView` remains detached presentation data.

`requests/combat_request_body.gd` is the detached command deck carried by `InteractionRequest`. It contains already-calculated actions and target records for presentation; command admission and mutation remain with the combat rules.

Within that aggregate, `BattlefieldState` identifies the constructed battle map and directly exposes two owners. `battlefield.terrain` stores the fixed grid plus its navigation-cache revision; `battlefield.actors` stores character and monster anchors, sizes, footprints, occupancy, and placement mutations. `BattlefieldGrid` owns the fixed 90-by-90 dimensions and footprint geometry. Save and restore go through `BattlefieldStateCodec`, which retains the existing flat battlefield keys without turning the aggregate into a forwarding facade.

Battlefield construction, physical attack policy and resolution, initiative, monster rules, and their typed command, retreat, attack, build, step, and projectile records are colocated here. These are pure collaborators rather than Nodes; the visible battlefield scene remains under `src/ui/combat`.

Important invariants:

- Simulation uses only the supplied serialized RNG.
- A rejected command leaves combat state and resources unchanged.
- Battlefield occupancy and footprints remain authoritative.
- UI playback never advances rules or owns a continuation.
- Collaborators call named public contracts, never another object's private implementation.

Combat navigation and automation are performance-sensitive. Preserve the retained occupancy, route, and projection structures; do not add per-cell actor scans or rebuild presentation during a command. Start behavioral changes in `tests/core/test_combat_flow.gd`, spatial changes in `tests/core/test_battlefield_navigation.gd`, and measure them with `tools/combat_performance_probe.gd` and `tools/battlefield_navigation_benchmark.gd`.

For automatic turns, enter through `CombatFlowAutomation`. Party Auto activation and pursuit live in `CombatPartyAutomation`; monster phases, spellcasting, movement, attacks, retreats, and charmed-character turns live in `CombatMonsterAutomation`; hostility and defeated-position cleanup live in `CombatOccupancyRules`. `CombatAiScoring` chooses a legal category, then monster automation reads in order as action dispatch, target preparation, ordinary combat resolution, and committed events. Its spell-target plan is transient calculation data, never saved battle state.

All of those rule collaborators are colocated in this folder. `src/playthrough/combat` translates player intents and saved handoffs into their public commands; `src/ui/combat` binds the scene-authored battle controls and renders detached views. Neither boundary owns a second combat rules implementation.
