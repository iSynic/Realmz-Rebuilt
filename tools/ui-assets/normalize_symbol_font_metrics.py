"""Rewrites a symbol font's vertical metrics so it can sit in a fallback chain.

Godot sizes every line by the tallest font in a fallback chain. Symbol fonts are tall, so an
unmodified one stretches every line of text that could fall back to it. This writes the same
glyphs with a line box no taller than the bundled text faces. Outlines, advances and the
baseline are untouched.

The file is patched in place at the byte level, with no font library, so the output depends
only on the input bytes and the two numbers given.
"""
import argparse
import struct


def _checksum(data: bytes) -> int:
    padded = data + b"\0" * (-len(data) % 4)
    return sum(struct.unpack(">%dI" % (len(padded) // 4), padded)) & 0xFFFFFFFF


def normalize(source: bytes, ascent: int, descent: int) -> bytes:
    font = bytearray(source)
    if font[:4] not in (b"\x00\x01\x00\x00", b"true"):
        raise SystemExit("only TrueType-flavoured sfnt files are supported")
    count = struct.unpack(">H", font[4:6])[0]
    tables = {}
    for index in range(count):
        record = 12 + index * 16
        tag, _, offset, length = struct.unpack(">4sIII", font[record:record + 16])
        tables[tag] = (record, offset, length)
    for tag in (b"hhea", b"OS/2", b"head"):
        if tag not in tables:
            raise SystemExit("font has no %s table" % tag.decode())
    _, hhea, _ = tables[b"hhea"]
    struct.pack_into(">hhh", font, hhea + 4, ascent, -descent, 0)
    _, os2, _ = tables[b"OS/2"]
    struct.pack_into(">hhhHH", font, os2 + 68, ascent, -descent, 0, ascent, descent)
    _, head, _ = tables[b"head"]
    struct.pack_into(">I", font, head + 8, 0)
    for tag in (b"hhea", b"OS/2", b"head"):
        record, offset, length = tables[tag]
        struct.pack_into(">I", font, record + 4, _checksum(bytes(font[offset:offset + length])))
    struct.pack_into(">I", font, head + 8, (0xB1B0AFBA - _checksum(bytes(font))) & 0xFFFFFFFF)
    return bytes(font)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--ascent", type=int, required=True, help="font units above the baseline")
    parser.add_argument("--descent", type=int, required=True, help="font units below the baseline, positive")
    arguments = parser.parse_args()
    with open(arguments.input, "rb") as handle:
        source = handle.read()
    with open(arguments.output, "wb") as handle:
        handle.write(normalize(source, arguments.ascent, arguments.descent))


if __name__ == "__main__":
    main()
