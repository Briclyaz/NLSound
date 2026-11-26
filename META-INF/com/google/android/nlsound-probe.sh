#!/sbin/sh
# NLSound — AROMA-Next Live Recovery Hardware & Environment Probe
# Scans mounted partitions, audio SmartPA/DAC hardware, OEM features, and saved profile.
# Outputs:
#   ${AROMA_TMP:-/tmp/aroma}/nls_env.prop       (machine-readable probe flags)
#   ${AROMA_TMP:-/tmp/aroma}/nls_hw_summary.txt (formatted dashboard for AROMA welcome)
#   ${AROMA_TMP:-/tmp/aroma}/saved_settings.nls (backup copy of previous settings.nls)

AROMA_DIR="${AROMA_TMP:-/tmp/aroma}"
mkdir -p "$AROMA_DIR"

# 1. Mount /data and read-only partitions safely if not yet mounted
if ! grep -q " /data " /proc/mounts 2>/dev/null; then
  mount /data >/dev/null 2>&1 || true
fi

for part in /system_root /system /vendor /product /system_ext /odm /mi_ext /my_product; do
  if [ -d "$part" ] && ! grep -q " $part " /proc/mounts 2>/dev/null; then
    mount -o ro "$part" >/dev/null 2>&1 || mount "$part" >/dev/null 2>&1 || true
  fi
done

# Helper to find a real build.prop key from mounted partitions if getprop is empty
read_prop_file() {
  local key="$1"
  local f val
  for f in /vendor/build.prop /system_root/vendor/build.prop /system/vendor/build.prop \
           /system_root/system/build.prop /system/build.prop /product/etc/build.prop; do
    if [ -r "$f" ]; then
      val="$(grep -E "^${key}=" "$f" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '\r')"
      if [ -n "$val" ]; then
        echo "$val"
        return 0
      fi
    fi
  done
  return 1
}

# 2. Detect Root Solution
has_magisk=0
has_ksu=0
has_apatch=0
can_install=0
root_summary="No Root Manager Detected (/data encrypted?)"

[ -d /data/adb/magisk ] || [ -f /data/adb/magisk.db ] && has_magisk=1
[ -d /data/adb/ksu ] || [ -f /data/adb/ksu/modules.img ] && has_ksu=1
[ -d /data/adb/ap ] && has_apatch=1

if [ "$has_magisk" = "1" ]; then
  can_install=1
  root_summary="Magisk (Systemless)"
elif [ "$has_ksu" = "1" ]; then
  can_install=1
  root_summary="KernelSU (Systemless)"
elif [ "$has_apatch" = "1" ]; then
  can_install=1
  root_summary="APatch (Systemless)"
elif [ -d /data/adb/modules ] || { [ -d /data/adb ] && [ -w /data/adb ]; }; then
  can_install=1
  root_summary="/data/adb Ready (Systemless)"
fi

# 3. Detect Device, SoC & Platform
DEVICE="$(getprop ro.product.vendor.device 2>/dev/null)"
[ -z "$DEVICE" ] && DEVICE="$(read_prop_file ro.product.vendor.device)"
if [ "$DEVICE" = "mivendor" ] || [ -z "$DEVICE" ]; then
  DEVICE="$(getprop ro.product.device 2>/dev/null)"
  [ -z "$DEVICE" ] && DEVICE="$(read_prop_file ro.product.device)"
fi
[ -z "$DEVICE" ] && DEVICE="$(getprop ro.build.product 2>/dev/null)"
[ -z "$DEVICE" ] && DEVICE="unknown"

MODEL="$(getprop ro.product.vendor.model 2>/dev/null)"
[ -z "$MODEL" ] && MODEL="$(getprop ro.product.model 2>/dev/null)"
[ -z "$MODEL" ] && MODEL="$(read_prop_file ro.product.model)"
[ -z "$MODEL" ] && MODEL="$DEVICE"

PROCESSOR="$(getprop ro.board.platform 2>/dev/null)"
[ -z "$PROCESSOR" ] && PROCESSOR="$(read_prop_file ro.board.platform)"
[ -z "$PROCESSOR" ] && PROCESSOR="unknown"

HW="$(getprop ro.hardware 2>/dev/null)"
[ -z "$HW" ] && HW="$(read_prop_file ro.hardware)"
SOC_TYPE="Qualcomm / Universal"
case "$HW" in
  mt*) SOC_TYPE="MediaTek ($PROCESSOR)" ;;
  *)   [ "$PROCESSOR" != "unknown" ] && SOC_TYPE="Qualcomm / $PROCESSOR" ;;
esac

