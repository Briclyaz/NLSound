# Changelog — NLSound (AROMA-Next Edition)

All notable changes in this **AROMA-Next Edition** fork of [Briclyaz/NLSound](https://github.com/Briclyaz/NLSound) are documented here.

---

## v4.5-AROMA-RC5 — 2026-11-27

Engine upgrade to **[AROMA-Next-Installer (`ANI`) V26.11-RC5](https://github.com/Miustone/AROMA-Next-Installer)** & **[AROMA-Next-Filemanager (`ANF`)](https://github.com/Miustone/AROMA-Next-Installer)**.

### Upgraded & Changed
- **Upgraded Embedded Engine (`aroma_installer-arm64` & `aroma_installer-arm32`) to `ANI` V26.11-RC5:**
  - Switched default theme to **`AMOLED Modern`** (`theme("amoled");`) — pure `#000000` OLED black surfaces, unified Material 3 rounded cards across the Welcome dashboard, Setup Hub, all 4 configuration pages, install log, and completion screen, **Monochrome White** default highlight, **8 Live Accent Colors**, and **17 redesigned Material 3 You icons** (all 7 classic themes preserved).
  - **1-Tap Stay-Open Live Appearance Bottom Sheet (`3-Dot → Appearance`):** Switch Themes, Accent Colors, Fonts, and Transitions live in-place without closing or losing scroll position.
  - **Slim Punch-Hole-Safe Top Status Bar:** Displays live clock + active A/B slot + battery level above the title bar.
  - **Lossless PNG Screenshots (`Vol-Down + Power`):** Captures ~250 KB lossless PNGs via `libpng 1.6.59` instead of 9 MB BMPs.
  - **Native `is_volkey()` Check in `aroma-config`:** Uses `ANI` RC5's built-in `is_volkey()` Edify function for mode-aware Setup Hub rendering.
  - **Upgraded `ANF` Recovery Toolkit:** Adds 1-tap **Bootloop-Saver** (*Disable ALL / Re-Enable ALL Modules*), **ZIP Inspector & Extractor**, **Quick Reboot Menu**, `/tmp/recovery.log` backup, and Hardware Diagnostics export.
  - **Upgraded `BOOTMODE=1` Volume Key Selector:** Adds step-back navigation (`<- Go Back` + `VOL-` long-press) and `--preset` unattended replay.
  - **Fixed Linux MT Protocol Type-B Touch Scrolling:** Smooth touch scrolling on modern high-Hz OLED panels, mutex-protected touch FIFO queue, automatic CRLF Edify stripping, and expanded `2048`-byte dialog text buffers.
- **Added `XDA_THREAD.txt`:** Ready-to-post XenForo 2 BBCode thread template (excluded from flashable ZIPs via `build.py`).

---

## v4.5-AROMA — 2026-11-26

### Added
- **Full AROMA-Next-Installer V26.11 Touch GUI in Custom Recovery (`BOOTMODE=0`):**
  - Bundled native static `arm64-v8a` and `armeabi-v7a` **AROMA-Next-Installer** binaries with DRM/KMS & `fbdev` backends, Google Sans + 7 SIL OFL fonts, 6 live themes (*Black & White* default), 5 smooth 60–120Hz transitions, and the integrated **AROMA-Next Filemanager & Root Module Manager**.
  - **Live Hardware & Environment Dashboard (`nlsound-probe.sh`):** Automatically detects device model/codename, SoC platform, speaker amplifiers (*Cirrus CS35L41, NXP TFA, TI TAS, Awinic, Maxim, Qualcomm WSA*), primary DAC/codec (*ESS Sabre, AKM, Qualcomm WCD*), root solution (*Magisk / KernelSU / APatch*), and saved `settings.nls` profiles before setup.
  - **Streamlined Setup Hub (`aroma-config`):**
    - **Custom Configuration (Touch Wizard):** All 15 NLSound audio tweaks organized cleanly across **4 touch pages** with Back button support.
    - **Audiophile Recommended (1-Tap):** Instant balanced Hi-Fi configuration (`30` volume steps, `24-bit / 96 kHz`, DRC off, `4 Hz` sub-bass HPF, Vendor Hi-Fi, `build.prop`, Bluetooth HD, Partial Effects cleanup, Hardware Tinymix).
    - **Restore Previous Profile (1-Tap):** Shared `/data/adb/modules/NLSound/settings.nls` compatibility across both Recovery and Root Manager app installs.
    - **AROMA-Next Filemanager & Modules:** Launch directly from the hub or 3-dot menu and return cleanly.
  - **Live Configuration Preview & Real-Time Progress Bar (`nlsound-summary.sh`):** Displays a complete summary before flashing and drives AROMA-Next's animated progress bar with per-phase headers and **Save Logs** support.
- **Zero-Duplication Native Volume Key Selector (`BOOTMODE=1`):**
  - When flashed inside **Magisk**, **KernelSU**, or **APatch** Manager apps (or on recoveries with locked display `EXIT 77`), AROMA-Next's built-in native C Volume Key engine automatically renders the **exact same `aroma-config`** using hardware Volume keys — no duplicate menu code required.
- **Reproducible Packaging Script (`build.py`):** Builds `dist/NLSound-v4.5-AROMA-Next.zip` with verified Unix `0755` executable bits and LF line endings.

### Changed & Removed
- **Removed MMT-Extended (`common/functions.sh`) and Duplicate Menu Files:**
  - Replaced MMT-Extended and the legacy 200-line bash Volume Key Selector (`englishtext.sh`, `russiantext.sh`, `chinesetext.sh`) with a lightweight, pure AROMA-Next `customize.sh` + `aroma-mod-lib.sh` flow.
- **POSIX `sh` / BusyBox `ash` Compatibility (`common/install.sh`):**
  - Removed bash/mksh-only syntax (`[[ =~ ]]`, `< <(...)`, `$'\n'`, `source`) so patching runs reliably across TWRP, OrangeFox, AERA, Magisk, KernelSU, and APatch.
  - Added read-only partition mirror mounting (`$ORIGDIR`) and `build.prop` fallback detection for full Recovery installation support.

### Fixed
- **Polished `BOOTMODE=1` Volume Key Console UX:**
  - Added automatic 48-column word-wrapping and multi-line item descriptions in AROMA-Next's native Volume Key engine so Magisk / KernelSU / APatch consoles never truncate text horizontally.
  - Made the Welcome screen and Setup Mode menu mode-aware via `AROMA_VOLKEY=1`: hides the Recovery-only Filemanager menu item and updates wording cleanly when flashed inside Android root manager apps.
- Preserved `/data/adb/modules/NLSound/settings.nls` across recovery upgrades before module directory reset.
- Prevented ACDB download step from overwriting the global `$ZIPFILE` variable.
- Ensured `mixer_paths*.xml` is always copied into `$MODPATH` before injecting tinymix XML parameters.
- Preserved `#!/system/bin/sh` and `0755` executable permissions on `action.sh`, `service.sh`, `post-fs-data.sh`, and `system/bin/tinymix_ext`.
- Verified live on **Google Pixel 7 Pro (`cheetah`)** in OrangeFox R12.0 Recovery (full Touch GUI + 6 QHD+ screenshots + clean module install).
