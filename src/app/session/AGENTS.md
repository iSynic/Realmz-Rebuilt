# Application session-hosting contract

## Purpose

Own host workflows around one replaceable pure `GameSession` without duplicating simulation state or leaking persistence records into presentation.

## Ownership

- `GameSessionController` owns the active session and one detached view per committed revision.
- Typed intent/response submission signals expose the input immediately before the public session transaction; optional diagnostics can correlate even failed steps without reading private state or changing gameplay.
- `ApplicationAdventureStorageHost` and `SaveHostController` own save, preview, restore, and backup coordination.
- `ApplicationCharacterFilesHost`, `CharacterVaultController`, and `CharacterCreationHostController` own the application catalog, reusable-character cache, publication, import, and standalone creation.
- `ApplicationCombatPolicy` translates combat presentation responses and Auto playback decisions into typed session commands.
- `PersistentAutoCoordinator` retains one generation-tracked, deduplicated host continuation across presented-revision, playback, modal, queued-toggle, and controller-suspension boundaries. It submits only after the presentation coordinator acknowledges that the matching committed revision has drawn, then rechecks session identity, revision, active actor, and Auto state before using the existing typed combat response. Revision changes during that wait remain pending for reevaluation; a failed revision is reported and latched instead of retried. Its testing observation marks combat active explicitly and never presents a terminal battle's last actor or round as pending work.
- Character-file identity and revision views are detached app-owned presentation records.

## Local Contracts

- Controllers may depend on storage repositories; presentation may not.
- Restore validates a replacement completely before swapping the active session.
- Explicit Half Truth save updating validates the exact old and current package identities, pinned media-only archive transition, and detached replacement restore before writing a separate copy. It never changes the active session or original save.
- A failed or cancelled operation leaves the active session and media catalog unchanged.
- Character Files revisions are cached by stable identity and revision hash and invalidated after mutation.
- Character Files refresh also publishes a detached notice when preserved current revisions are incompatible or invalid; the host never treats those files as an empty vault or requests their migration.
- `ApplicationCharacterFilesHost` accepts an explicitly injected vault controller; default construction uses the ordinary repository, while runtime fixtures supply scratch storage before entering the scene tree.
- No host controller contains Realmz rules, accesses presenter-private methods, or invents compatibility behavior.

## Work Guidance

- Enter simulation only through the public `GameSession` transaction surface.
- Return detached app or game views from repository-facing work; never return storage DTOs to UI.

## Verification

- Run the affected save, session-persistence, Character Files, and presentation suites.
- Prove transactional failure without mutating the current session.

## Child DOX Index
