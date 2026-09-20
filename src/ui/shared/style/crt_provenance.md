# CRT shader provenance

`crt_pi.gdshader` adapts `crt/shaders/crt-pi.glsl` from the pinned
[libretro/glsl-shaders](https://github.com/libretro/glsl-shaders) revision
`f8e23ff880668f0f0e837a05a316534d82a7f31b`. The upstream shader is copyright
2015–2016 davej and is released under the GNU General Public License, version
2 or any later version. Its copyright and GPL notice are retained in the
shader header. The port keeps the scanline, multisample scanline, gamma,
bloom, and green/magenta mask behavior; it removes the optional curvature and
maps the upstream texture/input/output uniforms to the shared Godot contract.
It binds the same retained texture through a separate nearest sampler for
pixel-exact pass-through outside the selected world region.

`crt_lottes.gdshader` adapts `crt/shaders/crt-lottes.slang` from the pinned
[libretro/slang-shaders](https://github.com/libretro/slang-shaders) revision
`afb1416b6b85d3e53c6e586a9209cb9097c7b4a4`. The upstream implementation is
the public-domain CRT styled scan-line shader by Timothy Lottes; its complete
public-domain notice is retained in the shader header. The port keeps the
three/five/seven-tap Gaussian filtering, scanline bloom, linear-gamma option,
and shadow-mask variants. It removes the Vulkan vertex/UBO plumbing and
intentionally makes `Warp` identity so curvature is disabled.

Both are Godot 4 `CanvasItem` shaders. They sample `source_texture` through
`UV`, accept `source_size`, `output_size`, and normalized `region_rect`, clamp
all internal taps to that region, and pass through pixels outside it. The
ports preserve sampled alpha and contain no runtime backend or integration
files. Upstream source revisions were retrieved and pinned on 2026-09-19.
