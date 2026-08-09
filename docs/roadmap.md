# Delivery roadmap

Status values describe current evidence, not intent. A phase completes only when its exit gate is proven.

## Phase 0 — Foundation and tooling (completed)

- Godot project and explicit composition root.
- DOX hierarchy, architecture docs, ADRs, provenance lock, test runner, CI, MCP integration.
- Clean pinned Castle and Remake reference worktrees.

Exit evidence: the application launched through MCP Pro 1.16.0 on Godot 4.7.1; runtime UI discovery and simulated input changed observed state; a 960×600 smoke screenshot was captured; the final editor error list was empty; headless verification passed; pinned clean reference worktrees were created; and the DOX hierarchy was re-read and reconciled.

## Phase 1 — Package contract and deterministic kernel (completed)

- Implemented: additive Providence `.realmz2` exporter, deterministic ZIP/JSON/hashes, desktop target/report, authoritative schema, byte-identical runtime mirror, and a 3×3 synthetic package generator.
- Implemented: independent ZIP/hash/capability/reference/topology validation into typed Realmz content; direct map/AP/Classic-action models; deterministic session, party/state, clock, QuickDraw-compatible RNG and traces; detached save envelope and transactional save repository.
- Implemented evidence: repeated Providence exports compare byte-for-byte; runtime accepts the generated package and rejects a valid-ZIP stale-hash mutation; deterministic search/save/reload resumes the same RNG branch and state revision.
Exit evidence: repeated Providence exports are byte-identical; the runtime independently accepts the generated package and rejects a valid-ZIP stale-hash mutation; seed 1 produces the verified QuickDraw/Castle search roll 52; save/reload preserves the session revision, one-minute clock advance, RNG state, and draw count; and failed restore leaves the active session untouched. Through MCP Pro, the composition root loaded the package, committed the search through simulated input, observed the expected runtime state, saved `mcp-phase1`, and captured the 960×600 loaded-session screenshot. The final editor error list was empty and the full 43-assertion verification suite passed.

## Phase 2 — Authoritative world and exploration (completed)

- Implemented: Providence normalization of land and packed dungeon representations into explicit cells, directional edges/features, random regions, and Layout transitions; strict independent runtime construction and validation.
- Implemented: typed world overlays, movement, deterministic pathfinding, LOS/visibility, search, secrets, doors, transitions, random rectangles, clock advancement, trigger execution, and terrain replacement through one topology.
- Implemented: a `GameView`-only Classic 2D presenter with topology-derived minimap and movement/LOS/trigger debug facts.

Exit evidence: the synthetic three-map fixture exercises message AP execution, terrain replacement, random-region gating, hidden-secret blocking/discovery, directional dungeon secrets, door opening, land transition, pathfinding, visibility, and save/reload through one topology. The 93-assertion suite passes across six suites. MCP Pro keyboard/mouse input traversed the message AP, search roll 52, secret, and transition; restart/restore retained map, coordinate, clock, RNG state/draw count, and overlays; the 960×600 topology/minimap screenshot was inspected; and a fresh editor inspection reported zero errors.

## Phase 3 — Scenario VM and Actions (completed)

- Implemented: a serializable, session-owned VM with preserved Classic instructions, signed GOSUB, CODE 111/112 stack behavior, XAP replacement, Simple Encounter yields, one runtime API, and explicit unsupported behavior.
- Implemented: compiled Safe Scenario Actions with typed calls, persistent state, private helpers, bounded flow/arrays/steps, separate Classic/Safe frame limits, and save/resume at interaction boundaries.
- Implemented: Providence ordinary Action calls and generated call editors, project-wide Scenario Action library, Safe bytecode compilation, derived export readiness, and removal of visible scripting tiers, gameplay profiles, behavior anchors, and sandbox creation from the normal 2.0 path.

