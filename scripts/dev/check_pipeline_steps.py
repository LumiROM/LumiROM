#!/usr/bin/env python3
"""Check that the pipeline steps agree everywhere.

`scripts/ci/steps.sh` is the source of truth: it lists the ordered steps and
maps each name to a command. The workflows call one step per job step and
`build_local.sh` walks a subset in-process. This check fails when a name is
unknown, when the workflow uses all steps but in another order, or when the
local order disagrees with the table.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Downloaded by CI before the build, so a local build has nothing to fetch.
LOCAL_SKIP = {"ota-fetch-source"}


def table() -> list[str]:
    result = subprocess.run(
        ["bash", "scripts/ci/steps.sh", "list"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.split()


def yaml_steps() -> list[str]:
    text = (ROOT / ".github/workflows/build-rom.yml").read_text()
    return re.findall(r"steps\.sh ([a-z0-9-]+)", text)


def local_steps() -> list[str]:
    text = (ROOT / "build_local.sh").read_text()
    block = re.search(r"for STEP in \\\n(.*?); do", text, re.S)
    if not block:
        raise SystemExit("build_local.sh: cannot find the run_pipeline step list")
    pipeline = re.findall(r"[a-z0-9-]+", block.group(1))

    # fetch_* runs the firmware steps, then the shared pipeline, then
    # package_output(). rom-img-zip is the mutually exclusive ZIP_IMG path, so
    # it is checked as a name but not for ordering.
    explicit = re.findall(r"run_step ([a-z0-9-]+)", text)
    firmware = [name for name in explicit if name.startswith("firmware-")]
    package = [name for name in explicit if not name.startswith("firmware-") and name != "rom-img-zip"]
    return firmware + pipeline + package


def is_ordered_subset(sequence: list[str], reference: list[str]) -> bool:
    positions = [reference.index(name) for name in sequence if name in reference]
    return positions == sorted(positions)


def main() -> int:
    steps = table()
    workflow = yaml_steps()
    local = local_steps()
    problems = []

    unknown = sorted({name for name in workflow + local if name not in steps})
    if unknown:
        problems.append(f"unknown step(s): {', '.join(unknown)}")

    if sorted(workflow) != sorted(steps):
        missing = sorted(set(steps) - set(workflow))
        extra = sorted(set(workflow) - set(steps))
        problems.append(f"workflow does not use every step (missing: {missing or 'none'}, extra: {extra or 'none'})")
    elif not is_ordered_subset(workflow, steps):
        problems.append("workflow step order does not match scripts/ci/steps.sh")

    if not is_ordered_subset(local, steps):
        problems.append("build_local.sh step order does not match scripts/ci/steps.sh")

    unexpected_local = sorted(set(local) - set(steps) - LOCAL_SKIP)
    if unexpected_local:
        problems.append(f"local build uses unknown step(s): {', '.join(unexpected_local)}")

    if problems:
        for problem in problems:
            print(f"ERROR: {problem}", file=sys.stderr)
        return 1

    print(f"OK: {len(steps)} steps, {len(workflow)} in the workflow, {len(local)} local (skips: {', '.join(sorted(LOCAL_SKIP))})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
