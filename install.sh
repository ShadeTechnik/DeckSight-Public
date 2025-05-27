#!/bin/bash

set -o pipefail

LOGFILE="/tmp/decksight-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

PATCHED_BIOS_VERSION="F7A0131"

cleanup() {
    [[ -n "$tmp_dir" && -d "$tmp_dir" ]] && rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir_all() {
    [ -z "$1" ] && return 1
    [ -d "$1" ] || mkdir -vp "$1"
}

main() {
    local skip_bios_check=false
    for arg in "$@"; do
        [[ "$arg" == "--test" ]] && skip_bios_check=true && break
    done

    if ! $skip_bios_check; then
        read -r bios_version < /sys/class/dmi/id/bios_version
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

    zenity --title "DeckSight" --info --width=600 --text="You can first install the DeckSight extras (recommended), then the BIOS.\n\nOnce the BIOS is installed, the stock LCD will no longer operate properly (if currently installed).\n\nAfter the DeckSight BIOS is installed, you can install the DeckSight OLED.\n\nIf DeckSight is already installed, you can ignore this warning and use this installer to update or re-install the extras or BIOS.\n\nIf this is the initial installation and the LCD is currently installed in the Steam Deck, it is recommended that you connect an external monitor (mirrored) and keyboard/mouse so that you can verify when the BIOS has finished installing and the Steam Deck has rebooted."

        action=$(zenity --title "DeckSight" --list \
        --radiolist \
        --height=200 --width=300 \
        --text="Install or remove DeckSight extras?" \
        --column "Select" --column "Action" \
        TRUE "Install" FALSE "Remove") || exit 0

    extras=$(zenity --title "DeckSight" --list --checklist \
        --width=500 --height=440 \
        --text="Choose which components to $action:\n\n\
    • Gamescope Script – framerate handling and modesetting in gamescope.\n\
    • Brightness Wrangler – Gamma-based brightness control service in Desktop." \
        --column "Apply" --column "Component" \
        TRUE "Gamescope Script" \
        TRUE "Brightness Wrangler") || exit 0


    for choice in ${extras//|/ }; do
        case "$choice" in
            "Gamescope Script")
                if [[ "$action" == "Install" ]]; then
                    mkdir_all ~/.config/gamescope/scripts/
                    cp -v "Gamescope/DeckSight.lua" ~/.config/gamescope/scripts/
                else
                    rm -v ~/.config/gamescope/scripts/DeckSight.lua
                fi
                ;;
            "Brightness Wrangler")
                if [[ "$action" == "Install" ]]; then
                    mkdir_all ~/.config/systemd/user/
                    cp -v "brightness-wrangler/brightness-wrangler.service" ~/.config/systemd/user/
                    cp -av "brightness-wrangler/brightness-wrangler.sh" ~/.local/bin/
                    systemctl --user daemon-reload
                    systemctl --user enable brightness-wrangler.service
                    systemctl --user restart brightness-wrangler.service
                else
                    systemctl --user disable brightness-wrangler.service
                    systemctl --user stop brightness-wrangler.service
                    rm -v ~/.config/systemd/user/brightness-wrangler.service
                    rm -v ~/.local/bin/brightness-wrangler.sh
                    systemctl --user daemon-reload
                fi
                ;;
        esac
    done

    read -r current_bios_version < /sys/class/dmi/id/bios_version
    current_bios_version="${current_bios_version//[$'\r\n']}"

    if [[ "$current_bios_version" != "$PATCHED_BIOS_VERSION" ]]; then
        zenity --title "DeckSight" --width=400 --warning \
               --text="Detected older BIOS version: ${current_bios_version}.\n\This installer will install the current patched BIOS version: ${PATCHED_BIOS_VERSION}.\n\This is expected if you are updating."
    fi

    if ! zenity --title "DeckSight" --question --text "Proceed with BIOS update to DeckSight ${PATCHED_BIOS_VERSION}?"; then
        exit 0
    fi

    bios_fd_path=$(find bios -type f -name '*.fd' | head -n 1)

    if [[ -z "$bios_fd_path" ]]; then
        zenity --title "DeckSight" --error --text "No .fd BIOS file found in extracted archive."
        exit 1
    fi

    zenity --title "DeckSight" --info \
           --text="Installing BIOS:\n$(basename "$bios_fd_path")"

    pass=$(zenity --title "DeckSight" --password --title="Enter sudo password")
    echo "$pass" | sudo -S /usr/share/jupiter_bios_updater/h2offt "$bios_fd_path"
}

main "$@"
