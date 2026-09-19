#!/usr/bin/env python3
"""Wifi teardown fix (three modes).

Mode 1 (default): patch decompiled smali
    softap_fix.py <WifiNative.smali>

Neutralises the blocking WifiVendorHal.stopVendorHal() call inside
WifiNative.stopHalAndWificondIfNecessary().

Why: on MediaTek devices ported to a newer base (A34/A24), whenever the
last wifi interface is torn down the framework stops the legacy wifi HAL
synchronously (WifiVendorHal.stopVendorHal -> HalDeviceManager.stopWifi ->
WifiHalHidlImpl.stop -> IWifi.stop) while
android.hardware.wifi@1.0-service-lazy is in the middle of wifi_cleanup.
That HIDL call never returns, so the WifiHandlerThread blocks forever.
Depending on the path this leaves the hotspot tile on "turning off"
(onSoftApInterfaceDestroyed) or wedges wifi entirely so the hotspot can
no longer be started (onClientInterfaceForConnectivityDestroyed /
onClientInterfaceForScanDestroyed). Patching the single stopVendorHal
call covers every path (AP, STA, NAN, P2P) while keeping the wificond
teardown and the rest of stopHalAndWificondIfNecessary intact.

Mode 2: patch the capex digest
    softap_fix.py --digest <apex_manifest.pb> <root_digest>

Writes the dm-verity root digest of the (post-patch) apex payload into the
originalApexDigest field of the capex-level apex_manifest.pb. apexd compares
the decompressed apex's AVB root digest against this value, so it must be the
avbtool root digest (64 hex chars), not a SHA-256 of the original_apex file.
A path to a file is also accepted and hashed, for convenience.

Mode 3: page-align an APEX zip
    softap_fix.py --align <apex> [alignment]

Re-writes the APEX zip so apex_payload.img (and every other stored entry)
starts on a multiple of `alignment` (default 4096). Used as a portable
fallback when the Android SDK's zipalign is not available.
"""

import hashlib
import os
import re
import shutil
import struct
import sys
import tempfile
import zipfile


# ------------------------------------------------------------------
# mode 1: smali edit
# ------------------------------------------------------------------
def patch_smali(path: str) -> int:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    start = end = None
    for i, line in enumerate(lines):
        if start is None:
            if line.startswith(".method") and "stopHalAndWificondIfNecessary" in line:
                start = i
        elif line.startswith(".end method"):
            end = i
            break

    if start is None or end is None:
        print("softap_fix: stopHalAndWificondIfNecessary method not found")
        return 1

    body = lines[start + 1:end]
    invoke = [j for j, line in enumerate(body)
              if "WifiVendorHal;->stopVendorHal()V" in line and "invoke-virtual" in line]
    if not invoke:
        print("softap_fix: stopVendorHal call not present (already patched or newer base)")
        return 0
    if len(invoke) != 1:
        print(f"softap_fix: expected 1 stopVendorHal invoke site, found {len(invoke)}; aborting")
        return 1

    body[invoke[0]] = "    nop\n"

    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.writelines(lines[:start + 1] + body + lines[end:])
    shutil.move(tmp, path)
    print("softap_fix: neutralised stopVendorHal in stopHalAndWificondIfNecessary")
    return 0


# ------------------------------------------------------------------
# mode 2: bump the capex-level apex_manifest originalApexFileDigest
# ------------------------------------------------------------------
# The capex apex_manifest.pb stores the digest nested inside field 12:
#   tag 0x62 (field 12, wiretype 2), varint len, then field 1 sub-bytes
#   (0x0a 0x40 + 64 hex chars).
def patch_apex_manifest_digest(manifest_path: str, digest: str) -> int:
    data = open(manifest_path, "rb").read()

    old = re.search(b"\x0a\x40([0-9a-f]{64})", data)
    if not old:
        old = re.search(b"\x0a\x38([0-9a-f]{56})", data)
    if not old:
        print("softap_fix: originalApexFileDigest not found in apex_manifest.pb")
        return 1

    # digest may be a 64-hex root digest (preferred: avbtool's hashtree root)
    # or a path to a file whose sha256 is used.
    if re.fullmatch(r"[0-9a-f]{64}", digest):
        new_hex = digest.encode()
    else:
        new_hex = hashlib.sha256(open(digest, "rb").read()).hexdigest().encode()

    patched = data.replace(old.group(1), new_hex)
    if patched == data:
        print("softap_fix: apex digest already up to date")
        return 0

    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(manifest_path) or ".")
    with os.fdopen(fd, "wb") as f:
        f.write(patched)
    shutil.move(tmp, manifest_path)
    print("softap_fix: originalApexFileDigest updated")
    return 0


# ------------------------------------------------------------------
# mode 3: page-align the stored entries of an APEX zip
# ------------------------------------------------------------------
# dm-verity needs apex_payload.img to start on a 4096-byte boundary inside
# the (decompressed) APEX. Re-zipping it with plain zip loses that
# alignment and apexd then fails to mount the package with EINVAL. This is
# a portable stand-in for `zipalign 4096`: it re-writes the zip adding a
# padding extra field to every stored file entry so its data offset is a
# multiple of the alignment (directories and deflated entries are left
# alone, matching zipalign).
def align_apex_zip(path: str, align: int = 4096) -> int:
    if align < 4 or (align & (align - 1)) != 0:
        print("softap_fix: alignment must be a power of two >= 4")
        return 1

    with zipfile.ZipFile(path, "r") as src:
        entries = [(zi, src.read(zi.filename)) for zi in src.infolist()]

    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", suffix=".align")
    os.close(fd)
    try:
        with zipfile.ZipFile(tmp, "w") as out:
            for zi, data in entries:
                info = zipfile.ZipInfo(zi.filename, zi.date_time)
                info.compress_type = zi.compress_type
                info.external_attr = zi.external_attr
                info.internal_attr = zi.internal_attr
                info.create_system = zi.create_system
                info.extra = zi.extra
                if zi.compress_type == zipfile.ZIP_STORED and not zi.is_dir():
                    base = out.fp.tell() + 30 + len(zi.filename.encode())
                    pad = (align - (base % align)) % align
                    if pad < 4:
                        pad += align
                    info.extra = struct.pack("<HH", 0xD935, pad - 4) + b"\x00" * (pad - 4)
                out.writestr(info, data)
        shutil.move(tmp, path)
    except BaseException:
        os.path.exists(tmp) and os.remove(tmp)
        raise
    print(f"softap_fix: apex zip aligned to {align}")
    return 0


def main() -> int:
    if len(sys.argv) == 4 and sys.argv[1] == "--digest":
        return patch_apex_manifest_digest(sys.argv[2], sys.argv[3])
    if len(sys.argv) in (3, 4) and sys.argv[1] == "--align":
        align = int(sys.argv[3]) if len(sys.argv) == 4 else 4096
        return align_apex_zip(sys.argv[2], align)
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    return patch_smali(sys.argv[1])


if __name__ == "__main__":
    sys.exit(main())