Exit evidence: the synthetic route executes AP opcode -4 to a serializable Simple Encounter request, selected result message, `CallScenarioAction`, Classic opcode 39 to an XAP, and CODE 111 return as one ordered trace. Save/reload reproduces the pending request and exact continuation. The 132-assertion runtime suite passes across seven suites; Providence passes 905 frontend tests plus its Rust exporter, typecheck, lint, architecture, module-size, production-build, and cargo-check gates. Repeated Phase 3 exports are byte-identical. MCP Pro exercised the pending-save, response, restore, repeated response, and final route state with a clean editor error inspection. Castle source/control-flow evidence and the precise proof boundary are recorded in `docs/scenario-vm-evidence.md`.

## Phase 4 — Realmz gameplay domains (completed)

- Implemented: direct race, caste, item, spell, monster, battle, treasure, shop, and Complex/Thief/Timed Encounter models with independently validated package construction.
- Implemented: fixed character, condition/time, inventory/economy, combat, magic, monster, and combat-flow rules; save-owned domain state; packed standard/scenario spell identities; opcode 7/8 program mutation; opcode 36 equipment escrow; and stateful opcode 122 fumble behavior.
- Implemented evidence: the 452-assertion suite covers rules, package construction, domain mutation, RNG ordering, save/restore, VM routing, and explicit error paths. A bounded hash-labelled Assault on Giant Mountain inventory declares 58 active normalized opcodes; every one has one owner, passes package readiness, and dispatches without top-level fallback. This is content-inventory evidence, not live-route proof.

Exit: every active capability needed by the synthetic fixture and Assault on Giant Mountain has executable source-backed behavior with no fallback or silent no-op.

Exit evidence: Providence commit `364755324fae1685b82bbf0c751572045ee6888d` passes its Rust library/exporter/example checks, 321 library tests, frontend typecheck, and production build. The runtime's full gate passes 452 assertions across eight suites plus schema, fixture-provenance, architecture, export-exclusion, and whitespace checks. A fresh MCP Pro editor session reported zero errors; the main scene played, exposed the expected runtime tree, accepted simulated mouse input, changed the observed status, captured a 960×600 frame, and stopped cleanly. Phase 4 domain behavior is proven by deterministic headless tests; the current minimal host does not yet expose those domain screens, which is Phase 5 work.

## Phase 5 — Classic shell and first campaign (route-certified; presentation fidelity ongoing)

- Implemented: Classic-first 2D shell with campaign discovery/install, party creation, exploration HUD, character/inventory/spell views, typed encounter/combat/shop/temple/bank presenters, package pictures/audio, settings, and save/load surfaces.
- Scope note: those are functional routes and surfaces, not a claim that the current shell reproduces the density, composition, interaction affordances, or finish of the Classic Realmz UI. Presentation fidelity remains active work even though the bounded AOGM route gate passed.
- Implemented: source-backed random-rectangle continuation, active-combat intent lockout, save v3 migration, Castle-correct AP post-action destinations, and deterministic synthetic interaction/save routes. The runtime gate passes 531 assertions across eight suites.
- Package/route evidence: a fresh local Providence export of Assault on Giant Mountain independently validates and starts with 21 decoded media assets. Package hash `7561aa2d2f1c2acf4dc57bc12cef1d79049473a2e9bd19fe8c6e377acf087e84` and route hash `b84ff7d68d2d203cb03aca65f94600d4f7c87e01054d8b9a97aba6d68ef19a95` remain local-only evidence; no campaign payload is committed. The route passes opening presentation, Battle 60, Baron briefing/macro, Battle 274, four fortress tile mutations, quest 17, rewards 68/467/625, final report, and final position land 0 (84,8).
- Compiler evidence: Providence commit `a06f2ef152139dfd3fccfc5e563ba9ee58b62d3a` passes 323 Rust library tests with one audit test ignored, frontend typecheck, production build, and `cargo check`.
- MCP evidence: Godot MCP Pro discovered the unfixed port automatically, opened and inspected the main scene, started the synthetic campaign, created the party, entered the typed random-surprise request, saved it as `quick`, declined it, loaded the save, observed the identical prompt and options again, and accepted the restored decline response. A 960×600 frame was captured. A fresh post-fix editor session repeated project/scene inspection, play, runtime text inspection, screenshot capture, and stop with zero editor errors.

