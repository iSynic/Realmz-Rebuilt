# Presentation workspace controller contract

## Purpose

Own route-local presentation state and control construction behind typed detached views.

## Local Contracts

- Controllers receive an explicit target container and detached values; they never receive `GameSession`, repositories, or the owning router.
- Controllers emit typed intents, host actions, or presentation-setting changes. They never mutate gameplay state.
- `ClassicScreenRouter` alone mounts primary workspaces and restores route focus.
- `ClassicWorkspacePresenter` owns route-local controller composition, detached route state, content rendering, and route-specific audio. The router supplies the mounted route body and navigation-owned back label; it does not render domain content.
- A controller may preserve selection, filtering, sorting, tabs, and draft text for its own route only.
- `CampaignLibraryController` owns splash and installed-campaign controls, package-operation presentation, and campaign-list selection. Campaign party setup is layered by responsibility: shared setup state and helpers, character inspection, party assembly, five-step creation, then the public `CampaignPartySetupController` coordinator. Each layer owns only its named controls and signals; none reimplements campaign-library state or receives the router. Both public controllers mount under an explicit overlay host supplied by the shell scene.

## Verification

- Exercise controllers through their public `present` and signal boundaries.
- Route lifecycle tests own primary-workspace exclusivity and modal input ownership; do not add one test per overlap symptom.
