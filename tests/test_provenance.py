import json
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

from scripts.utils.provenance import (
    create_provenance,
    prefer_incremental,
    record_cache,
    sha256_file,
    verify_cache,
)


class ProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.images = self.root / "images"
        self.images.mkdir()
        (self.images / "product.img").write_bytes(b"product image")
        (self.images / "system.img").write_bytes(b"system image")
        (self.images / "vendor.img").write_bytes(b"vendor image")

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_cache_manifest_verifies_identity_and_content(self) -> None:
        manifest = self.root / "base-cache.json"
        record_cache(Namespace(
            kind="base",
            device="SM-A245F",
            csc="DBT",
            firmware_version="A245FXXU1",
            image_dir=self.images,
            partitions="product,system",
            manifest=manifest,
        ))

        verify_cache(Namespace(
            kind="base",
            device="SM-A245F",
            csc="DBT",
            image_dir=self.images,
            partitions="product,system",
            manifest=manifest,
            firmware_version="A245FXXU1",
        ))

        (self.images / "system.img").write_bytes(b"modified image")
        with self.assertRaisesRegex(ValueError, "image hashes"):
            verify_cache(Namespace(
                kind="base",
                device="SM-A245F",
                csc="DBT",
                image_dir=self.images,
                partitions="product,system",
                manifest=manifest,
                firmware_version="",
            ))

    def test_provenance_records_source_and_output_image_hashes(self) -> None:
        base_cache = self.root / "base-cache.json"
        vendor_cache = self.root / "vendor-cache.json"
        record_cache(Namespace(
            kind="base", device="SM-A245F", csc="DBT",
            firmware_version="A245FXXU1", image_dir=self.images,
            partitions="product,system", manifest=base_cache,
        ))
        record_cache(Namespace(
            kind="vendor", device="SM-A325F", csc="",
            firmware_version="unknown", image_dir=self.images,
            partitions="vendor", manifest=vendor_cache,
        ))
        output_images = self.root / "output"
        output_images.mkdir()
        output_system = output_images / "system.img"
        output_system.write_bytes(b"built system image")
        provenance_file = self.root / "provenance.json"

        create_provenance(Namespace(
            output=provenance_file,
            input_image_dir=self.images,
            output_image_dir=output_images,
            base_cache=base_cache,
            vendor_cache=vendor_cache,
            stock_device="SM-A325F",
            base_device="SM-A245F",
            csc="DBT",
            firmware_version="",
            rom_version="8.6.5",
            source_commit="abc123",
        ))

        data = json.loads(provenance_file.read_text(encoding="utf-8"))
        self.assertEqual(data["source_commit"], "abc123")
        self.assertEqual(data["firmware_version"], "A245FXXU1")
        self.assertEqual(data["source_images_sha256"]["system.img"], sha256_file(self.images / "system.img"))
        self.assertEqual(data["output_images_sha256"]["system.img"], sha256_file(output_system))

    def test_incremental_threshold_requires_configured_savings(self) -> None:
        full = self.root / "full.zip"
        incremental = self.root / "incremental.zip"
        full.write_bytes(b"f" * 100)
        incremental.write_bytes(b"i" * 80)
        self.assertTrue(prefer_incremental(full, incremental, 0.20))

        incremental.write_bytes(b"i" * 81)
        self.assertFalse(prefer_incremental(full, incremental, 0.20))

        with self.assertRaisesRegex(ValueError, "min_savings"):
            prefer_incremental(full, incremental, 1.0)


if __name__ == "__main__":
    unittest.main()
