# NLSound — Pure AROMA-Next Module Installer (Zero MMT-Extended!)
# Single aroma-config drives BOTH:
#   - Custom Recovery (BOOTMODE=0): Full 60-120Hz AROMA-Next Touch GUI
#   - Booted Android  (BOOTMODE=1): Built-in AROMA-Next Volume Key Selector (Magisk / KernelSU / APatch)

SKIPUNZIP=1

# 1. Load AROMA-Next Module Helper Library
unzip -qjo "$ZIPFILE" 'META-INF/com/google/android/aroma-mod-lib.sh' -d "$TMPDIR" >/dev/null 2>&1
[ -f "$TMPDIR/aroma-mod-lib.sh" ] && . "$TMPDIR/aroma-mod-lib.sh"

# Normalize BOOTMODE
case "$BOOTMODE" in
  true|1)  BOOTMODE=true ;;
  false|0) BOOTMODE=false ;;
  *)
    if (ps -A 2>/dev/null || ps 2>/dev/null) | grep -qE "zygote|surfaceflinger"; then
      BOOTMODE=true
    else
      BOOTMODE=false
    fi
    ;;
esac

# Detect KernelSU / APatch (in both App and Recovery)
[ -z "$KSU" ] && KSU=false
[ -z "$APATCH" ] && APATCH=false
if [ "$BOOTMODE" != "true" ]; then
  [ -d /data/adb/ksu ] || [ -f /data/adb/ksu/modules.img ] && KSU=true
  [ -d /data/adb/ap ] && APATCH=true
fi
[ "$APATCH" = "true" ] && KSU=true
[ -z "$NVBASE" ] && NVBASE="/data/adb"
[ -z "$API" ] && API="$(getprop ro.build.version.sdk 2>/dev/null)"
[ -z "$API" ] && API=34

# 2. In BOOTMODE=1 (Magisk / KernelSU / APatch App), automatically launch
#    AROMA-Next's built-in Volume Key Selector from the exact same aroma-config!
aroma_run_config_if_needed

aroma_progress 0.08 "Preparing read-only audio mirrors..."

# 3. Clean POSIX file-copy helper (replaces MMT-Extended cp_ch)
cp_ch() {
  local FOL=false
  while [ $# -gt 0 ]; do
    case "$1" in
      -n) shift ;;
      -r) FOL=true; shift ;;
      --) shift; break ;;
      *)  break ;;
    esac
  done
  local SRC="$1" DEST="$2" PERM="${3:-0644}"
  [ -e "$SRC" ] || return 1
  if [ "$FOL" = "true" ]; then
    local OFILE FILE
    for OFILE in $(find "$SRC" -type f 2>/dev/null); do
      if [ "$(basename "$SRC")" = "$(basename "$DEST")" ]; then
        FILE="$(echo "$OFILE" | sed "s|$SRC|$DEST|")"
      else
        FILE="$(echo "$OFILE" | sed "s|$SRC|$DEST/$(basename "$SRC")|")"
      fi
      mkdir -p "$(dirname "$FILE")"
      cp -f "$OFILE" "$FILE"
      chmod "$PERM" "$FILE" 2>/dev/null || true
    done
  else
    local FILE="$DEST"
    [ -d "$DEST" ] && FILE="$DEST/$(basename "$SRC")"
    mkdir -p "$(dirname "$FILE")"
    cp -f "$SRC" "$FILE"
    chmod "$PERM" "$FILE" 2>/dev/null || true
  fi
}

# 4. Build read-only $ORIGDIR mirror so NLSound always patches clean stock configs
ORIGDIR=""
CLEANUP_ORIG=0

