#!/sbin/sh
# NLSound — AROMA-Next Configuration Compiler & Summary Generator
# Translates AROMA Touch GUI choices (Custom / Recommended / Restore) into
# canonical ${AROMA_TMP:-/tmp/aroma}/nlsound.cfg and a readable summary.txt.

AROMA_DIR="${AROMA_TMP:-/tmp/aroma}"
mkdir -p "$AROMA_DIR"

read_prop() {
  local file="$AROMA_DIR/$1"
  local key="$2"
  local def="$3"
  if [ -f "$file" ]; then
    local val
    val="$(grep -E "^${key}=" "$file" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '\r')"
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
  fi
  echo "$def"
}

MODE_SEL="$(read_prop "setup_mode.prop" "selected" "1")"
DEVICE="$(read_prop "nls_env.prop" "device" "unknown")"
MODEL="$(read_prop "nls_env.prop" "model" "$DEVICE")"
ROOT_TARGET="$(read_prop "nls_env.prop" "root_summary" "Systemless")"
HAS_PREPATCHED="$(read_prop "nls_env.prop" "has_prepatched_acdb" "0")"

# Defaults
VOLSTEPS="false"
VOLMEDIA="false"
VOLMIC="false"
BITNES="false"
SAMPLERATE="false"
STEP6="false"
STEP7="false"
STEP8="false"
STEP9="false"
STEP10="false"
STEP11="false"
STEP12="false"
STEP13="false"
STEP14="false"
PATCHACDB="false"
DELETEACDB="false"
PROFILE_LABEL="Custom Touch Configuration"
EXTRA_NOTE=""

if [ "$MODE_SEL" = "2" ]; then
  # 1-Tap Audiophile Recommended Preset
  PROFILE_LABEL="Audiophile Recommended Preset (1-Tap)"
  VOLSTEPS="30"
  VOLMEDIA="false"
  VOLMIC="false"
  BITNES="24"
  SAMPLERATE="96000"
  STEP6="true"
  STEP7="true"
  STEP8="true"
  STEP9="true"
  STEP10="true"
  STEP11="true"
  STEP12="part"
  STEP13="true"
  STEP14="true"
  PATCHACDB="false"
  DELETEACDB="false"
elif [ "$MODE_SEL" = "3" ] && [ -f "$AROMA_DIR/saved_settings.nls" ]; then
  # 1-Tap Restore Previous Profile
  PROFILE_LABEL="Restored Previous Profile (settings.nls)"
  . "$AROMA_DIR/saved_settings.nls"
else
  # Custom Configuration from AROMA Touch Wizard
  PROFILE_LABEL="Custom Touch Configuration"

  # Page 1: Volume & Gain (vol_gain.prop)
  v_steps="$(read_prop "vol_gain.prop" "volsteps" "30")"
  v_media="$(read_prop "vol_gain.prop" "volmedia" "skip")"
  v_mic="$(read_prop "vol_gain.prop" "volmic" "skip")"

  [ "$v_steps" != "skip" ] && VOLSTEPS="$v_steps"
  [ "$v_media" != "skip" ] && VOLMEDIA="$v_media"
  [ "$v_mic" != "skip" ]   && VOLMIC="$v_mic"

  # Page 2: Bit Depth & Sample Rate (format_rate.prop)
  v_bit="$(read_prop "format_rate.prop" "bitnes" "24")"
  v_sr="$(read_prop "format_rate.prop" "samplerate" "96000")"

  [ "$v_bit" != "skip" ] && BITNES="$v_bit"
  [ "$v_sr" != "skip" ]  && SAMPLERATE="$v_sr"

  # Page 3: Core Audio Engine & Hardware Tweaks (engine_tweaks.prop)
  [ "$(read_prop "engine_tweaks.prop" "item.1.1" "1")" = "1" ] && STEP6="true"
  [ "$(read_prop "engine_tweaks.prop" "item.1.2" "1")" = "1" ] && STEP8="true"
  [ "$(read_prop "engine_tweaks.prop" "item.1.3" "1")" = "1" ] && STEP11="true"
  [ "$(read_prop "engine_tweaks.prop" "item.2.1" "1")" = "1" ] && STEP7="true"
  [ "$(read_prop "engine_tweaks.prop" "item.2.2" "1")" = "1" ] && STEP9="true"
  [ "$(read_prop "engine_tweaks.prop" "item.2.3" "1")" = "1" ] && STEP10="true"
  [ "$(read_prop "engine_tweaks.prop" "item.2.4" "1")" = "1" ] && STEP13="true"

  # Page 4: Effects, Dolby Atmos & ACDB (effects_acdb.prop)
  v_fx="$(read_prop "effects_acdb.prop" "effects" "part")"
  case "$v_fx" in
    part) STEP12="part" ;;
    full) STEP12="full" ;;
    *)    STEP12="false" ;;
  esac

  if [ "$(read_prop "effects_acdb.prop" "dolby_tune" "1")" = "1" ]; then
    if [ "$STEP12" = "full" ]; then
      STEP14="false"
      EXTRA_NOTE="Note: Dolby Atmos tuning auto-skipped because 'Disable All Effects' is selected."
    else
      STEP14="true"
    fi
  fi

  v_acdb="$(read_prop "effects_acdb.prop" "acdb" "skip")"
  case "$v_acdb" in
    basic)   DELETEACDB="Basic" ;;
    general) DELETEACDB="General" ;;
    speaker) DELETEACDB="Speaker" ;;
    patched)
      if [ "$HAS_PREPATCHED" = "1" ]; then
        PATCHACDB="true"
      else
        PATCHACDB="false"
        EXTRA_NOTE="${EXTRA_NOTE:+$EXTRA_NOTE\n}Note: Pre-patched ACDB is not available for $DEVICE (kept stock)."
      fi
      ;;
  esac
