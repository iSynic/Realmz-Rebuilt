# Application host controller contract

## Purpose

Own host-side package, save, vault, and creator workflows behind detached app values while leaving session replacement and presenter coordination in the composition root.

## Local Contracts

- Controllers may depend on infrastructure repositories; presentation may not.
- Package and save controllers return detached app/core values and never replace `GameSession` themselves.
- A failed or cancelled operation leaves the active session, media catalog, and current package unchanged.
- Controllers own repository/task lifecycle and release retained resources on close.
- `PackageHostController` loads the immutable built-in Character Files catalog on its own joined worker after the first-frame boundary. It hands one detached result to the composition root and never applies media, starts a session, or leaves the worker running on close.
- `PackageHostController` merges manifest-only bundled and user campaign discovery deterministically. User revisions replace matching bundled baselines; rejected duplicates do not hide a ready campaign.
- No controller contains Realmz rules, accesses presenter Nodes, or invents compatibility behavior.

## Verification

- Test controllers through their public operations; do not call repository or controller private helpers.
- Transactional failure must be proven without mutating the current session.
