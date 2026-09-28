# CRT shader provenance

`crt_pi.gdshader` adapts `crt/shaders/crt-pi.glsl` from the pinned
[libretro/glsl-shaders](https://github.com/libretro/glsl-shaders) revision
`f8e23ff880668f0f0e837a05a316534d82a7f31b`. The upstream shader is copyright
2015–2016 davej and is released under the GNU General Public License, version
2 or any later version. Its copyright and GPL notice are retained in the
shader header. The port keeps the gamma, bloom, and green/magenta mask behavior;
it replaces the source-relative scanline contrast with an output-pixel pattern
and removes the optional curvature, then
maps the upstream texture/input/output uniforms to the shared Godot contract.
It explicitly interpolates four source texels for linear filtering, avoiding
backend-dependent filtering of viewport textures. Outside the selected world
region, one exact texel fetch preserves nearest pass-through.

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

The ports adapt fine detail to the effective output pixels per source pixel.
At responsive 1x they leave native pixels sharp while applying a restrained
three-output-pixel scanline pattern and output-pixel mask. Source filtering fades
from zero at 2x to full at 3x. Source-relative scanline contrast is normalized
to mean beam energy rather than producing phase-dependent grouped bars.
Lottes normalizes its original row weights against the integral of its curated
shape-2 Gaussian; Pi uses the period average of its clamped parabolic beam.
The original colour taps, gamma, bloom, and high-scale filtering remain.
Both scanlines and masks use final-pass fragment coordinates, so fractional Fill
offsets or world-region origins cannot resample the physical patterns. These
are deliberate display adaptations, not changes to either upstream revision.
