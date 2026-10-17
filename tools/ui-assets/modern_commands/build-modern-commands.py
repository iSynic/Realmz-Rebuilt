#!/usr/bin/env python3
"""Rebuild the reviewed 32px modern command icons from committed SVG masters."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
ASSET_ROOT = ROOT / "src/ui/shared/assets/ui/commands/modern"
STATIC_MASTERS = {
    "search-face": ("cJM1t", False),
    "area-search": ("o7GH5X", False),
    "heal": ("V0p7d4", False),
    "camp": ("Ddgog", False),
    "rest": ("y99lA", False),
    "encounter": ("ViqhR", False),
    "money": ("S5DXC", False),
    "items": ("s8IR3S", False),
    "spells": ("MotNE", False),
    "maps": ("OXEW2", False),
    "pause": ("atgag", False),
    "torch": ("r6XHlY", True),
    "torch-unlit": ("derived-from-r6XHlY", True),
}
TORCH_PALETTE = [
    "441704", "491e0d", "572510", "5f2a15", "682f16", "882a09", "923f15", "9d3008",
    "b55210", "ce841d", "e2a326", "ed4208", "f75d11", "fc6e14", "f9b61b", "fff18a",
]
SNAP_ARGS = [
    "16", "--mode", "pixelize", "--size", "32x32", "--sampling", "average",
    "--dither", "none", "--hard-alpha", "128",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args: list[str], *, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(args, check=True, text=True, capture_output=True, env=env)
    return result.stdout.strip()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pixel-snapper", required=True, type=Path, help="Pixel Snapper executable")
    parser.add_argument("--renderer-node", required=True, type=Path, help="Node.js executable")
    parser.add_argument("--sharp-module-dir", required=True, type=Path, help="Directory containing the sharp Node module")
    parser.add_argument("--source", type=Path, default=ASSET_ROOT / "source", help="Committed SVG/keyframe source directory")
    parser.add_argument("--output", type=Path, default=ASSET_ROOT, help="Directory for production PNGs and manifest")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    snapper = args.pixel_snapper.resolve(strict=True)
    node = args.renderer_node.resolve(strict=True)
    sharp_dir = args.sharp_module_dir.resolve(strict=True)
    source = args.source.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env["NODE_PATH"] = str(sharp_dir)
    sharp_versions = json.loads(run([str(node), "-e", "console.log(JSON.stringify(require('sharp').versions))"], env=env))
    snapper_version = run([str(snapper), "--version"])
    if snapper_version != "spritefusion-pixel-snapper 1.1.0-beta.1":
        raise SystemExit(f"Unexpected Pixel Snapper version: {snapper_version}")

    records: list[dict[str, object]] = []
    render_js = (
        "const sharp=require('sharp');"
        "sharp(process.argv[1]).resize({width:1152,height:1152,fit:'fill',kernel:'lanczos3'})"
        ".png().toFile(process.argv[2]).then(()=>{}).catch(e=>{console.error(e);process.exit(1)})"
    )

    def build_one(master_rel: str, dest_rel: str, pen_id: str, palette: bool) -> None:
        master = source / master_rel
        if not master.is_file():
            raise FileNotFoundError(master)
        dest = output / dest_rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="realmz-modern-command-") as temp:
            raster = Path(temp) / "render-1152.png"
            run([str(node), "-e", render_js, str(master), str(raster)], env=env)
            command = [str(snapper), str(raster), str(dest), *SNAP_ARGS]
            if palette:
                command.extend(["--palette", ",".join(TORCH_PALETTE)])
            run(command)
        records.append({
            "path": dest_rel.replace("\\", "/"),
            "source": ("source/" + master_rel).replace("\\", "/"),
            "pen_frame_id": pen_id,
            "source_sha256": sha256(master),
            "sha256": sha256(dest),
            "dimensions_px": [32, 32],
        })

    for name, (pen_id, palette) in STATIC_MASTERS.items():
        build_one(f"{name}.svg", f"{name}.png", pen_id, palette)

    for index in range(1, 9):
        frame = f"torch-flame-{index:02d}"
        build_one(
            f"torch-animation/{frame}.svg",
            f"torch-animation/{frame}.png",
            f"r6XHlY/keyframe-{index:02d}",
            True,
        )

    keyframes = source / "torch-keyframes.json"
    manifest = {
        "schema_version": 1,
        "asset_family": "Realmz Rebuilt modern command icons",
        "production_assets": "Reviewed 32px PNGs only; external 44px and 48px studies are not included.",
        "provenance": {
            "provider": "Pen",
            "classic_assets_preserved": True,
            "classic_source_replacement": False,
            "masters": [
                {"path": f"source/{name}.svg", "pen_frame_id": pen_id, "sha256": sha256(source / f"{name}.svg")}
                for name, (pen_id, _) in STATIC_MASTERS.items()
            ] + [
                {"path": f"source/torch-animation/torch-flame-{i:02d}.svg", "pen_frame_id": f"r6XHlY/keyframe-{i:02d}", "sha256": sha256(source / f"torch-animation/torch-flame-{i:02d}.svg")}
                for i in range(1, 9)
            ] + [
                {"path": "source/torch-keyframes.json", "sha256": sha256(keyframes)},
            ],
            "unlit_torch_derivation": "Same r6XHlY silhouette, clipped below y=118; retain source child paths 12 onward for the unchanged shaft and wrap, omit flame paths 1 through 11.",
        },
        "build": {
            "provider": "Pixel Snapper",
            "pixel_snapper_version": snapper_version,
            "renderer": "sharp",
            "renderer_versions": sharp_versions,
            "svg_render_px": [1152, 1152],
            "svg_kernel": "lanczos3",
            "pixelization": "pixelize",
            "target_px": [32, 32],
            "sampling": "average",
            "dither": "none",
            "hard_alpha_cutoff": 128,
            "max_colors": 16,
            "torch_palette_rgb_hex": TORCH_PALETTE,
            "torch_palette_sha256": hashlib.sha256(("\n".join(TORCH_PALETTE) + "\n").encode("ascii")).hexdigest(),
        },
        "outputs": records,
    }
    (output / "modern-command-assets.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print(f"Built {len(records)} 32px PNG assets and modern-command-assets.json in {output}")


if __name__ == "__main__":
    main()
