# What's changed on LumiROM 9.0.3?

> [!NOTE]
> LumiROM 9.0.3 is a maintenance update over 9.0.2.

## Fixes
- Fixed apps that use `android:useAppZygote` (Chromium-based browsers and some banking apps) freezing the phone for about 30 seconds and soft-rebooting it. The AppZygote subspecies aborted because `reset_for_subspecies()` ran the file-descriptor audit after `register_new()` had skipped the descriptors that liblog reopened. The audit is skipped for the subspecies reset, while `register_new()` keeps its checks and the audit in `Server::new()` is untouched.
- Fixed the FaceService crash loop. The AI cleanup removed the whole `/system/saiv` tree, but FaceService loads `/system/saiv/face/fr/MobileFace.{bin,param}` for face recognition and `/system/saiv/imageCropper/sce_detector_cnn.tflite` for the ICE detector. With those files missing the native interpreters were created as null and `FaceDetectionWorker` died with a SIGSEGV in `libtensorflowlite_c` or `libHpr_RecFace_dl`. The shared SAIV models are kept now; only the 96 MB `textrecognition` OCR set is removed.
- Fixed the JPEG decode path at the kernel level. The A32 boot images now carry the DMA-BUF heaps backport and the MediaTek ION mm heap exported as `/dev/dma_heap/mtk_mm`, so `libhwui` and `libkumihodecoderservice` can allocate from it. The `debug.jpegfull.opt.switch=0` workaround is gone on the A32, so the vendor JPEG optimization is active again.
- Fixed "Hide developer status" crashing with `NoSuchFieldError: mMainSwitch`. One UI 9 removed `SettingsActivity.mMainSwitch`; the fragment now inflates Samsung's app-picker switch header and adds it with `SeslAppPickerView.addHeader()`, like Samsung's own app-picker screens.
- Fixed the reboot menu crashing with `AbstractMethodError`. `PopupMenu.OnMenuItemClickListener.onMenuItemClick()` was declared as `void` instead of returning `boolean`; Reboot, Reboot to Recovery and Reboot to Download work again.
- Fixed the screen turning off while the boot keyguard is still being drawn. The keyguard window asks for a 5 s user-activity timeout during boot; if the keyguard takes longer, the display slept before it was interactive and the power button had to be pressed two or three times. That exact 5 s timeout is now 30 s; the normal 60 s timeout and the `-1` clear are unchanged.
- Removed the "User guide" entry between Software update and About phone.
- The installer now empties the leftover preload folders on `/prism` (`priv-app`, `app`, `preload/SER/hidden_app`, `sipdb/SwiftKey`) and their dalvik-cache entries. It keeps the folders themselves, skips anything that does not exist and works in both the full ROM and incremental OTAs.

## More
- [Repo] `ChromeFix` now ships the patched `libzygote.dylib.so`: `bl audit` at `0x27eb0` branches to the function's `Ok(())` path. The mod README documents the byte-level patch and both hashes.
- [Repo] AI cleanup keeps the shared SAIV models and drops only `system/system/saiv/textrecognition`; the face and imageCropper models add about 9 MB to `system.img`.
- [Repo] Kernel: DMA-BUF heaps framework backport plus the MTK ION mm heap (`CONFIG_DMABUF_HEAPS`, `CONFIG_DMABUF_HEAPS_MTK_MM`).
- [Repo] A32 boot images rebuilt with that kernel; the ODM rules no longer set `debug.jpegfull.opt.switch=0` on the A32, while the M32 keeps the workaround in `local_m32.rc` until its boot image is rebuilt.
- [Repo] Kernel: BPF `get_netns_cookie` is exposed to `sock_ops` programs as well, which One UI 9.5 needs during boot; the A32 boot images were rebuilt with it.
- [Repo] `services.jar` patch that clamps the keyguard window's 5000 ms timeout to 30000 ms in `RootWindowContainer$MyHandler`.
- [Repo] `SecSettings` patch that removes the `top_level_user_manual` preference.
- [Repo] `updater-script` prism cleanup for the full ROM and incremental OTAs, including the matching `*prism*` dalvik-cache entries.

# Download
[Download LumiROM 9.0.3](https://t.me/LumiROMs)
