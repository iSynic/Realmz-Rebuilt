# The New Builder's Trial

This short exercise tests whether Realmz Rebuilt explains itself to a capable Godot contributor who has not learned the project through its construction. It is not a test of memory or speed. It asks whether names, scenes, nearby guides, and public interfaces form a usable map of the works.

## Preparing the trial

Use a clean checkout of the candidate commit with Git LFS materialized. Import `project.godot` in Godot 4.7.1 and allow the first scan to finish. The participant may use the repository search, the Realmz Builder dock, the Builder's Manual, feature guides, and `docs/system-manifest.json`. They may run tests and inspect any tracked file.

The participant must not receive file paths, class names, diagrams, or spoken hints that are not already in the public repository. The observer may clarify the wording of a task but may not point toward its answer. Record any place where the participant needs folklore, follows a misleading name, or opens an unrecognizable scene; that is a repository defect even if the final answer is correct.

Record the candidate commit, operating system, Godot version, participant, prior familiarity, start and finish times, and every requested hint. Elapsed time is diagnostic rather than a pass/fail limit.

## Six journeys

For each journey, the participant should identify the owning feature, the best starting file, the public input or lookup path, the authoritative state or content, the detached presentation boundary when applicable, and at least one owning test. They should also name the file they would edit for the requested change and explain why.

1. **Fatigue and travel.** Find how an ordinary movement attempt reaches the fatigue rule, how a fully fatigued party is refused, and how that refusal becomes player-visible feedback without letting Godot decide the rule.
2. **One adventurer.** Find the type that owns a character's mutable playthrough truth. Distinguish it from immutable race/caste content, the detached character view, persistence conversion, and the Godot screen that displays it.
3. **A portable item.** Trace an item carried in a Character File into an active campaign. Explain how the application catalog and scenario-owned overlay produce the winning item definition without changing the stored item identity.
4. **One Classic instruction.** Choose a supported Classic scenario opcode and trace it from package decoding through VM dispatch, its runtime operation or continuation, and a behavior-focused test. Explain where authored data ends and universal game rules begin.
5. **The Inventory room.** Open the Inventory scene in Godot and use Realmz Builder to inspect Wide, Compact, Empty, and Long Content profiles. Identify which stable hierarchy belongs to the scene, which script binds it, which detached view supplies its data, which repeated records use reusable scenes, and which tests protect the layout.
6. **Combat Auto.** Trace the player's Auto command from the visible combat control through the session transaction, deterministic category choice, legal target/action selection, movement planning when needed, and returned combat events. Explain which choices consume serialized RNG and how the player regains manual control.

## The observer's ledger

| Journey | Owner found | Data flow explained | Test found | Safe edit point named | No private hint | Notes |
|---|---|---|---|---|---|---|
| Fatigue and travel |  |  |  |  |  |  |
| One adventurer |  |  |  |  |  |  |
| A portable item |  |  |  |  |  |  |
| One Classic instruction |  |  |  |  |  |  |
| The Inventory room |  |  |  |  |  |  |
| Combat Auto |  |  |  |  |  |  |

The candidate passes when all six explanations are materially correct, every owning test is runnable or clearly identified, Inventory is recognizable and editable through its production scene and preview profiles, and no answer required a private hint. A failed or circuitous journey produces a concrete repair: improve the misleading name, neighboring guide, scene composition, public interface, manifest entry, or test location, then repeat that journey from a fresh checkout with a different newcomer.

Keep the completed ledger outside the public repository if it contains personal information or local paths. Record only the candidate commit, pass/fail result, and resulting repository fixes in release evidence.
