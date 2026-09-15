# ADR 0018: Ordered equipment in save v5 and Character Files v2

## Status

Accepted.

## Context

Castle applies wearable effects in source wear order. Armor has a zero floor and damage bonus has an upper cap, so mixed modifiers cannot be reconstructed from an unordered set of equipped flags. Wearable items also mutate character and party facts that must be reversed exactly when an item is removed by Inventory, scenario code, a temple, a spell, or combat.

Save v4 and Character Files v1 record only each item's equipped flag. Inferring historical wear order would make restored results dependent on inventory layout rather than the committed playthrough.

## Decision

`CharacterState` owns an ordered list of equipped item-instance identities. Equipment admission appends to that order; normal and forced removal delete from it and reverse passive effects through `EquipmentRules`. Combat projection folds floor- and cap-sensitive modifiers in the recorded order. Low-level inventory removal rejects an equipped instance.

`.r2save` v5 and Character Files v2 require the ordered list to contain every equipped instance exactly once. Save v1 through v4 and Character Files v1 are incompatible. Browsing may report these records, but runtime code does not infer, migrate, overwrite, or delete them.

## Consequences

- Exact wear order survives save/restore, Character Files publication, transfer, and combat projection.
- Starter-character revisions are regenerated deterministically as Character Files v2 and therefore receive new revision hashes.
- Existing scenario packages and presentation settings do not change.
- Previously stored saves and Character Files remain on disk but cannot be loaded by this version.
