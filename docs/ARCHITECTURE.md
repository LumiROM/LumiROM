# LumiROM architecture

LumiROM takes Samsung's Galaxy A34 (SM-A346B) firmware as the base and turns it
into a flashable One UI 9 ROM for five MediaTek devices:

| Model | Codename | Notes |
|---|---|---|
| SM-A325F | a32 | |
| SM-A325M | a32m | |
| SM-M325F | m32 | |
| SM-A225F | a22 | |
| SM-E225F | f22 | |

Everything else (system, product, odm, system_ext) comes from the A34 base; only
the vendor image and the boot image are per device.

## Pipeline

```
                 ┌─────────────────────────────┐
 Samsung  ──────▶│ FAC zip (8.3 GB)            │
 (samloader)     └──────────────┬──────────────┘
                                │ 7z → tar → lz4
                                ▼
                 ┌─────────────────────────────┐
                 │ super.img.lz4 → super.img   │
                 └──────────────┬──────────────┘
                                │ simg2img + lpunpack
                                ▼
                 ┌─────────────────────────────┐
 FW bucket  ◀───▶│ IMGs/*.img (base images)    │  ← shared by every device
 (HF, public)    │ vendor.img is dropped here  │
                 └──────────────┬──────────────┘
                                │ per-device vendor download + extraction
                                ▼
                 ┌─────────────────────────────┐
                 │ FIRMWARE/ (partition trees) │
                 └──────────────┬──────────────┘
                                │ rom_* / mods_* / apps_* / knox_* features
                                ▼
                 ┌─────────────────────────────┐
                 │ OUT/*.img (erofs)           │  build_fs_image.sh
                 └──────────────┬──────────────┘
                                │ img2sdat + brotli
                                ▼
   template/ ───▶ │ makerom/ + updater-script   │ ──▶ ROM/LumiROM_*.zip
   (placeholders) └──────────────┬──────────────┘      (signed with signapk)
                                  │
                                  ├─▶ TARGET_FILES/…zip  (base for incremental OTAs)
                                  ├─▶ LumiROM_…-INCREMENTAL_from_X.zip
                                  └─▶ OTA manifests ──▶ LumiROM/updater
```

## Entry points

| Entry point | What it is |
|---|---|
| `build_local.sh` | CLI build. Loads `.env`, validates, runs the whole pipeline in one process. |
| `.github/workflows/build-rom.yml` | The reusable pipeline (all 40 steps), called by both entry points. |
| `.github/workflows/OneUi9.yml` | "LumiROM Tools": one device chosen by the user (the documented path for forks). |
| `.github/workflows/OneUi9-Matrix.yml` | All five devices at once (maintainer). Both callers only forward inputs. |
| `.github/workflows/firmware-mirror.yml` | Weekly check that keeps the FW bucket current. |
| `scripts/tui/` | Textual UI: form → argv → embedded terminal, over the same CLI. |

The workflows are deliberately dumb: each step calls
`bash scripts/ci/steps.sh <name>`, which maps the name to one script under
`scripts/ci/`. That table is the single ordered list of pipeline steps;
`build_local.sh` walks the same names in-process (threading logging through
`run`/`die`), and `scripts/dev/check_pipeline_steps.py` fails the lint when the
workflow or the local list drift from it. The step list itself lives once in
`build-rom.yml` (a `workflow_call` with a device JSON).

The TUI is a third entry point but not a third implementation: `state.py` turns
the form into the same argv `build_local.sh` accepts, reads the device list from
`LumiROM/Devices/` and the base firmware from `LumiROM/Devices/base.conf`, and
the CLI validates again before building, so the shell stays the authority.

## Directory layout

```
build_local.sh              local orchestration
scripts/ci/                 pipeline steps (steps.sh is the ordered list) and their scripts
scripts/firmware/           Samsung download, extraction, image building, FW bucket mirror
scripts/features/           LumiROM (rom/*.sh), Mods, HotspotFix, Galaxy AI, LumiFota, Knox, AppPatches
scripts/package/            updater-script rendering, zip creation, signing, OTA manifests
scripts/utils/              config (shared defaults), logging, install_packages, mod_utils, keys, validation
scripts/build_fs_image.sh   erofs/ext4 image builder (sorted fs_config/file_contexts)
bin/                        vendored tools: apktool, lpunpack, erofs-utils, img2sdat, avb, MergeOTA
LumiROM/Devices/<model>/    per-device config + boot.img
LumiROM/Mods/               files and patches applied by mods_add
LumiROM/vndks/              VNDK sets used by rom_fix_vndk
scripts/patches/            framework.jar / SecSettings patches
template/                   recovery template: update-binary and updater-script (@PLACEHOLDER@)
```

