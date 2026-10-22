# ADR 0024: Preserve native records in compiled packages

Status: accepted

Providence remains the only production native decoder. Rebuilt prepares immutable typed catalogs from schema-v7 packages and executes through its existing VM and game systems. A second native parser in gameplay would duplicate format ownership and create another source of drift.

Compilation preserves supplied records independently of reachability, apparent usefulness or valid references. Fixed slots, signed fields and fragments retain their identities; source bytes remain exactly recoverable. Lookup distinguishes absent, partial and complete records. Consumer safety is a separate decision from preservation.

An established authored absence receives an operation-specific continuation or cancellation. It must not invent authored content, quest outcomes or rewards. Missing compiled content that exists in the native source remains an admission/release defect. Integrity faults and runtime invariants retain explicit failure handling.

Earlier package versions retain their meanings. Save v5 and Character Files v2 stay unchanged. Only an individually pinned, explicit save-copy transition may translate recorded positions to native slots; it preserves the original package, save and recorded consequences.

The [complete-record contract](../faithful-scenario-records.md) owns the format, signed-reference, safe-boundary, save-update and verification details. Independent byte accounting, runtime evidence and export verification are required separately from compiler provenance and review scores.
