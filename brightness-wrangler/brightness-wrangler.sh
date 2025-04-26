#!/bin/bash

# --- Configurable ---
MAX_BRIGHTNESS=1.0
MIN_BRIGHTNESS=0.2
BRIGHTNESS_PATH="/sys/class/backlight/amdgpu_bl0/brightness"
BRIGHTNESS_MAX=65535

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

# --- Main Event Loop ---
while true; do
    # Wait for brightness file change or timeout
    inotifywait -e modify -t 1 "$BRIGHTNESS_PATH" >/dev/null 2>&1

    # If brightness file exists, process it
    if [[ -f "$BRIGHTNESS_PATH" ]]; then
        value=$(cat "$BRIGHTNESS_PATH")

        if [[ "$value" -le 500 ]]; then
            brightness=$MIN_BRIGHTNESS
        else
            brightness=$(awk "BEGIN { print ($value / $BRIGHTNESS_MAX) }")

            if (( $(echo "$brightness > $MAX_BRIGHTNESS" | bc -l) )); then
                brightness=$MAX_BRIGHTNESS
            fi
            if (( $(echo "$brightness < $MIN_BRIGHTNESS" | bc -l) )); then
                brightness=$MIN_BRIGHTNESS
            fi
        fi

        # Apply brightness to display
        xrandr --output "$DISPLAY_NAME" --brightness "$brightness"
    fi
done