setup_orig_mirrors() {
  if [ "$BOOTMODE" != "true" ]; then
    # Custom Recovery: mount read-only partitions and symlink canonical layout
    ORIGDIR="/tmp/nlsound_orig"
    CLEANUP_ORIG=1
    rm -rf "$ORIGDIR"
    mkdir -p "$ORIGDIR"
    for mp in /system_root /system /vendor /product /system_ext /odm /mi_ext /my_product; do
      if [ -d "$mp" ] && ! grep -q " $mp " /proc/mounts 2>/dev/null; then
        mount -o ro "$mp" >/dev/null 2>&1 || mount "$mp" >/dev/null 2>&1 || true
      fi
    done
    local sys_src="" cand part src
    for cand in /system_root/system /mnt/system/system /system; do
      if [ -d "$cand/etc" ] || [ -f "$cand/build.prop" ] || [ -d "$cand/framework" ]; then
        sys_src="$cand"
        break
      fi
    done
    [ -n "$sys_src" ] && ln -s "$sys_src" "$ORIGDIR/system"
    for part in vendor product system_ext odm mi_ext my_product; do
      src=""
      for cand in "/$part" "/mnt/$part" "/system_root/$part" "/system_root/system/$part" "/system/$part"; do
        if [ -d "$cand" ] && [ -n "$(ls -A "$cand" 2>/dev/null)" ]; then
          src="$cand"
          break
        fi
      done
      [ -n "$src" ] && ln -s "$src" "$ORIGDIR/$part"
    done
  elif [ "$KSU" = "true" ] || [ "${MAGISK_VER_CODE:-0}" -ge 27000 ]; then
    # Booted Android (KernelSU / APatch / Magisk v27+ Atomic Mount): mount clean RO mirrors
    ORIGDIR="${TMPDIR:-/dev/tmp}/nlsound_orig"
    CLEANUP_ORIG=1
    rm -rf "$ORIGDIR"
    mkdir -p "$ORIGDIR/system"
    mount -o ro,bind /system "$ORIGDIR/system" 2>/dev/null || ln -s /system "$ORIGDIR/system"
    for part in vendor product system_ext odm mi_ext my_product; do
      if [ -d "/$part" ]; then
        mkdir -p "$ORIGDIR/$part"
        mount -o ro,bind "/$part" "$ORIGDIR/$part" 2>/dev/null || ln -s "/$part" "$ORIGDIR/$part"
      fi
    done
  elif [ -n "$(magisk --path 2>/dev/null)" ] && [ -d "$(magisk --path 2>/dev/null)/.magisk/mirror" ]; then
    ORIGDIR="$(magisk --path 2>/dev/null)/.magisk/mirror"
  else
    ORIGDIR=""
  fi
}

cleanup_orig_mirrors() {
  if [ "$CLEANUP_ORIG" = "1" ] && [ -d "$ORIGDIR" ]; then
    for i in "$ORIGDIR"/*; do
      [ -L "$i" ] && rm -f "$i" 2>/dev/null && continue
      umount -l "$i" 2>/dev/null || true
    done
    rm -rf "$ORIGDIR" 2>/dev/null || true
  fi
}

setup_orig_mirrors

# 5. Extract module payload (excludes AROMA-Next META-INF & build/docs files)
aroma_progress 0.14 "Extracting NLSound payload..."
ui_print "- Extracting NLSound module files..."
unzip -o "$ZIPFILE" -x 'META-INF/*' 'docs/*' 'build.py' '.git*' -d "$MODPATH" >/dev/null 2>&1

# 6. Run pure NLSound audio patching engine (reads ${AROMA_TMP}/nlsound.cfg)
aroma_progress 0.20 "Patching audio configs & hardware profiles..."
if [ -f "$MODPATH/common/install.sh" ]; then
  . "$MODPATH/common/install.sh"
fi

# 7. Finalize lifecycle scripts, permissions & SELinux contexts
aroma_progress 0.92 "Finalizing scripts & permissions..."
for s in service.sh post-fs-data.sh; do
  if [ -f "$MODPATH/$s" ]; then
    grep -q '^#!/system/bin/sh' "$MODPATH/$s" 2>/dev/null || sed -i '1i #!/system/bin/sh' "$MODPATH/$s"
    grep -q '^MODDIR=' "$MODPATH/$s" 2>/dev/null || sed -i '1a MODDIR=${0%/*}\nMODPATH=$MODDIR' "$MODPATH/$s"
  fi
done

rm -rf "$MODPATH/common" 2>/dev/null || true
cleanup_orig_mirrors

set_perm_recursive "$MODPATH" 0 0 0755 0644
for i in /system/vendor /vendor /system/vendor/app /vendor/app /system/vendor/etc /vendor/etc /system/odm/etc /odm/etc /system/vendor/odm/etc /vendor/odm/etc /system/vendor/overlay /vendor/overlay; do
  if [ -d "$MODPATH$i" ] && [ ! -L "$MODPATH$i" ]; then
    case "$i" in
      *"/vendor")  set_perm_recursive "$MODPATH$i" 0 0 0755 0644 u:object_r:vendor_file:s0 ;;
      *"/app")     set_perm_recursive "$MODPATH$i" 0 0 0755 0644 u:object_r:vendor_app_file:s0 ;;
      *"/overlay") set_perm_recursive "$MODPATH$i" 0 0 0755 0644 u:object_r:vendor_overlay_file:s0 ;;
      *"/etc")     set_perm_recursive "$MODPATH$i" 0 2000 0755 0644 u:object_r:vendor_configs_file:s0 ;;
    esac
  fi
done
for i in $(find "$MODPATH/system/vendor" "$MODPATH/vendor" -type f -name "*.apk" 2>/dev/null); do
  chcon u:object_r:vendor_app_file:s0 "$i" 2>/dev/null || true
done
[ -d "$MODPATH/system/bin" ] && set_perm_recursive "$MODPATH/system/bin" 0 0 0755 0755
for s in action.sh service.sh post-fs-data.sh; do
  [ -f "$MODPATH/$s" ] && chmod 0755 "$MODPATH/$s" 2>/dev/null || true
done

aroma_progress 1.00 "NLSound v4.5 installation complete!"
