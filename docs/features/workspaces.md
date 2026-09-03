# Workspaces and interactions

A major workspace has one scene whose stable hierarchy is recognizable in the editor, one controller that binds detached values and translates signals, and reusable row or card scenes for variable collections. A typed interaction follows the same rule but remains modal and emits only its declared response payload.

Do not build panels, splits, tabs, headings, action rails, details, or empty-state regions with `Control.new()`. Export the row scene a collection needs, pool or rebind retained children, and keep layout values in the Inspector. The system manifest lists every major surface and the Realmz Builder preview registry must cover each one.
