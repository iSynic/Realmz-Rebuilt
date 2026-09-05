# Shared UI component contract

## Purpose

Own reusable scene components, presentation policies, and interaction hosting used by more than one player-facing feature.

## Ownership

- `interactions/interaction_presenter.tscn` owns the generic typed-request mount point.
- `InteractionPresenter` retains request identity and delegates request-specific rendering to feature or shared components.
- `InteractionComponentFactory` selects typed components; `InteractionLayoutPolicy` calculates request placement; `InteractionOverlayHost` and `InteractionFlashController` own reusable overlay behavior.
- `screen_frame.tscn`, `screen_message_label.tscn`, and `screen_summary_card.tscn` own the reusable workspace frame and generic detached-record components used across feature routes.
- `assets/` owns application-wide presentation media and exact provenance shared by shell, workspace, and renderer features.
- `media/` owns application and effective Classic catalogs, presentation audio, and route-aware music context.
- `style/` owns reusable Classic controls, typography, theme resources, scroll-arrow binding, content icons, and responsive layout profiles.

## Local Contracts

- Shared code contains no feature rules, saved state, package lookup, or route-specific stable layout.
- Feature-specific scenes remain with their owning UI feature even when the shared presenter mounts them.
- Shared policies may calculate geometry or bind detached values but do not reconstruct major screen hierarchies.
- Generic workspace components contain no route-specific facts or commands; their feature owner supplies detached text and navigation remains shell-owned.

## Work Guidance

- Prefer a shared component only when at least two feature owners use the same visual and behavioral contract.
- Keep source-backed Classic specializations named explicitly rather than generalizing them into ambiguous helpers.

## Verification

- Run the presentation shell/system suites and Realmz Builder preview suite after interaction-host changes.

## Child DOX Index

- `interactions/AGENTS.md` owns typed request surfaces, modal chrome, exact response payload emission, and the generic interaction host.
- `exchange/AGENTS.md` owns reusable Trade and Shop ledger drag/drop presentation.
- `assets/AGENTS.md` owns application-wide chrome, Classic media, fonts, sounds, music, shaders, and their provenance catalogs.
- `media/AGENTS.md` owns media lookup, audio playback, and music context.
- `style/AGENTS.md` owns reusable visual controls, typography, themes, and layout profiles.
