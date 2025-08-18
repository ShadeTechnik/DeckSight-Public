#!/bin/bash

set -o pipefail

abort() {
    exit 2
}

panic() {
    zenity --error --text="$*"
    abort
}

mkdir_all() {
    if [ -d "$1" ]; then
        return 0
    fi
    mkdir -vp "$1"
}

catch_error() {
    res=$?
    if [ $res -eq 0 ]; then
        return 0
    fi
    msg=$1
    zenity --error --text="$msg: Failure"
    exit 2
}

zenity_sudo() {
    PASSWORD=$(zenity --password --title="DeckSight Installer - Sudo Required") || exit 1
    echo "$PASSWORD" | sudo -S -v >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        zenity --error --text="Incorrect password or sudo failed. Exiting."
        exit 1
    fi
    export DECKSIGHT_SUDO_PASSWORD="$PASSWORD"
}

# --- OS detection helpers ---
OS_ID=""; OS_ID_LIKE=""; OS_NAME=""; OS_VARIANT_ID="";
detect_os() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="$ID"; OS_ID_LIKE="$ID_LIKE"; OS_NAME="$NAME"; OS_VARIANT_ID="$VARIANT_ID"
    fi
}

is_steamos() {
    detect_os
    grep -qi steamos <<<"$OS_ID $OS_ID_LIKE $OS_NAME" 2>/dev/null
}

is_bazzite() {
    detect_os
    grep -qi bazzite <<<"$OS_ID $OS_VARIANT_ID $OS_NAME" 2>/dev/null
}

