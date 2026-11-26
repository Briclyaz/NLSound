##########################################################################################
#
# MMT Extended Utility Functions (AROMA-Next Recovery + Android App Dual-Mode Edition)
#
##########################################################################################

# Emit smooth progress & section headers to AROMA-Next GUI when running inside AROMA
aroma_progress() {
  local frac="$1"
  local title="$2"
  if [ -n "$AROMA_TMP" ] && [ -n "$OUTFD" ] && [ -e "/proc/self/fd/$OUTFD" ]; then
    [ -n "$frac" ] && printf 'set_progress %s\n' "$frac" > "/proc/self/fd/$OUTFD" 2>/dev/null || true
    [ -n "$title" ] && printf 'ui_print @%s\nui_print\n' "$title" > "/proc/self/fd/$OUTFD" 2>/dev/null || true
  fi
}

require_new_ksu() {
  ui_print "**********************************"
  ui_print " Please install KernelSU v0.6.6+! "
  ui_print "**********************************"
  exit 1
}

umount_mirrors() {
  [ -d "$ORIGDIR" ] || return 0
  for i in "$ORIGDIR"/*; do
    [ -L "$i" ] && rm -f "$i" 2>/dev/null && continue
    umount -l "$i" 2>/dev/null || true
  done
  rm -rf "$ORIGDIR" 2>/dev/null || true
  if [ "$KSU" = "true" ] && [ "$BOOTMODE" = "true" ]; then
    mount -o ro,remount "$MAGISKTMP" 2>/dev/null || true
  fi
}

cleanup() {
  if [ "$BOOTMODE" != "true" ] || [ "$KSU" = "true" ] || [ "${MAGISK_VER_CODE:-0}" -ge 27000 ]; then
    umount_mirrors
  fi
  rm -rf "$MODPATH/common" "$MODPATH/install.zip" 2>/dev/null || true
}

abort() {
  ui_print "$1"
  rm -rf "$MODPATH" 2>/dev/null || true
  cleanup
  rm -rf "$TMPDIR" 2>/dev/null || true
  exit 1
}

# POSIX-safe cp_ch (works identically in BusyBox ash recovery & Android mksh/busybox)
cp_ch() {
  local BAK=true UBAK=true FOL=false
  while [ $# -gt 0 ]; do
    case "$1" in
      -n) UBAK=false; shift ;;
      -r) FOL=true; shift ;;
      --) shift; break ;;
      -*) abort "Invalid cp_ch argument $1! Aborting!" ;;
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
    local FILE
    if [ -d "$DEST" ]; then
      FILE="$DEST/$(basename "$SRC")"
    else
      FILE="$DEST"
    fi
    mkdir -p "$(dirname "$FILE")"
    cp -f "$SRC" "$FILE"
    chmod "$PERM" "$FILE" 2>/dev/null || true
  fi
}

install_script() {
  local INPATH="$SERVICED"
  case "$1" in
    -b) shift
        if [ "$KSU" = "true" ]; then
          INPATH="$NVBASE/boot-completed.d"
        else
          INPATH="$SERVICED"
          sed -i -e '1i (\nwhile [ "$(getprop sys.boot_completed)" != "1" ]; do\n  sleep 1\ndone\nsleep 3\n' -e '$a)&' "$1"
        fi ;;
    -l) shift; INPATH="$SERVICED" ;;
    -p) shift; INPATH="$POSTFSDATAD" ;;
  esac
  grep -q "#!/system/bin/sh" "$1" 2>/dev/null || sed -i "1i #!/system/bin/sh" "$1"
  local i
  for i in "MODPATH" "LIBDIR" "MODID" "MODDIR"; do
    case "$i" in
      "MODPATH") sed -i "1a $i=$NVBASE/modules/$MODID" "$1" ;;
      "MODDIR")  sed -i "1a $i=\${0%/*}" "$1" ;;
      *)         sed -i "1a $i=$(eval echo \$$i)" "$1" ;;
    esac
  done
  case "$1" in
    "$MODPATH/post-fs-data.sh"|"$MODPATH/service.sh"|"$MODPATH/uninstall.sh")
      sed -i "s|^MODPATH=.*|MODPATH=\$MODDIR|" "$1" ;;
    "$MODPATH/boot-completed.sh")
      if [ "$KSU" = "true" ]; then
        sed -i "s|^MODPATH=.*|MODPATH=\$MODDIR|" "$1"
      else
        cp_ch -n "$1" "$INPATH/$MODID-$(basename "$1")" 0755
        rm -f "$MODPATH/boot-completed.sh"
      fi ;;
    *)
      cp_ch -n "$1" "$INPATH/$(basename "$1")" 0755 ;;
  esac
}

mount_mirrors() {
  [ "$KSU" = "true" ] && mount -o rw,remount "$MAGISKTMP" 2>/dev/null || true
  mkdir -p "$ORIGDIR/system"
  if [ "$SYSTEM_ROOT" = "true" ]; then
    mkdir -p "$ORIGDIR/system_root"
    mount -o ro / "$ORIGDIR/system_root" 2>/dev/null || true
    mount -o bind "$ORIGDIR/system_root/system" "$ORIGDIR/system" 2>/dev/null || true
  else
    mount -o ro /system "$ORIGDIR/system" 2>/dev/null || true
  fi
  for i in /vendor $PARTITIONS; do
    [ ! -d "$i" ] || [ -d "$ORIGDIR$i" ] && continue
    mkdir -p "$ORIGDIR$i"
    mount -o ro "$i" "$ORIGDIR$i" 2>/dev/null || true
  done
}

# Build a clean read-only partition view in Recovery (handles SAR /system_root, /mnt/system, /vendor, etc.)
mount_recovery_mirrors() {
  ORIGDIR="/tmp/nlsound_orig"
  rm -rf "$ORIGDIR"
  mkdir -p "$ORIGDIR"

  # Try mounting standard partitions read-only if not yet mounted
  for mp in /system_root /system /vendor /product /system_ext /odm /mi_ext /my_product; do
    if [ -d "$mp" ] && ! grep -q " $mp " /proc/mounts 2>/dev/null; then
      mount -o ro "$mp" >/dev/null 2>&1 || mount "$mp" >/dev/null 2>&1 || true
    fi
  done

  # Locate canonical /system
  local sys_src=""
  for cand in /system_root/system /mnt/system/system /system; do
    if [ -d "$cand/etc" ] || [ -f "$cand/build.prop" ] || [ -d "$cand/framework" ]; then
      sys_src="$cand"
      break
    fi
  done
  [ -n "$sys_src" ] && ln -s "$sys_src" "$ORIGDIR/system"

  # Locate vendor & dynamic sub-partitions
  local part cand src
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
}

# Normalize BOOTMODE (true/1 vs false/0)
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

# Credits
aroma_progress 0.05 "Initializing NLSound v4.5..."
ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
ui_print "        NLSound v4.5 (AROMA-Next)      "
ui_print " "
ui_print "    Telegram Channels:"
ui_print "      • Support: @nlsound_support"
ui_print "      • Updates: @nlsound_updates"
ui_print "    AROMA-Next: github.com/Miustone"
ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "

# Detect KernelSU / APatch (works in both Booted Android and Recovery)
[ -z "$KSU" ] && KSU=false
[ -z "$APATCH" ] && APATCH=false
if [ "$BOOTMODE" != "true" ]; then
  [ -d /data/adb/ksu ] || [ -f /data/adb/ksu/modules.img ] && KSU=true
  [ -d /data/adb/ap ] && APATCH=true
fi
if [ "$KSU" = "true" ] && [ -n "$KSU_VER_CODE" ] && [ "$KSU_VER_CODE" -lt 11184 ]; then
  require_new_ksu
fi
[ "$APATCH" = "true" ] && KSU=true

# Set variables
[ -z "$NVBASE" ] && NVBASE="/data/adb"
[ -z "$MODULEROOT" ] && MODULEROOT="$NVBASE/modules"
[ -z "$API" ] && API="$(getprop ro.build.version.sdk 2>/dev/null)"
[ -z "$API" ] && API=34
[ -z "$IS64BIT" ] && {
  case "$(uname -m)" in
    aarch64|arm64*|x86_64) IS64BIT=true ;;
    *) IS64BIT=false ;;
  esac
}
[ -z "$ARCH32" ] && ARCH32="$(echo "${ABI32:-armeabi-v7a}" | cut -c-3)"
[ "$API" -lt 26 ] 2>/dev/null && DYNLIB=false
[ -z "$DYNLIB" ] && DYNLIB=false
[ -z "$PARTOVER" ] && PARTOVER=false
[ -z "$SYSTEM_ROOT" ] && SYSTEM_ROOT="${SYSTEM_AS_ROOT:-true}"
[ -z "$SERVICED" ] && SERVICED="$NVBASE/service.d"
[ -z "$POSTFSDATAD" ] && POSTFSDATAD="$NVBASE/post-fs-data.d"

if [ "$BOOTMODE" != "true" ]; then
  # Recovery Mode (AROMA-Next Touch GUI or EXIT 77 fallback)
  ui_print "- Recovery Mode: Mounting read-only system/vendor mirrors..."
  mount_recovery_mirrors
elif [ "$KSU" = "true" ]; then
  MAGISKTMP="/mnt"
  ORIGDIR="$MAGISKTMP/mirror"
  mount_mirrors
elif [ -n "$(magisk --path 2>/dev/null)" ]; then
  if [ "${MAGISK_VER_CODE:-0}" -ge 27000 ]; then # Atomic Mount
    if [ -z "$MAGISKTMP" ]; then
      [ -d /sbin ] && MAGISKTMP=/sbin || MAGISKTMP=/debug_ramdisk
    fi
    ORIGDIR="$MAGISKTMP/mirror"
    mount_mirrors
  else
    ORIGDIR="$(magisk --path 2>/dev/null)/.magisk/mirror"
  fi
elif [ "$(echo "$MAGISKTMP" | awk -F/ '{ print $NF }')" = ".magisk" ]; then
  ORIGDIR="$MAGISKTMP/mirror"
else
  ORIGDIR="$MAGISKTMP/.magisk/mirror"
fi

if [ "$DYNLIB" = "true" ]; then
  LIBPATCH="\/vendor"
  LIBDIR=/system/vendor
else
  LIBPATCH="\/system"
  LIBDIR=/system
fi

# Detect extra partition compatibility (KernelSU or Magisk Delta/Kitsune)
EXTRAPART=false
if [ "$KSU" = "true" ] || [ "$(echo "$MAGISK_VER" | awk -F- '{ print $NF }')" = "delta" ] || [ "$(echo "$MAGISK_VER" | awk -F- '{ print $NF }')" = "kitsune" ]; then
  EXTRAPART=true
elif [ "$PARTOVER" != "true" ]; then
  unset PARTITIONS
fi

# Extract module payload (excludes AROMA-Next META-INF & build/docs files)
aroma_progress 0.10 "Extracting NLSound payload..."
ui_print "- Extracting module files"
unzip -o "$ZIPFILE" -x 'META-INF/*' 'common/functions.sh' 'docs/*' 'build.py' '.git*' -d "$MODPATH" >&2

### Install
aroma_progress 0.15 "Running NLSound installer..."
ui_print "- Installing"

[ -f "$MODPATH/common/install.sh" ] && . "$MODPATH/common/install.sh"

aroma_progress 0.92 "Finalizing scripts & permissions..."

# Remove comments from module scripts/props and wire lifecycle scripts
for i in $(find "$MODPATH" -type f \( -name "*.sh" -o -name "*.prop" -o -name "*.rule" \) 2>/dev/null); do
  [ -f "$i" ] || continue
  case "$i" in
    "$MODPATH/action.sh")
      # Keep action.sh intact (including #!/system/bin/sh shebang)
      chmod 0755 "$i" 2>/dev/null || true
      continue
      ;;
  esac
  sed -i -e "/^#/d" -e "/^ *$/d" "$i"
  [ -n "$(tail -1 "$i")" ] && echo "" >> "$i"
  case "$i" in
    "$MODPATH/boot-completed.sh") install_script -b "$i" ;;
    "$MODPATH/service.sh")        install_script -l "$i" ;;
    "$MODPATH/post-fs-data.sh")   install_script -p "$i" ;;
  esac
done

[ "$IS64BIT" = "true" ] || for i in $(find "$MODPATH/system" -type d -name "lib64" 2>/dev/null); do rm -rf "$i" 2>/dev/null || true; done
[ -d "/system/priv-app" ] || [ -d "$ORIGDIR/system/priv-app" ] || mv -f "$MODPATH/system/priv-app" "$MODPATH/system/app" 2>/dev/null || true
[ -d "/system/xbin" ] || [ -d "$ORIGDIR/system/xbin" ] || mv -f "$MODPATH/system/xbin" "$MODPATH/system/bin" 2>/dev/null || true

if [ "$DYNLIB" = "true" ]; then
  for FILE in $(find "$MODPATH/system/lib"* -type f 2>/dev/null | sed "s|$MODPATH/system/||"); do
    [ -s "$MODPATH/system/$FILE" ] || continue
    case "$FILE" in
      lib*/modules/*) continue ;;
    esac
    mkdir -p "$(dirname "$MODPATH/system/vendor/$FILE")"
    mv -f "$MODPATH/system/$FILE" "$MODPATH/system/vendor/$FILE"
    [ -n "$(ls -A "$(dirname "$MODPATH/system/$FILE")" 2>/dev/null)" ] || rm -rf "$(dirname "$MODPATH/system/$FILE")"
  done
  toybox find "$MODPATH/system/lib"* -type d -empty -delete >/dev/null 2>&1 || true
fi

# Set permissions & SELinux contexts
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
set_permissions

# Complete install
cleanup
aroma_progress 1.00 "NLSound v4.5 installation complete!"
