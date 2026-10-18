"""Store seekable Godot resources directly inside an unsigned Android APK."""
import argparse
from pathlib import Path
import zipfile


def prepare(source: Path, destination: Path) -> None:
    if destination.exists():
        raise FileExistsError(destination)
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination, "w") as output:
        for entry in original.infolist():
            # Re-sign after zipalign; retain unrelated META-INF dependency metadata.
            if entry.filename.upper().startswith("META-INF/") and entry.filename.upper().endswith((".SF", ".RSA", ".DSA", ".EC", "MANIFEST.MF")):
                continue
            data = original.read(entry.filename)
            # Android compressed-asset seeks inflate from the beginning again.
            # Godot binary resources and nested package ZIPs require random access.
            if entry.filename.startswith("assets/"):
                entry.compress_type = zipfile.ZIP_STORED
            output.writestr(entry, data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    prepare(arguments.source, arguments.destination)
