"""Build configuration for the LumiROM Builder TUI.

The TUI is a thin wrapper over ``build_local.sh``: it collects the same options,
turns them into argv (:meth:`BuildConfig.to_args`) and runs the CLI in a PTY.

Device support and the base firmware come from the repository itself
(``LumiROM/Devices/<model>/config`` and ``LumiROM/Devices/base.conf``), so the
shell and the TUI resolve them from the same files. ``validate()`` mirrors
``scripts/utils/validation.sh``; the CLI validates again before doing anything,
so the shell remains the authority.
"""

from __future__ import annotations

import json
import re
import shlex
import subprocess
from dataclasses import asdict, dataclass, fields
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEVICES_DIR = REPO_ROOT / "LumiROM" / "Devices"
BASE_CONF = DEVICES_DIR / "base.conf"
STATE_FILE = Path(__file__).resolve().parent / ".tui_state.json"

CSC_RE = re.compile(r"^[A-Za-z]{3}$")
IMEI_RE = re.compile(r"^[0-9]{15}$")


def read_base_conf() -> dict[str, str]:
    """Parse ``KEY=VALUE`` lines from ``LumiROM/Devices/base.conf``."""
    try:
        lines = BASE_CONF.read_text().splitlines()
    except OSError:
        return {}

    values: dict[str, str] = {}
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()
    return values


def list_devices() -> list[str]:
    """Models with a directory in ``LumiROM/Devices``."""
    if not DEVICES_DIR.is_dir():
        return []
    return sorted(p.name for p in DEVICES_DIR.iterdir() if p.is_dir())


def base_device_for(stock: str) -> str | None:
    """Base firmware for ``stock``, or None when the device has no config."""
    if not (DEVICES_DIR / stock / "config").is_file():
        return None
    return read_base_conf().get("BASE_DEVICE") or None


def example_imei_for(stock: str) -> str | None:
    """Example IMEI of the base device, used to prefill the form."""
    if base_device_for(stock) is None:
        return None
    return read_base_conf().get("BASE_IMEI") or None


def default_maintainer() -> str:
    """``git config user.name`` of the repository, or an empty string."""
    try:
        result = subprocess.run(
            ["git", "config", "user.name"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout.strip()


@dataclass
class BuildConfig:
    stock: str = ""
    csc: str = ""
    imei: str = ""
    maintainer: str = ""
    use_mods: bool = True
    use_ai: bool = False
    bpf_legacy: bool = False
    img_zip: bool = False
    skip_target_files: bool = False
    incremental_from: str = ""

    def to_args(self) -> list[str]:
        args = ["-s", self.stock, "-c", self.csc.upper(), "-i", self.imei]
        if self.maintainer:
            args += ["-m", self.maintainer]
        if not self.use_mods:
            args.append("--no-mods")
        if self.use_ai:
            args.append("--ai")
        else:
            args.append("--no-ai")
        if self.bpf_legacy:
            args.append("--bpf-legacy")
        if self.img_zip:
            args.append("--img-zip")
        if self.skip_target_files:
            args.append("--no-target-files")
        if self.incremental_from:
            args += ["--incremental-from", self.incremental_from]
        return args

    def command(self) -> str:
        return "bash build_local.sh " + " ".join(self.to_args())

    def pty_command(self) -> list[str]:
        args = " ".join(shlex.quote(arg) for arg in self.to_args())
        inner = f"cd {shlex.quote(str(REPO_ROOT))} && exec bash build_local.sh {args}"
        return ["bash", "-c", inner]

    def validate(self) -> list[str]:
        # Mirrors scripts/utils/validation.sh. Keep both in sync; the CLI runs
        # the shell version again, so a mismatch fails there with its message.
        errors: list[str] = []
        if not self.stock:
            errors.append("Stock device is required.")
        elif self.stock not in list_devices():
            errors.append(f"Unsupported stock device: {self.stock}.")
        if not self.csc:
            errors.append("CSC / region is required.")
        elif not CSC_RE.match(self.csc):
            errors.append("CSC must be exactly 3 letters.")
        if not self.imei:
            errors.append("IMEI is required.")
        elif not IMEI_RE.match(self.imei):
            errors.append("IMEI must be exactly 15 digits.")
        if not self.maintainer:
            errors.append("Maintainer is required.")
        return errors


def save_state(cfg: BuildConfig) -> None:
    try:
        STATE_FILE.write_text(json.dumps(asdict(cfg), indent=2))
    except OSError:
        pass


def load_state() -> BuildConfig:
    try:
        data = json.loads(STATE_FILE.read_text())
    except (OSError, ValueError):
        return BuildConfig()
    if not isinstance(data, dict):
        return BuildConfig()
    known = {f.name for f in fields(BuildConfig)}
    return BuildConfig(**{k: v for k, v in data.items() if k in known})


def human_size(num: float) -> str:
    """Format a byte count for the output list."""
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if num < 1024 or unit == "TB":
            return f"{num:.0f} {unit}" if unit == "B" else f"{num:.1f} {unit}"
        num /= 1024
    return f"{num:.1f} TB"


def find_outputs(started: float = 0.0, limit: int = 20) -> list[Path]:
    """ZIPs in ROM/ and TARGET_FILES/ newer than ``started``, newest first."""
    files = list(REPO_ROOT.glob("ROM/*/*.zip")) + list(REPO_ROOT.glob("TARGET_FILES/*.zip"))
    fresh: list[Path] = []
    for path in files:
        if not path.is_file():
            continue
        try:
            if path.stat().st_mtime >= started:
                fresh.append(path)
        except OSError:
            continue
    fresh.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return fresh[:limit]
