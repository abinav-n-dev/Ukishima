# AGENTS.md — Ukishima (quickshell/Hyprland shell)

This tree is **upstream [amanhex/Ukishima](https://github.com/amanhex/Ukishima)** (`master`
@ `17aef08`) plus exactly two local additions that are deliberately kept:

| Local addition | What it is |
| --- | --- |
| `Polkit.qml` + `components/polkit/` | built-in polkit authentication agent (no hyprpolkitagent/polkit-gnome) |
| `lockscreen/` + `scripts/lock.sh` | Quickshell session-lock screen (upstream ships `exec hyprlock` instead) |

Everything else — `Pill.qml`, `shell.qml`, `Singletons/`, `components/`, `surfaces/`,
`lib/`, `modules/`, the other `scripts/` — is upstream, unmodified. Keep it that way:
pull upstream instead of forking it again. Two tracked files carry local edits
(`shell.qml` — one `Polkit { }` mount; `scripts/lock.sh` — the QS lockscreen launcher);
`git diff` should only ever show those.

## Git remotes and contributing

| Remote | URL | Role |
| --- | --- | --- |
| `origin` | `git@github.com:bry-ly/Ukishima-V2.git` (SSH) | your fork — push here |
| `upstream` | `https://github.com/amanhex/Ukishima.git` | the real project — read-only, PR target |

`master` = `upstream/master` + exactly two local commits (`05b4f0e` the two additions
above, plus a docs commit for this file). `local/polkit-lockscreen` points at `05b4f0e`
as a restore handle; `local-rice-backup-20260927-110206` holds the pre-swap fork (island,
settings app, widgets) in case any of it is ever wanted back.

Take upstream updates with `git fetch upstream && git rebase upstream/master` (two
commits to replay, both additive; conflicts can only land in `shell.qml` /
`scripts/lock.sh`), then kill and relaunch the shell.

To contribute upstream, never branch off `master` — branch off `upstream/master` so the
PR carries only your change:

```bash
git fetch upstream
git switch -c <topic> upstream/master
# …edit, then: git push -u origin <topic>
```

Then open the PR from `bry-ly/Ukishima-V2:<topic>` → `amanhex/Ukishima:master`.

## Run / reload / verify

- Launch only via `./launch.sh -d` (sets jemalloc decay; plain `quickshell --config` skips
  it). QML edits need kill-then-relaunch, not a second backgrounded launch:
  `PID=$(pgrep -x quickshell | head -1); kill $PID; sleep 2; ./launch.sh -d`
- Never `pkill -f` (self-matches). Never run `qs -p lockscreen/shell.qml` to "test" it —
  it locks the session; lint it instead.
- Lint: `QML_IMPORT_PATH=/usr/lib/qt6/qml /usr/lib/qt6/bin/qmllint <files>`; ignore
  Quickshell-unknown noise (`unresolved-type`, `missing-property`, `unqualified`,
  `uncreatable`, etc.). Format with `qmlformat -i`.
- Open/close a surface non-interactively: `qs -p <path> ipc call ukishima page "" <name>`
  then `... hide`. Runtime errors: `strings $(ls -t /run/user/$UID/quickshell/by-id/*/log.qslog
  | head -1) | grep -a -e TypeError -e ReferenceError`.
- JS lib test: `node lib/monitors.test.mjs`.

## Architecture

- `shell.qml`: per-monitor `reserve` (exclusive-zone strip) + `overlay` (full-screen layer
  hosting one morphing `Pill`). The pill is never re-parented; every surface grows out of
  it. Input routing lives in the window mask.
- `Pill.qml`, `surfaces/` (one file per surface), `components/` (reusable UI), `Singletons/`
  (state backends), `scripts/` (wallpaper/theme/record helpers), `lib/` (plain JS + node
  test), `modules/` (Hyprland `decoration.lua` snippet).
- New QML files must be registered in the nearest `qmldir`: `singleton Name Name.qml` in
  `Singletons/qmldir`, bare `Name Name.qml` in `components/qmldir` — otherwise imports
  silently fail.
