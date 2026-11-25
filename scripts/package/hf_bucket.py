#!/usr/bin/env python3
"""Inspect and prune files in a Hugging Face bucket.

Used by scripts/firmware/fw_bucket.sh: the firmware mirror publishes one
versioned directory per base firmware and deletes the previous one.

Subcommands:
  ensure                 Create the bucket as public if it does not exist.
  list <prefix>          Print the path of every file under <prefix>.
  delete <path> [...]    Delete the given files from the bucket.
"""

import argparse
import os
import sys

from huggingface_hub import HfApi


def default_bucket() -> str | None:
    bucket = os.environ.get("FW_BUCKET") or os.environ.get("HF_BUCKET")
    if bucket:
        return bucket
    user = os.environ.get("HF_USER", "")
    return f"{user}/FW" if user else None


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage files in a Hugging Face bucket.")
    parser.add_argument(
        "--bucket",
        default=default_bucket(),
        help="Bucket id (owner/name). Defaults to $FW_BUCKET, $HF_BUCKET or $HF_USER/FW",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("HF_TOKEN"),
        help="Hugging Face access token. Defaults to $HF_TOKEN",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("ensure", help="Create the bucket as public if needed")

    listing = sub.add_parser("list", help="Print every file under a prefix")
    listing.add_argument("prefix", help="Path prefix inside the bucket")

    delete = sub.add_parser("delete", help="Delete files from the bucket")
    delete.add_argument("paths", nargs="+", help="Remote paths to delete")

    return parser


def main() -> int:
    args = build_parser().parse_args()

    if not args.bucket:
        print("ERROR: no bucket given and HF_USER is not set.", file=sys.stderr)
        return 1

    api = HfApi(token=args.token)

    if args.command == "ensure":
        api.create_bucket(args.bucket, exist_ok=True, visibility="public")
        print(f"OK: bucket {args.bucket} exists (public)")
        return 0

    if args.command == "list":
        try:
            entries = api.list_bucket_tree(args.bucket, prefix=args.prefix, recursive=True)
        except Exception as exc:
            print(f"ERROR: cannot list {args.bucket}/{args.prefix}: {exc}", file=sys.stderr)
            return 1
        for entry in entries:
            if getattr(entry, "type", "file") == "folder":
                continue
            print(entry.path)
        return 0

    if args.command == "delete":
        try:
            api.batch_bucket_files(args.bucket, delete=args.paths)
        except Exception as exc:
            print(f"ERROR: delete failed: {exc}", file=sys.stderr)
            return 1
        for path in args.paths:
            print(f"deleted {path}")
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
