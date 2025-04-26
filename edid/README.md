# EDID Files contained here.

edid.bin is the base-only EDID that is patched into the DeckSight BIOS. decksight_edid.bin is an EDID with the CEA extension block that can be used by kernel parameter loading

## Usage
Place decksight_edid.bin in /lib/firmware/edid/decksight_edid.bin

Add drm.edid_firmware=eDP-1:edid/decksight_edid.bin to end of GRUB_CMDLINE_LINUX_DEFAULT= in /etc/default/grub

sudo update-grub
sudo mkinitcpio -P

## Notes
The external EDID location is the typical Linux directory and is used because it is loaded early enough in the boot process to take over for the hardware EDID but it is overwritten by SteamOS updates.

Currently SteamOS on the LCD Steam Deck does not respect HDR EDID triggers even when loading an external EDID. This may be from the way the GPU driver is compiled. Otherwise on an external connector, it seems that Gamescope will trigger HDR controls based on some colorimetry data or HDR metadata in the CEA extension block. However it is not recognized as "HDR capable" unless BT2020 colorimetry is present. BT2020 in the EDID being enabled will cause color wash out. The correct mix of bridge/panel reconfigurations to make Gamescope happy with HDR is unknown, but since it's currently not respected on the eDP connector it is left out of the extended EDID to prevent the washout issue. The external EDID currently does not serve any useful purpose.
