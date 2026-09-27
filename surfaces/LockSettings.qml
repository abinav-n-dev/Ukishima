pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../Singletons"
import "../components"

/**
 * 錠 LOCK sub-surface: how the session lock looks, and when it engages. The lock
 * itself runs as a separate process (lockscreen/) that cannot import
 * ../Singletons, so its presentation flags live in the shared flags.json and the
 * lock reads them back on start. The idle timeouts are different again: they
 * belong to hypridle, so they are read from and written to its config by
 * scripts/lock-idle.sh rather than persisted here. Reached from the Appearance
 * index and folds back to it on the back chevron or an empty click.
 */
SettingsSurface {
    id: root

    backSurface: "appearance"
    implicitHeight: content.implicitHeight

    readonly property string idleScript: Config.hyprPath("scripts", "lock-idle.sh")

    /** hypridle refuses a 0 timeout as "never", so 0 is spelled as off = 0 here. */
    function applyIdle() {
        if (applyProc.running)
            return;
        applyProc.command = ["sh", root.idleScript, String(Flags.idleLockMin), String(Flags.idleScreenOffMin), String(Flags.idleSuspendMin)];
        applyProc.running = true;
    }

    /** Pull the live timeouts so the rows show what hypridle is really doing. */
    function readIdle() {
        if (readProc.running)
            return;
        readProc.command = ["sh", root.idleScript, "--read"];
        readProc.running = true;
    }

    rows: [
        { item: bgRow, kind: "seg", vals: ["capture", "wallpaper", "solid"], get: function () { return Flags.lockBackground; }, set: function (v) { Flags.lockBackground = v; } },
        { item: blurRow, kind: "seg", vals: [0, 32, 64, 96], get: function () { return Flags.lockBlur; }, set: function (v) { Flags.lockBlur = v; } },
        { item: avatarRow, kind: "toggle", get: function () { return Flags.lockShowAvatar; }, set: function (v) { Flags.lockShowAvatar = v; } },
        { item: wifiRow, kind: "toggle", get: function () { return Flags.lockShowWifi; }, set: function (v) { Flags.lockShowWifi = v; } },
        { item: batteryRow, kind: "toggle", get: function () { return Flags.lockShowBattery; }, set: function (v) { Flags.lockShowBattery = v; } },
        { item: lockMinRow, kind: "scrub", bump: function (dir) {
            lockMin.value = Math.max(0, Math.min(60, lockMin.value + dir));
            Flags.idleLockMin = lockMin.value;
            root.applyIdle();
        } },
        { item: screenMinRow, kind: "scrub", bump: function (dir) {
            screenMin.value = Math.max(0, Math.min(120, screenMin.value + dir * 2));
            Flags.idleScreenOffMin = screenMin.value;
            root.applyIdle();
        } },
        { item: suspendMinRow, kind: "scrub", bump: function (dir) {
            suspendMin.value = Math.max(0, Math.min(240, suspendMin.value + dir * 5));
            Flags.idleSuspendMin = suspendMin.value;
            root.applyIdle();
        } }
    ]

    Process {
        id: readProc

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = root.parseIdle(text);
                if (!parts)
                    return;
                if (lockMin.value !== parts[0]) {
                    lockMin.value = parts[0];
                    Flags.idleLockMin = parts[0];
                }
                if (screenMin.value !== parts[1]) {
                    screenMin.value = parts[1];
                    Flags.idleScreenOffMin = parts[1];
                }
                if (suspendMin.value !== parts[2]) {
                    suspendMin.value = parts[2];
                    Flags.idleSuspendMin = parts[2];
                }
            }
        }
    }

    Process {
        id: applyProc
    }

    /** "<lock> <screen> <suspend>" in minutes, or null if the script said nothing usable. */
    function parseIdle(out) {
        const bits = String(out || "").trim().split(/\s+/);
        if (bits.length < 3)
            return null;
        const nums = [];
        for (let i = 0; i < 3; i++) {
            const v = parseInt(bits[i], 10);
            if (isNaN(v) || v < 0)
                return null;
            nums.push(v);
        }
        return nums;
    }

    Component.onCompleted: root.readIdle()

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

        SettingsRow {
            id: lockMinRow
            surface: root
            name: "Lock after"
            icon: "lock"
            sub: lockMin.value === 0 ? "Never" : "Idle " + lockMin.value + " min"

            Item {
                width: lockPct.width + 10 * root.s + 120 * root.s
                height: 52 * root.s

                Row {
                    anchors.top: parent.top
                    anchors.topMargin: 8 * root.s
                    spacing: 10 * root.s

                    Text {
                        id: lockPct

                        anchors.verticalCenter: parent.verticalCenter
                        width: 30 * root.s
                        horizontalAlignment: Text.AlignRight
                        text: lockMin.value === 0 ? "Off" : lockMin.value + "m"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.features: { "tnum": 1 }
                    }

                    Slider {
                        id: lockMin

                        width: 120 * root.s
                        height: 26 * root.s
                        from: 0
                        to: 60
                        stepSize: 1
                        onMoved: {
                            Flags.idleLockMin = value;
                            root.applyIdle();
                        }
                        Component.onCompleted: value = Flags.idleLockMin

                        background: Rectangle {
                            y: lockMin.availableHeight / 2 - 2 * root.s
                            width: lockMin.availableWidth
                            height: 4 * root.s
                            radius: 2 * root.s
                            color: Theme.tileBg
                            border.width: 1
                            border.color: Theme.hairSoft
                        }
                        handle: Rectangle {
                            x: lockMin.leftPadding + lockMin.visualPosition * (lockMin.availableWidth - width)
                            y: lockMin.availableHeight / 2 - height / 2
                            width: 14 * root.s
                            height: 14 * root.s
                            radius: width / 2
                            color: Theme.verm
                            border.width: 2 * root.s
                            border.color: Theme.cream
                            Behavior on x { NumberAnimation { duration: Motion.fast } }
                        }
                    }
                }
            }
        }

        SettingsRow {
            id: screenMinRow
            surface: root
            name: "Screen off after"
            icon: "sun"
            sub: screenMin.value === 0 ? "Never" : "Idle " + screenMin.value + " min"

            Item {
                width: screenPct.width + 10 * root.s + 120 * root.s
                height: 52 * root.s

                Row {
                    anchors.top: parent.top
                    anchors.topMargin: 8 * root.s
                    spacing: 10 * root.s

                    Text {
                        id: screenPct

                        anchors.verticalCenter: parent.verticalCenter
                        width: 30 * root.s
                        horizontalAlignment: Text.AlignRight
                        text: screenMin.value === 0 ? "Off" : screenMin.value + "m"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.features: { "tnum": 1 }
                    }

                    Slider {
                        id: screenMin

                        width: 120 * root.s
                        height: 26 * root.s
                        from: 0
                        to: 120
                        stepSize: 2
                        onMoved: {
                            Flags.idleScreenOffMin = value;
                            root.applyIdle();
                        }
                        Component.onCompleted: value = Flags.idleScreenOffMin

                        background: Rectangle {
                            y: screenMin.availableHeight / 2 - 2 * root.s
                            width: screenMin.availableWidth
                            height: 4 * root.s
                            radius: 2 * root.s
                            color: Theme.tileBg
                            border.width: 1
                            border.color: Theme.hairSoft
                        }
                        handle: Rectangle {
                            x: screenMin.leftPadding + screenMin.visualPosition * (screenMin.availableWidth - width)
                            y: screenMin.availableHeight / 2 - height / 2
                            width: 14 * root.s
                            height: 14 * root.s
                            radius: width / 2
                            color: Theme.verm
                            border.width: 2 * root.s
                            border.color: Theme.cream
                            Behavior on x { NumberAnimation { duration: Motion.fast } }
                        }
                    }
                }
            }
        }

        SettingsRow {
            id: suspendMinRow
            surface: root
            name: "Suspend after"
            icon: "moon"
            sub: suspendMin.value === 0 ? "Never" : "Idle " + suspendMin.value + " min"
            last: true

            Item {
                width: suspendPct.width + 10 * root.s + 120 * root.s
                height: 52 * root.s

                Row {
                    anchors.top: parent.top
                    anchors.topMargin: 8 * root.s
                    spacing: 10 * root.s

                    Text {
                        id: suspendPct

                        anchors.verticalCenter: parent.verticalCenter
                        width: 30 * root.s
                        horizontalAlignment: Text.AlignRight
                        text: suspendMin.value === 0 ? "Off" : suspendMin.value + "m"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.features: { "tnum": 1 }
                    }

                    Slider {
                        id: suspendMin

                        width: 120 * root.s
                        height: 26 * root.s
                        from: 0
                        to: 240
                        stepSize: 5
                        onMoved: {
                            Flags.idleSuspendMin = value;
                            root.applyIdle();
                        }
                        Component.onCompleted: value = Flags.idleSuspendMin

                        background: Rectangle {
                            y: suspendMin.availableHeight / 2 - 2 * root.s
                            width: suspendMin.availableWidth
                            height: 4 * root.s
                            radius: 2 * root.s
                            color: Theme.tileBg
                            border.width: 1
                            border.color: Theme.hairSoft
                        }
                        handle: Rectangle {
                            x: suspendMin.leftPadding + suspendMin.visualPosition * (suspendMin.availableWidth - width)
                            y: suspendMin.availableHeight / 2 - height / 2
                            width: 14 * root.s
                            height: 14 * root.s
                            radius: width / 2
                            color: Theme.verm
                            border.width: 2 * root.s
                            border.color: Theme.cream
                            Behavior on x { NumberAnimation { duration: Motion.fast } }
                        }
                    }
                }
            }
        }
    }
}
