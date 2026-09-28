pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
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
            name: "Avatar path"
            icon: "image"
            sub: "Leave empty for ~/.face"

            TextField {
                text: Flags.lockAvatarPath
                placeholderText: "~/.face"
                onTextChanged: Flags.lockAvatarPath = text
                width: 180 * root.s
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