Exit: a fresh export completes the certified route with no unsupported active mechanic or save/reload divergence.

Exit evidence: the source-backed route completes through the ordinary 2.0 session/VM API with no fallback, the synthetic suite covers save/reload at its typed interaction boundaries, and the compiler/runtime gates above pass. This certifies the bounded completion spine; it does not claim exhaustive Castle parity for every optional branch.

## Phase 6 — Corpus, releases, and extensions (implemented; cross-platform certification pending)

- Implemented: Windows, Linux, and macOS export presets plus three-runner verify/export CI matrices. Release exports exclude MCP, tests, references, and local evidence.
- Implemented: optional Classic dungeon 3D whose floor, edges, doors, secrets, stairs, and columns are projected from the same `MapView` facts as the 2D map. No second collision or discovery model exists.
- Implemented: explicit rejection of packages requiring `realmz.scenario.gdscript-actions-v1`. Safe packages remain portable; an in-process or token-scanned GDScript fallback was not introduced.
- Implemented: generic external corpus probing/routing, expanded source-backed opcode ownership, held-over ally combat with serializable Castle body-count selection, serializable battle-round/death macros, and Providence reachability retention for direct opcode 88/89 monster references.
- Local campaign evidence: a fresh War in the Sword Lands package at hash `4509fcda9f3684292b5406c151b7108979f4f6211eb1ee198b808ce798e464dd` passes all eight external route stages and observes Battles 377, 473, 474, and 212 before ending at land 16 (78,36) with quest flags 1, 42, and 75. Route hash `fa08b47bd53e0f506333c3c488ccb609b7387fc324b7784586b88d9899e5b1d3`; package, route, and report remain local-only.
- Compiler evidence: Providence commit `84a5afde2ec13b218289fcb02ace20adfc71b6f2` retains direct ally monster definitions, preserves Classic column-major land storage, separates negative-land `cicn` overlays from base terrain, packages every referenced map atlas, resolves reachable shared Classic sounds, and normalizes odd terminal WAV chunks. Its focused twelve-test Realmz 2.0 exporter gate and focused WAV decoder/round-trip tests pass. Runtime unit/integration coverage currently passes 815 assertions across nine suites.
- Current AOGM visual/audio evidence: local package hash `45dd3caa73b58b29afdbe071ea120a812f64595b716468ecede61b27c1e69ae3` independently validates with 119 media assets, including 40 scenario/shared Classic sounds. Its unchanged world document retains the verified 8,100-cell land 0 layer, tile 155 start at (48,15), and 59 special-cell overlays. The view retains native 32×32 art, a clipped 530×452 map viewport, the unadorned built-in CICN 186 party image, and click/hold plus numpad/arrow/WASD input. The opening AP now preserves Castle opcode 1 pacing: message 896 and message 897 each yield a dedicated, saveable Continue textbox before later actions execute; negative message 898 remains in the same textbox without adding a click. MCP observed no dispatched sound at either positive textbox, then observed the 1.480-second Horn, 1.726-second Angry Mob, and 1.440-second Camp streams playing simultaneously on three channels immediately after the second acknowledgement. The concise shell status no longer expands to the message text, and internal picture/sound event names never enter player-facing textbox history. A 960×600 frame was captured. The runtime suite passes 815 assertions across nine suites. This does not replace the earlier route package's `live-route` evidence or constitute a human auditory comparison.
- Local release-pack evidence: Windows, Linux, and macOS presets each produce a 497,592-byte Safe runtime PCK with SHA-256 `530c3d07f020fa90ee0cb9da5223086d8d1d745b052795665643f65b33494b5a`; inspection of Godot's export inventory found no MCP configuration/addon, tests, tools, docs, contract mirrors, references, or GitHub workflow entries.
- Current Windows handoff evidence: the exported `Realmz Remake 2.0.exe` is 109,071,360 bytes with SHA-256 `04baf75cc1d69dd93eb709533ecab4fd7770bb8a530645717017a06a9d9809fc`; its 526,344-byte PCK has SHA-256 `678dcea7e2daa765894a9562dba8d554085929be7c8e6ac416d172962515e1b8`. A hidden headless launch smoke exited successfully. The current AOGM package remains local and separate from the executable.
- MCP evidence: the 1.16.0 doctor check passed; automatic port discovery inspected the Godot 4.7.1 project and scene tree; the main scene played; the latest AOGM package loaded and created a party through simulated input; ten ordinary movement intents reached the public-well `yes_no` request; runtime UI inspection returned `Yes` and `No`; audio inspection returned four channels, final sound 10001, and an empty queue; no choice-label or WAV decoder error occurred; a 960×600 frame was captured; and the scene stopped. The opening-AP replay separately observed two serial positive textbox requests, a passive negative textbox with no Continue button, and three concurrent final sound channels before stopping cleanly. The editor inspection contained only the existing `classic_map_presenter.gd` integer-division and shadowing warnings plus transient MCP execution diagnostics, with no new product runtime error. A subsequent installed-campaign check over three valid AOGM revisions rendered exactly one campaign row and one Play button while preserving all content-hash files.

