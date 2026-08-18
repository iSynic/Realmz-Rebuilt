# Presentation workspace controller contract

## Purpose

Own route-local presentation state and control construction behind typed detached views.

## Local Contracts

- Controllers receive an explicit target container and detached values; they never receive `GameSession`, repositories, or the owning router.
- Controllers emit typed intents, host actions, or presentation-setting changes. They never mutate gameplay state.
- `ClassicScreenRouter` alone mounts primary workspaces and restores route focus.
- `ClassicWorkspacePresenter` owns route-local controller composition, detached route state, content rendering, and route-specific audio. The router supplies the mounted route body and navigation-owned back label; it does not render domain content.
- A controller may preserve selection, filtering, sorting, tabs, and draft text for its own route only.
- Application-route controllers own compact task-specific character selection inside their full-width workspace. They do not depend on the exploration/combat roster, and item-local operations such as Trade keep their exact source item and recipient choices together.
- `SpellsWorkspaceController` groups known spells by Classic level and keeps one selected spell/power visible with detached scaling, target, resistance, save, cost, and availability facts. Fast Spell and scroll-case tabs retain their typed intent paths. The controller may format supplied facts but cannot infer legal powers, targets, effects, or resource identities.
- `CreatureLibraryWorkspaceController` owns read-only selection and rendering for current held-over allies. It consumes detached `MonsterView` records and exact media keys; it never constructs combat state, changes ally membership, or treats current allies as the Bestiary denominator. Wide composition uses one backed current-allies list beside a dominant record, while the optional Classic profile stacks those same panes so facts remain legible. List and detail art must resolve the ally's exact CICN resource key with nearest-neighbor sampling; unavailable media stays visibly absent rather than substituting a generic creature.
- `CampaignLibraryController` owns splash and installed-campaign controls, package-operation presentation, and campaign-list selection. `CampaignPartySetupController` composes explicit shared setup state with independent inspection, party-assembly, and five-step creation controllers; those collaborators never inherit behavior from one another or receive the router. The facade preserves construction, visibility, focus, and its public signal/method boundary. Both public controllers mount under an explicit overlay host supplied by the shell scene.

## Verification

- Exercise controllers through their public `present` and signal boundaries.
- Route lifecycle tests own primary-workspace exclusivity and modal input ownership; do not add one test per overlap symptom.
