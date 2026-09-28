pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../Singletons"
import "../components"

/**
 * 錠 LOCK sub-surface: how the session lock looks — which lock script runs,
 * the backdrop, blur and indicator toggles. The lock itself runs as a separate
 * process (lockscreen/) that cannot import ../Singletons, so its presentation
 * flags live in the shared flags.json and the lock reads them back on start.
 * Reached from the Appearance index and folds back to it on the back chevron
 * or an empty click.
 */
SettingsSurface {
    id: root

    backSurface: "appearance"
    implicitHeight: content.implicitHeight

    // ── Avatar path helpers ────────────────────────────────────────────
    //
    // The lock is a separate process and reads this flag verbatim, so what is
    // stored here has to survive being turned into a `file://` URL by a QML
    // Image over there. Two things that is sensitive to:

    readonly property string homeDir: Quickshell.env("HOME") || ""
    //* `~` and `~/x` are what a person actually types, and the placeholder
    //* used to advertise exactly that. A `file://` URL does not expand a
    //* leading tilde, though: the Image just sits at status=Null forever and
    //* the avatar silently never appears. Verified — `file://~/...` loads as
    //* status 0, the same path with $HOME substituted loads as status 1.
    //* Expand here so the flag is always an absolute path.
    function expandPath(p) {
        const t = (p === undefined || p === null) ? "" : String(p).trim();
        if (t === "")
            return "";
        if (t === "~")
            return homeDir;
        if (t.indexOf("~/") === 0)
            return homeDir + t.slice(1);
        return t;
    }

    //* The default is ~/.face, which is a fairly obscure convention and is
    //* not where a picker will ever start you. The stored empty string means
    //* "use the default", so this is only ever the label.
    readonly property string avatarPlaceholder: homeDir + "/.face"
    readonly property string avatarStored: expandPath(Flags.lockAvatarPath)
    //* Does the path we would actually use resolve to a real file? Checked
    //* with a FileView rather than assumed, so a typo shows up here instead of
    //* as a blank circle on the lock screen.
    //*
    //* `loaded` is the whole signal: true for a file that exists, false for
    //* one that does not. `loadFailed` is a *signal* here, not a property, so
    //* reading it yields a function object — which is truthy, and would have
    //* marked every path invalid. And text() is no use either: it is the
    //* file's contents, so a JPEG returns kilobytes of binary.
    readonly property bool avatarValid: avatarProbe.loaded
    readonly property string avatarSub: {
        if (Flags.lockAvatarPath.trim() === "")
            return "default: " + avatarPlaceholder;
        if (!avatarValid)
            return "no such file: " + avatarStored;
        return avatarStored;
    }

    FileView {
        id: avatarProbe
        //* No ?v= cache-busting here. That trick is for Image, which latches
        //* an Error on a missing file and will not re-read the same URL; this
        //* is a FileView, and a query string on a file:// URL makes it fail
        //* outright — verified: the same path loads with `loaded=true` plain
        //* and `loaded=false` with `?v=12345` appended, which reported a real
        //* wallpaper as "no such file".
        //*
        //* The path is a binding on avatarStored, and the flag only changes
        //* when the user commits an edit, so it re-arms on exactly the events
        //* that matter without needing to defeat any cache.
        path: root.avatarStored !== "" ? "file://" + root.avatarStored : ""
        printErrors: false
    }

    function commitAvatar(raw) {
        Flags.lockAvatarPath = expandPath(raw);
    }

    //* Open a file manager at the current path so it is easy to *find* the
    //* image, then paste the path in. This build of Quickshell has no Qt file
    //* dialog and the repo has no portal client, so a chooser that returns a
    //* selection would mean adding a dependency for it. xdg-open is the
    //* honest, dependency-free half of the job: the field accepts a typed or
    //* pasted path, and this just gets you to the right directory. If
    //* avatarStored is a file, its parent is what you want open.
    function browseAvatar() {
        //* xdg-open on a *file* opens it in the default viewer, which is not
        //* what you want here — you want the folder to pick the next one from.
        let dir = homeDir + "/Pictures";
        if (avatarStored !== "" && avatarStored.indexOf("/") >= 0)
            dir = avatarStored.substring(0, avatarStored.lastIndexOf("/")) || "/";
        browseProc.command = ["xdg-open", dir];
        browseProc.running = true;
    }

    Process {
        id: browseProc
        running: false
    }

    rows: [
        { item: methodRow, kind: "seg", vals: ["hyprlock", "quickshell"], get: function () { return Flags.lockMethod; }, set: function (v) { Flags.lockMethod = v; } },
        { item: bgRow, kind: "seg", vals: ["capture", "wallpaper", "solid"], get: function () { return Flags.lockBackground; }, set: function (v) { Flags.lockBackground = v; } },
        { item: blurRow, kind: "seg", vals: [0, 32, 64, 96], get: function () { return Flags.lockBlur; }, set: function (v) { Flags.lockBlur = v; } },
        { item: avatarRow, kind: "toggle", get: function () { return Flags.lockShowAvatar; }, set: function (v) { Flags.lockShowAvatar = v; } },
        { item: avatarPathRow, kind: "text", get: function () { return Flags.lockAvatarPath; }, set: function (v) { Flags.lockAvatarPath = v; } },
        { item: wifiRow, kind: "toggle", get: function () { return Flags.lockShowWifi; }, set: function (v) { Flags.lockShowWifi = v; } },
        { item: batteryRow, kind: "toggle", get: function () { return Flags.lockShowBattery; }, set: function (v) { Flags.lockShowBattery = v; } }
    ]

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "錠"
            title: "LOCK"
            showBack: true
        }

        Item { width: 1; height: 12 * root.s }

        SettingsRow {
            id: methodRow
            surface: root
            name: "Lock method"
            icon: "lock"
            sub: "Quickshell lockscreen or plain hyprlock"

            SettingsSeg {
                s: root.s
                options: [
                    { label: "Hyprlock", value: "hyprlock" },
                    { label: "Quickshell", value: "quickshell" }
                ]
                value: Flags.lockMethod
                onPicked: (v) => Flags.lockMethod = v
            }
        }

        SettingsRow {
            id: bgRow
            surface: root
            name: "Background"
            icon: "wallpaper"

            SettingsSeg {
                s: root.s
                options: [
                    { label: "Capture", value: "capture" },
                    { label: "Wallpaper", value: "wallpaper" },
                    { label: "Solid", value: "solid" }
                ]
                value: Flags.lockBackground
                onPicked: (v) => Flags.lockBackground = v
            }
        }

        SettingsRow {
            id: blurRow
            surface: root
            name: "Blur"
            icon: "droplet"
            sub: "Background blur strength"
            enabled: Flags.lockBackground === "capture"

            SettingsSeg {
                s: root.s
                options: [
                    { label: "Off", value: 0 },
                    { label: "Low", value: 32 },
                    { label: "Med", value: 64 },
                    { label: "High", value: 96 }
                ]
                value: Flags.lockBlur
                onPicked: (v) => Flags.lockBlur = v
            }
        }

        SettingsRow {
            id: avatarRow
            surface: root
            name: "Avatar"
            icon: "dot"

            LinkToggle {
                s: root.s
                on: Flags.lockShowAvatar
                onToggled: Flags.lockShowAvatar = !Flags.lockShowAvatar
            }
        }

        SettingsRow {
            id: avatarPathRow
            surface: root
            //* Not "Avatar" — the row above already owns that label, and two
            //* rows with the same name read as a rendering bug. This is the
            //* *source* behind the toggle, so that is what it is called.
            name: "Image"
            icon: "image"
            sub: root.avatarSub

            TextField {
                id: avatarField
                width: 168 * root.s
                //* Seeded once, never bound. Binding `text` to the flag while
                //* also writing the flag from onTextChanged makes the field
                //* fight the writer: every keystroke writes flags.json, the
                //* file watcher reloads, and the bound text is reassigned
                //* under the cursor. It only looked stable because the value
                //* round-tripped to the same string. Half-typed paths are
                //* written and persisted as you go, so an abandoned edit is
                //* indistinguishable from a committed one.
                text: Flags.lockAvatarPath
                placeholderText: root.avatarPlaceholder
                selectByMouse: true
                onEditingFinished: root.commitAvatar(text)
                //* Escape abandons the edit and puts the stored value back.
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) {
                        text = Flags.lockAvatarPath;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        root.commitAvatar(text);
                        e.accepted = true;
                    }
                }
            }

            //* "Browse" opens a file manager at the current path so you can
            //* navigate to the image. It cannot hand the selection back — see
            //* browseAvatar(). The field stays the source of truth.
            Label {
                id: browseLabel
                text: "browse"
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                color: browseMouse.containsMouse ? Theme.accent : Theme.dim

                MouseArea {
                    id: browseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.browseAvatar()
                }
            }
        }

        SettingsRow {
            id: wifiRow
            surface: root
            name: "Wifi indicator"
            icon: "wifi"

            LinkToggle {
                s: root.s
                on: Flags.lockShowWifi
                onToggled: Flags.lockShowWifi = !Flags.lockShowWifi
            }
        }

        SettingsRow {
            id: batteryRow
            surface: root
            name: "Battery indicator"
            icon: "bolt"

            LinkToggle {
                s: root.s
                on: Flags.lockShowBattery
                onToggled: Flags.lockShowBattery = !Flags.lockShowBattery
            }
        }

    }
}