Exit: Safe packages are cross-platform deterministic, certified routes pass, 2D/3D agree, and unsupported sandbox requirements reject cleanly.

Remaining exit evidence: execute the configured native-binary verify/export matrices on actual Windows, macOS, and Linux runners. The byte-identical cross-preset PCK is local packaging evidence, not proof that each native executable launches. The implementation does not claim Phase 6 certification until those jobs pass; additional campaign routes expand corpus confidence without weakening the completed AOGM and War route boundaries.

## Current follow-on tranche — Classic-wide application system (implemented; live campaign acceptance pending)

The kernel, package loader, scenario VM, and bounded campaign routes are established. The current work shifts the primary effort to reconstructing Realmz as a complete application instead of adding more scenario-driver coverage in isolation.

Implemented in this tranche:

- `ClassicApplicationShell` map-first composition: compact menu strip, dominant map/picture stage, persistent right roster, bottom narrative/status well, and contextual command deck over the existing typed session boundary.
- Campaign-aware party setup with schema-v2 title/version/author/restriction metadata, Race-left/Class-right filtering, and explicit setup errors.
- Character creator foundation with the five visible stages, Classic-default appearance identities, review/spell guidance, and session-owned finalization.
- Immutable `.r2char` character vault records/repository, explicit import intent, transactional persistence, archive/recovery, and target-package eligibility checks.
- Providence schema v2 exporter plus byte-identical runtime mirror and regenerated synthetic fixtures.
- One scene-backed component for each of the nine workspaces, with clipped scrolling and responsive stacked headers.
- Typed interaction placement in the stage or Classic textbox region for text, choices, encounters, services, and combat.
- Compact/Standard/Wide profiles, one route registry and Back stack, named input actions, independent UI/text scale, and 800×600 through widescreen reflow.
- Sixty exact-commit Remake bitmap controls with semantic scene-use evidence, byte hashes, dimensions, and 1×/2× nearest-neighbor rules. The selected SpriteCook charcoal surface and two matching frame textures are derived deterministically.
- Bundled Alegreya/Alegreya Sans fonts, pinned Google Fonts provenance, file hashes, and OFL licenses with no runtime network dependency.
- Presentation-complete honest states for all nine workspaces, CICN/ICON/PICT collision-free media lookup, safe unidentified-item views, and explicit action availability from `GameSession`.
- Typed interaction components for text/choice, selection, encounters, shops, temples, banks, and battles. The old procedural presenter is removed.
- A test-only gallery covers nine states for every route and interaction kind. Local rendered frames have been inspected at 800×600, 960×600, 1280×720, and 1920×1080, including dense inventory/services and 150% compact settings.

