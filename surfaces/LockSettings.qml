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

    //* The lock has no default avatar path — it used to be ~/.face, an i3lock
    //* convention that does not exist on most systems, so the default resolved
    //* to a blank grey circle. Empty means no image and the lock draws a
    //* person glyph. This is the resting hint in the field.
    readonly property string avatarPlaceholder: "no image"
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
    //* Deliberately short. The field itself renders the path, so repeating it
    //* here just wrapped to two lines and crowded out the row. What the field
    //* cannot say is whether the path resolved and what an empty flag means.
    readonly property string avatarSub: {
        if (Flags.lockAvatarPath.trim() === "")
            return "unset, so the lock shows a person glyph";
        if (!avatarValid)
            return "no such file";
        return "";
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

    /**
     * Leave the avatar field, either committing what was typed or throwing it
     * away. Both paths only close the field — on abandon the flag was never
     * touched, so there is nothing to roll back, and on commit the new value
     * is already written. Drops focus explicitly, or the TextInput keeps the
     * key handler alive and the next Return lands in a field nobody is in.
     */
    function endAvatarEdit(commit, typed) {
        if (commit)
            commitAvatar(typed);
        avatarPathRow.editing = false;
        if (avatarInput.focus)
            avatarInput.focus = false;
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
            //* While editing, the sub explains how to get out of the field,
            //* the same way the wallpaper folder row does. At rest it reports
            //* the one thing the box cannot: whether the path resolved, and
            //* what an empty flag means.
            sub: avatarPathRow.editing ? "Return to save · Esc to cancel" : root.avatarSub
            captionOnFocus: true

            property bool editing: false

            //* Same click-to-edit affordance as the wallpaper folder field
            //* (surfaces/ThemeSurface.qml wpDirField, surfaces/Wallpaper.qml
            //* dirField): resting, the row shows the stored path dimmed and
            //* middle-elided; a click swaps in a TextInput seeded with the
            //* value, and Enter commits while Escape abandons. Reused rather
            //* than a bare TextField because a permanently-open input invites
            //* the question of what is live — here the resting state is the
            //* committed value and there is only one way in.
            Item {
                //* Fixed width, not the wallpaper row's 26 → 200 collapse.
                //* That row shrinks because a GlyphIcon stands in for the text
                //* when idle; here the resting state *is* the path, so there
                //* is nothing to collapse to and animating it would just make
                //* the value you are reading flicker.
                width: 190 * root.s
                height: 26 * root.s

                Rectangle {
                    anchors.fill: parent
                    radius: 9 * root.s
                    color: Qt.alpha(Theme.frameBg, 0.7)
                    border.width: 1
                    border.color: avatarInput.activeFocus ? Qt.alpha(Theme.vermLit, 0.7) : Theme.hairSoft
                }

                //* The committed value at rest. Shown in the box rather than
                //* only in the sub-caption, because the sub wraps to two lines
                //* on a real path and that is a lot to ask anyone to read back.
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 10 * root.s
                    rightPadding: 10 * root.s
                    visible: !avatarPathRow.editing
                    text: root.avatarStored.length > 0 ? root.avatarStored : root.avatarPlaceholder
                    elide: Text.ElideMiddle
                    color: avatarFieldHover.hovered ? Theme.subtle : Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                TextInput {
                    id: avatarInput
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10 * root.s
                    anchors.rightMargin: 10 * root.s
                    visible: avatarPathRow.editing
                    enabled: avatarPathRow.editing
                    clip: true
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                    selectByMouse: true
                    selectionColor: Theme.verm

                    Keys.onPressed: (e) => {
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            root.endAvatarEdit(true, text);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Escape) {
                            root.endAvatarEdit(false, "");
                            e.accepted = true;
                        }
                    }

                    //* While typing, show the current committed value as a
                    //* ghost so the field is never just blank.
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: avatarInput.text.length === 0
                        text: root.avatarStored.length > 0 ? root.avatarStored : root.avatarPlaceholder
                        elide: Text.ElideMiddle
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                    }
                }

                HoverHandler {
                    id: avatarFieldHover
                    enabled: !avatarPathRow.editing
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !avatarPathRow.editing
                    cursorShape: Qt.IBeamCursor
                    onClicked: {
                        avatarPathRow.editing = true;
                        //* Seeded from the flag, not from avatarStored, so an
                        //* escape and a re-edit show what is actually stored.
                        avatarInput.text = Flags.lockAvatarPath;
                        Qt.callLater(avatarInput.forceActiveFocus);
                    }
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
