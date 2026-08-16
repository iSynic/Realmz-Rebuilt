# Presentation workspace controller contract

## Purpose

Own route-local presentation state and control construction behind typed detached views.

## Local Contracts

- Controllers receive an explicit target container and detached values; they never receive `GameSession`, repositories, or the owning router.
- Controllers emit typed intents, host actions, or presentation-setting changes. They never mutate gameplay state.
- `ClassicScreenRouter` alone mounts primary workspaces and restores route focus.
- A controller may preserve selection, filtering, sorting, tabs, and draft text for its own route only.
- `CampaignLibraryController` owns splash and installed-campaign controls, package-operation presentation, and campaign-list selection. `CampaignPartySetupController` composes it with party assembly and character creation without reimplementing campaign-library state.

## Verification

- Exercise controllers through their public `present` and signal boundaries.
- Route lifecycle tests own primary-workspace exclusivity and modal input ownership; do not add one test per overlap symptom.
