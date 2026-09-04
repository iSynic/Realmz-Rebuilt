# Combat rules

Start with `CombatFlow` when you need to submit a battle command. It is intentionally small: it accepts mutations such as moving, casting, using an item, or completing a battle. For a read-only question, go directly to the collaborator that owns the answer—`actions`, `reactions`, `magic`, `rounds`, `fields`, `summoning`, `phase`, or `automation`.

All collaborators share one `CombatContext`. The context supplies the pure rule services and public collaborator references; it does not copy battle state or hide a second combat model. The command receives `GameState`, immutable content, and the serialized session RNG, performs one transaction, and returns a `CombatFlowResult` with already-committed domain events. `CombatState` remains the saved truth and `CombatView` remains detached presentation data.

Important invariants:

- Simulation uses only the supplied serialized RNG.
- A rejected command leaves combat state and resources unchanged.
- Battlefield occupancy and footprints remain authoritative.
- UI playback never advances rules or owns a continuation.
- Collaborators call named public contracts, never another object's private implementation.

Combat navigation and automation are performance-sensitive. Preserve the retained occupancy, route, and projection structures; do not add per-cell actor scans or rebuild presentation during a command. Start behavioral changes in `tests/core/test_combat_flow.gd`, spatial changes in `tests/core/test_battlefield_navigation.gd`, and measure them with `tools/combat_performance_probe.gd` and `tools/battlefield_navigation_benchmark.gd`.
