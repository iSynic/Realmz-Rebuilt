"""Compress the exact reviewed program-restoration receipt for the runtime package."""
import argparse
import hashlib
import platform
import sys
import zlib
from pathlib import Path


SOURCE_RELATIVE = Path("src/storage/packages/bundled_campaigns/program-restoration.json")
OUTPUT_RELATIVE = SOURCE_RELATIVE.with_name(SOURCE_RELATIVE.name + ".zlib")
EXPECTED_SOURCE_BYTES = 18_764_897
EXPECTED_SOURCE_SHA256 = "c8211ba873d25dbebf9a92f7af760952071aa19e6c6cad2e4580a55fc050ef94"
EXPECTED_COMPRESSED_BYTES = 696_217
EXPECTED_COMPRESSED_SHA256 = "3c622bb423d2123f23ea2d3cfde03f6f12caec887f3a43e40f13e870ec070272"
PINNED_GENERATOR_BUILD = (
    "CPython 3.14.7 (tags/v3.14.7:823f032, Aug  5 2026, 10:51:32) "
    "[MSC v.1944 64 bit (AMD64)]; zlib compile=1.3.1.zlib-ng; "
    "runtime=1.3.1.zlib-ng"
)
COMPRESSION_LEVEL = 9


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def validate_source(data):
    if len(data) != EXPECTED_SOURCE_BYTES:
        raise ValueError("source receipt length differs from the pinned original")
    if sha256(data) != EXPECTED_SOURCE_SHA256:
        raise ValueError("source receipt SHA-256 differs from the runtime pin")


def generator_build():
    return (platform.python_implementation() + " " + sys.version +
            "; zlib compile=" + zlib.ZLIB_VERSION +
            "; runtime=" + zlib.ZLIB_RUNTIME_VERSION)


def require_pinned_compressor():
    actual = generator_build()
    if actual != PINNED_GENERATOR_BUILD:
        raise RuntimeError("generation requires pinned build " + repr(PINNED_GENERATOR_BUILD) +
                           "; found " + repr(actual))


def compress_receipt_bytes(source_bytes):
    """Return level-9 zlib bytes after checking the immutable source identity."""
    validate_source(source_bytes)
    return zlib.compress(source_bytes, level=COMPRESSION_LEVEL)


def decompress_receipt_bytes(compressed_bytes):
    """Decode one bounded zlib stream and require the exact reviewed source identity."""
    decoder = zlib.decompressobj()
    source_bytes = decoder.decompress(compressed_bytes, EXPECTED_SOURCE_BYTES + 1)
    if len(source_bytes) > EXPECTED_SOURCE_BYTES:
        raise ValueError("decompressed receipt exceeds the pinned length")
    if decoder.unconsumed_tail:
        raise ValueError("compressed receipt exceeds the bounded output size")
    if not decoder.eof:
        raise ValueError("compressed receipt is truncated")
    if decoder.unused_data:
        raise ValueError("compressed receipt has trailing data or another stream")
    if len(source_bytes) != EXPECTED_SOURCE_BYTES:
        raise ValueError("decompressed receipt length differs from the pinned source")
    if sha256(source_bytes) != EXPECTED_SOURCE_SHA256:
        raise ValueError("decompressed receipt SHA-256 differs from the runtime pin")
    return source_bytes


def verify_files(source_path, output_path, reproduce=False):
    source_bytes = source_path.read_bytes()
    validate_source(source_bytes)
    compressed_bytes = output_path.read_bytes()
    if len(compressed_bytes) != EXPECTED_COMPRESSED_BYTES:
        raise ValueError("compressed receipt length differs from the pinned output")
    if sha256(compressed_bytes) != EXPECTED_COMPRESSED_SHA256:
        raise ValueError("compressed receipt SHA-256 differs from the runtime pin")
    if decompress_receipt_bytes(compressed_bytes) != source_bytes:
        raise ValueError("compressed receipt does not reproduce the exact source bytes")

    if reproduce:
        require_pinned_compressor()
        if compress_receipt_bytes(source_bytes) != compressed_bytes:
            raise ValueError("compressed receipt differs from deterministic level-9 output")
        return "reproduction performed under the pinned generator build"
    return "reproduction not performed (use --reproduce on the pinned generator build)"


def generate(source_path, output_path):
    require_pinned_compressor()
    source_bytes = source_path.read_bytes()
    compressed_bytes = compress_receipt_bytes(source_bytes)
    if len(compressed_bytes) != EXPECTED_COMPRESSED_BYTES:
        raise ValueError("generated compressed receipt length differs from its pin")
    if sha256(compressed_bytes) != EXPECTED_COMPRESSED_SHA256:
        raise ValueError("generated compressed receipt SHA-256 differs from its pin")
    if output_path.resolve() == source_path.resolve():
        raise ValueError("compressed output may not replace the plain JSON source")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(compressed_bytes)
    verify_files(source_path, output_path, reproduce=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="repository root (default: resolved from this script)")
    parser.add_argument("--source", type=Path,
                        help="source receipt override for bounded probes")
    parser.add_argument("--output", type=Path,
                        help="compressed receipt override for bounded probes")
    parser.add_argument("--check", action="store_true",
                        help="verify existing compressed bytes without writing")
    parser.add_argument("--reproduce", action="store_true",
                        help="also recompress and compare under the exact pinned generator build")
    args = parser.parse_args(argv)
    source_path = args.source if args.source is not None else args.root / SOURCE_RELATIVE
    output_path = args.output if args.output is not None else args.root / OUTPUT_RELATIVE
    try:
        if args.check:
            reproduction_status = verify_files(source_path, output_path,
                                               reproduce=args.reproduce)
            print("Verified compressed program receipt; " + reproduction_status + ".")
        else:
            if args.reproduce:
                raise ValueError("--reproduce requires --check; generation always reproduces before success")
            generate(source_path, output_path)
            print("Generated and verified compressed program receipt; reproduction performed under the pinned generator build.")
    except (OSError, RuntimeError, ValueError, zlib.error) as error:
        print("Program receipt compression failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