Still required for live visual acceptance and later gameplay completion:

- Complete the full MCP keyboard/focus matrix. The official Godot MCP Pro 1.16.0 CLI now provides live-campaign evidence for package selection and startup, while the broader gallery remains synthetic evidence.
- Inspect every interaction kind beside the Classic reference board; deterministic gallery coverage is broader than the currently reviewed representative frames.
- Gameplay implementations for rewards, level-up, storage/treasure assignment, and tactical combat positions; their current controls remain explicitly unavailable.
- Package media catalogs for portraits/combat icons and the remaining character review/spell choices.
- Re-run the external AOGM ordinary-play route through the new shell; the committed gallery remains synthetic and is not live-campaign proof.

## Current rolling fidelity pass — blocking age updates (implemented)

- Remake supplies the live-aging mutation lead but has no equivalent blocking age-update presentation. Castle `showageupdate`, its midnight caller, and its spell callers establish the interaction: resulting band/range, character and race identity, portrait/icon, fifteen forward or reversed deltas, sound 3002, and one modal input boundary per changed character.
- Providence commit `cad17d11bd8ec798d29bf5468ed8071019f32c1f` already emits the immutable names, media identities, ranges, and change rows, so package schema v2 remains unchanged.
- `age_update` is now a supported typed interaction with a dedicated inset presenter. Direct clock work queues updates before destination AP processing; scenario spells retain the issuing VM frame. Both forms serialize through save envelope v3, reject generic acknowledgements, and resume one ordered character at a time.
- Monster attack special 17 now preserves Castle's generic potency and save-slot-seven draws, applies one source-backed age transition, and defers physical damage and the next actor behind the same saveable interaction in direct and scenario combat.
- The age-update tranche landed with 1,640 assertions across 11 suites and ten validated differential cases.

Remaining fidelity boundary: the dialog carries stable portrait and combat-icon IDs, but the current programmatic component does not yet draw those package media assets.

## Current rolling fidelity pass — monster status attacks (implemented)

- Remake's explicit status table and tests supplied the functional lead for specials 1–7 and 16, party/monster duration differences, permanent traits, and resistance. Castle `attack` and `savevs` adjudicate the details Remake's isolated helper cannot: generic potency precedes the save; save families and monster indexing remain exact; the party checks its starting duration against 30; the result may exceed 30; failed effects at 30 still report; and magic resistance above 100 turns a monster-target special into a whole-attack whiff.
- `CombatRules` now owns all eight status mappings and branches for party and monster targets. It records exact save, condition, mutation, block, and sound facts in `AttackResolution`; `CombatFlow` publishes the special and asynchronous source sound before ordinary damage feedback. Condition state and RNG remain session-owned and save without a new continuation or `.r2save` revision.
- Providence schema v2 already exports attack rows, hit dice, runtime magic resistance inputs, type flags, saves, and spell immunities. No compiler or package-contract change was required.
- The typed suite passes 1,690 assertions across 11 suites. Differential validation covers eleven cases against the pinned Castle, Remake, and Providence roots.

The later remaining-monster-specials pass completes specials 10–15 and 18–19; this section records only the earlier status tranche's narrower evidence.

## Current rolling fidelity pass — monster resource drains (implemented)

