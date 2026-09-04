# Spatial presentation

The map, battlefield, and first-person dungeon are algorithmic renderers surrounded by scene-authored controls. Their presenters may create rendering nodes and geometry where an authored scene cannot express variable topology, but they must consume detached authoritative views and retain their current incremental caches.

The 2D map, combat board, and 3D dungeon never invent movement, collision, LOS, target, or discovery rules. Their viewport, cameras, layers, materials, masks, and surrounding controls belong in scenes. `ClassicMapPresenter` owns 2D drawing and pointer input; `MapTextureCache` owns decoded atlas, overlay, darkness-mask, and land-marker reuse so ordinary movement does not repeat media work. Use the rendered movement, dungeon-transition, combat, and navigation probes before and after a sensitive change.
