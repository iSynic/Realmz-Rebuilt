# Application session-hosting contract

## Purpose

Own host workflows around one replaceable pure `GameSession` without duplicating simulation state or leaking persistence records into presentation.

## Ownership

- `GameSessionController` owns the active session and one detached view per committed revision.
- `ApplicationAdventureStorageHost` and `SaveHostController` own save, preview, restore, and backup coordination.
- `ApplicationCharacterFilesHost`, `CharacterVaultController`, and `CharacterCreationHostController` own the application catalog, reusable-character cache, publication, import, and standalone creation.
- `ApplicationCombatPolicy` translates combat presentation responses and Auto playback decisions into typed session commands.
- Character-file identity and revision views are detached app-owned presentation records.

## Local Contracts

- Controllers may depend on storage repositories; presentation may not.
- Restore validates a replacement completely before swapping the active session.
- A failed or cancelled operation leaves the active session and media catalog unchanged.
- Character Files revisions are cached by stable identity and revision hash and invalidated after mutation.
- No host controller contains Realmz rules, accesses presenter-private methods, or invents compatibility behavior.

## Work Guidance

- Enter simulation only through the public `GameSession` transaction surface.
- Return detached app or game views from repository-facing work; never return storage DTOs to UI.

## Verification

- Run the affected save, session-persistence, Character Files, and presentation suites.
- Prove transactional failure without mutating the current session.

## Child DOX Index
