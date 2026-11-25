#!/usr/bin/env python3
"""Fail when a script calls a module helper that is never defined.

The shell resolves function names at call time, so a rename that misses a call
site only explodes in the middle of a build (this happened when `MOD_COPY_FILE`
became `mod_copy_file` and a mod payload kept the old name). This check makes
that class of mistake visible in the Lint workflow instead.

Only names carrying a module prefix are checked, which keeps the output free of
noise from environment variables, commands and awk identifiers.
"""

import pathlib
import re
import sys

PREFIXES = (
    "fw_", "rom_", "apps_", "knox_", "hotspot_", "mods_", "ai_", "fota_",
    "pkg_", "ota_", "deps_", "mod_", "key_", "fs_", "validate_", "is_local_",
)

# Tokens that look like a helper but are not: a SELinux context name and a
# jq --arg name. Keep this list short and justified.
ALLOWED = {
    "ota_package_file",  # SELinux context in LumiFota.sh
    "rom_name",          # jq --arg name in generate_ota_manifest.sh
}

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEF_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)", re.M)
CALL_RE = re.compile(r"(?<![\w$])([a-z][a-z0-9_]*)\b(?=[\s(]|$)")


def iter_scripts():
    for path in ROOT.rglob("*.sh"):
        if ".git" in path.parts:
            continue
        # bin/ holds vendored tools with their own helpers.
        if path.relative_to(ROOT).parts[0] == "bin":
            continue
        yield path


def main() -> int:
    scripts = list(iter_scripts())
    defined = set()
    for path in scripts:
        defined.update(DEF_RE.findall(path.read_text(errors="ignore")))

    problems = []
    for path in scripts:
        for number, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for match in CALL_RE.finditer(line):
                name = match.group(1)
                if not name.startswith(PREFIXES):
                    continue
                if name in defined or name in ALLOWED:
                    continue
                problems.append(f"{path.relative_to(ROOT)}:{number}: {name}")

    if problems:
        print("Undefined module helpers:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1

    print(f"OK: {len(defined)} helpers defined, every referenced one exists")
    return 0


if __name__ == "__main__":
    sys.exit(main())
