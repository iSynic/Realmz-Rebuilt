# Shared presentation

This folder contains visual contracts reused by more than one Realmz screen. Begin with `interactions/` for typed modal and workspace requests, `exchange/` for the shared Trade and Shop ledger, and the small `screen_*` scenes for generic workspace framing and detached-record presentation.

Application-wide media bytes and provenance live under `assets/`, their lookup and playback boundary lives under `media/`, and the reusable Classic control, typography, theme, scrolling, and responsive-profile vocabulary lives under `style/`. Feature-specific scene composition remains with its owning UI feature; shared code must not accumulate route-specific commands, gameplay rules, saved state, or package lookup.

Run the shell and system presentation suites plus the Realmz Builder preview suite after changing shared scene behavior. Media changes additionally use the catalog-specific verification tools documented under `assets/`.
