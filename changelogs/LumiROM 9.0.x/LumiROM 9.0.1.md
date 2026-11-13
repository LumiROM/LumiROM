# What's changed on LumiROM 9.0.1?

> [!NOTE]
> LumiROM 9.0.1 is a maintenance update over 9.0.0.

## Fixes
- Fixed Chrome tabs staying on the loading screen or dying on Android 17: `zygote_next` asked the kernel for capabilities 38 to 40, which do not exist on the 4.14 kernel. The capability scan now stops at 37 in `libzygote.dylib.so`.
- Fixed blank JPEG photos caused by the vendor's `jpeg_decode_sw_opt` path trying to use a dma-buf heap that does not exist on the 4.14 kernel.
- Restored **BBR** TCP congestion control on the A32 kernel; the ODM init rules select it at boot.
- Fixed the ODM init rules path so they are read from `/odm/etc/init`.

## More
- [Repo] New `ChromeFix` mod with the patched `libzygote.dylib.so` for the 4.14 kernel capability scan.
- [Repo] New `ODMFix` mod with `local_a32.rc` and `local_a22.rc` for the JPEG and BBR fixes.
- [Repo] Mods are auto-discovered from `LumiROM/Mods` via `module.prop`; manual paths were removed from `Mods.sh`.
- [Repo] The `Files` mod now replaces `gsid` and permission XMLs instead of skipping existing files.
- [Repo] A32 kernel rebuilt with `CONFIG_TCP_CONG_BBR` for the A325F/A325M boot images.

# Download
[Download LumiROM 9.0.1](https://t.me/LumiROMs)