## Concepts

**Base vs target device.** `TARGET_DEVICE` (SM-A346B) is the firmware source;
`STOCK_DEVICE` is the phone being built. `fw_get_base_device` resolves it from
`LumiROM/Devices/base.conf` once it has checked that the device has a config
directory, and the TUI reads the same file.

**Image cache.** `IMGs/*.img` are the extracted base images. When all of them
exist, the firmware download and extraction are skipped. This is what
`cache_manager.sh` inspects and clears.

**FW bucket.** Because every device shares the same base, the images are
published once in a public Hugging Face bucket (`FW/<model>/<version>/images.zip`
plus `latest.txt` with version, sizes and sha256). `fw_bucket.sh pull` restores
them, and falls back to Samsung when the bucket is cold or unreachable. The
bucket is `LuminousJD418/FW` and reads need no credentials, so forks build from
it without configuring anything; only its owner can publish to it. The weekly
mirror keeps it current, and only one version is kept.

**Updater script.** `template/.../updater-script` is data with `@PLACEHOLDER@`
tokens and `#@IF KEY` blocks. `render_updater_script` (in
`scripts/package/updater_script.sh`) fills it and fails if a value is missing;
nothing rewrites it with `sed` afterwards.

**Build metadata.** `build_info.txt` inside every package records the codename,
version, fingerprint, `base_firmware_version` (the A34 release the images came
from, when the FW bucket was used) and `kernel_version`, which is read from the
device's prebuilt `boot.img` by `scripts/utils/kernel_version.py`.

**Target files and incremental OTAs.** `pkg_create_target_files` stores the
images plus their block maps. `ota_build` diffs a previous target-files zip
against the current images and emits an incremental package whose updater-script
verifies the touched ranges before patching.

**OTA manifests.** `ota_generate_manifest` produces `<codename>.json` (full
releases, with history) and `ota_generate_incremental_manifest` produces
`<codename>_ota.json`. `scripts/ci/manifests.sh publish` copies them into
`LumiROM/updater`.

## Conventions

**Function names** are `<area>_<verb>_<noun>`, with the area matching the module
(`fw_` firmware, `rom_` LumiROM features, `knox_`, `hotspot_`, `apps_`, `mods_`,
`ai_`, `fota_`, `pkg_` packaging, `ota_` OTA, `deps_` third-party packages,
`mod_` mod helpers, `key_` platform keys, `fs_` image builder). The prefix exists
so a module function can never shadow an orchestration helper.

**LumiROM features.** `scripts/features/LumiROM.sh` is only a facade: it sources
`scripts/features/rom/{encryption,fstab,props,debloat,framework,display,misc}.sh`
and keeps the legacy entry point working. Add a feature to the module that owns
its topic.

**Modules.** `build_local.sh` loads every library in `load_modules()` (after the
paths exist, before the first step), so a step never pulls a module in halfway
through a build. `bash_colors`, `logging`, `platform_key` and `AppPatches` carry
include guards, so sourcing them again is a no-op; `bash_colors.sh` used to be
loaded about fifteen times per local build.

**Errors.** `build_local.sh` runs `set -uo pipefail` and wraps every step in
`run` (aborts on failure, reading `PIPESTATUS`), `par`/`wait_jobs` for parallel
work, and `try` for optional steps. `scripts/ci/*.sh` use `set -eo pipefail`, the
same settings GitHub applies to `run:` steps. Libraries return non-zero and let
the caller decide.

**Idempotence.** Every stage that can be skipped checks for its output first
(firmware cache, bucket pull, existing target files).

## Recipes

*Add a device*: create `LumiROM/Devices/<model>/config` and `boot.img`, add the
model to `fw_get_base_device` (FW.sh), to the codename maps in
`pkg_render_updater_script`/`pkg_create_flashable_zip` and to
`ota_codename`/`ota_display_name`, upload its vendor image, and add it to the
matrix.

*Change the recovery UI text*: edit the template with a placeholder, never with a
`sed` afterwards.

*Add a mod*: drop it in `LumiROM/Mods/` and register it in `mods_add`.

*Bump the version*: set the `LUMIROM_VERSION` repository variable in CI, or
`LUMIROM_VERSION` in `.env` locally, and add the changelog entry.

## Known limitations

* `set -e` is not enabled in `build_local.sh` (documented in the file): steps go
  through `run`, and some helpers use non-zero returns for control flow.
* The incremental OTA flashes `boot.img` only when it differs from the previous
  target files.
