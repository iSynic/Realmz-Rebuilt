# Shared presentation style contract

## Purpose

Own reusable Classic controls, typography, theme resources, scroll-arrow behavior, content icons, and responsive layout profiles.

## Ownership

- `ClassicBitmapButton` and `classic_content_icon.tscn` are reusable source-backed control components.
- `ClassicTypography` and `classic_ui_theme.tres` own the application-wide font and theme language.
- `ClassicRosterText` and `ClassicRosterAuto` retain the roster's larger scene-authored type sizes while selecting Theldrow Rebuilt in Classic mode and Inter in Readable mode. Roster labels inherit these roles so changing Preferences updates the existing controls.
- `UiLayoutProfile` carries the Wide or Compact presentation profile supplied to scene binders.
- `xbrz_freescale.gdshader` is the pinned Libretro freescale adaptation; `xbrz_freescale_provenance.md` records its license, revision, and Godot sampling changes.
- `crt_pi.gdshader` and `crt_lottes.gdshader` are pinned Libretro CRT adaptations; `crt_provenance.md` records their source revisions, notices, and curvature-free Godot sampling contract.
- `ClassicScrollArrowController` binds reusable scroll arrows to an existing scene-owned scroll container.

## Local Contracts

- Shared style components contain no route-specific facts, gameplay legality, saved state, or package I/O.
- Stable visual hierarchy remains scene-authored. Scripts bind inspector properties, focus, scrolling, and supplied media.
- Wide and Compact profiles alter presentation only and never change simulation or detached data.
- Fill mode alone permits a logical stage wider than the usual 16:9 application bound. Compact 800x600 reserves enough footer height and width to expose twelve commands and party effects without clipping.
- `ClassicBitmapButton.caption_text()` exposes its current rendered caption to read-only control catalogues without exposing private drawing state or duplicating command-label logic.
- Grouped bitmap buttons may provide `caption_lines` for an intentionally stacked live caption; the shared renderer keeps each line fitted inside the authored caption band without changing the command identity.

## Work Guidance

- Add a component here only when multiple feature scenes share the same visual and behavioral contract.

## Verification

- Run the presentation shell/system suites and Realmz Builder previews after shared-style changes.

## Child DOX Index

- This feature has no child DOX documents.
