#!/usr/bin/env python3
"""Remove MediaCodec entries from an Android media_codecs XML file.

Hiding the software decoder of a codec the SoC cannot decode in hardware makes
players fall back to one they can (AV1 -> VP9/HEVC on MT6786/MT6768).

Usage: media_codecs.py --remove <substring> <file> [...]

The element is cut textually and the result is re-parsed, so comments and the
original formatting survive while malformed output is rejected before writing.
Exit status 1 means the file could not be read, parsed or written.
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

USAGE = "Usage: media_codecs.py --remove <substring> <file> [...]"


def remove_decoders(text: str, needle: str) -> tuple[str, int]:
    """Drop every <MediaCodec> whose name contains ``needle`` (case-insensitive)."""
    below = needle.lower()
    pieces: list[str] = []
    index = 0
    removed = 0

    while True:
        start = text.find("<MediaCodec", index)
        if start == -1:
            pieces.append(text[index:])
            break

        tag_end = text.find(">", start)
        if tag_end == -1:
            raise ValueError("unterminated <MediaCodec tag")

        opening = text[start:tag_end + 1]
        if below not in opening.lower():
            pieces.append(text[index:tag_end + 1])
            index = tag_end + 1
            continue

        if opening.rstrip().endswith("/>"):
            end = tag_end + 1
        else:
            close = text.find("</MediaCodec>", tag_end)
            if close == -1:
                raise ValueError("unterminated <MediaCodec> element")
            end = close + len("</MediaCodec>")

        # Swallow the whitespace that separated the element from its neighbours.
        while end < len(text) and text[end] in " \t\r\n":
            end += 1

        pieces.append(text[index:start])
        index = end
        removed += 1

    return "".join(pieces), removed


def main() -> int:
    if len(sys.argv) < 4 or sys.argv[1] != "--remove":
        print(USAGE, file=sys.stderr)
        return 2

    needle = sys.argv[2]
    status = 0

    for name in sys.argv[3:]:
        path = Path(name)
        try:
            text = path.read_text()
        except OSError as exc:
            print(f"ERROR: cannot read {path}: {exc}", file=sys.stderr)
            status = 1
            continue

        try:
            updated, removed = remove_decoders(text, needle)
            # Reject malformed output instead of writing a broken codec list.
            ET.fromstring(updated)
        except (ValueError, ET.ParseError) as exc:
            print(f"ERROR: {path}: {exc}", file=sys.stderr)
            status = 1
            continue

        if removed == 0:
            print(f"  - no '{needle}' decoder in {path}")
            continue

        try:
            path.write_text(updated)
        except OSError as exc:
            print(f"ERROR: cannot write {path}: {exc}", file=sys.stderr)
            status = 1
            continue

        print(f"  - removed {removed} '{needle}' decoder(s) from {path}")

    return status


if __name__ == "__main__":
    sys.exit(main())
