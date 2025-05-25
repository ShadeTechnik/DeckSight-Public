#!/bin/bash

set -o pipefail

PIPE="/tmp/decksight-update-pipe"
LOGFILE="/tmp/decksight-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

TARBALL_URL="https://github.com/ShadeTechnik/DeckSight-Public/releases/download/v01-test/DeckSight_release_01.tar.gz"
PATCHED_BIOS_VERSION="F7A0131"

cleanup() {
    rm -f "$PIPE"
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

    if zenity --title "DeckSight" --question --text 'Do you want to install/remove extras?'; then
        tmp_dir=$(mktemp -d)
        curl --fail --location --output /tmp/decksight.tgz "$TARBALL_URL" || {
            zenity --title "DeckSight" --error --text "Failed to retrieve release archive."
            exit 1
        }
        tar -xzf /tmp/decksight.tgz -C "$tmp_dir"

        extras=$(zenity --title "DeckSight" --list --checklist \
            --column "Install" --column "Component" \
            TRUE "Gamescope Script" TRUE "Brightness Wrangler")

        for choice in ${extras//|/ }; do
            case "$choice" in
                "Gamescope Script")
                    mkdir_all ~/.config/gamescope/scripts/
                    cp -v "$tmp_dir/Gamescope/DeckSight.lua" ~/.config/gamescope/scripts/
                    ;;
                "Brightness Wrangler")
                    mkdir_all ~/.config/systemd/user/
                    cp -v "$tmp_dir/brightness-wrangler/brightness-wrangler.service" ~/.config/systemd/user/
                    cp -av "$tmp_dir/brightness-wrangler/brightness-wrangler.sh" ~/.local/bin/
                    systemctl --user daemon-reload
                    systemctl --user enable brightness-wrangler.service
                    systemctl --user restart brightness-wrangler.service
                    ;;
            esac
        done
    fi

    read -r current_bios_version < /sys/class/dmi/id/bios_version
    current_bios_version="${current_bios_version//[$'\r\n']}"

    if [[ "$current_bios_version" != "$PATCHED_BIOS_VERSION" ]]; then
        zenity --title "DeckSight" --warning \
               --text="Detected older BIOS version: ${current_bios_version}.\n\
This installer will install the current patched BIOS version: ${PATCHED_BIOS_VERSION}.\n\
This is expected if you are updating."
    fi

    if ! zenity --title "DeckSight" --question --text "Proceed with BIOS update to DeckSight ${PATCHED_BIOS_VERSION}?"; then
        exit 0
    fi

    tmp_dir=$(mktemp -d)
    # BIOS already extracted from release tarball above

    bios_fd_path=$(find "$tmp_dir/bios" -type f -name '*.fd' | head -n 1)

    if [[ -z "$bios_fd_path" ]]; then
        zenity --title "DeckSight" --error --text "No .fd BIOS file found in release archive."
        exit 1
    fi

    zenity --title "DeckSight" --info \
           --text="Installing BIOS:\n$(basename "$bios_fd_path")"

    pass=$(zenity --title "DeckSight" --password --title="Enter sudo password")
    echo "$pass" | sudo -S /usr/share/jupiter_bios_updater/h2offt "$bios_fd_path"
}

main "$@"
