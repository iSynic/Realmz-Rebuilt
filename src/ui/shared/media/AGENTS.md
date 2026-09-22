# Shared presentation media contract

## Purpose

Own application-wide media catalogs, exact Classic resource lookup, presentation audio, and route-aware music context.

## Ownership

- `ApplicationMediaCatalog`, `ClassicMediaCatalog`, and `ClassicUiAssetCatalog` index immutable application and scenario presentation resources.
- `ClassicMapAtlas` owns the cached presentation-only dungeon crop of complete PICT 302; exploration, retained maps, and acquired maps share that view. Exact image lookup keeps the full source pixels, while battle tiles and land markers address the full 640-by-640 resource through scenario-first exact lookup.
- `ClassicAudioPresenter` owns presentation playback channels and completion timing without deciding gameplay cues.
- `ClassicMusicCatalog` and `ClassicMusicContext` resolve the source-backed music identity supplied by the active route and map.

## Local Contracts

- Catalogs resolve exact typed resource identities and never reinterpret scenario ownership or gameplay state.
- Runtime `landlook-N` aliases resolve through exact `PICT:(300+N)` lookup before any application-ID fallback, so scenario-owned custom art and stock-ID overrides keep Castle's scenario-first precedence.
- Audio and music consume committed presentation requests; they do not emit gameplay intents or advance simulation.
- Media bytes remain in `../assets`; these classes index and present them without duplicating payloads.

## Work Guidance

- Keep stock application lookup, scenario override composition, playback, and route context as separate named responsibilities.

## Verification

- Run the application-media and music verifiers plus the presentation system suite after media-boundary changes.

## Child DOX Index

- This feature has no child DOX documents.
