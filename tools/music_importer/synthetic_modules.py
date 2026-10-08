"""Build small tracker modules with a generated tone and public format structures.

These fixtures contain no third-party or campaign music. Each uses one short,
looped sine sample and one note to exercise loading and finite rendering.
"""

from __future__ import annotations

import struct
import math


def _signed_sample() -> bytes:
    """Return a short 8-bit looped sine wave generated specifically for tests."""
    return bytes(
        (int(112 * math.sin(2 * math.pi * index / 32)) & 0xFF)
        for index in range(512)
    )


def mod() -> bytes:
    header = bytearray(1084)
    sample = _signed_sample()
    struct.pack_into(">H", header, 42, len(sample) // 2)
    header[45] = 64
    struct.pack_into(">HH", header, 46, 0, len(sample) // 2)
    header[950] = 1  # One order.
    header[952] = 0
    header[1080:1084] = b"M.K."
    pattern = bytearray(64 * 4 * 4)
    # Sample 1, period 428, on channel zero at the first row.
    pattern[:4] = bytes([0x01, 0xAC, 0x10, 0])
    return bytes(header) + bytes(pattern) + sample


def xm() -> bytes:
    sample = _signed_sample()
    header = bytearray(b"Extended Module: ")
    header.extend(bytes(20))
    header.extend(b"\x1a")
    header.extend(b"Realmz fixture".ljust(20, b" "))
    header.extend(struct.pack("<HI", 0x0104, 276))
    header.extend(struct.pack("<8H", 1, 0, 1, 1, 1, 1, 6, 125))
    header.extend(bytes([0]) + bytes(255))
    pattern_events = bytes([0x83, 49, 1]) + bytes(63)
    header.extend(struct.pack("<IBHH", 9, 0, 64, len(pattern_events)))
    header.extend(pattern_events)

    instrument = bytearray(263)
    struct.pack_into("<I", instrument, 0, len(instrument))
    struct.pack_into("<H", instrument, 27, 1)
    struct.pack_into("<I", instrument, 29, 40)
    sample_header = bytearray(40)
    struct.pack_into("<III", sample_header, 0, len(sample), 0, len(sample))
    sample_header[12:18] = bytes([64, 0, 1, 128, 0, 0])  # Volume, forward loop, center pan.
    header.extend(instrument)
    header.extend(sample_header)
    # XM sample data is delta encoded, so derive each byte from the previous
    # signed sample value while preserving the generated waveform.
    previous = 0
    for value in sample:
        signed_value = value if value < 128 else value - 256
        header.append((signed_value - previous) & 0xFF)
        previous = signed_value
    return bytes(header)


def s3m() -> bytes:
    header = bytearray(96)
    sample = bytes((value + 128) & 0xFF for value in _signed_sample())
    header[28:30] = b"\x1a\x10"
    struct.pack_into("<6H", header, 32, 1, 1, 1, 0, 0x1320, 1)
    header[44:48] = b"SCRM"
    header[48:54] = bytes([64, 6, 125, 0x80, 0, 0])
    header[64] = 0
    header[65:96] = bytes([0xFF]) * 31

    # The sample header is at byte 112 and the packed pattern at 192. S3M
    # paragraph pointers address 16-byte boundaries.
    tables = bytes([0]) + struct.pack("<HH", 7, 12)
    padding = bytes(112 - (len(header) + len(tables)))
    sample_header = bytearray(80)
    sample_header[0] = 1  # PCM sample.
    sample_header[13] = 0
    struct.pack_into("<H", sample_header, 14, 17)  # 272-byte data paragraph.
    struct.pack_into("<III", sample_header, 16, len(sample), 0, len(sample))
    sample_header[28] = 64
    sample_header[31] = 1  # Forward loop.
    struct.pack_into("<I", sample_header, 32, 8363)
    sample_header[76:80] = b"SCRS"

    events = bytes([0x20, 0x40, 1, 0]) + bytes(63)
    pattern = struct.pack("<H", len(events)) + events
    pattern_to_sample_padding = bytes(272 - (112 + len(sample_header) + len(pattern)))
    return bytes(header) + tables + padding + bytes(sample_header) + pattern + pattern_to_sample_padding + sample


def it() -> bytes:
    header = bytearray(192)
    sample = _signed_sample()
    header[:4] = b"IMPM"
    struct.pack_into("<4H", header, 32, 1, 0, 1, 1)
    struct.pack_into("<4H", header, 40, 0x0214, 0x0214, 0, 0)
    header[48:54] = bytes([128, 0x80, 6, 125, 128, 0])
    header[64:128] = bytes([32]) * 64
    header[128:192] = bytes([64]) * 64
    orders = bytes([0])
    sample_header_offset = 201
    pattern_offset = sample_header_offset + 80
    sample_data_offset = pattern_offset + 8 + 67
    pointers = struct.pack("<II", sample_header_offset, pattern_offset)
    sample_header = bytearray(80)
    sample_header[:4] = b"IMPS"
    sample_header[17] = 64
    sample_header[18] = 0x09  # Sample data present and forward loop enabled.
    sample_header[19] = 64
    struct.pack_into("<IIIII", sample_header, 48, len(sample), 0, len(sample), 8363, 0)
    struct.pack_into("<II", sample_header, 68, 0, sample_data_offset)
    sample_header[46] = 1  # Signed 8-bit PCM.
    note_event = bytes([0x81, 0x03, 60, 1])
    pattern_data = note_event + bytes(63)
    pattern = struct.pack("<HHI", len(pattern_data), 64, 0) + pattern_data
    sample_data = sample
    return bytes(header) + orders + pointers + bytes(sample_header) + pattern + sample_data


def fixtures() -> dict[str, bytes]:
    return {"mod": mod(), "xm": xm(), "s3m": s3m(), "it": it()}
