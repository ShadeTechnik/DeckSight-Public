# Brightness-Wrangler

SteamOS on the Steam Deck uses X11 for it's desktop mode display server. In order to control the display brightness via software we must use the brightness-wrangler service

## Usage
- move brightness-wrangler.sh to `~/.local/bin/`
- create directory `~/.config/systemd/user/`
- move brightness-wrangler.service to `~/.config/systemd/user/`
- run the following:
    - `$ chmod +x ~/.local/bin/brightness-wrangler.sh`
    - `$ systemctl --user daemon-reload`
    - `$ systemctl --user enable brightness-wrangler.service`
    - `$ systemctl --user start brightness-wrangler.service`
