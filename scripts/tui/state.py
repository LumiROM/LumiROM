from __future__ import annotations

import json
import re
import shlex
import subprocess
from dataclasses import asdict, dataclass, fields
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEVICES_DIR = REPO_ROOT / "LumiROM" / "Devices"
STATE_FILE = Path(__file__).resolve().parent / ".tui_state.json"

BASE_DEVICE_MAP = {
    "SM-A325F": "SM-A346B",
    "SM-A325M": "SM-A346B",
    "SM-M325F": "SM-A346B",
    "SM-A225F": "SM-A245F",
    "SM-A225M": "SM-A245F",
    "SM-E225F": "SM-A245F",
    "SM-M225F": "SM-A245F",
    "SM-A226B": "SM-A245F",
}

BASE_DEVICE_IMEI = {
    "SM-A346B": "353117555323497",
    "SM-A245F": "358212589089183",
}

CSC_RE = re.compile(r"^[A-Za-z]{3}$")
IMEI_RE = re.compile(r"^[0-9]{15}$")


def list_devices() -> list[str]:
    if not DEVICES_DIR.is_dir():
        return []
    return sorted(p.name for p in DEVICES_DIR.iterdir() if p.is_dir())


def base_device_for(stock: str) -> str | None:
    return BASE_DEVICE_MAP.get(stock)


def example_imei_for(stock: str) -> str | None:
    base = base_device_for(stock)
    if base is None:
        return None
    return BASE_DEVICE_IMEI.get(base)


def default_maintainer() -> str:
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
    use_ai: bool = True
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
        if not self.use_ai:
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
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if num < 1024 or unit == "TB":
            return f"{num:.0f} {unit}" if unit == "B" else f"{num:.1f} {unit}"
        num /= 1024
    return f"{num:.1f} TB"


def find_outputs(started: float = 0.0, limit: int = 20) -> list[Path]:
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
