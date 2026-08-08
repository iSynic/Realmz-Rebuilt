# Source intelligence tooling contract

## Purpose

Own the deterministic source-intelligence generator, validator, HTML template, authored catalog, and graph schema used by `docs/codemap/`.

## Ownership

- File discovery, exact-byte hashing, GDScript/Markdown/DOX extraction, conservative relationship resolution, flow projection, and atomic artifact generation.
- The generator is package-free and uses the repository's PowerShell automation surface.
- The validator is read-only and is also callable from the aggregate verification lane.

## Local Contracts

- Resolve the repository root from the script path; never commit machine-specific paths or external campaign locations.
- Enumerate current tracked and nonignored source files while excluding generated outputs, binary archives, vendored addons, references, caches, builds, exports, and artifacts.
- A tracked path deleted in the current working tree is not an input file; discovery fingerprints only text files that exist in the current snapshot.
- Use exact path, symbol, line, column, file hash, and generation commit evidence for every local source relationship.
- Never turn an ambiguous name match or dynamic dispatch into a resolved edge.
- Stage and validate all generated outputs before replacing the existing snapshot.
- Reuse a prior snapshot commit only when the working tree is clean and Git confirms that commit and current `HEAD` contain identical indexed inputs. A dirty snapshot always names current `HEAD`; matching fingerprints alone cannot preserve a commit that lacks the embedded bytes.
- Preserve the existing overview catalog while allowing the detailed graph to grow beyond 20 nodes.

## Work Guidance

- Keep extraction deterministic, sorted, and independent of wall-clock time except for a new snapshot timestamp.
- Reuse the previous generation timestamp when the input fingerprint is unchanged.
- Keep HTML presentation logic in the template and keep source/index data in the generated JSON surfaces.

## Verification

- Run `validate.ps1` after generation.
- Run the repository aggregate gate through `tools/verify.ps1`.

## Child DOX Index

- No child AGENTS.md files are currently required.
