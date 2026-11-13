# LumiROM Mods

Mods are auto-discovered by `scripts/features/Mods.sh`. A directory is treated
as a mod only when it contains a `module.prop` file. Directories without it
(`Cloudy`, `Galaxy_AI`, `KnoxPatch`, `LumiSettings`, etc.) keep their own
build scripts and are ignored by the auto-loader.

## Layout

Each mod mirrors the root of the partition it changes:

```text
MyMod/
├── module.prop
├── customize.sh          # optional
├── system/...            # files under /system
├── system_ext/...        # files under /system_ext
├── product/...           # files under /product
├── vendor/...            # files under /vendor
└── odm/...               # files under /odm
```

Do not use the old `system/system/...` or `odm/odm/...` layouts for
auto-applied mods. The build script maps `system/` to the extracted
`system/system` root and `odm/` to the extracted `odm` root automatically.
Feature-specific folders handled by other scripts (`Cloudy`, `Galaxy_AI`,
etc.) may still use their legacy layout until they are converted.

## module.prop

```properties
id=lumibomb
name=This is a module
version=1.0
versionCode=1
author=Luminous418
description=Bread with tomatoes
order=40
```

- `order` is optional. Lower values run first; the default is `50`.
- `devices` is optional. Example: `devices=SM-A325F,SM-A325M`. The mod is
  skipped when `STOCK_DEVICE` and `TARGET_DEVICE` do not match.
- `overwrite=false` avoids replacing files that already exist. The default is
  `true`.
- A `disable` file in the mod directory skips the mod.
- `disabled=true` in `module.prop` also skips it.

## customize.sh

Use a `customize.sh` when the mod needs logic instead of a full tree copy.
Put `SKIPUNZIP=1` on its own line to disable the automatic tree copy:

```bash
SKIPUNZIP=1

case "$STOCK_DEVICE" in
    SM-A325F|SM-A325M)
        MOD_COPY_FILE "$MODPATH" system "etc/init/example.rc" "etc/init/example.rc"
        ;;
esac
```

Available helpers:

- `MOD_PARTITION_DIR <partition>`: prints the firmware destination.
- `MOD_COPY_TREE <mod_dir> <partition>`: copies a whole partition tree.
- `MOD_COPY_FILE <mod_dir> <partition> <source> <destination>`: copies one
  file or directory. Paths are relative to the partition root.
- `MOD_PROP_GET <file> <key>`: reads a value from a properties file.

`customize.sh` is sourced, so use `return 0` / `return 1` instead of `exit`.
