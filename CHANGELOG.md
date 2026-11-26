# Changelog — NLSound (AROMA-Next Edition)

All notable changes in this **AROMA-Next Edition** fork of [Briclyaz/NLSound](https://github.com/Briclyaz/NLSound) are documented here.

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
