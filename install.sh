#!/bin/bash

set -o pipefail

INSTALLER_VERSION="r04"
INSTALLER_BUILD_DATE="2026-05-11"
INSTALL_USER=""
INSTALL_UID=""
INSTALL_HOME=""

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
    if [[ -n "${DECKSIGHT_SUDO_PASSWORD:-}" ]]; then
        if echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S -v >/dev/null 2>&1; then
            return 0
        fi
    fi

    PASSWORD=$(zenity --password --title="DeckSight Installer - Sudo Required") || exit 1
    if ! echo "$PASSWORD" | sudo -S -v >/dev/null 2>&1; then
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

capture_install_user() {
    INSTALL_USER="${SUDO_USER:-$(id -un)}"
    INSTALL_UID="$(id -u "$INSTALL_USER")"
    INSTALL_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6)"

    if [[ -z "$INSTALL_HOME" ]]; then
        INSTALL_HOME="$HOME"
    fi
}

apply_decksight_display_rotation() {
    if ! command -v kscreen-doctor >/dev/null 2>&1; then
        echo "[INFO] kscreen-doctor not found; skipping DeckSight desktop rotation."
        return 0
    fi

    local xdg_runtime_dir="/run/user/$INSTALL_UID"
    local dbus_session_bus_address="unix:path=${xdg_runtime_dir}/bus"
    local display="${DISPLAY:-:0}"
    local xauthority="${XAUTHORITY:-$INSTALL_HOME/.Xauthority}"
    local wayland_display="${WAYLAND_DISPLAY:-}"
    local qt_platform="${QT_QPA_PLATFORM:-}"

    if [[ -z "$qt_platform" ]]; then
        if [[ "${XDG_SESSION_TYPE:-}" == "wayland" && -n "$wayland_display" ]]; then
            qt_platform="wayland"
        else
            qt_platform="xcb"
        fi
    fi

    echo "[INFO] Applying DeckSight desktop rotation for ${INSTALL_USER}."

    if [[ "$(id -u)" -eq "$INSTALL_UID" ]]; then
        XDG_RUNTIME_DIR="$xdg_runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="$dbus_session_bus_address" \
        DISPLAY="$display" \
        XAUTHORITY="$xauthority" \
        WAYLAND_DISPLAY="$wayland_display" \
        QT_QPA_PLATFORM="$qt_platform" \
        kscreen-doctor output.eDP.rotation.right || true
    else
        sudo -u "$INSTALL_USER" \
        XDG_RUNTIME_DIR="$xdg_runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="$dbus_session_bus_address" \
        DISPLAY="$display" \
        XAUTHORITY="$xauthority" \
        WAYLAND_DISPLAY="$wayland_display" \
        QT_QPA_PLATFORM="$qt_platform" \
        kscreen-doctor output.eDP.rotation.right || true
    fi
}

remove_brightness_wrangler() {
    echo "[INFO] Removing legacy brightness-wrangler if present..."
    systemctl --user disable --now brightness-wrangler.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/brightness-wrangler.service"
    rm -f "$HOME/.local/bin/brightness-wrangler.sh"
    systemctl --user daemon-reload 2>/dev/null || true
}

install_brightness_control() {
    local src_dir="$SCRIPT_DIR/decksight-brightnessctrl"

    if [[ ! -x "$src_dir/decksight-brightnessctrl" ]]; then
        zenity --error --text="DeckSight Brightness Control binary not found in installer package."
        return 1
    fi
    if [[ ! -f "$src_dir/decksight-brightnessctrl.service" ]]; then
        zenity --error --text="DeckSight Brightness Control service file not found in installer package."
        return 1
    fi

    remove_brightness_wrangler

    zenity_sudo

    if command -v steamos-readonly >/dev/null 2>&1; then
        echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S steamos-readonly disable || panic "Failed to disable read-only filesystem"
    fi

    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S systemctl stop decksight-brightnessctrl.service 2>/dev/null || true
    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S systemctl reset-failed decksight-brightnessctrl.service 2>/dev/null || true

    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S mkdir -p /var/local/bin || panic "Failed to create /var/local/bin"
    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S install -m 755 -T "$src_dir/decksight-brightnessctrl" /var/local/bin/decksight-brightnessctrl || panic "Failed to install decksight-brightnessctrl"
    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S install -m 644 -T "$src_dir/decksight-brightnessctrl.service" /etc/systemd/system/decksight-brightnessctrl.service || panic "Failed to install decksight-brightnessctrl.service"

    if command -v getenforce >/dev/null 2>&1; then
        if [[ "$(getenforce 2>/dev/null)" != "Disabled" ]]; then
            if command -v semanage >/dev/null 2>&1; then
                echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S semanage fcontext -a -t bin_t "/var/local/bin(/.*)?" 2>/dev/null || true
                echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S restorecon -Rv /var/local/bin || true
            else
                echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S chcon -t bin_t /var/local/bin 2>/dev/null || true
                echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S chcon -t bin_t /var/local/bin/decksight-brightnessctrl 2>/dev/null || true
            fi
        fi
    fi

    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S systemctl daemon-reload || panic "systemctl daemon-reload failed"
    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S systemctl enable --now decksight-brightnessctrl.service || panic "Failed to enable DeckSight Brightness Control"

    if command -v steamos-readonly >/dev/null 2>&1; then
        echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S steamos-readonly enable || panic "Failed to re-enable read-only filesystem"
    fi
}

