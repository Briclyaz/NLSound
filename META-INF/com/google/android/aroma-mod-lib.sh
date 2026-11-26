#!/sbin/sh
# AROMA-Next Systemless & Optional Pre-RW Modding Library
# Works in Recovery (TWRP/OrangeFox) and Booted Android (Magisk/KernelSU/APatch).
#
# Modes:
#   systemless (default): Generates a Magisk/KernelSU/APatch overlay module under $MODPATH.
#                         Safe on EROFS, shared_blocks ext4, Virtual A/B, and active dm-verity.
#   rw (advanced):        Writes directly to partitions ONLY if already converted to RW
#                         beforehand using RO2RW or SystemRW (requires reboot prior to AROMA).

AROMA_MOD_MODE="systemless"
AROMA_MOD_ROOT=""
AROMA_SYS_SRC=""

# Emit progress bar & @Section updates to AROMA-Next Touch GUI when running in Recovery
aroma_progress() {
  local frac="$1"
  local title="$2"
  if [ "$BOOTMODE" != "true" ] && [ -n "$AROMA_TMP" ] && [ -n "$OUTFD" ] && [ -e "/proc/self/fd/$OUTFD" ]; then
    [ -n "$frac" ] && printf 'set_progress %s\n' "$frac" > "/proc/self/fd/$OUTFD" 2>/dev/null || true
    [ -n "$title" ] && printf 'ui_print @%s\nui_print\n' "$title" > "/proc/self/fd/$OUTFD" 2>/dev/null || true
  fi
}

# Run AROMA-Next's built-in Volume Key Selector automatically in BOOTMODE=1
# (works identically across Magisk App, KernelSU App, and APatch App!)
# Sets and exports AROMA_TMP pointing to the generated *.prop directory.
aroma_run_config_if_needed() {
  if [ "$AROMA_DONE" = "1" ] && [ -d "${AROMA_TMP:-/tmp/aroma}" ]; then
    export AROMA_TMP="${AROMA_TMP:-/tmp/aroma}"
    return 0
  fi

  local work="${TMPDIR:-/dev/tmp}/aroma-vk-bin"
  local prop_dir="${TMPDIR:-/dev/tmp}/aroma"
  local arch bin_path c candidates

  rm -rf "$work" "$prop_dir"
  mkdir -p "$work" "$prop_dir"

  arch="$(uname -m)"
  case "$arch" in
    aarch64|arm64*) candidates="META-INF/com/google/android/bin/aroma_installer-arm64 META-INF/com/google/android/bin/aroma_installer-arm32" ;;
    armv7*|armv8*|arm*) candidates="META-INF/com/google/android/bin/aroma_installer-arm32" ;;
    x86_64|amd64) candidates="META-INF/com/google/android/bin/aroma_installer-x86_64" ;;
    *) candidates="META-INF/com/google/android/bin/aroma_installer-arm64 META-INF/com/google/android/bin/aroma_installer-arm32" ;;
  esac

  bin_path=""
  for c in $candidates; do
    unzip -o "$ZIPFILE" "$c" -d "$work" >/dev/null 2>&1
    if [ -f "$work/$c" ]; then
      bin_path="$work/$c"
      chmod 755 "$bin_path"
      break
    fi
  done

  if [ -z "$bin_path" ] || [ ! -x "$bin_path" ]; then
    ui_print "! AROMA-Next binary unavailable for $arch; continuing with defaults."
    return 1
  fi

  export AROMA_TMP="$prop_dir"

  # Use Magisk OUTFD recovery protocol when available; plain stdout in KernelSU / APatch
  if [ -n "$OUTFD" ] && [ -e "/proc/self/fd/$OUTFD" ] && [ "$KSU" != "true" ] && [ "$APATCH" != "true" ]; then
    "$bin_path" --volkey --config-only 3 "$OUTFD" "$ZIPFILE"
  else
    "$bin_path" --volkey --config-only --plain 3 1 "$ZIPFILE"
  fi
  local rc=$?
  rm -rf "$work" 2>/dev/null || true

  if [ "$rc" -eq 0 ]; then
    export AROMA_DONE=1
    return 0
  fi
  return "$rc"
}

