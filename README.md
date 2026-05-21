# DeckSight-Public
 DeckSight BIOS and utillities
 
## Preferred Method
- Go to https://www.shadetechnik.com/decksight-bios-inst, download the DeckSight.desktop.download file and follow the instructions. That is a downloader script that will automate the process of downloading the
release from this repo, flashing the BIOS, etc. This repo does not contain general instructions for installation, it contains the sources for some utillities and the release package itself.

## Components
 
- ## Brightness-wrangler
    - Note: This is a legacy service that creates a software brightness adjustment in the Desktop mode as hardware control was not possible at release. This will likely be removed in favor of [decksight-brightnessctrl](https://github.com/ShadeTechnik/DeckSight-Public/discussions/41).
      decksight-brightnessctrl is a hardware brightness adjustment. It has been tested but has not made it's way into a new installer yet. The recommendation is to just leave Brightness-wrangler uchecked when running the installer and install decksight-brightnessctrl as explained in the thread.
    - Service that monitors the AMDGPU backlight interface and applies a gamma based brightness control through xrandr
    - Brightness-wrangler only works in X11, which means it will not work on Bazzite etc,
    
- ## DeckSight.lua Gamescope script.
    - Adds modesetting and incrimental frame limits for DeckSight. SteamOS current Stable (3.7.8) has a version of gamescope that supports lua scripts in user directories. Older versions of SteamOS may not work with it. In that case the frame limit slider will only work in about 20hz incriments. 
    
- ## EDID
    - edid.bin is just here for reference. It is the binary version of the EDID that is patched into the BIOS. decksight_edid.bin is an EDID file with CEA extension that Gamescope will reference to enable HDR support. 
    
- ## DeckSight.icc ICC profile.
    - This ICC profile was generated with a colorimeter and provides good color representation for SDR in X11 based desktops (SteamOS), it can otherwise be a bit over saturated. There is currently no good way to apply it in SteamOS as KDE Plasma on X11 does not support ICC profiles unless the packages colord and colord-kde are installed but these packages are outside of SteamOS repos. Enabling the holo repo will allow the installation of these packages but in SteamOS they won't survive an update. Once colord and colord-kde are installed the ICC profile can easily be applied from display settings. 
    - If using an alternate OS like Bazzite, which uses KDE Plasma under Wayland, the icc profile can be applied from display settings, however it is probably unnecessary in that case. Enabling "Wide Color Gamut" makes the color accurate. Due to the hardware EDID limitation of the LCD Steam Deck, KDE Plasma may not pick up the wide color gamut abillity, otherwise it can be enabled from display settings. kscreen-doctor can also enable wide color gamut if it can see the display as "capable" which it may not. In either case, the icc profile can be applied easily in display settings in KDE/Wayland based Desktops. An ICC profile has no effect in Gamescope/Game UI
    
- # Installation (Outside of the download script above)
    - Make sure sudo password is set in SteamOS before running
    - install.sh is a Zenity based graphical installer.
    - It will first allow installing the "extras" (Gamescope script and brightness-wrangler). Then it will install the BIOS
    
- ## Manual install
    - It's fairly easy to install all components manually just by following the readme's in each component's directory.
