#!/bin/bash

# --- Configurable ---
MAX_BRIGHTNESS=1.0
MIN_BRIGHTNESS=0.2
BRIGHTNESS_PATH="/sys/class/backlight/amdgpu_bl0/brightness"
# BRIGHTNESS_MAX=65535
BRIGHTNESS_MAX=$(cat /sys/class/backlight/amdgpu_bl0/max_brightness 2>/dev/null)
[[ -z "$BRIGHTNESS_MAX" || "$BRIGHTNESS_MAX" -le 0 ]] && BRIGHTNESS_MAX=65535  # guard

# --- Setup environment ---
export DISPLAY=:0

# Detect XAUTHORITY dynamically if needed
if [[ -z "$XAUTHORITY" ]]; then
    export XAUTHORITY=$(find /run/user/$(id -u) -name 'xauth_*' | head -n 1)
fi

# Detect display name dynamically (e.g., eDP, eDP-1)
DISPLAY_NAME=$(xrandr --listmonitors | grep -oE 'eDP[^ ]*' | head -n 1)

if [[ -z "$DISPLAY_NAME" ]]; then
    echo "No eDP output detected. Exiting brightness-wrangler."
    exit 1
fi

POLL_INTERVAL=0.2
LAST_APPLIED=""
PREV_VALUE=""
LAST_APPLIED=""

# --- Main Loop ---
while true; do
    sleep "$POLL_INTERVAL"

    if [[ -f "$BRIGHTNESS_PATH" ]]; then
        value=$(< "$BRIGHTNESS_PATH")

        # Only react when the raw value actually changed
        [[ "$value" == "$PREV_VALUE" ]] && continue
        PREV_VALUE="$value"

        if [[ "$value" -le 500 ]]; then
            brightness="$MIN_BRIGHTNESS"
        else
            brightness=$(awk -v v="$value" -v maxraw="$BRIGHTNESS_MAX" -v minf="$MIN_BRIGHTNESS" -v maxf="$MAX_BRIGHTNESS" '
            BEGIN {
                b = (maxraw > 0) ? (v / maxraw) : minf
                if (b > maxf) b = maxf
                if (b < minf) b = minf
                printf "%.4f", b
            }')
        fi

        # Only call xrandr if the effective brightness changed
        if [[ "$brightness" != "$LAST_APPLIED" ]]; then
            xrandr --output "$DISPLAY_NAME" --brightness "$brightness"
            LAST_APPLIED="$brightness"
        fi
    fi
done

