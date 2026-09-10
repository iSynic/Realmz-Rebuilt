# Shared presentation style contract

## Purpose

Own reusable Classic controls, typography, theme resources, scroll-arrow behavior, content icons, and responsive layout profiles.

## Ownership

- `ClassicBitmapButton` and `classic_content_icon.tscn` are reusable source-backed control components.
- `ClassicTypography` and `classic_ui_theme.tres` own the application-wide font and theme language.
- `UiLayoutProfile` carries the Wide or Compact presentation profile supplied to scene binders.
- `ClassicScrollArrowController` binds reusable scroll arrows to an existing scene-owned scroll container.

## Local Contracts

- Shared style components contain no route-specific facts, gameplay legality, saved state, or package I/O.
- Stable visual hierarchy remains scene-authored. Scripts bind inspector properties, focus, scrolling, and supplied media.
- Wide and Compact profiles alter presentation only and never change simulation or detached data.
- `ClassicBitmapButton.caption_text()` exposes its current rendered caption to read-only control catalogues without exposing private drawing state or duplicating command-label logic.

## Work Guidance

- Add a component here only when multiple feature scenes share the same visual and behavioral contract.

## Verification

- Run the presentation shell/system suites and Realmz Builder previews after shared-style changes.

## Child DOX Index

- This feature has no child DOX documents.
