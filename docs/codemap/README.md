# Realmz source intelligence

This directory contains a generated, offline encyclopedia of the Realmz Remake 2.0 source. Open `codemap.html` directly in a browser for the interactive map, repository explorer, source viewer, DOX browser, flow explorer, diagnostics, and unknown relationship views. Agents can consume `intelligence.json` or one stable retrieval record at a time from `chunks.jsonl`.

## Regenerate

From the repository root:

```powershell
./tools/source-intelligence/generate.ps1
./tools/source-intelligence/validate.ps1
```

`tools/verify.ps1` runs generation automatically. It leaves changed artifacts in the worktree for review. CI regenerates and fails when the committed snapshot is stale. Generation stages all five generated outputs, validates them, and only then moves them into this directory. If input fingerprints are unchanged, the previous UTC timestamp is reused so verification does not churn bytes.

## Artifacts

- `codemap.html` is the self-contained human interface. It embeds the overview and the complete indexed text corpus; it has no network, server, font, script, or stylesheet dependency.
- `codemap.json` is the compact architectural contract: at most 20 overview nodes and five primary flows.
- `intelligence.json` is the complete entity/relation graph. Stable identifiers use `module:`, `file:`, `symbol:`, `doc:`, `concept:`, and `external:` prefixes.
- `chunks.jsonl` contains deterministic retrieval chunks for files, functions, classes, Markdown sections, DOX sections, and bounded continuations.
- `codemap.lock` records the commit, dirty state, scope, exclusions, generator/schema versions, input/output hashes, and module fingerprints.

Every local file is embedded with its exact SHA-256. Every local source span records its path, symbol, line/column range, file hash, and generation commit. External Castle and Providence material remains citation-only.

## Browser search

Search accepts normal words, quoted phrases, and filters:

- `kind:function` — entity kind such as `module`, `file`, `class`, `function`, `test`, `concept`, `doc-section`, or `dox`.
- `path:src/scenario` — path prefix.
- `module:scenario-vm` — overview/module identifier.
- `dox:src/core` — governing DOX scope.
- `test:scenario` — related test text.
- `flow:save` — related flow text.
- `unknown:true` — unresolved relationships and diagnostics.

Select a result to see source lines, callers, dependencies, tests, documents, DOX constraints, flows, and evidence. Source links use the embedded snapshot and remain usable when the HTML is opened with `file://`.

Selecting a source reference updates the URL hash with the stable entity, path, and line. Those links work with browser back/forward navigation and include a copyable `path:line` reference. Graph node selections stay pinned after the pointer is released; click the graph background to clear them. The inspector favors readable source/context space, while search results stay compact and scroll within a bounded panel. The graph supports node selection, upstream/downstream highlighting, complete flow highlighting, zoom, fit, and drag repositioning.

## Deterministic semantic layer

The initial semantic layer is structural and searchable rather than model-generated. GDScript relationships are emitted only when the generator has explicit evidence: preload/load paths, global classes, constructors, typed receivers, unique local symbols, property writes, or signal calls. Dynamic dispatch, ambiguous overloads, and unresolved citations remain `unknown` with their local evidence and diagnostic text. No relationship is inferred from name similarity alone. Authored concept aliases in the catalog provide deterministic semantic vocabulary; the schema leaves room for a future embeddings adapter without shipping a model, vectors, credentials, or API dependency.

The full corpus is intentionally local and searchable, but binary archives, vendored addons, generated directories, caches, builds, exports, and external reference source text are excluded. Fixture archives are represented by authored metadata and catalog nodes.

## Machine consumption

Use `entities` to navigate repository, module, file, symbol, test, document section, DOX, concept, flow, and external-evidence records. Use `relations` for calls, imports, reads, writes, publishes, subscribes, containment, documentation, tests, and explicit unknown/external edges. Use `flows` for ordered evidence-backed paths. Resolve a chunk's `source_sha256` and `commit` against `files` before using its text. `diagnostics` is the authoritative list of unresolved references, malformed citations, duplicate/ambiguous symbols, skipped encodings, and extractor limitations.

## Evidence boundaries

Local source, tests, documentation, and DOX contracts are embedded with exact file hashes and line spans. Castle and Providence references are retained as external citations with repository, commit, path, and line metadata from `docs/references.lock.json`; their source text is not copied into the repository. When a citation names no target line, the target range remains null and `diagnostics` records the limitation rather than inventing one.

Generated files are never hand-edited. Deliberate overview modules, aliases, and flows belong in `tools/source-intelligence/catalog.json`. The machine contract is in `intelligence.schema.json`.