main() {
    SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
    echo "[DEBUG] SCRIPT_DIR=$SCRIPT_DIR"

    logfile="/tmp/decksight-install.log"
    exec > >(tee -a "$logfile") 2>&1

    patched_bios_version="F7A0131"

    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export XDG_RUNTIME_DIR
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

    detect_os
    echo "[INFO] Detected OS: ID=$OS_ID NAME=$OS_NAME VARIANT_ID=$OS_VARIANT_ID"

    local skip_bios_check=false
    for arg in "$@"; do
        [[ "$arg" == "--test" ]] && skip_bios_check=true && break
    done

    if ! $skip_bios_check; then
        read -r bios_version < /sys/class/dmi/id/bios_version
        catch_error 'failed to read bios version'
        bios_version="${bios_version//[$'\r\n']}"

        if [[ "$bios_version" == F7G* ]]; then
            zenity --title "DeckSight" --error \
                   --text="Installer has detected that this is an OLED model Steam Deck (${bios_version}).\n\nDeckSight is not compatible and cannot proceed."
            exit 1
        elif [[ "$bios_version" != F7A* ]]; then
            zenity --title "DeckSight" --error \
                   --text="Installer has detected that this device is not a Steam Deck (BIOS version: ${bios_version}).\n\nDeckSight cannot proceed."
            exit 1
        fi
    fi

    zenity --title "DeckSight" --info --width=600 --text="You can first install the DeckSight extras (recommended), then the BIOS.\n\nOnce the BIOS is installed, the stock LCD will no longer operate properly (if currently installed).\n\nAfter the DeckSight BIOS is installed, you can install the DeckSight OLED.\n\nIf DeckSight is already installed, you can ignore this warning and use this installer to update or re-install the extras or BIOS.\n\nIf the charger is not plugged in, you should plug it in now to avoid disruptions while flashing the BIOS.\n\nOnce the BIOS is flashed, the Steam Deck will shut down. If the charger is plugged in it will turn itself back on when finished. If the charger is not plugged in, it will enter battery storage mode and will not turn back on until a charger is plugged in."

    action=$(zenity --title "DeckSight" --list \
        --radiolist \
        --height=300 --width=300 \
        --text="Install or remove DeckSight extras?" \
        --column "Select" --column "Action" \
        TRUE "Install" FALSE "Remove") || exit 0

    # Adjust component list depending on OS
    if is_bazzite; then
        extras=$(zenity --title "DeckSight" --list --checklist \
            --width=500 --height=420 \
            --text="Choose which components to $action:\n\n\
    • Gamescope Script – framerate handling and modesetting in gamescope.\n\
    • DeckSight EDID – Extended EDID for HDR support." \
            --column "Apply" --column "Component" \
            TRUE "Gamescope Script" \
            TRUE "DeckSight EDID") || exit 0
    else
        extras=$(zenity --title "DeckSight" --list --checklist \
            --width=500 --height=480 \
            --text="Choose which components to $action:\n\n\
    • Gamescope Script – framerate handling and modesetting in gamescope.\n\
    • Brightness Wrangler – Gamma-based brightness control service.(X11/SteamOS only)\n\
    • DeckSight EDID – Extended EDID for HDR support." \
            --column "Apply" --column "Component" \
            TRUE "Gamescope Script" \
            TRUE "Brightness Wrangler" \
            TRUE "DeckSight EDID") || exit 0
    fi

    cd "$SCRIPT_DIR" 2>/dev/null || {
      zenity --error --text="DeckSight install failed: extracted files not found."
      exit 1
    }

    IFS="|" read -ra choices <<< "$extras"
    for choice in "${choices[@]}"; do
        case "$choice" in
            "Gamescope Script")
                if [[ "$action" == "Install" ]]; then
                    mkdir_all "$HOME/.config/gamescope/scripts/"
                    catch_error 'mkdir_all failed'
                    cp -v "$SCRIPT_DIR/Gamescope/DeckSight.lua" "$HOME/.config/gamescope/scripts/"
                    catch_error 'failed to copy DeckSight.lua'
                else
                    rm -v "$HOME/.config/gamescope/scripts/DeckSight.lua"
                fi
                ;;
            "Brightness Wrangler")
                # Only relevant on SteamOS/X11; skip if Bazzite
                if is_bazzite; then
                    echo "[INFO] Skipping Brightness Wrangler on Bazzite (Wayland)."
                else
                    if [[ "$action" == "Install" ]]; then
                        if ! systemctl --user is-active --quiet default.target 2>/dev/null; then
                            zenity --error --text="User systemd session is not active. Cannot enable Brightness Wrangler service."
                            return 1
                        fi

                        mkdir_all "$HOME/.config/systemd/user/"
                        catch_error "failed to create $HOME/.config/systemd/user/"

                        mkdir_all "$HOME/.local/bin/"
                        catch_error "failed to create $HOME/.local/bin/"

                        cp -av "$SCRIPT_DIR/brightness-wrangler/brightness-wrangler.sh" "$HOME/.local/bin/"
                        catch_error 'failed to install brightness-wrangler.sh'

                        cp -v "$SCRIPT_DIR/brightness-wrangler/brightness-wrangler.service" "$HOME/.config/systemd/user/"
                        catch_error 'failed to install brightness-wrangler.service'

                        chmod +x "$HOME/.local/bin/brightness-wrangler.sh"

                        systemctl --user daemon-reload
                        catch_error 'systemctl daemon-reload failed'
                        systemctl --user enable brightness-wrangler.service
                        catch_error 'systemctl failed to enable brightness wrangler service'
                        systemctl --user restart brightness-wrangler.service
                        catch_error 'systemctl failed to restart brightness wrangler service'
                    else
                        systemctl --user disable brightness-wrangler.service
                        systemctl --user stop brightness-wrangler.service

                        rm -v "$HOME/.config/systemd/user/brightness-wrangler.service"
                        rm -v "$HOME/.local/bin/brightness-wrangler.sh"

                        systemctl --user daemon-reload
                    fi
                fi
                ;;
            "DeckSight EDID")
                # --- LEAVE THIS SECTION AS-IS (per user) ---
                if [[ "$action" == "Install" ]]; then
                    mkdir_all "$HOME/.local/share/decksight/"
                    mkdir_all "$HOME/.config/environment.d/"
                    cp -v "$SCRIPT_DIR/edid/decksight_edid.bin" "$HOME/.local/share/decksight/decksight_edid.bin"
                    catch_error "failed to copy decksight_edid.bin"
                    cp -v "$SCRIPT_DIR/edid/decksight-edid.conf" "$HOME/.config/environment.d/decksight-edid.conf"
                    catch_error "failed to copy decksight-edid.conf"

                    systemctl --user import-environment DISPLAY XAUTHORITY
                    dbus-update-activation-environment --systemd DISPLAY XAUTHORITY
                else
                    rm -v "$HOME/.local/share/decksight/decksight_edid.bin"
                    rm -v "$HOME/.config/environment.d/decksight-edid.conf"
                fi
                ;;
        esac
    done

    if [[ "$action" == "Remove" ]]; then
        zenity --info --title "DeckSight" --text="Selected components have been removed.\n\nExiting installer."
        exit 0
    fi

    rm -rf "$HOME/.local/share/kscreen/"*

    bios_fd_path=$(find "$SCRIPT_DIR/bios" -type f -name '*.fd' | head -n 1)

    if [[ -z "$bios_fd_path" ]]; then
        zenity --title "DeckSight" --error --text "No .fd BIOS file found in extracted archive."
        exit 1
    fi

    zenity_sudo

    # --- Block BIOS updates (SteamOS or Bazzite) ---
    if zenity --question \
        --title="DeckSight" \
        --text="Block BIOS updates?\n\nThis prevents automatic updates from overwriting the DeckSight BIOS. You can still flash manually or via this installer."; then

        zenity --info --title="DeckSight" --text="Locking BIOS update service. This will require sudo."

        if is_steamos; then
            # SteamOS: mask updater and create INHIBIT flag
            if command -v steamos-readonly >/dev/null 2>&1; then
                echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S steamos-readonly disable || panic "Failed to disable read-only filesystem"
            fi
            echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S systemctl mask jupiter-biosupdate || panic "Failed to mask BIOS update service"
            echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S mkdir -p /foxnet/bios/ || panic "Failed to create /foxnet/bios directory"
            echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S touch /foxnet/bios/INHIBIT || panic "Failed to create INHIBIT flag"
            if command -v steamos-readonly >/dev/null 2>&1; then
                echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S steamos-readonly enable || panic "Failed to re-enable read-only filesystem"
            fi

        elif is_bazzite; then
            # Bazzite: use ujust convenience command
            if command -v ujust >/dev/null 2>&1; then
                echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S ujust disable-bios-updates || panic "ujust disable-bios-updates failed"
            else
                zenity --warning --title="DeckSight" --text="'ujust' not found. Skipping automated lock on Bazzite.\nYou can run it later: ujust disable-bios-updates"
            fi

        else
            echo "[INFO] BIOS auto-update lock: unsupported OS; skipped"
        fi

        zenity --info --title="DeckSight" --text="BIOS updates have been locked."
    fi

        # --- Confirm and Flash BIOS ---
    if ! zenity --title "DeckSight" --question \
        --width=480 \
        --text="Ready to flash the DeckSight BIOS (version: ${patched_bios_version}).

    This will Flash The BIOS and the Deck will Reset.\nMake sure charger is connected or it will not restart until it is.

        Proceed?"; then
        zenity --info --title "DeckSight" --text="Flash canceled. No changes were made."
        exit 0
    fi

    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S /usr/share/jupiter_bios_updater/h2offt "$bios_fd_path"
}

main "$@"