- Remake's Classic monster-special dispatcher supplied the functional lead for spell-point and experience drains. Castle `attack`, `savevs`, and the direct struct fields resolve the important distinctions: the generic potency draw still occurs first; spell drain tests save six before checking the balance, transfers hit dice times three, and may leave the attacker above maximum; experience drain tests save five, subtracts from earned experience rather than a level-progress adapter, and has no monster-target branch.
- `CombatRules` now owns specials 8 and 9 for party and monster targets. `AttackResolution` records the exact resource, amount, target balance, attacker balance, save, block, and sound facts; `CombatFlow` publishes those facts before ordinary damage and requests sound 630 asynchronously only for a failed experience drain.
- Monster spell points now restore across the central state boundary when a source-backed drain has raised them above maximum. Direct negative experience, both sides of spell transfer, RNG order, empty/saved branches, monster-only applicability, events, and whole-session restoration are covered without changing `.r2save` v3.
- Providence schema v2 already emits the attack special, hit dice, stamina bonus, spell points, saves, immunities, and magic resistance needed by the fixed runtime construction path. No Providence or package-contract change was required. The typed suite passes 1,725 assertions across 11 suites, and differential validation covers twelve cases.

## Current rolling fidelity pass — remaining monster specials (implemented)

- Special 10 now uses a persisted character allegiance field rather than a presentation trait. Party charm resistance adds fifty to save zero, undead and immunity saves remain source-ordered, charmed actors run automatically against the opposite side, battle resolution counts both character and monster allegiance, and battle cleanup restores the party's base side.
- Specials 11–15 now preserve the generic potency draw, separate elemental damage draw, save 1–5, matching protection, integer truncation, and total health loss. `FD-COMBAT-001` deliberately corrects Castle's monster-target cold-through-mental display-only protection bug; the source observation, synthetic fixture hash, player-facing problem, and chosen-result test are recorded in `fidelity-ledger.md`.
- Specials 18 and 19 now preserve save seven, permanent blindness, party-versus-monster stone sentinels, resistance whiffs, and petrification's force-kill path that skips ordinary physical damage after it was rolled.
- The session emits typed special facts for element, rolled/committed/display damage, allegiance, condition, and force-kill ordering. Mid-battle Charm survives save/restore; automatic charmed turns never yield a player action request; cleanup publishes restored allegiance.
- Providence schema v2 already carries every immutable input. No package, compiler, or `.r2save` envelope revision was required. The typed suite passes 1,775 assertions across 11 suites, including allegiance-aware hostile targeting, enemy-count participation, and rejection of battle-scoped allegiance from reusable vault records, and differential validation now covers fifteen cases.

## Current rolling fidelity pass — character melee foundation (implemented)

- Combat builds a typed equipment snapshot from immutable item definitions. A zero-plus sword remains armed, while a nonweapon damage item no longer suppresses hand-to-hand damage. Conflicting type-2 weapons and missing definitions fail explicitly instead of depending on inventory order.
- The bounded resolver includes equipped damage/luck/armor, the type-2 weapon physical die, target-tag and heat/cold/electrical ranges, condition weapons, double-to-hit, auto-hit, reflection, helpless targets, type hatred, and Castle's two critical RNG draws. Critical chance values are not fabricated because Providence does not yet export the separate character `spec[15]` table.
- `FD-COMBAT-002` makes the defending monster's save mitigate an elemental weapon. The fixture separately records Castle's attacker-save observation; runtime tests prove the chosen result.
- Castle and Divinity use two unrelated distance concepts: Data BD battle `distance` randomizes initial monster placement, while the historically named Data MD `dist` byte is a weapon-to-hit restriction. Providence now emits that monster field as `requiredWeapon` and emits `magicToHit` separately; the runtime no longer treats battle placement as an attack prerequisite.
- `FD-COMBAT-003` follows Divinity's documented Item Number semantics because Castle's `item.itemid - 1024` comparison cannot match its shipped 1–999 item records. It also requires an actual matching weapon for blunt/sharp restrictions rather than preserving Castle's unarmed bypass. Signed stored values 128–253 normalize at the rules boundary.
- The schema-v2 hash changed in place because `.realmz2` remains unpublished; `.r2save` v3 is unchanged. Fumbles, attack half-units, missile toggling, and full equipment side effects remain future cases rather than inferred behavior.

## Current rolling fidelity pass — ordinary monster melee (implemented)

