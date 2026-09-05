# Shared presentation assets

This directory is the application-wide media library used by the shell, workspaces, and algorithmic renderers. It contains exact Classic controls and media, project-owned chrome, dungeon surfaces, fonts, shaders, sounds, music, and the provenance catalogs that identify every selected production asset.

Keep scenario-owned media in `.realmz2` packages. Add application media only through its owning import or generation workflow under `tools/ui-assets`, update the adjacent catalog and notices atomically, and preserve exact source bytes where the catalog says an asset is unmodified. Runtime code should resolve media through the appropriate catalog rather than infer ownership from a numeric ID.

Run the relevant `tools/ui-assets/verify-*` script, presentation tests, export-contract verification, and Godot import after changing this directory. The `.import` sidecars preserve stable Godot UIDs and import settings; do not hand-repaint or silently replace their source assets.
