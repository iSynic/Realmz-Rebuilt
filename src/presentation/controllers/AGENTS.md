# Presentation workspace controller contract

## Purpose

Own route-local presentation state and control construction behind typed detached views.

## Local Contracts

- Controllers receive an explicit target container and detached values; they never receive `GameSession`, repositories, or the owning router.
- Controllers emit typed intents, host actions, or presentation-setting changes. They never mutate gameplay state.
- `ClassicScreenRouter` alone mounts primary workspaces and restores route focus.
- `ClassicWorkspacePresenter` owns route-local controller composition, detached route state, content rendering, and route-specific audio. The router supplies the mounted route body and navigation-owned back label; it does not render domain content.
- A controller may preserve selection, filtering, sorting, tabs, and draft text for its own route only.
- `CreatureLibraryWorkspaceController` owns read-only selection and rendering for current held-over allies. It consumes detached `MonsterView` records and exact media keys; it never constructs combat state, changes ally membership, or treats current allies as the Bestiary denominator.
- `CampaignLibraryController` owns splash and installed-campaign controls, package-operation presentation, and campaign-list selection. `CampaignPartySetupController` composes explicit shared setup state with independent inspection, party-assembly, and five-step creation controllers; those collaborators never inherit behavior from one another or receive the router. The facade preserves construction, visibility, focus, and its public signal/method boundary. Both public controllers mount under an explicit overlay host supplied by the shell scene.

## Verification

- Exercise controllers through their public `present` and signal boundaries.
- Route lifecycle tests own primary-workspace exclusivity and modal input ownership; do not add one test per overlap symptom.
