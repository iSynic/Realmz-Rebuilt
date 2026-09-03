# Workspaces and interactions

A major workspace has one scene whose stable hierarchy is recognizable in the editor, one controller that binds detached values and translates signals, and reusable row or card scenes for variable collections. A typed interaction follows the same rule but remains modal and emits only its declared response payload.

Do not build panels, splits, tabs, headings, action rails, details, or empty-state regions with `Control.new()`. Export the row scene a collection needs, pool or rebind retained children, and keep layout values in the Inspector. The system manifest lists every major surface and the Realmz Builder preview registry must cover each one.

Complex Encounters begin at `src/ui/interaction_components/encounter_interaction.tscn`. That scene owns the persistent six-command dock and exports the neighboring Action, Items, Spells, and Speak workspace scenes used by `encounter_interaction.gd`. The controller classifies authored actions, binds those stable scenes, and instantiates only the request-sized action-button collection; Inventory and Spells continue through their ordinary screen controllers so an encounter does not invent parallel item or magic UI.