# 4. Detect Audio Hardware (Amplifiers & DAC / Codec)
is_chip_connected() {
  local drv
  for drv in /sys/bus/i2c/drivers/*"$1"* \
             /sys/bus/soundwire/drivers/*"$1"* \
             /sys/bus/slimbus/drivers/*"$1"* \
             /sys/bus/platform/drivers/*"$1"*; do
    [ -d "$drv" ] && ls "$drv" 2>/dev/null | grep -qEv '^(bind|unbind|uevent|module)$' && return 0
  done
  return 1
}

SYS_AUDIO="$(
  {
    cat /proc/asound/cards /proc/asound/pcm 2>/dev/null
    ls -d /sys/bus/soundwire/drivers/* /sys/bus/soundwire/devices/* 2>/dev/null
    ls -d /sys/bus/slimbus/drivers/* /sys/bus/slimbus/devices/* 2>/dev/null
    ls -d /sys/bus/i2c/drivers/* /sys/bus/i2c/devices/* 2>/dev/null
    ls -d /sys/bus/platform/drivers/* 2>/dev/null
    ls -d /sys/devices/platform/soc/*macro* /sys/devices/platform/soc/*audio* 2>/dev/null
    [ -d /proc/device-tree ] && grep -saoE '[a-zA-Z0-9_-]+(wcd|bolero|macro|es9|ak4|cs4)[a-zA-Z0-9_-]+' /proc/device-tree 2>/dev/null
  } | tr '[:upper:]' '[:lower:]'
)"

AMP_LIST=""
add_amp() {
  if [ -z "$AMP_LIST" ]; then
    AMP_LIST="$1"
  else
    AMP_LIST="$AMP_LIST, $1"
  fi
}

is_chip_connected "cs35l" && add_amp "Cirrus Logic (CS35L41)"
is_chip_connected "tfa9"  && add_amp "NXP / Goodix TFA"
is_chip_connected "tas25" && add_amp "Texas Instruments (TAS)"
is_chip_connected "aw88"  && add_amp "Awinic (AW88xx)"
is_chip_connected "max98" && add_amp "Maxim Integrated"
is_chip_connected "wsa88" && add_amp "Qualcomm WSA"
[ -z "$AMP_LIST" ] && AMP_LIST="Standard / Integrated PA"

CODEC_NAME="Integrated SoC Audio Codec"
if echo "$SYS_AUDIO" | grep -qE "es90[0-9]{2}|es92[0-9]{2}|es93[0-9]{2}|sabredac" || is_chip_connected "sabredac"; then
  CODEC_NAME="ESS Sabre Dedicated Hi-Fi DAC"
elif echo "$SYS_AUDIO" | grep -qE "ak43[0-9]{2}|ak44[0-9]{2}|ak49[0-9]{2}"; then
  CODEC_NAME="Asahi Kasei (AKM) Hi-Fi DAC"
elif echo "$SYS_AUDIO" | grep -qE "wcd|bolero|rx_macro|tx_macro|lpass.*macro"; then
  CODEC_NAME="Qualcomm WCD (Aqstic Hi-Fi)"
fi

# 5. Check Device-Specific ACDB Support & Previous Saved Profile
has_prepatched_acdb=0
case "$DEVICE" in
  alioth*|Pong*|marble*|RE5465*|mondrian*|ishtar*|aurora*|REE2B2L1*|PQ83A01*)
    has_prepatched_acdb=1
    ;;
esac

has_saved=0
saved_info="None found"
SAVED_SRC="/data/adb/modules/NLSound/settings.nls"
if [ -f "$SAVED_SRC" ]; then
  cp -f "$SAVED_SRC" "$AROMA_DIR/saved_settings.nls" 2>/dev/null || true
  has_saved=1
  s_vol="$(grep -E '^VOLSTEPS=' "$SAVED_SRC" | head -n1 | cut -d'=' -f2)"
  s_bit="$(grep -E '^BITNES=' "$SAVED_SRC" | head -n1 | cut -d'=' -f2)"
  s_sr="$(grep -E '^SAMPLERATE=' "$SAVED_SRC" | head -n1 | cut -d'=' -f2)"
  saved_info="Found (Steps: ${s_vol:-skip}, ${s_bit:-stock}-bit, ${s_sr:-stock} Hz)"
fi

# 6. Write probe outputs
cat > "$AROMA_DIR/nls_env.prop" <<EOF
can_install=$can_install
root_summary=$root_summary
device=$DEVICE
model=$MODEL
soc=$SOC_TYPE
amp=$AMP_LIST
codec=$CODEC_NAME
has_saved=$has_saved
saved_info=$saved_info
has_prepatched_acdb=$has_prepatched_acdb
EOF

cat > "$AROMA_DIR/nls_hw_summary.txt" <<EOF
<b>NLSound v4.5 — AROMA-Next Edition</b>
System-level Android Hi-Fi Audio Enhancement Module
Powered by <#selectbg_g><b>AROMA-Next-Installer V26.11</b></#>

<b>Detected Device & Audio Hardware:</b>
• <b>Device:</b> $MODEL ($DEVICE)
• <b>Platform:</b> $SOC_TYPE
• <b>Speaker Amp:</b> $AMP_LIST
• <b>Audio Codec:</b> $CODEC_NAME
• <b>Root Target:</b> <#selectbg_g>$root_summary</#>
• <b>Saved Profile:</b> $saved_info

<i>No more tapping Volume buttons 20 times! Configure all 15 NLSound tweaks visually with touch, live themes, fonts & built-in Filemanager (3-dot menu).</i>
EOF

exit 0
