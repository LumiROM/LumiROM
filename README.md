<p align="center">
  <img src="LumiROM/logo/LumiROM.png" alt="LumiROM Logo">
</p>

<p align="center">
  <a href="https://github.com/LumiROM/LumiROM/actions/workflows/OneUi8-5.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/LumiROM/LumiROM/OneUi8-5.yml?branch=OneUI8.5&label=Specific%20Device&logo=github" alt="Specific Device Workflow">
  </a>
  <a href="https://github.com/LumiROM/LumiROM/actions/workflows/OneUi8-5-Matrix.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/LumiROM/LumiROM/OneUi8-5-Matrix.yml?branch=OneUI8.5&label=All%20Devices&logo=github" alt="All Devices Workflow">
  </a>
  <a href="https://github.com/LumiROM/LumiROM/stargazers">
    <img src="https://img.shields.io/github/stars/LumiROM/LumiROM?style=flat&logo=github&label=Stars" alt="Stars">
  </a>
  <a href="https://github.com/LumiROM/LumiROM/network/members">
    <img src="https://img.shields.io/github/forks/LumiROM/LumiROM?style=flat&logo=github&label=Forks" alt="Forks">
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/github/license/LumiROM/LumiROM?style=flat&label=License" alt="License">
  </a>
</p>

LumiROM is a custom ROM created to provide a totally new experience to low-end MediaTek devices.
It focuses on stability while upgrading the Android version, so you can test new One UI releases and enjoy new features such as Galaxy AI ✨

