# Application host controller contract

## Purpose

Own host-side package, save, vault, and creator workflows behind detached app values while leaving session replacement and presenter coordination in the composition root.

## Local Contracts

- Controllers may depend on storage repositories; presentation may not.
- Host controllers construct registered repository and task classes by their public names; generic preload aliases are not part of this boundary.
- Package and save controllers return detached app/core values and never replace `GameSession` themselves.
- A failed or cancelled operation leaves the active session, media catalog, and current package unchanged.
- Controllers own repository/task lifecycle and release retained resources on close.
- `PackageHostController` loads the immutable built-in Character Files catalog on its own joined worker after the first-frame boundary. It hands one detached result to the composition root and never applies media, starts a session, or leaves the worker running on close.
- `PackageHostController` attaches the validated application definition/media catalog to its repository only while no package preparation is running. Scenario preparation composes exact-ID scenario overlays over that immutable baseline; the package assembler remains the completeness and rules-version authority.
- `PackageHostController` merges manifest-only bundled and user campaign discovery deterministically. User revisions replace matching bundled baselines; rejected duplicates do not hide a ready campaign.
- `PackageHostController` resolves optional last-campaign prewarm only from those detached discovery rows, runs it on the existing cancellable worker, and retains at most one prepared candidate. A matching foreground request claims it immediately; a different request cooperatively supersedes it and receives foreground status/progress without exposing package DTOs to presentation. Background failure retains nothing and permits retry.
- `CharacterVaultController` caches only records already validated while listing Character Files, keyed by `(characterId, revisionHash)`. Import returns a detached `CharacterState` clone from that cache, while publish, archive, restore, and a fresh listing invalidate or replace cached records so repository mutations cannot leave stale imports.
- Starter installation validates the pinned catalog against the application-library hash before invoking the repository's atomic empty-vault boundary; it invalidates the cache on success and reports failure without disabling ordinary character creation.
- No controller contains Realmz rules, accesses presenter Nodes, or invents compatibility behavior.

## Verification

- Test controllers through their public operations; do not call repository or controller private helpers.
- Transactional failure must be proven without mutating the current session.