remove_brightness_control() {
    zenity_sudo

    if command -v steamos-readonly >/dev/null 2>&1; then
        echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S steamos-readonly disable || panic "Failed to disable read-only filesystem"
    fi

    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S systemctl disable --now decksight-brightnessctrl.service 2>/dev/null || true
    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S rm -f /etc/systemd/system/decksight-brightnessctrl.service
    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S rm -f /var/local/bin/decksight-brightnessctrl
    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S rm -f /usr/local/bin/decksight-brightnessctrl
    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S systemctl daemon-reload || panic "systemctl daemon-reload failed"

    if command -v steamos-readonly >/dev/null 2>&1; then
        echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S steamos-readonly enable || panic "Failed to re-enable read-only filesystem"
    fi

    remove_brightness_wrangler
}

find_bios_fd() {
    local best_path=""
    local best_release=-1
    local best_name=""
    local bios_path bios_name release

    while IFS= read -r bios_path; do
        bios_name=$(basename "$bios_path")
        release=$(bios_release_number "$bios_path")

        if (( release > best_release )) ||
           { (( release == best_release )) && [[ "$bios_name" > "$best_name" ]]; }; then
            best_path="$bios_path"
            best_release=$release
            best_name="$bios_name"
        fi
    done < <(find "$SCRIPT_DIR/bios" -maxdepth 1 -type f -name '*.fd' ! -name '*tester*' | sort -V)

    if [[ -z "$best_path" ]]; then
        while IFS= read -r bios_path; do
            bios_name=$(basename "$bios_path")
            release=$(bios_release_number "$bios_path")

            if (( release > best_release )) ||
               { (( release == best_release )) && [[ "$bios_name" > "$best_name" ]]; }; then
                best_path="$bios_path"
                best_release=$release
                best_name="$bios_name"
            fi
        done < <(find "$SCRIPT_DIR/bios" -maxdepth 1 -type f -name '*.fd' | sort -V)
    fi

    printf '%s\n' "$best_path"
}

bios_release_number() {
    local bios_name
    bios_name=$(basename "$1")

    if [[ "$bios_name" =~ _r([0-9]+)([^0-9]|$) ]]; then
        printf '%d\n' "$((10#${BASH_REMATCH[1]}))"
    else
        printf '0\n'
    fi
}

bios_build_date() {
    local bios_path="$1"

    if stat -c '%Y' "$bios_path" >/dev/null 2>&1; then
        date -d "@$(stat -c '%Y' "$bios_path")" '+%Y-%m-%d'
    else
        printf 'unknown\n'
    fi
}

remove_edid_spoof() {
    echo "[INFO] Removing DeckSight EDID spoof files if present..."
    rm -f "$HOME/.local/share/decksight/decksight_edid.bin"
    rm -f "$HOME/.config/environment.d/decksight-edid.conf"
}

install_edid_spoof() {
    mkdir_all "$HOME/.local/share/decksight/"
    mkdir_all "$HOME/.config/environment.d/"
    cp -v "$SCRIPT_DIR/edid/decksight_edid.bin" "$HOME/.local/share/decksight/decksight_edid.bin"
    catch_error "failed to copy decksight_edid.bin"
    cp -v "$SCRIPT_DIR/edid/decksight-edid.conf" "$HOME/.config/environment.d/decksight-edid.conf"
    catch_error "failed to copy decksight-edid.conf"

    systemctl --user import-environment DISPLAY XAUTHORITY
    dbus-update-activation-environment --systemd DISPLAY XAUTHORITY
}

