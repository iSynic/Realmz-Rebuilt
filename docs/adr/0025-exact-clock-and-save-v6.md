# ADR 0025: Exact clock and execution state in save v6

Status: accepted for the clock/combat compatibility batch.

Castle's clock permits signed and noncanonical day/hour/minute components. A normalized minute total cannot preserve them. Timer scans and scripted fumbles also require facts that the previous wire representation did not record.

Write save v6 and continue strict v5 reading. V6 stores exact clock components, explicit timer scan state, Classic physical/spell guards and the last loaded Classic VM record. One session-owned native header/selected-AP record is serialized at the root; per-invocation timer, secondary-door, no-second-door and early-return facts remain in VM schema 3. The outer movement marker decision survives timer relocation. V5 decodes its recorded minute total without executing scripts; legacy continuations and active turns retain only their recorded semantics. Never infer lost history or rewrite a file merely by loading it.

Normal saving and separately named Update Save copies use the existing verified transaction and unchanged exact package policies. Retain originals and backups. Older builds reject v6. Package schema v7, immutable campaign identities and Character Files v2 are unchanged.

This decision does not authorize generic hash rebinding, automatic migration, character repair, source pruning or terminal-fault recovery. See [clock/combat behavior and evidence](../clock-combat-compatibility.md).
