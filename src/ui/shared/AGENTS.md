# Shared UI component contract

## Purpose

Own reusable scene components, presentation policies, and interaction hosting used by more than one player-facing feature.

## Ownership

- `interactions/interaction_presenter.tscn` owns the generic typed-request mount point.
- `InteractionPresenter` retains request identity and delegates request-specific rendering to feature or shared components.
- `InteractionComponentFactory` selects typed components; `InteractionLayoutPolicy` calculates request placement; `InteractionOverlayHost` and `InteractionFlashController` own reusable overlay behavior.

## Local Contracts

- Shared code contains no feature rules, saved state, package lookup, or route-specific stable layout.
- Feature-specific scenes remain with their owning UI feature even when the shared presenter mounts them.
- Shared policies may calculate geometry or bind detached values but do not reconstruct major screen hierarchies.

## Work Guidance

- Prefer a shared component only when at least two feature owners use the same visual and behavioral contract.
- Keep source-backed Classic specializations named explicitly rather than generalizing them into ambiguous helpers.

## Verification

- Run the presentation shell/system suites and Realmz Builder preview suite after interaction-host changes.

## Child DOX Index
