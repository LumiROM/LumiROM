#!/usr/bin/env python3
"""Print the kernel version embedded in an Android boot image.

The ROM ships a prebuilt boot image per device (LumiROM/Devices/<model>/boot.img),
so its kernel version is the one to publish in build_info.txt and the OTA
manifests. The kernel is compressed inside the image; the version comes from
the "Linux version ..." banner.

Usage: kernel_version.py <boot.img>

Exit status is 1 when the version cannot be determined, so callers can fall
back to leaving the field empty.
"""

import lzma
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path

ANDROID_MAGIC = b"ANDROID!"
BANNER = re.compile(rb"Linux version (\S+)")

# Compression magics seen in the kernel blob.
GZIP = b"\x1f\x8b"
LZ4_LEGACY = b"\x02\x21\x4c\x18"
LZ4_FRAME = b"\x04\x22\x4d\x18"
ZSTD = b"\x28\xb5\x2f\xfd"
XZ = b"\xfd\x37\x7a\x58\x5a\x00"


def kernel_blob(data: bytes) -> bytes:
    """Return the kernel section of a v0-v2 boot image."""
    if data[:8] != ANDROID_MAGIC:
        raise ValueError("not an Android boot image")

    kernel_size = struct.unpack_from("<I", data, 8)[0]
    page_size = struct.unpack_from("<I", data, 0x24)[0]
    header_version = struct.unpack_from("<I", data, 0x28)[0]

    if header_version >= 3:
        # v3/v4 moved the layout (fixed 4096-byte header, optional boot
        # signature). Best effort: 4096, plus the signature page for v4.
        offset = 4096 + (4096 if header_version == 4 else 0)
    else:
        # v0-v2: page-aligned header, kernel immediately after the first page.
        offset = page_size

    if not page_size or offset + kernel_size > len(data):
        raise ValueError("unexpected boot image layout")

    return data[offset:offset + kernel_size]


def decompress(blob: bytes) -> bytes:
    if blob.startswith(GZIP):
        # decompressobj stops at the end of the stream and ignores the padding
        # that follows the kernel.
        return zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(blob)

    if blob.startswith(XZ):
        return lzma.decompress(blob)

    if blob.startswith((LZ4_LEGACY, LZ4_FRAME)):
        return subprocess.run(["lz4", "-d", "-c"], input=blob,
                              capture_output=True, check=True).stdout

    if blob.startswith(ZSTD):
        return subprocess.run(["zstd", "-d", "-c"], input=blob,
                              capture_output=True, check=True).stdout

    # Some images ship the kernel uncompressed.
    return blob


def kernel_version(path: Path) -> str:
    data = path.read_bytes()
    match = BANNER.search(decompress(kernel_blob(data)))
    if not match:
        raise ValueError("no Linux version banner in the kernel")
    return match.group(1).decode("ascii", errors="replace")


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: kernel_version.py <boot.img>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"ERROR: boot image not found: {path}", file=sys.stderr)
        return 1

    try:
        print(kernel_version(path))
    except Exception as exc:  # noqa: BLE001 - report and let the caller fall back
        print(f"ERROR: cannot read the kernel version from {path}: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
