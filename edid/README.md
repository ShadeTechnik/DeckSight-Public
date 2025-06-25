# EDID Files contained here.

edid.bin is the base-only EDID that is patched into the DeckSight BIOS. decksight_edid.bin is an EDID with the CEA extension block that can be used by kernel parameter loading or parsed into Gamescope for HDR support

## Usage
### Kernel override (Not recommended) 
Place decksight_edid.bin in /lib/firmware/edid/decksight_edid.bin

Add drm.edid_firmware=eDP-1:edid/decksight_edid.bin to end of GRUB_CMDLINE_LINUX_DEFAULT= in /etc/default/grub

sudo update-grub
sudo mkinitcpio -P

### For Gamescope (Recommended)
Create directory and place decksight_edid.bin in ~/.local/share/decksight/

Create directory and place decksight-edid.conf in ~/.config/environment.d/ - This file creates an environment variable which redirects gamescope to parse this extended EDID that can't (easily) be included in the Steam Deck's BIOS

$ systemctl --user daemon-reexec

## Notes
If used via a kernel parameter, decksight_edid.bin becomes the system-wide EDID. The kernel parameter override is a typical Linux way of doing it but it's not recommended for the Steam Deck. Directing Gamescope towards the EDID is really all that is necessary as only Gamescope really cares about the extension block in SteamOS. The Gamescope method will also survive updates, which the kernel method will not on an immutable OS.
