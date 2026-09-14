from __future__ import annotations

import struct
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ICON_ROOT = REPO_ROOT / "src" / "ui" / "shared" / "assets" / "ui" / "application-icon"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def read_png(size: int) -> bytes:
    path = ICON_ROOT / f"realmz-icon-{size}.png"
    data = path.read_bytes()
    if data[:8] != PNG_SIGNATURE:
        raise ValueError(f"{path} is not a PNG")
    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (size, size):
        raise ValueError(f"{path} is {width}x{height}, expected {size}x{size}")
    return data


def build_ico() -> bytes:
    sizes = (16, 32, 48, 64, 128, 256)
    images = [read_png(size) for size in sizes]
    offset = 6 + 16 * len(images)
    entries: list[bytes] = []
    for size, image in zip(sizes, images, strict=True):
        encoded_size = 0 if size == 256 else size
        entries.append(
            struct.pack("<BBBBHHII", encoded_size, encoded_size, 0, 0, 1, 32, len(image), offset)
        )
        offset += len(image)
    return struct.pack("<HHH", 0, 1, len(images)) + b"".join(entries) + b"".join(images)


def build_icns() -> bytes:
    chunks = []
    for chunk_type, size in (
        (b"icp4", 16),
        (b"icp5", 32),
        (b"icp6", 64),
        (b"ic07", 128),
        (b"ic08", 256),
        (b"ic09", 512),
        (b"ic10", 1024),
    ):
        image = read_png(size)
        chunks.append(chunk_type + struct.pack(">I", len(image) + 8) + image)
    body = b"".join(chunks)
    return b"icns" + struct.pack(">I", len(body) + 8) + body


def main() -> None:
    ICON_ROOT.joinpath("realmz-icon.ico").write_bytes(build_ico())
    ICON_ROOT.joinpath("realmz-icon.icns").write_bytes(build_icns())


if __name__ == "__main__":
    main()
