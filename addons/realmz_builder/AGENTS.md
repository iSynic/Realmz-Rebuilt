# Purpose

- Own the public, editor-only Realmz Builder plugin used to understand and preview major scenes.

# Ownership

- `scene_previews.json` registers major scenes, their maintainer links, supported profiles, and preview-completion status.
- `RealmzBuilderPreviewFixtures` supplies deterministic detached interaction requests, while `realmz_builder_screen_preview_fixtures.gd` supplies detached game views to the same production controllers used by major screens.
- The plugin and dock own editor lifecycle and transient preview helpers only.

# Local Contracts

- Nothing in this folder may be required by runtime startup or simulation.
- Release exports exclude the complete folder.
- Preview helpers have no scene owner and must never become saved children.
- Production-bound previews instantiate one ownerless scene clone and bind it after the clone enters the edited scene tree; they never mutate the scene being authored.
- Registration alone is not preview completion; `productionBinding` becomes true only when representative data uses the production binding method and row scenes.
- All registered major surfaces are production-bound. The application shell's pre-ready editor clone binds its scene-authored facts and production roster directly; a ready runtime shell uses `GameShell.present`.

# Work Guidance

- Keep preview fixtures detached, synthetic, deterministic, and clearly identified as editor-only.
- Link each registered scene to its public guide, controller, detached view, and owning tests.

# Verification

- Run a headless editor import, `tools/verify_architecture_overhaul.ps1`, and `tools/verify_export_contract.ps1`.

# Child DOX Index
