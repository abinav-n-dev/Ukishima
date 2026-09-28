# Dependencies

The list lives in [`dependencies.json`](dependencies.json) at the repo root, which
`remote-install.sh` and `scripts/check-deps.sh` both read. The tables below are a
rendering of it.

## Checking what you have

```sh
scripts/check-deps.sh          # what is missing; exits 1 if something required is
scripts/check-deps.sh --all    # also list missing optional dependencies
scripts/check-deps.sh --page   # write a full HTML report and open it
```

`--json` prints a single line of JSON, which is what the in-app check under
**Appearance → Update** reads, so the pill and the terminal always agree. The
report is opened at most once per distinct set of missing required dependencies,
so something you have not installed yet stays quiet across restarts.

## Core

Missing any of these breaks a feature the shell is expected to have.

| Tool | Package | Used for |
| --- | --- | --- |
| `quickshell` | `quickshell` | the shell runtime itself — nothing starts without it |
| `hyprctl` | `hyprland` | IPC for workspaces, monitors, dispatch and reload |
| `notify-send` | `libnotify` | desktop notifications for the pill and for these dependency reports |
| `jq` | `jq` | JSON parsing in the helper scripts, and for reading the manifest |
| `xdg-open` | `xdg-utils` | opening files and links, including the dependency report page |
| `upower` | `upower` | battery status and charge reporting |
| `bluetoothctl` | `bluez-utils` | the bluetooth surface |
| `nmcli` | `networkmanager` | the wifi surface |
| `brightnessctl` | `brightnessctl` | internal laptop backlight control |
| `hyprsunset` | `hyprsunset` | the night light |
| `awww + awww-daemon` | `awww` | the wallpaper backend (client and daemon) |
| `curl + magick + python3 + ffmpeg` | `curl`, `imagemagick`, `python`, `ffmpeg` | wallpaper download, thumbnails, palette generation and video-wallpaper stills |
| `cava` | `cava` | the music visualiser |
| `cliphist + wl-paste` | `cliphist`, `wl-clipboard` | the clipboard history surface |
| `slurp` | `slurp` | the window/region picker for screen recording |

## Optional, for full functionality

These only add features. Nothing breaks without them, and nothing here is
reported after an update. The first few are also named by the installer when it
runs, because they are commonly wanted.

| Package | Adds |
| --- | --- |
| `gpu-screen-recorder` | the screen-recording backend — recording is disabled without it |
| `mpvpaper` | animated / video wallpapers |
| `matugen` | Material base16 palettes (always-dark terminal theme, dynamic wallpaper palette) |
| `ddcutil` | monitor brightness via DDC (external display faders) |
| `kdialog` / `zenity` | the native folder picker for the record output directory |
| `power-profiles-daemon` | the power-profile picker on the battery hover — the row shows "Not installed" without it, and it isn't needed on desktops. Checked as a *running unit*, not a binary |
| `hyprlock` | the default lock backend — without it the lock falls back to the built-in Quickshell one, and the LOCK settings surface hides the option |
| `grim` | the screen capture behind the lock's capture backdrop — without it that backdrop falls back to the wallpaper |
| `kitty` | live terminal palette reload via `kitty @ set-colors` (needs `allow_remote_control yes`, and `include ~/.cache/ukishima/kitty-colors` for persistence) |
| `ghostty` | live terminal palette reload over D-Bus |
| `fastfetch` | the recoloured system readout (needs `~/.config/fastfetch/config.jsonc.in`) |
| `hypridle` | idle / DPMS lock integration alongside the built-in keep-awake |
