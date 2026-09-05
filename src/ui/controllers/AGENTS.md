# UI controller contract

## Purpose

Own route-local UI state and detached-view binding for scene-authored workspaces and variable record scenes.

## Local Contracts

- Controllers receive an explicit target container and detached values; they never receive `GameSession`, repositories, or the owning router.
- Controllers emit typed intents, host actions, or presentation-setting changes. They never mutate gameplay state.
- Controller scripts reached by the background application graph must not script-preload imported textures or themes; resolve those resources only while constructing controller-owned controls on the main thread.
- `ScreenNavigator` alone mounts primary workspaces and owns route history. `WorkspaceFocusController` restores route focus and scroll state. The production scene owns the workspace and overlay hosts; neither the navigator nor a test harness may manufacture fallback hosts. Callers address `CampaignPartySetupController` and `ScreenContentPresenter` directly for their owned state rather than adding forwarding methods to the navigator.
- `ScreenContentPresenter` owns route-local controller composition, detached route state, content rendering, and route-specific audio. Its initialization groups signal relays by the system, character, inventory, services, maps, or spells controller that owns the source event. Its generic detached summaries instantiate the exported message and summary-card scenes; the router supplies the mounted route body and navigation-owned back label and does not render domain content.
- A controller may preserve selection, filtering, sorting, tabs, and draft text for its own route only.
- Application-route controllers own compact task-specific character selection inside their routed workspace. They do not depend on roster-row interaction, and item-local operations such as Trade keep their exact source item and recipient choices together.
- `SystemScreenController` exposes the host-owned traveled-area preview and Auto Note toggles in Controls plus the default-on Classic exploration-distance policy in Display. All persist only through `PresentationSettings`; map preferences change rendering from detached visited facts and Auto Note selects the acknowledgement payload, without mutating simulation directly. Its Audio tab keeps master, effects, and music volumes separate, persists global music enablement and source-classified Reduced Sound, and opens the shell-owned playlist modal without owning playback. Controls also owns the fixed keyboard/mouse reference derived from the public input contract; it does not imply unsupported remapping.
- `SystemScreenController` constructs no Controls and binds the complete scene-authored `SystemWorkspace`, instantiating only its exported detached save-slot row. Save & Load remains separate from Display, Audio, Pacing, Accessibility, Controls, and Diagnostics. Every preference tab uses a backed, vertically scrollable slate card so 800×600 at maximum text scale remains reachable; scene-authored rows align wide and stack in the compact `UiLayoutProfile`. Display pick lists use the shared Rebuilt-font option role in either typography mode. The Game menu exposes the full Save & Load route, and that workspace owns slot/source selection, one detached preview, and fixed host actions: Quick Save 1 retains legacy slot `quick`, Quick Save 2 uses `quick-2`, Save Selected overwrites the selected slot through the existing host boundary, and Save New Slot accepts only the repository's portable slot alphabet. A host-requested Save and Quit mode replaces ordinary save controls with one selected-slot Save and Quit action, while Back cancels that host mode. It distinguishes primary and backup loads and leaves corrupt/incompatible records visible with their exact reason. Preference tabs emit only existing typed presentation-setting changes and apply immediately; they never alter Classic rules or invent Apply/Reset, deletion, screenshots, schema mutation, or migration controls absent from the host contracts.

## Verification

- Exercise controllers through their public `present` and signal boundaries.
- Route lifecycle tests own primary-workspace exclusivity and modal input ownership; do not add one test per overlap symptom.