- With optional fumbles disabled, the resolver now includes Castle's damage-plus accuracy term, carried-weapon accuracy and damage fields, defender-luck draw, effective equipped armor, Realmz-day bonus, attacker conditions, evil-conditional protection, ten-percent floor, zero-minimum attack-row fallback, helpless branch, target-type damage, elemental mitigation, required-weapon gate, and Dragon Hide physical reduction plus asynchronous sound 694.
- Remake corroborates `hitDice + damageBonus` accuracy and signed physical damage materialization. Castle controls the exact percentage and RNG ordering. Providence schema v2 already emits signed `damageBonus`, attack rows, weapon identity, and complete item metadata, so no compiler or package-contract change was required.
- `FD-COMBAT-004` records Castle's negative-damage healing defect and the 2.0 zero floor. The source observation is synthetic control-flow evidence, not a Castle-runtime fixture.
- A monster weapon condition and Dragon Hide feedback that follow a monster-caused age dialog now remain in the central pending-attack state. Restore validates the saved condition baseline, applies both effects exactly once after acknowledgement, and preserves Castle's feedback-before-damage order without changing `.r2save` v3.
- Castle's random-weapon table 2 has an overlapping roll-85 boundary with context-dependent precedence: the summon helper returns the first match, while ordinary battle setup allows the later match to overwrite it. The current single `build_monster` path cannot represent both outcomes, so this remains an explicit spawn-origin modeling defect for the tactical construction pass rather than receiving a guessed global precedence change.
- Fumbles, reflection, missile-weapon replacement, and behind/facing derivation remain explicit tactical-state boundaries. The typed suite passes 1,823 assertions across 11 suites before aggregate closeout, and differential validation covers eighteen cases.

The following rolling pass closes the active-turn attack half-unit priority while retaining missile, spell, and fumble work as separate evidence cases.

## Current rolling fidelity pass — active-turn physical attack cadence (implemented)

- Player-controlled character melee now uses Castle's signed half-attack reserve directly. Activation carries at most one positive leftover, adds normal attacks and attack bonus, applies Speedy's source-control-flow four-unit bonus, resets movement, and spends two units plus three movement per attempt. A character with at least two units remaining keeps the same activation.
- Monster physical AI chooses one action, draws and retains one opposed target, and executes each authored attack row in order. Its active actor, action, target, and next row are central combat state; death macros and blocking age updates resume the exact remaining sequence rather than repeating row zero or advancing early.
- Providence schema v2 already emits race/caste attack values and monster attack count/rows. The runtime loader now rejects a count beyond the supplied rows or Classic's five-row storage, so no compiler change was required.
- Remake's floating `MaxActions` formula grants one extra full action relative to Castle for normal values and was rejected as a donor. Castle's own zero/one-half-unit display, Speedy/Slow display discrepancy, charmed-character cadence, monster Speedy row overflow, spell/item action limits, missile replacement, and tactical movement remain explicitly unresolved.
- The typed suite passes 1,858 assertions across 12 suites. Nineteen differential cases validate against the pinned Castle, Remake, and Providence roots.

## Current rolling fidelity pass — fumbles and battle recovery (implemented)

- Character and armed-monster physical attacks now consume Castle's distinct level/HD-scaled fumble draw after the hit roll. Character fumbles require an equipped removable melee weapon and capacity in the twenty-entry battle queue; cursed weapons and a full queue retain the original attack result. Monster fumbles clear only the active weapon, so later authored rows become unarmed without deleting the monster's authored booty slots.
- Opcode 122 now requires the active party combatant to have committed a physical action. Its `q[up] < 10` outer guard makes Castle's nested monster branch unreachable, so Remake's monster-disarm behavior was rejected. Authored opcode text and sound are suppressed with the outer guard; exact live-`inspell` suppression remains deferred until spell activation owns an equivalent lifecycle fact.
- Body-count selection precedes one-at-a-time typed recovery. Recovery remains available after victory, defeat, or retreat without inventing a survivor-only restriction; it enforces recipient capacity/load, identifies the item, and survives direct-session or VM save/resume. `FD-COMBAT-005` preserves the exact item instance and remaining charges instead of Castle's ID-only reconstruction.
- The dedicated Battle Recovery stage shows exact charge count, active/disabled recipients, and Leave Behind without exposing simulation objects. A normal-renderer 1280×720 gallery capture was inspected for overlap, reachability, and enabled-state accuracy; the local image remains under ignored artifacts.
- Providence schema v2 already emits every immutable item fact required by the runtime. No compiler, package-schema, or `.r2save` envelope revision was required; the additive battle and active-turn fields default safely when restoring older v3 state.
- The typed suite passes 1,923 assertions across 12 suites before aggregate closeout. Twenty differential cases validate against the pinned Castle, Remake, and Providence roots.