fi

# Write canonical configuration consumed by common/install.sh
cat > "$AROMA_DIR/nlsound.cfg" <<EOF
AROMA_CONFIGURED=1
VOLSTEPS=$VOLSTEPS
VOLMEDIA=$VOLMEDIA
VOLMIC=$VOLMIC
BITNES=$BITNES
SAMPLERATE=$SAMPLERATE
STEP6=$STEP6
STEP7=$STEP7
STEP8=$STEP8
STEP9=$STEP9
STEP10=$STEP10
STEP11=$STEP11
STEP12=$STEP12
STEP13=$STEP13
STEP14=$STEP14
PATCHACDB=$PATCHACDB
DELETEACDB=$DELETEACDB
EOF

# Human-readable formatters for AROMA Summary View
fmt_bool() { [ "$1" = "true" ] && echo "Enabled" || echo "Skipped"; }
fmt_val()  { [ "$1" = "false" ] && echo "Stock (Skip)" || echo "$1$2"; }

case "$STEP12" in
  part) FX_TXT="Partial Cleanup (Keep EQ)" ;;
  full) FX_TXT="Disable All Effects" ;;
  *)    FX_TXT="Stock (Keep All)" ;;
esac

if [ "$PATCHACDB" = "true" ]; then
  ACDB_TXT="Pre-Patched Download ($DEVICE)"
elif [ "$DELETEACDB" != "false" ]; then
  ACDB_TXT="Override ($DELETEACDB)"
else
  ACDB_TXT="Stock (Safe)"
fi

cat > "$AROMA_DIR/summary.txt" <<EOF
<b>Profile:</b> <#selectbg_g>$PROFILE_LABEL</#>
<b>Device:</b> $MODEL ($DEVICE)  •  <b>Target:</b> $ROOT_TARGET

<b>Volume & Format:</b>
• Volume Steps: $(fmt_val "$VOLSTEPS" " steps")
• Max Mixer Volume: $(fmt_val "$VOLMEDIA" "")  •  Mic Gain: $(fmt_val "$VOLMIC" "")
• PCM Bit Depth: $(fmt_val "$BITNES" "-bit")  •  Sample Rate: $(fmt_val "$SAMPLERATE" " Hz")

<b>Audio Engine & Hardware:</b>
• Disable Limiters & DRC: $(fmt_bool "$STEP6")
• 4 Hz Sub-Bass HPF & Mixer: $(fmt_bool "$STEP8")
• Vendor Hi-Fi Unlock: $(fmt_bool "$STEP7")  •  Direct PCM: $(fmt_bool "$STEP11")
• build.prop Tweaks: $(fmt_bool "$STEP9")  •  Bluetooth HD: $(fmt_bool "$STEP10")
• Hardware Registers (Tinymix): $(fmt_bool "$STEP13")

<b>Effects, Dolby & ACDB:</b>
• Audio Effects Policy: $FX_TXT
• Dolby Atmos Hi-Fi Profile: $(fmt_bool "$STEP14")
• Qualcomm ACDB Calibration: $ACDB_TXT
EOF

if [ -n "$EXTRA_NOTE" ]; then
  printf "\n<i>%b</i>\n" "$EXTRA_NOTE" >> "$AROMA_DIR/summary.txt"
fi

printf "\nTap <b>Install Now</b> to patch & install NLSound, or <b>Back</b> to adjust options.\n" >> "$AROMA_DIR/summary.txt"

exit 0
