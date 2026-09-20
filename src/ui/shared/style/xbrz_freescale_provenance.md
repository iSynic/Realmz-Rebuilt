# xBRZ freescale shader provenance

`xbrz_freescale.gdshader` is adapted from [libretro/glsl-shaders `xbrz/shaders/xbrz-freescale.glsl`](https://github.com/libretro/glsl-shaders/blob/f8e23ff880668f0f0e837a05a316534d82a7f31b/xbrz/shaders/xbrz-freescale.glsl), pinned to commit `f8e23ff880668f0f0e837a05a316534d82a7f31b`.

The upstream file contains Hyllian's MIT-licensed xBR vertex/texel mapping and code or concepts from xBRZ in DeSmuME/HqMAME under GPL-3.0, with the HqMAME/MAME linking exception. The complete upstream notices are preserved in the shader header. This Godot 4 CanvasItem adaptation samples an explicit viewport texture through Godot's `UV`, accepts logical source/output dimensions for fractional scaling, treats already-enlarged world pixels as one logical source pixel through the supplied source dimensions, carries sampled alpha through blends, and clamps every tap to `world_rect` to avoid atlas seams and leave UI outside the world rectangle untouched.

Upstream source retrieved and commit pinned on 2026-09-19. No upstream source files are vendored beyond the adapted shader.
