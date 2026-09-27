pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "../Singletons"
import "../components"

/**
 * 錠 LOCK sub-surface: how the session lock looks. The lock itself runs as a
 * separate process (lockscreen/) that cannot import ../Singletons, so these
 * flags live in the shared flags.json and the lock reads them back on start.
 * Reached from the Appearance index and folds back to it on the back chevron
 * or an empty click.
 */
SettingsSurface {
    id: root

    backSurface: "appearance"
    implicitHeight: content.implicitHeight

    rows: [
        { item: bgRow, kind: "seg", vals: ["capture", "wallpaper", "solid"], get: function () { return Flags.lockBackground; }, set: function (v) { Flags.lockBackground = v; } },
        { item: blurRow, kind: "seg", vals: [0, 32, 64, 96], get: function () { return Flags.lockBlur; }, set: function (v) { Flags.lockBlur = v; } },
        { item: avatarRow, kind: "toggle", get: function () { return Flags.lockShowAvatar; }, set: function (v) { Flags.lockShowAvatar = v; } },
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
            id: bgRow
            surface: root
            name: "Background"
            icon: "image"

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
            icon: "user"

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
            icon: "battery"
            last: true

            LinkToggle {
                s: root.s
                on: Flags.lockShowBattery
                onToggled: Flags.lockShowBattery = !Flags.lockShowBattery
            }
        }
    }
}