Flagged boundary: Castle's `allowfumble` preference is coupled to a five-percent XP penalty when disabled. Realmz 2.0 currently uses the default enabled behavior and has no source-backed gameplay-settings owner for that pair; no UI toggle or uncoupled rule has been invented.

## Current rolling fidelity pass — battle-terrain contract and tactical blockers (compiler/runtime boundary complete)

- Castle battle state owns a per-character melee/missile toggle. Setup selects melee when type 2 is equipped, otherwise missile when type 15 is equipped; returning to melee permits hand-to-hand. Switching consumes no attacks, movement, turn, or RNG. Realmz 2.0 now persists that toggle, validates unique type-2/type-10/type-15 slots, exposes the same legal action set in `CombatView` and `combat_action`, and renders a typed Switch response.
- Character missile mode no longer falls through to the melee resolver. Fire remains visible but disabled with the exact missing position/range/LOS reason. Monster AI missile selection no longer runs physical row zero under a `missile` label; it emits `combat_monster_action_unavailable` and loses that activation until the tactical resolver exists.
- Castle's positive `behind` flag is not facing. `checkforenemy(2)` gives each hostile left adjacent by movement a temporary +20 attack, while character `face` and monster `lr` only choose icon orientation. Remake's once-per-round `reaction_ready` is a functional lead but materially differs from Castle and was not ported.
- Providence now imports the shared `Combat Data BD` table, enriches old projects by exact source/landlook/tile identity, and emits complete effective battle-terrain sets. Land sets preserve active landlook 0 through 200 followed by global 201 through 400; dungeon sets preserve global 200 through 400. The runtime mirror and typed loader independently validate every range, 3×3 build, map reference, level type, and landlook. The synthetic fixture gives the two tile-200 sources different solidity values to prove the overlap is resolved correctly.
- Full tactical implementation is now blocked only on session behavior: Castle constructs a 90×90 field and consumes random terrain-decoration draws before direction and placement. Positions, adjacency, Euclidean range, LOS, point-blank rules, item-backed projectile resistance, movement cost, opportunity attacks, and missile-to-melee replacement remain disabled rather than approximated.
- Four Castle inconsistencies or hazards remain flagged for explicit decisions: manual and automated character missile paths disagree about twelve-movement cost; `attack2` uses global `monsterup` while replacing a ranged weapon; `combatmap` evaluates the top tile with `bottom.ispath`; and expanding-square placement has no no-solution bound. Current 2.0 melee target selection is also not proximity-filtered, so existing battle routes are not tactical-fidelity proof.
- The typed suite passes 1,986 assertions across 12 suites before aggregate closeout. Twenty-three differential cases target the pinned Castle, Remake, and Providence checkpoints. Providence commit `76dccf3841dc4a097b561b4293bc8618105e50ad` passes the focused 17-test exporter lane and reproducibly generates the updated fixture.

Next rolling priority: implement deterministic Castle battlefield generation and bounded session-owned placement, then proximity-gate melee before projectile firing or withdrawal attacks. Decide the top-tile path typo and no-solution placement policy explicitly. Keep spell-per-activation, Castle haste/display contradictions, and the random-weapon-table spawn-origin split separate.