main() {
    SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
    echo "[DEBUG] SCRIPT_DIR=$SCRIPT_DIR"
    capture_install_user
    echo "[DEBUG] INSTALL_USER=$INSTALL_USER INSTALL_UID=$INSTALL_UID INSTALL_HOME=$INSTALL_HOME"

    logfile="/tmp/decksight-install.log"
    exec > >(tee -a "$logfile") 2>&1

    XDG_RUNTIME_DIR="/run/user/$INSTALL_UID"
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

    bios_fd_path=$(find_bios_fd)

    if [[ -z "$bios_fd_path" ]]; then
        zenity --title "DeckSight" --error --text "No .fd BIOS file found in extracted archive."
        exit 1
    fi

    patched_bios_version=$(basename "$bios_fd_path" .fd)
    patched_bios_build_date=$(bios_build_date "$bios_fd_path")
    bios_release=$(bios_release_number "$bios_fd_path")
    bios_has_embedded_edid=false
    if (( bios_release >= 4 )); then
        bios_has_embedded_edid=true
    fi
    echo "[INFO] Selected BIOS: $patched_bios_version (release r${bios_release}, build date ${patched_bios_build_date})"

    zenity --title "DeckSight" --info --width=600 --text="DeckSight Installer ${INSTALLER_VERSION}\nBuild date: ${INSTALLER_BUILD_DATE}\nBIOS payload: ${patched_bios_version}\nBIOS build date: ${patched_bios_build_date}\n\nYou can first install the DeckSight extras (recommended), then the BIOS.\n\nOnce the BIOS is installed, the stock LCD will no longer operate properly (if currently installed).\n\nAfter the DeckSight BIOS is installed, you can install the DeckSight OLED.\n\nIf DeckSight is already installed, you can ignore this warning and use this installer to update or re-install the extras or BIOS.\n\nIf the charger is not plugged in, you should plug it in now to avoid disruptions while flashing the BIOS.\n\nOnce the BIOS is flashed, the Steam Deck will shut down. If the charger is plugged in it will turn itself back on when finished. If the charger is not plugged in, it will enter battery storage mode and will not turn back on until a charger is plugged in."

    action=$(zenity --title "DeckSight" --list \
        --radiolist \
        --height=300 --width=300 \
        --text="Install or remove DeckSight extras?" \
        --column "Select" --column "Action" \
        TRUE "Install" FALSE "Remove") || exit 0

    if $bios_has_embedded_edid && [[ "$action" == "Install" ]]; then
        extras=$(zenity --title "DeckSight" --list --checklist \
            --width=500 --height=480 \
            --text="Choose which components to $action:\n\n\
    • Gamescope Script – framerate handling and modesetting in gamescope.\n\
    • DeckSight Brightness Control – Hardware panel brightness control service.\n\n\
    This BIOS includes the extended EDID. The old EDID spoof files will be removed automatically." \
            --column "Apply" --column "Component" \
            TRUE "Gamescope Script" \
            TRUE "DeckSight Brightness Control") || exit 0
    else
        extras=$(zenity --title "DeckSight" --list --checklist \
            --width=500 --height=480 \
            --text="Choose which components to $action:\n\n\
    • Gamescope Script – framerate handling and modesetting in gamescope.\n\
    • DeckSight Brightness Control – Hardware panel brightness control service.\n\
    • DeckSight EDID – Extended EDID for HDR support." \
            --column "Apply" --column "Component" \
            TRUE "Gamescope Script" \
            TRUE "DeckSight Brightness Control" \
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
            "DeckSight Brightness Control")
                if [[ "$action" == "Install" ]]; then
                    install_brightness_control || panic "Failed to install DeckSight Brightness Control"
                else
                    remove_brightness_control || panic "Failed to remove DeckSight Brightness Control"
                fi
                ;;
            "DeckSight EDID")
                if [[ "$action" == "Install" ]]; then
                    install_edid_spoof
                else
                    remove_edid_spoof
                fi
                ;;
        esac
    done

    if [[ "$action" == "Remove" ]]; then
        zenity --info --title "DeckSight" --text="Selected components have been removed.\n\nExiting installer."
        exit 0
    fi

    rm -rf "$INSTALL_HOME/.local/share/kscreen/"*
    apply_decksight_display_rotation

    zenity_sudo

    # --- Block BIOS updates (SteamOS or Bazzite) ---
    if zenity --question \
        --title="DeckSight" \
        --text="Block BIOS updates?\n\nThis prevents automatic updates from overwriting the DeckSight BIOS. You can still flash manually or via this installer."; then

        zenity --info --title="DeckSight" --text="Locking BIOS update service. This will require sudo."
        bios_updates_locked=false

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
            bios_updates_locked=true

        elif is_bazzite; then
            # Bazzite: use ujust convenience command
            if command -v ujust >/dev/null 2>&1; then
                echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S ujust disable-bios-updates || panic "ujust disable-bios-updates failed"
                bios_updates_locked=true
            else
                zenity --warning --title="DeckSight" --text="'ujust' not found. Skipping automated lock on Bazzite.\nYou can run it later: ujust disable-bios-updates"
            fi

        else
            echo "[INFO] BIOS auto-update lock: unsupported OS; skipped"
        fi

        if $bios_updates_locked; then
            zenity --info --title="DeckSight" --text="BIOS updates have been locked."
        else
            zenity --warning --title="DeckSight" --text="BIOS update locking was skipped for this OS."
        fi
    fi

        # --- Confirm and Flash BIOS ---
    if ! zenity --title "DeckSight" --question \
        --width=480 \
        --text="Ready to flash the DeckSight BIOS (version: ${patched_bios_version}).

    This will Flash The BIOS and the Deck will Reset.\nMake sure charger is connected or it will not restart until it is.

        Proceed?"; then
        zenity --info --title "DeckSight" --text="BIOS flash canceled. Any selected extras changes have already been applied."
        exit 0
    fi

    if $bios_has_embedded_edid; then
        remove_edid_spoof
    fi

    echo "$DECKSIGHT_SUDO_PASSWORD" | sudo -S /usr/share/jupiter_bios_updater/h2offt "$bios_fd_path"
}

main "$@"
