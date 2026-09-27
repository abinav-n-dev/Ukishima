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
        if (!manageIdle)
            return;
        if (applyProc.running)
            return;
        applyProc.command = ["sh", root.idleScript, String(Flags.idleLockMin), String(Flags.idleScreenOffMin), String(Flags.idleSuspendMin)];
        applyProc.running = true;
    }

    /**
     * One discrete step for the keyboard path, so arrow keys behave exactly
     * like clicking [−]/[+] — and still apply at most one write per press.
     */
    function stepIdle(current, dir, step, from, to, commit) {
        if (!manageIdle)
            return;
        const lo = Math.ceil(from / step) * step;
        const hi = Math.floor(to / step) * step;
        const snapped = Math.round(current / step) * step;
        const v = Math.max(lo, Math.min(hi, snapped + dir * step));
        if (v === snapped)
            return;
        commit(v);
        root.applyIdle();
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
            root.stepIdle(Flags.idleLockMin, dir, 1, 0, 60, function (v) { Flags.idleLockMin = v; });
        } },
        { item: screenMinRow, kind: "scrub", bump: function (dir) {
            root.stepIdle(Flags.idleScreenOffMin, dir, 2, 0, 120, function (v) { Flags.idleScreenOffMin = v; });
        } },
        { item: suspendMinRow, kind: "scrub", bump: function (dir) {
            root.stepIdle(Flags.idleSuspendMin, dir, 5, 0, 240, function (v) { Flags.idleSuspendMin = v; });
        } }
    ]

    Process {
        id: readProc

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = root.parseIdle(text);
                if (!parts)
                    return;
                if (Flags.idleLockMin !== parts[0])
                    Flags.idleLockMin = parts[0];
                if (Flags.idleScreenOffMin !== parts[1])
                    Flags.idleScreenOffMin = parts[1];
                if (Flags.idleSuspendMin !== parts[2])
                    Flags.idleSuspendMin = parts[2];
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
            id: manageRow
            surface: root
            name: "Manage timeouts"
            icon: "cog"
            sub: manageIdle ? "Shell writes hypridle.conf" : "Read-only · edit hypridle.conf"

            LinkToggle {
                s: root.s
                on: root.manageIdle
                onToggled: root.manageIdle = !root.manageIdle
            }
        }

        SettingsRow {
            id: lockMinRow
            surface: root
            name: "Lock after"
            icon: "lock"
            sub: lockMinText

            MinuteStep {
                s: root.s
                interactive: root.manageIdle
                value: Flags.idleLockMin
                from: 0
                to: 60
                step: 1
                onPicked: (v) => {
                    Flags.idleLockMin = v;
                    root.applyIdle();
                }
            }
        }

        SettingsRow {
            id: screenMinRow
            surface: root
            name: "Screen off after"
            icon: "sun"
            sub: screenMinText

            MinuteStep {
                s: root.s
                interactive: root.manageIdle
                value: Flags.idleScreenOffMin
                from: 0
                to: 120
                step: 2
                onPicked: (v) => {
                    Flags.idleScreenOffMin = v;
                    root.applyIdle();
                }
            }
        }

        SettingsRow {
            id: suspendMinRow
            surface: root
            name: "Suspend after"
            icon: "moon"
            sub: suspendMinText
            last: true

            MinuteStep {
                s: root.s
                interactive: root.manageIdle
                value: Flags.idleSuspendMin
                from: 0
                to: 240
                step: 5
                onPicked: (v) => {
                    Flags.idleSuspendMin = v;
                    root.applyIdle();
                }
            }
        }
    }
    /**
     * Master switch for writing hypridle.conf. Off by default, and while it is
     * off nothing on this surface can touch the file: the rows are read-only and
     * applyIdle() returns immediately. Turning it on is an explicit statement
     * that the shell owns the idle timeouts from here on.
     */
    property bool manageIdle: false

    readonly property string lockMinText: Flags.idleLockMin === 0 ? "Never" : "Idle " + Flags.idleLockMin + " min"
    readonly property string screenMinText: Flags.idleScreenOffMin === 0 ? "Never" : "Idle " + Flags.idleScreenOffMin + " min"
    readonly property string suspendMinText: Flags.idleSuspendMin === 0 ? "Never" : "Idle " + Flags.idleSuspendMin + " min"

    /** Square [-] / [+] nudge button; `live` greys it out at a bound. */
    component NudgeButton: Rectangle {
        id: nb

        property real s: 1
        property string glyph: ""
        property bool live: true

        signal tapped()

        width: 22 * s
        height: 20 * s
        radius: 6 * s
        color: nb.live ? Theme.tileBg : "transparent"
        border.width: 1
        border.color: Theme.border
        opacity: nb.live ? 1 : 0.3

        Text {
            anchors.centerIn: parent
            text: nb.glyph
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 13 * nb.s
        }

        MouseArea {
            anchors.fill: parent
            enabled: nb.live
            cursorShape: Qt.PointingHandCursor
            onClicked: nb.tapped()
        }
    }

    /**
     * Discrete minute stepper: [-] value [+]. Buttons rather than a slider on
     * purpose. A drag emits onMoved per pixel, and every one of those would
     * rewrite hypridle.conf and bounce the idle daemon, so dragging from 5 to
     * 30 could restart it a dozen times. One click, one value, one restart.
     * The row's sub-text carries the "Idle N min" wording.
     */
    component MinuteStep: Row {
        id: ms

        property real s: 1
        property int value: 0
        property int from: 0
        property int to: 100
        property int step: 1
        property bool interactive: true
        signal picked(int v)

        spacing: 6 * s
        opacity: interactive ? 1 : 0.45

        readonly property int snapped: Math.round(value / step) * step
        readonly property int lowBound: Math.ceil(from / step) * step
        readonly property int highBound: Math.floor(to / step) * step

        function bump(dir) {
            const v = Math.max(lowBound, Math.min(highBound, snapped + dir * step));
            if (v !== snapped)
                ms.picked(v);
        }

        NudgeButton {
            s: ms.s
            glyph: "\u2212"
            live: ms.interactive && ms.snapped > ms.lowBound
            onTapped: ms.bump(-1)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 32 * ms.s
            horizontalAlignment: Text.AlignRight
            text: ms.snapped === 0 ? "Off" : ms.snapped + "m"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 11 * ms.s
            font.features: { "tnum": 1 }
        }

        NudgeButton {
            s: ms.s
            glyph: "+"
            live: ms.interactive && ms.snapped < ms.highBound
            onTapped: ms.bump(1)
        }
    }
}
