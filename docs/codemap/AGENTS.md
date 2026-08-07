# Source intelligence artifact contract

## Purpose

Own the generated Realmz Remake source encyclopedia, its machine-readable graph, embedded source snapshot, retrieval chunks, and the authored catalog/schema that define their durable shape.

## Ownership

- `codemap.html` is the self-contained human browser.
- `codemap.json` is the backward-compatible 20-node architectural overview.
- `intelligence.json` is the full entity and relationship graph.
- `chunks.jsonl` is the stable agent retrieval surface.
- `codemap.lock` records the source snapshot, generator version, input fingerprints, and output hashes.
- `catalog.json` and `intelligence.schema.json` are authored inputs; generated artifacts must never be hand-edited.

## Local Contracts

- Local source and documentation may be embedded; Castle and Providence source remains citation-only external evidence.
- Every resolved relationship has source-span evidence. Ambiguous or dynamic relationships use `status: "unknown"` and do not receive a guessed target.
- The overview remains at most 20 primary nodes and five primary flows; the detailed entity graph is not subject to that limit.
- Generated artifacts are produced together from one source snapshot and must agree on commit, file hashes, entities, relations, flows, and source spans.
- Excluded directories and binary/generated files stay outside the embedded corpus and are recorded in the lock.
- HTML is direct-open, offline, escaped, and free of external scripts, styles, fonts, network calls, and runtime services.
- Graph node details remain pinned after pointer release; background clicks clear the selection, and node dragging redraws after release without losing the selection.

## Work Guidance

- Update `catalog.json` only for deliberate module, concept, alias, or flow changes.
- Use the generator and validator under `tools/source-intelligence/`; do not patch generated JSON, JSONL, HTML, or lock content by hand.
- Preserve exact source bytes and line endings in the embedded file records; normalize only derived search/chunk text.
- Keep provenance labels clear: local source, DOX/documentation, test evidence, external citation, and unknown extraction.

## Verification

- `tools/source-intelligence/validate.ps1` checks source spans, entity/relation references, graph parity, embedded HTML data, chunks, and lock hashes.
- `tools/verify.ps1` regenerates the snapshot before the existing Godot, architecture, export, and diff checks.

## Child DOX Index

- No child AGENTS.md files are currently required.
