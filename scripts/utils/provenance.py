#!/usr/bin/env python3
"""Record and verify LumiROM firmware cache and build provenance."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as stream:
        data = json.load(stream)
    if not isinstance(data, dict):
        raise ValueError(f"Expected a JSON object in {path}")
    return data


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    temporary.replace(path)


def image_hashes(image_dir: Path, names: list[str]) -> dict[str, str]:
    result = {}
    for name in sorted({name.strip() for name in names if name.strip()}):
        image = image_dir / f"{name}.img"
        if not image.is_file():
            raise FileNotFoundError(f"Required image is missing: {image}")
        result[image.name] = sha256_file(image)
    if not result:
        raise ValueError("At least one partition image is required")
    return result


def record_cache(args: argparse.Namespace) -> None:
    data = {
        "schema_version": 1,
        "kind": args.kind,
        "device": args.device,
        "csc": args.csc or "",
        "firmware_version": args.firmware_version or "unknown",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "images_sha256": image_hashes(args.image_dir, args.partitions.split(",")),
    }
    write_json(args.manifest, data)


def verify_cache(args: argparse.Namespace) -> None:
    data = read_json(args.manifest)
    expected = {
        "schema_version": 1,
        "kind": args.kind,
        "device": args.device,
        "csc": args.csc or "",
    }
    for field, value in expected.items():
        if data.get(field) != value:
            raise ValueError(f"Cache {field} mismatch in {args.manifest}")
    if args.firmware_version and data.get("firmware_version") != args.firmware_version:
        raise ValueError(f"Cache firmware version mismatch in {args.manifest}")

    hashes = image_hashes(args.image_dir, args.partitions.split(","))
    if data.get("images_sha256") != hashes:
        raise ValueError(f"Cached image hashes do not match {args.manifest}")


def create_provenance(args: argparse.Namespace) -> None:
    source_images = {
        image.name: sha256_file(image)
        for image in sorted(args.input_image_dir.glob("*.img"))
        if image.is_file()
    }
    output_images = {
        image.name: sha256_file(image)
        for image in sorted(args.output_image_dir.glob("*.img"))
        if image.is_file()
    }
    caches = {}
    for name, manifest in (("base", args.base_cache), ("vendor", args.vendor_cache)):
        if manifest.is_file():
            caches[name] = read_json(manifest)

    firmware_version = args.firmware_version
    if not firmware_version and "base" in caches:
        firmware_version = str(caches["base"].get("firmware_version", ""))

    write_json(args.output, {
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source_commit": args.source_commit or "unknown",
        "rom_version": args.rom_version,
        "stock_device": args.stock_device,
        "base_device": args.base_device,
        "csc": args.csc,
        "firmware_version": firmware_version or "unknown",
        "cache_manifests": caches,
        "source_images_sha256": source_images,
        "output_images_sha256": output_images,
    })


def prefer_incremental(full_zip: Path, incremental_zip: Path, min_savings: float) -> bool:
    if not 0 <= min_savings < 1:
        raise ValueError("min_savings must be a fraction from 0 up to (but not including) 1")
    if not full_zip.is_file() or not incremental_zip.is_file():
        return False
    full_size = full_zip.stat().st_size
    return full_size > 0 and incremental_zip.stat().st_size <= full_size * (1 - min_savings)


def add_cache_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--kind", choices=("base", "vendor"), required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--csc", default="")
    parser.add_argument("--image-dir", type=Path, required=True)
    parser.add_argument("--partitions", required=True)
    parser.add_argument("--manifest", type=Path, required=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    record = subparsers.add_parser("record-cache", help="Hash images and write a cache manifest")
    add_cache_arguments(record)
    record.add_argument("--firmware-version", default="")

    verify = subparsers.add_parser("verify-cache", help="Check cache identity and image hashes")
    add_cache_arguments(verify)
    verify.add_argument("--firmware-version", default="")

    version = subparsers.add_parser("cache-version", help="Print a cached firmware version")
    version.add_argument("--manifest", type=Path, required=True)

    provenance = subparsers.add_parser("create", help="Write build provenance JSON")
    provenance.add_argument("--output", type=Path, required=True)
    provenance.add_argument("--input-image-dir", type=Path, required=True)
    provenance.add_argument("--output-image-dir", type=Path, required=True)
    provenance.add_argument("--base-cache", type=Path, required=True)
    provenance.add_argument("--vendor-cache", type=Path, required=True)
    provenance.add_argument("--stock-device", required=True)
    provenance.add_argument("--base-device", required=True)
    provenance.add_argument("--csc", required=True)
    provenance.add_argument("--firmware-version", default="")
    provenance.add_argument("--rom-version", required=True)
    provenance.add_argument("--source-commit", default="")

    delta = subparsers.add_parser("prefer-incremental", help="Check whether a delta meets the size savings threshold")
    delta.add_argument("--full", type=Path, required=True)
    delta.add_argument("--incremental", type=Path, required=True)
    delta.add_argument("--min-savings", type=float, default=0.20)

    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "record-cache":
            record_cache(args)
        elif args.command == "verify-cache":
            verify_cache(args)
        elif args.command == "cache-version":
            print(read_json(args.manifest).get("firmware_version", "unknown"))
        elif args.command == "prefer-incremental":
            return 0 if prefer_incremental(args.full, args.incremental, args.min_savings) else 1
        else:
            create_provenance(args)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"provenance: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