- Persisted flags: `Singletons/Flags.qml` ↔ `$XDG_STATE_HOME/ukishima/flags.json`
  (FileView, watchChanges); the adapter rewrites the file with only its own keys, so keys
  from older versions disappear on their own. Disk cache under `~/.cache/ukishima`.
- Hyprland IPC is expensive: `shell.qml` `refreshEvents` allowlist gates the triple model
  refresh (monitors/workspaces/toplevels) — add event names there, don't refresh
  unconditionally.
- `Hyprland.dispatch` strings use Lua syntax (Hyprland 0.55+):
  `'hl.dsp.window.move({ workspace = "…", window = "address:…" })'`.

## Local addition: polkit agent

- `shell.qml` mounts `Polkit { }` as a child of the `ShellRoot`. That mount is the only
  thing that instantiates the agent — with it removed, `Polkit.qml` is never loaded (a
  config directory only auto-loads `shell.qml`, never sibling root files) and polkitd
  silently falls back to a textual agent.
- `Polkit.qml` is a `Scope`: one `PolkitAgent` (registers on D-Bus by itself) plus one
  `PolkitDialog` per `Quickshell.screens`; only the focused monitor's dialog activates.
- `components/polkit/` is self-contained — `MsTheme.qml` is a local singleton with its own
  palette, so the dialog never touches `Singletons/`. It does need the system-wide
  `M3Shapes` module (`/usr/lib/qt6/qml/M3Shapes`).
- Known-benign log noise: `MsText at @components/polkit/PolkitDialog.qml[683/703] Cannot
  anchor to an item that isn't a parent or sibling`.
- `~/.config/hypr/modules/rules.lua` has the matching
  `namespace = "ukishima-polkit"` layer rule (blur, no_anim). Keep it.

## Local addition: lockscreen

- `lockscreen/` is a **separate ShellRoot** launched by `scripts/lock.sh`
  (`hypridle` lock_cmd → that script). It cannot import `../Singletons` or
  `../components`; shared art must be ported self-contained.
- `LockContext.qml` wraps `PamContext` (`lockscreen/pam/password.conf`) and owns the
  typed text, failure banner and the `unlocked()` / `failed()` signals.
- `Image` SVG loads fail silently in the lockscreen process — use baked `ShapePath`
  vectors there. `LockBattery.qml` / `LockWifi.qml` are hand-rolled for that reason and
  must not grow a dependency on `../components`.
- `scripts/lock.sh` is a deliberate override of upstream's one-liner: it grim-captures the
  desktop first (ScreencopyView inside ext-session-lock is racy on Hyprland/NVIDIA), then
  `exec`s `quickshell -p lockscreen/shell.qml`, logging to `/tmp/ukishima-lock.log`; if
  quickshell or the file is missing it falls back to `hyprlock`. If you `git checkout`
  this file the lockscreen silently degrades to hyprlock.

## Gotchas

- **`FileView.text` is a method at runtime, not a property.** Call it: `text()`.
  `quickshell-core.qmltypes` declares it as a read-only `Property`, and `qmllint`
  is happy either way, so `text.trim()` type-checks and then dies at runtime with
  `TypeError: Property 'trim' of object function text() { [native code] } is not a
  function`. It throws inside the `onLoaded` handler, so the assignment silently
  never happens and the fallback path is used instead — which is how the lockscreen
  kept showing a months-old wallpaper. Copy `sharedFlags.text()` in
  `lockscreen/LockSurface.qml`, which is known to work.
- `qmlformat` normalizes on save (`//*` comments, `return ;` spacing) — derive `edit`
  `oldString` from current file bytes and keep boundaries small.
- Battery: UPower `percentage` is 0–1 (`frac`), so `pct = round(frac*100)`; sysfs
  `Not charging` maps to full. Name charge state `chargeState`, never `state` (clashes
  with `QQuickItem.state`).
- Palette: `scripts/wallcolors.py` writes `~/.cache/ukishima/colors.json`; external apps
  consume that file rather than being rewritten (e.g. `~/.config/hypr/colors.conf` sources
  it directly). Keep it that way — never overwrite a user's own config file.