## Quick Start
- Just want the ROM? Download the latest release from my [Telegram channel](https://t.me/LumiROMs) and head over to [Installing the ROM](#installing-the-rom).
- Want to build it yourself? Pick one of the methods in [How to Use](#how-to-use).

## What does it do?

It downloads the firmware from Samsung servers using [samloader](https://github.com/ananjaser1211/samloader), extracts the partition images and then applies all the features implemented in the repository - Galaxy AI, heavy debloat, Knox patches, performance tweaks and QoL improvements - so the device can be used again with a fresh and modern experience.

The whole process can run either on **GitHub Actions** or **locally** on your machine (requires Ubuntu/Debian distro or WSL) - either with the CLI script or with the **LumiROM Builder** terminal UI.

## Changelogs
Check the [changelogs folder](https://github.com/LumiROM/LumiROM/blob/OneUI8.5/changelogs/README.md) to learn more about each release and useful information.

## Supported Devices

| Device | Model | Fingerprint | Base |
| :--- | :--- | :--- | :--- |
| Samsung Galaxy A22 | SM-A225F | Side-FP | SM-A245F (A24) |
| Samsung Galaxy A32 | SM-A325F | FOD | SM-A346B (A34) |
| Samsung Galaxy A32 | SM-A325M | FOD | SM-A346B (A34) |
| Samsung Galaxy F22 | SM-E225F | Side-FP | SM-A245F (A24) |
| Samsung Galaxy M32 | SM-M325F | FOD | SM-A346B (A34) |

Where:
- **Fingerprint**: **FOD** means fingerprint under display, **Side-FP** means side-mounted fingerprint (power button).
- **Base**: the newer Samsung device whose firmware LumiROM downloads and uses to build the port for your phone, so it can run a modern One UI build on older hardware.

## Features

### System Optimization
- Heavy debloated system (150+ bloatware apps removed).
- Deodexed ROM for cleaner and smaller partitions.
- Improved performance and smoother UI experience.
- Optimized background processes.
- Better battery efficiency.
- Enhanced CPU responsiveness and processing.
- HighEnd launcher animations.
- EROFS filesystem - compressed, read-only, saves storage space.
- Disabled file-based encryption (FBE) and full-disk encryption (FDE).
- VNDK and SELinux fixes applied per-device.
- Init tweaks for extra performance.
- VoLTE fix.
- Custom wallpapers included.

### Galaxy AI ✨
- **Call assist** - change the caller's voice and make real-time translated calls.
- **Writing assist** - compose and translate text, summarize long texts and more.
- **Note assist** - automatic text organization and summarization.
- **Transcript assist** - AI-powered voice transcriptions.
- **Browsing assist** - summarized web browsing.
- **Photo assist** - AI photo editing and object removal.
- **Weather wallpaper** - wallpapers that change based on time and weather conditions.
- **Now brief** - smart notification summaries.
- **Now nudge** - intelligent reminders and prompts.
- **Health assist** - AI-powered health assistance.

### Enhanced Functionality
- Screenshot anywhere (enabled globally).
- More floating features enabled.
- Screen recorder support.
- Bluetooth recording support.
- Built-in [Cloudy](https://github.com/Luminous418/cloudy) app - download and install new ROM versions directly from the phone, even from a ZIP stored on the sdcard (available since 8.6.4).

### Knox Patches (built-in, no root needed)
Knox functionality is patched directly via smali modifications - no modules or root required:
- **Knox Guard** - disabled to prevent carrier locking.
- **Flag Secure** - bypassed to allow screenshots everywhere.
- **Secure Folder** - patched to work without Knox integrity checks.
- **Private Share** - patched for integrity verification bypass.
- **Signature Verification** - minimum scheme lowered for sideloading.
- **SSRM** - patched to match stock device policies.
- **ICCC** - removed to prevent soft-bootloops.
- **KnoxGuard app** - removed from system.

### Supported apps with Knox Patches
-  [Auto Blocker](https://www.samsung.com/uk/support/mobile-devices/protect-your-galaxy-device-with-the-new-auto-blocker-feature/)
-  Samsung Cloud ([FMM](https://www.samsung.com/uk/support/mobile-devices/what-is-find-my-mobile-and-how-can-i-use-it-to-locate-lock-or-wipe-my-device/), [Enhanced data protection](https://www.samsung.com/ae/support/mobile-devices/what-is-the-enhanced-data-protection-function-and-when-can-i-use-it/))
-  [Samsung Flow](https://www.samsung.com/uk/apps/samsung-flow/)
-  [Samsung Health](https://www.samsung.com/uk/apps/samsung-health/)
-  [Samsung Health Monitor](https://www.samsung.com/uk/apps/samsung-health-monitor/)
-  [Secure Folder](https://www.samsungknox.com/en/solutions/personal-apps/secure-folder)
-  [Secure Wi-Fi](https://www.samsung.com/uk/support/mobile-devices/what-is-the-secure-wifi-feature-and-how-do-i-enable-or-use-it/)
-  [SmartThings](https://www.samsung.com/uk/smartthings/app/)

These apps will work without installing any module or having root on the device.

## How to Use

### Method 1: GitHub Actions

#### 1. Fork the Repository
Give a ⭐ star to the repository.
Fork the repository to your GitHub account.

#### 2. Run the Workflow:
Open your forked repository.
- Go to the Actions tab.
- Select LumiROM Tools.
- Click Run workflow.

> [!IMPORTANT]
> The build version is read from a **repository variable** named `LUMIROM_VERSION`, so you never edit the workflow to bump a release. Set it once under Settings → Secrets and variables → Actions → **Variables** tab, with the version as the value (e.g. `1.0.0`).

#### 3. Set Your Device Model:
Fill in the `STOCK_DEVICE` and `TARGET_DEVICE` options:
- `STOCK_DEVICE`: your phone's model. If it is present in the /LumiROM/Devices folder of this repository (see [Supported Devices](#supported-devices)), the tool will work for your device. If not, it will not work.
- `TARGET_DEVICE`, `TARGET_CSC` and `TARGET_IMEI`: refer to your device's **Base** from the Supported Devices table - the base model, a region code and a valid 15-digit IMEI of that base device.

> [!NOTE]
> The `All Devices` workflow (Matrix) is only intended for the developer, as it builds LumiROM for every supported device at once in a single run. If you are building from a fork, always use the `LumiROM Tools` workflow instead.

#### 4. Kernel BPF Version Option (`USE_UI_8_TETHERING_APEX`):
Tick this option only if your kernel BPF version is lower than 5.10 (e.g. 5.4); otherwise leave it disabled.
You can check your kernel version under Settings → About phone → Software information → Kernel version.

> All supported devices in this repository already have BPF 5.10-compatible kernels, so leave it disabled when building for them.

#### 5. Output Filesystem:
The tool builds the images in EROFS format because:
- It is recommended for devices with small partitions.
- It saves storage space.
- Compression allows fitting more content in the image.

> [!NOTE]
> The only downside is that your kernel must support EROFS, but all supported devices already use EROFS kernels, so there is no problem.

#### 6. Upload
Use the `DESTINATION` option to choose where the ROM will be uploaded - Hugging Face or GoFile (**GoFile is the default**, since it doesn't need any account):

- If you choose Hugging Face, the ROM will be auto uploaded to Hugging Face servers using a custom upload mechanism, but you need to create an account and set up two things on your fork before running the workflow:

> [!TIP]
> - Create a Hugging Face account.
> - Go to Settings and then to Access Tokens. Create a new token with write permissions and copy it.
> - Go back to the repository, go to Settings → Secrets and variables → Actions and add the token as a **repository secret** with the name `HF_TOKEN`.
> - On the same page, in the **Variables** tab, add a **repository variable** with the name `HF_USER` and your Hugging Face username as the value.

- If you choose GoFile, it will generate a link once the ROM is uploaded, ready to be downloaded. No need for any account.

#### 7. Images Only (Optional):
Tick the `ZIP_IMG` option if you want the partition images (.img) inside a ZIP instead of a flashable ROM - useful if you prefer flashing the images yourself. Leave it disabled to get the normal flashable ZIP.

### Method 2: Local Build (CLI)

You can also build LumiROM directly on your Linux machine using the local build script. This method includes a **firmware cache system** so you only need to download the firmware once.

#### Requirements:
- A Linux machine with Ubuntu/Debian (or WSL on Windows).
- Around 15 GB of free disk space for the firmware download and the build.

#### 1. Clone the repository:
```bash
git clone https://github.com/LumiROM/LumiROM.git
cd LumiROM
```

> [!IMPORTANT]
> The local build reads `LUMIROM_VERSION` from a `.env` file in the repository root (the same file used for signing keys). Create it if you don't have one, otherwise the build has no version:
> ```bash
> echo 'export LUMIROM_VERSION="1.0.0"' >> .env
> ```

#### 2. Choose your options:
Only the stock model, region and IMEI are required - everything else has a default:

```bash
bash build_local.sh -s SM-A325F -c DBT -i 353117555323497
```

| Option | Meaning |
| :--- | :--- |
| `-s, --stock` | Your phone model - must be one of the supported models (e.g. `SM-A325F`) |
| `-c, --csc` | Region code of the base firmware (e.g. `DBT`) |
| `-i, --imei` | A valid 15-digit IMEI of the base device - you can find examples inside `build_local.sh` |
| `-t, --target` | Base device to port from - auto-derived from your stock model if omitted (see the **Base** column of the Supported Devices table) |
| `-m, --maintainer` | Your name - defaults to your git username |
| `--no-mods` | Exclude mods (Cloudy app, Vulkan fix, VoLTE fix, tweaks, wallpapers) |
| `--no-ai` | Exclude Galaxy AI features |
| `--bpf-legacy` | Enable only if your kernel BPF is lower than 5.10 |
| `--img-zip` | Deliver the partition images (.img) in a ZIP instead of a flashable ROM |
| `-h, --help` | Show all options and the supported devices |

> [!TIP]
> If you omit a required option, the script asks for it interactively, so running `bash build_local.sh` alone also works.

#### 3. Run the build:
Add any extra options you need:
```bash
bash build_local.sh -s SM-A225F -c DBT -i 358212589089183 --no-mods --img-zip
```
<br>
The script will install dependencies, download firmware (if not cached), apply all patches and build the ROM. The output ZIP will be in the `ROM/` folder.

Before building, the script validates all your inputs intensively (models, CSC, IMEI) and detects the One UI version automatically, so you don't need to configure anything else. Builds made locally are tagged as **Unofficial**.

#### 4. Manage firmware cache:
Use the cache manager to check, list or clear your cached firmware images:
```bash
bash scripts/firmware/cache_manager.sh status    # Show cache status
bash scripts/firmware/cache_manager.sh check     # Verify required images
bash scripts/firmware/cache_manager.sh size      # Show cache size
bash scripts/firmware/cache_manager.sh list      # List all images with sizes
bash scripts/firmware/cache_manager.sh clear     # Clear cached images
```

> [!IMPORTANT]
> If you're building locally, the script logs everything it does. If something fails, please report the error to me via GitHub issues or on my [Telegram channel](https://t.me/LumiROMs), attaching the LOGS folder.

> [!NOTE]
> If you don't want to mess with the repo or don't know how to do any of this, I will keep releasing updates of my ROM on my [Telegram channel](https://t.me/LumiROMs).
> Suggestions are welcome too - I'm still learning from this project, so if you find a bug or want to make the code a bit easier to understand, feel free to open a pull request!

### Method 3: Local Build (TUI)

If you prefer a guided interface, **LumiROM Builder** is a terminal UI (TUI) that wraps `build_local.sh`. You fill a form on the right, watch the build run in an embedded terminal on the left, and get the resulting ZIP listed when it finishes.

#### Requirements:
- The same as Method 2 (Ubuntu/Debian or WSL).
- Python 3.10 or newer.

#### 1. Clone the repository and enter it:
```bash
git clone https://github.com/LumiROM/LumiROM.git
cd LumiROM
```

> [!IMPORTANT]
> Like the CLI method, the TUI reads `LUMIROM_VERSION` from a `.env` file in the repository root. Create it if you don't have one:
> ```bash
> echo 'export LUMIROM_VERSION="1.0.0"' >> .env
> ```

#### 2. Install the TUI dependencies:
```bash
python3 -m pip install --break-system-packages -r scripts/tui/requirements.txt
```

#### 3. Launch the TUI:
```bash
python3 -m scripts.tui
```

#### 4. Fill the form and build:
On the right panel, choose your **Stock device**, type the **CSC/region** (3 letters, always uppercased automatically) and the **IMEI** of the base device, then set your **Maintainer** name. You can also toggle mods, Galaxy AI, the BPF-legacy option, image-only ZIP delivery and an incremental build. The exact command is always previewed on the left.

Press **Start Build** and the build runs in the terminal panel on the left. Since it is a real terminal, colors, progress bars and `sudo` prompts all work as usual - type your password there when asked.

#### Controls:
| Control | Action |
| :--- | :--- |
| `Start Build` | Validate the form and start the build |
| `Cancel Build` / `Ctrl+X` | Stop a running build |
| `Ctrl+S` | Save the current form |
| `Ctrl+Q` | Quit |

> [!TIP]
> The form is remembered in `scripts/tui/.tui_state.json` and restored the next time you launch the TUI.

> [!NOTE]
> The TUI runs the exact same steps as the CLI method, so the [firmware cache](#4-manage-firmware-cache) and the output in the `ROM/` folder work identically.

## Installing the ROM

> [!WARNING]
> Flashing a custom ROM will erase all data on your device. Back up everything before continuing. You are doing this at your own risk - I am not responsible for any lost data or damaged devices.

Once you have downloaded or built LumiROM, there are three ways to install it:

### Option 1: Cloudy app (LumiROM 8.6.4+)
Starting from LumiROM 8.6.4, the ROM includes [Cloudy](https://github.com/Luminous418/cloudy), which handles the whole installation process for you:
- Open Cloudy and download the ROM directly from inside the app, **or**
- Tap **Select ROM from internal storage** and pick the ZIP if you already downloaded it.

### Option 2: Recovery
If you don't have the Cloudy app:
1. Download the ROM ZIP.
2. Reboot your phone into recovery mode.
3. Select the ROM ZIP and flash it.

### Option 3: ADB sideload (from PC)
1. Install [ADB](https://developer.android.com/tools/adb) on your PC.
2. Download the ROM ZIP and open a terminal in the folder where it is located.
3. Reboot your phone into recovery mode and select **Apply update from ADB** (sideload mode).
4. From the PC, run:
```bash
adb sideload <rom>.zip
```

## OTA Signing

Every flashable package - both the full ROM and the incremental OTA - must be signed with `signapk -w`. The signature is appended as a ZIP comment (the *footer*) that Cloudy and Android's `RecoverySystem` read before installing. Without it the device rejects the package with:

```text
Package verification failed: no signature in file (no footer)
```

Signing is fully automatic:
- The **full ROM** is signed by `SIGN_OTA_ZIP` (`scripts/package/sign_ota.sh`).
- The **incremental OTA** is built by `scripts/package/build_incremental_ota.sh` and then signed by `SIGN_INCREMENTAL_OTA` **after** its post-processing (the SamsungCamera cleanup re-zips the package, which would otherwise strip an earlier signature).
- Both workflows (`OneUi8-5.yml` and `OneUi8-5-Matrix.yml`) and `build_local.sh` perform this signing using the OTA key from the `OTA_PK8`/`OTA_CERT` secrets (or `~/.lumi/keys/ota.{pk8,x509.pem}` locally). If the key is missing, the build fails on purpose so a broken OTA is never published. This step requires `signapk` (`/usr/share/signapk/signapk.jar`).

### Re-signing already published OTAs

OTAs published before the incremental signing step was added lack the footer and must be re-signed and re-uploaded:

```bash
HF_USER=<hf-user> HF_TOKEN=<token> \
  scripts/package/resign_published_ota.sh [--dry-run] [device ...]
```

It defaults to `a32 a22 m32 f22`. For each device it downloads the incremental from its OTA manifest, re-signs it, regenerates the manifest at `OTA_MANIFESTS/{device}_ota.json`, and (unless `--dry-run`) re-uploads it to the `<HF_USER>/OTAs` bucket. Remember to commit the regenerated manifests to the [cloudy](https://github.com/Luminous418/cloudy) repository (`updater/ota/{device}.json`).

## Licensing
This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.
- **[android-tools](https://github.com/nmeum/android-tools)** - Licensed under Apache License 2.0
- **[apktool](https://github.com/iBotPeaches/Apktool)** - Licensed under Apache License 2.0  
- **[erofs-utils](https://github.com/sekaiacg/erofs-utils)** - Dual licensed (GPL-2.0, Apache-2.0)
- **[platform_build](https://android.googlesource.com/platform/build)** - Licensed under Apache License 2.0
- **[e2fsprogs](https://github.com/tytso/e2fsprogs)** - Licensed under GPL-2.0 / LGPL-2.1
- **[img2sdat](https://github.com/xpirt/img2sdat)** - Licensed under the MIT License
- **[samloader](https://github.com/samloader/samloader)** - Licensed under GPL-3.0
- **[Textual](https://github.com/Textualize/textual)** - Licensed under the MIT License (TUI only)
- **[textual-tty](https://github.com/bitplane/textual-tty)** - WTFPL with one additional clause (TUI only)
- **[UN1CA](https://github.com/salvogiangri/UN1CA)** - Licensed under GPL-3.0 (LumiSettings and KnoxPatch are based on it)
