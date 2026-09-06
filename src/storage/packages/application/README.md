# Realmz application library

This directory is Rebuilt's immutable runtime copy of Providence's canonical stock Realmz application library. It owns the shared items, spells, Races, Castes, portraits, tactical icons, tilesets, sounds, pictures, and other stock media that scenarios reference.

Providence owns the readable JSON catalogs and deterministic compiler. Rebuilt deliberately keeps only the compiled package and the compact acceptance lock needed to prove which Providence inputs produced it. Scenario archives must contain only scenario-owned records and exact overrides; they do not copy this library.

Start at `ApplicationLibraryIdentity` in the parent directory to follow runtime loading. Run the Providence alignment probe before replacing either file here.