# Normalize a partition-relative path (e.g. "/system/app/Foo" or "product/app/Bar")
# into canonical Magisk-style module subpaths: system/..., system/product/..., system/vendor/...
_aroma_norm_rel() {
  local p="${1#/}"
  case "$p" in
    system/*)     echo "$p" ;;
    vendor/*)     echo "system/$p" ;;
    product/*)    echo "system/$p" ;;
    system_ext/*) echo "system/$p" ;;
    odm/*)        echo "system/$p" ;;
    *)            echo "system/$p" ;;
  esac
}

# Find where read-only system files live in the current environment
_aroma_find_sys_src() {
  if [ -n "$AROMA_SYS_SRC" ]; then
    echo "$AROMA_SYS_SRC"
    return
  fi
  for cand in /system_root /mnt/system /system /; do
    if [ -f "${cand%/}/system/build.prop" ] || [ -d "${cand%/}/system/framework" ]; then
      AROMA_SYS_SRC="${cand%/}"
      echo "$AROMA_SYS_SRC"
      return
    fi
  done
  AROMA_SYS_SRC=""
  echo ""
}

# Resolve target live path for Direct RW mode
_aroma_rw_target_path() {
  local p="${1#/}"
  local root="$(_aroma_find_sys_src)"
  case "$p" in
    system/*)
      if [ -n "$root" ] && [ -d "${root}/system" ]; then
        echo "${root}/${p}"
      else
        echo "/${p}"
      fi
      ;;
    vendor/*|product/*|system_ext/*|odm/*)
      if [ -d "/${p%%/*}" ] && [ -n "$(ls -A "/${p%%/*}" 2>/dev/null)" ]; then
        echo "/${p}"
      elif [ -n "$root" ] && [ -d "${root}/system/${p%%/*}" ]; then
        echo "${root}/system/${p}"
      else
        echo "/${p}"
      fi
      ;;
    *)
      echo "${root}/system/${p}"
      ;;
  esac
}

# Probe whether a mountpoint is genuinely writable (i.e. pre-converted via RO2RW / SystemRW)
# Returns 0 if writable, 1 if read-only / EROFS / unmounted.
aroma_probe_rw() {
  local mp="$1"
  local fstype=""
  if [ -r /proc/mounts ]; then
    fstype="$(awk -v m="$mp" '$2==m {print $3; exit}' /proc/mounts 2>/dev/null)"
  fi

  case "$fstype" in
    erofs|squashfs)
      ui_print "! $mp uses $fstype (read-only filesystem by kernel design)."
      ui_print "! Run RO2RW / SystemRW and reboot first, or use Systemless Mode."
      return 1
      ;;
  esac

  mount -o rw,remount "$mp" 2>/dev/null || true

  local probe="${mp%/}/.aroma_rw_probe_$$"
  if touch "$probe" 2>/dev/null; then
    rm -f "$probe" 2>/dev/null || true
    return 0
  fi

  ui_print "! $mp is NOT writable (shared_blocks ext4 / locked RO / dm-verity)."
  return 1
}

# Initialize modding session:
#   aroma_mod_init <requested_mode: systemless|rw|auto> <modpath> [fallback_to_systemless: 1|0]
aroma_mod_init() {
  local req_mode="${1:-systemless}"
  local modpath="$2"
  local fallback="${3:-1}"

  AROMA_MOD_ROOT="$modpath"
  mkdir -p "$AROMA_MOD_ROOT"

  if [ "$req_mode" = "systemless" ]; then
    AROMA_MOD_MODE="systemless"
    ui_print "- Mode: Systemless Overlay Module ($AROMA_MOD_ROOT)"
    return 0
  fi

  # In booted Android (App mode), direct /system RW is never used
  if [ "$BOOTMODE" = "true" ]; then
    if [ "$req_mode" = "rw" ] && [ "$fallback" != "1" ]; then
      ui_print "! Direct RW mode requires Recovery with RO2RW/SystemRW partitions."
      return 1
    fi
    AROMA_MOD_MODE="systemless"
    ui_print "- Booted Android detected: forcing Systemless Mode."
    return 0
  fi

  # Verify target partition is genuinely RW (pre-converted via RO2RW / SystemRW)
  local sys_mp="/system"
  [ -d /system_root ] && grep -q " /system_root " /proc/mounts 2>/dev/null && sys_mp="/system_root"

  if aroma_probe_rw "$sys_mp"; then
    AROMA_MOD_MODE="rw"
    ui_print "- Mode: Direct RW ($sys_mp verified writable)"
    return 0
  fi

  if [ "$fallback" = "1" ] || [ "$req_mode" = "auto" ]; then
    AROMA_MOD_MODE="systemless"
    ui_print "- Falling back safely to Systemless Mode ($AROMA_MOD_ROOT)"
    return 0
  fi

  ui_print "! Aborting: Direct RW requested, but partitions are not RW."
  return 1
}

# Copy/replace a file into target system-relative path (e.g. "system/etc/hosts")
aroma_mod_copy() {
  local src="$1"
  local rel_target="$2"
  local mode="${3:-0644}"

  if [ ! -f "$src" ]; then
    ui_print "! aroma_mod_copy: missing source $src"
    return 1
  fi

  if [ "$AROMA_MOD_MODE" = "rw" ]; then
    local dst
    dst="$(_aroma_rw_target_path "$rel_target")"
    mkdir -p "$(dirname "$dst")"
    [ -f "$dst" ] && [ ! -f "${dst}.aroma.bak" ] && cp -af "$dst" "${dst}.aroma.bak" 2>/dev/null || true
    cp -f "$src" "$dst"
    chmod "$mode" "$dst"
  else
    local norm
    norm="$(_aroma_norm_rel "$rel_target")"
    local dst="${AROMA_MOD_ROOT}/${norm}"
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    chmod "$mode" "$dst"
  fi
}

# Systemlessly hide/debloat (or directly delete in RW mode) a file or directory
aroma_mod_delete() {
  local rel_target="$1"
  local is_dir="${2:-auto}"

  if [ "$AROMA_MOD_MODE" = "rw" ]; then
    local dst
    dst="$(_aroma_rw_target_path "$rel_target")"
    if [ -e "$dst" ]; then
      rm -rf "$dst"
      ui_print "  [RW] Deleted /$rel_target"
    fi
    return 0
  fi

  local norm
  norm="$(_aroma_norm_rel "$rel_target")"
  local dst="${AROMA_MOD_ROOT}/${norm}"
  local src_live
  src_live="$(_aroma_rw_target_path "$rel_target")"

  if [ "$is_dir" = "dir" ] || { [ "$is_dir" = "auto" ] && [ -d "$src_live" ]; } || [ "${rel_target%/}" != "$rel_target" ]; then
    if [ "$KSU" = "true" ] || [ "$APATCH" = "true" ]; then
      mkdir -p "$(dirname "$dst")"
      rm -rf "$dst"
      mknod "$dst" c 0 0 2>/dev/null || {
        mkdir -p "$dst"
        touch "$dst/.replace"
      }
    else
      mkdir -p "$dst"
      touch "$dst/.replace"
    fi
    ui_print "  [Systemless] Masked directory /$rel_target"
  else
    mkdir -p "$(dirname "$dst")"
    if [ "$KSU" = "true" ] || [ "$APATCH" = "true" ]; then
      rm -f "$dst"
      mknod "$dst" c 0 0 2>/dev/null || : > "$dst"
    else
      : > "$dst"
    fi
    ui_print "  [Systemless] Masked file /$rel_target"
  fi
}

# Set/override a system property (system.prop in Systemless mode, build.prop in RW mode)
aroma_mod_edit_prop() {
  local key="$1"
  local val="$2"

  if [ "$AROMA_MOD_MODE" = "rw" ]; then
    local bprop
    bprop="$(_aroma_rw_target_path "system/build.prop")"
    if [ -f "$bprop" ]; then
      [ ! -f "${bprop}.aroma.bak" ] && cp -af "$bprop" "${bprop}.aroma.bak" 2>/dev/null || true
      if grep -qE "^${key}=" "$bprop"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$bprop"
      else
        printf "\n%s=%s\n" "$key" "$val" >> "$bprop"
      fi
      return 0
    fi
  fi

  local sprop="${AROMA_MOD_ROOT}/system.prop"
  touch "$sprop"
  if grep -qE "^${key}=" "$sprop"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$sprop"
  else
    printf "%s=%s\n" "$key" "$val" >> "$sprop"
  fi
}

# Copy an existing read-only file into $MODPATH and patch it with sed (or patch live in RW mode)
aroma_mod_patch_file() {
  local rel_target="$1"
  local sed_expr="$2"

  if [ "$AROMA_MOD_MODE" = "rw" ]; then
    local dst
    dst="$(_aroma_rw_target_path "$rel_target")"
    if [ -f "$dst" ]; then
      [ ! -f "${dst}.aroma.bak" ] && cp -af "$dst" "${dst}.aroma.bak" 2>/dev/null || true
      sed -i "$sed_expr" "$dst"
      return 0
    fi
    return 1
  fi

  local src_live
  src_live="$(_aroma_rw_target_path "$rel_target")"
  if [ ! -f "$src_live" ]; then
    ui_print "! aroma_mod_patch_file: source not found ($src_live)"
    return 1
  fi
  local norm
  norm="$(_aroma_norm_rel "$rel_target")"
  local dst="${AROMA_MOD_ROOT}/${norm}"
  mkdir -p "$(dirname "$dst")"
  cp -f "$src_live" "$dst"
  sed -i "$sed_expr" "$dst"
}
