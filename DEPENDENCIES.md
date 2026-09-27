# Dependencies

The list of dependencies lives in [`dependencies.json`](dependencies.json) at the
repo root. That file is the single source of truth: `remote-install.sh`,
`scripts/check-deps.sh` and this page all describe the same set, because they all
read it. The tables below are a rendering of it.

## Adding or changing a dependency

Add an entry to `dependencies.json` and nothing else. Do not add a `check` line
to `remote-install.sh` — it no longer has a list of its own.

```json
{
  "id": "hypridle",
  "check": { "bin": "hypridle" },
  "pkg": ["hypridle"],
  "why": "idle / DPMS lock integration alongside the built-in keep-awake"
}
```

`check` is how presence is detected, and which form to use matters:

| Form | Use for | Satisfied when |
| --- | --- | --- |
| `{ "bin": "x" }` | a normal executable | `x` is on `$PATH` |
| `{ "bins": ["a", "b"] }` | one feature needing several tools | **all** of them are present |
| `{ "anyBin": ["a", "b"] }` | interchangeable alternatives | **at least one** is present |
| `{ "service": "unit" }` | a feature gated on a running daemon | `systemctl is-active` says the unit is running |
| `{ "path": "…" }` | something with no executable, e.g. a QML module | **any one** of the space-separated patterns matches |

Two of these exist because `command -v` is the wrong tool for the job, which is
the whole reason a manifest was needed rather than a shell loop:

- **`path`** — a dependency delivered as a QML module directory has no binary to
  find at all, so a `bin` check can never detect it.
- **`service`** — some dependencies are a running daemon, not a program.
  `power-profiles-daemon` is the case in point: the package ships
  `/usr/bin/powerprofilesctl` and no binary called `power-profiles-daemon`, and
  the shell gates the feature on the *unit* being active. Checking for a binary
  with the package's name would report it missing forever on a system where it is
  installed and running. Installed-but-stopped deliberately still reads as
  missing, because the feature is equally unavailable.

The same trap applies to `pkg`: it must name what actually provides the thing.
`bluetoothctl` comes from `bluez-utils`, not `bluez`, so a report that told
users to install `bluez` would be sending them after the wrong package.

### Other distributions

**Detecting** what is installed is distribution-independent. `command -v` finds a
binary the same way on every system, and `path` takes a *list* of patterns
precisely because the Qt module directory is not in one place:

| Distribution | Qt 6 QML modules |
| --- | --- |
| Arch | `/usr/lib/qt6/qml` |
| Fedora | `/usr/lib64/qt6/qml` |
| Debian / Ubuntu | `/usr/lib/x86_64-linux-gnu/qt6/qml` |

So a module entry lists them all, and is satisfied if any one matches:

```json
{ "path": "/usr/lib*/qt6/qml/M3Shapes /usr/lib/*/qt6/qml/M3Shapes" }
```

The **list** is what does that work, not the glob. In bash's pathname expansion
`*` stops at `/`, so `/usr/lib*/qt6/qml/Foo` reaches Arch and Fedora but never
Debian's extra `x86_64-linux-gnu` component; the second pattern is what covers
it. A leading `~/` or `$HOME/` is expanded. Hardcoding one absolute path would
report every Fedora and Debian user as missing something they have.

`service` assumes systemd, which is the only init the shell itself is written
against.

**Advice**, unlike detection, is not distribution-independent, so the install
command is detected (`pacman`, `apt-get`, `dnf`, `zypper`, `apk`, `xbps-install`,
`emerge`, `brew`) and each entry may override its package names per manager,
because plenty of them genuinely differ:

```json
"pkg":     ["bluez-utils"],
"pkgAlt":  { "apt-get": ["bluez"], "dnf": ["bluez"], "zypper": ["bluez"] }
```

`pkg` stays the Arch name and is the fallback everywhere else, which is right on
Arch and at worst a recognisable hint elsewhere. When no package manager is
recognised the report lists bare names rather than inventing a command nobody
can run. A wrong guess can only make the *suggested command* wrong — never the
verdict about what is missing.

`"nudge": true` on an optional entry makes the installer mention it when absent;
without it the entry is documented and reported but not printed at install time.

## Checking what you have

```sh
scripts/check-deps.sh          # what is missing; exits 1 if something required is
scripts/check-deps.sh --all    # also list missing optional dependencies
scripts/check-deps.sh --page   # write a full HTML report and open it
```

`--json` prints a single line of JSON, which is what the in-app check under
**Appearance → Update** reads, so the pill and the terminal always agree.

The check is a shell script rather than part of the shell on purpose. The update
it guards against can introduce a dependency whose absence stops the shell from
loading at all — an unresolvable QML import — and code that fails to load cannot
report its own missing dependencies. So it runs from the update path, in a
process, against the outgoing shell that is still alive, immediately before the
reload. It is bounded by `timeout` so a hung notification server cannot strand
the surface on "Updating...".

It notifies and opens the report **at most once per distinct set of missing
required dependencies**, tracked in `$XDG_STATE_HOME/ukishima/deps-notified`. A
dependency you have not installed yet therefore stays quiet across restarts
instead of re-notifying every login. A new set, or a manual check, reports again.

`jq` is both the parser for the manifest and one of the dependencies it reports
on. Rather than duplicating the list to cover that case, the check says plainly
that `jq` is missing and how to fix it; `remote-install.sh` checks the manifest
independently, so a fresh install is unaffected.

## Core

Missing any of these breaks a feature the shell is expected to have.

| Tool | Package | Used for |
| --- | --- | --- |
| `quickshell` | `quickshell` | the shell runtime itself — nothing starts without it |
| `hyprctl` | `hyprland` | IPC for workspaces, monitors, dispatch and reload |
| `notify-send` | `libnotify` | desktop notifications for the pill and for these dependency reports |
| `jq` | `jq` | JSON parsing in the helper scripts, and for reading this manifest |
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
reported after an update.

| Package | Adds |
| --- | --- |
| `gpu-screen-recorder` | the screen-recording backend — recording is disabled without it |
| `mpvpaper` | animated / video wallpapers |
| `matugen` | Material base16 palettes (always-dark terminal theme, dynamic wallpaper palette) |
| `ddcutil` | monitor brightness via DDC (external display faders) |
| `kdialog` / `zenity` | the native folder picker for the record output directory |
| `power-profiles-daemon` | the power-profile picker on the battery hover — the row shows "Not installed" without it, and it isn't needed on desktops. Checked as a *running unit*, not a binary |
| `kitty` | live terminal palette reload via `kitty @ set-colors` (needs `allow_remote_control yes`, and `include ~/.cache/ukishima/kitty-colors` for persistence) |
| `ghostty` | live terminal palette reload over D-Bus |
| `fastfetch` | the recoloured system readout (needs `~/.config/fastfetch/config.jsonc.in`) |
| `hypridle` | idle / DPMS lock integration alongside the built-in keep-awake |
