# ADR 0029: Explicit scenario execution and save v9

Status: accepted and implemented; replacement acceptance gates passed.

Before this decision, the Classic interpreter expressed native record replacement, GOSUB, encounter repetition and nested application work through generic frames and nested VM snapshots. The same frame could therefore mean several different kinds of return. Some operations also discovered their next work by inspecting committed events. Those representations obscured Castle's ownership rules and made a restored continuation harder to validate.

## Decision

- Bound each uninterrupted external entry with one runner-local counter, retaining the 65,536-step policy from ADR 0027. Child calls and returns consume the same allowance; no runtime budget reference or serialized counter is needed.
- Keep `ScenarioVm` as the sole execution runner. Its ordered, closed execution records distinguish a Classic invocation, a Safe Action call and an unfinished gameplay operation. Each suspended operation names its return owner and next phase explicitly.
- Represent the active compiled position and native slot separately. One mapping owns native-slot transfers and preserves the order of interleaved Safe Action calls without changing immutable programs or package identities.
- Save native encounter memory as pure game state: independent loaded structures and marks, stored structure copies and shared text-source references. A structure's immutable base, its stored destination and its text owner may differ. The invocation separately owns its save destination. Loaded code distinguishes a compiled program, zero code and the slot-seven Keep Codes form; result copies never re-resolve later package overrides.
- Keep Castle's shared native state distinct from invocation-local state. In particular, the selected placed AP is independent of the active code and destination header. A GOSUB return restores the saved record, not the selected AP. Native entry and each caller's return perform their source-specific resets and copies explicitly.
- Preserve the retained `gosub` flag and opcode-specific stack operations from Castle `491816ad60037394f92c428e99c004494d3c28b3`. A negative opcode is not a generic call instruction. Opcode 111, opcode 112, reaching the end of a record, encounter repetition and returning from a native invocation are distinct transitions.
- Each placed invocation names its entry owner explicitly and retains a typed completion path, removal phase, header guards and backout reason. Natural completion removes the selected one-shot AP before the header epilogue; Keep Codes, native return and Safe HALT retain their source-specific policies. Child completion never controls the root caller through emitted events. Failed rechecks return immediately after selecting their code.
- Combat retains queue-time macro program, subject, signed allegiance, native index/name and coordinate as detached gameplay values. Existing queue IDs remain an ordered projection. Required combat work persists separately from feedback and crosses the runner through typed outcomes; missing legacy capture history remains explicitly unavailable.
- Gameplay operations return committed events separately from the next required operation. Macro, timer, age, header and application work is scheduled from typed outcomes and saved phases. Event history never schedules execution.
- Direct and scenario-owned battles share macro entry, suspension, completion and return. Their callers remain distinct typed values. Safe Actions retain their existing language, capabilities, types and limits in dedicated records. Their saved invocation owner bounds HALT, so a nested action returns through retained operation callers.
- Application hooks enter the same typed call lifecycle. FD-SCENARIO-026 retains explicit native caller control instead of a VM snapshot and excludes the live shared destination header. Native return values and the committed revival fact are separate typed results.
- Keep gameplay mutation in existing rules and operation owners. The session retains transaction, rollback and final restore assignment; detached checkpoints remain available where rollback needs them.
- Write save v9 with VM snapshot schema 5. Read v5-v9 and strictly convert admitted legacy execution at the codec boundary. Historical nested callers and age exit tags normalize before runner assignment; schema 5 rejects those old execution forms. Loading does not write, replay, reroll, infer unavailable historical state or broaden package rebinding and Update Save eligibility.
- Encode new type-tagged Safe integers as canonical decimal text so a JSON round trip preserves all 64 bits. Legacy numeric tags remain readable at the historical codec boundary.
- Preserve ordered equipment, adventure rules, artwork, combat, world, RNG and package bindings. Character Files v2 and packages are unchanged. Beta 27 cannot read v9: returning to it requires a preserved v8-or-earlier save.

Clock, spell and combat outcomes carry ordered age acknowledgements separately from committed feedback. Saved age owners retain the exact batch and resume phase; event history never reconstructs required work.

## Consequences and acceptance

The runner replaces the old execution machinery rather than adding another executor. Completion requires removal of nested live-VM reconstruction, ordinary call-state VM snapshots, backward searches for Classic return ownership, event-driven execution dispatch and duplicate combat macro lifecycles.

Every supported yield in the branch, encounter, macro, timer, age and application-hook matrix must compare uninterrupted execution with real JSON save/read/restore: gameplay state, next request, effects and ordered RNG draws must agree. Rejected responses preserve the complete pending state. Malformed v9 and unsupported versions reject before changing the active session or files.

The source ownership and transition contract is in [scenario-execution-contract.md](../scenario-execution-contract.md). Source inspection, controlled Castle execution, synthetic Rebuilt cases, ordinary commands, visible controls and campaign certification remain distinct evidence. Uncertain Classic-visible behavior requires a controlled Castle fixture before implementation.

Beta 27 was published and accepted before implementation began. Development uses an isolated worktree and save storage, with the architecture and test ceilings frozen through the four implementation batches. Only the fully verified replacement is integrated into the primary local main; a subsequent public release is separate.
