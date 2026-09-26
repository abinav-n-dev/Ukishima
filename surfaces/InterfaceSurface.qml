pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "../Singletons"
import "../components"

/**
 * 面 INTERFACE sub-surface: general shell behaviour that is not tied to the
 * clock, the theme or the dock — the UI scale, reduced motion, whether the pill
 * auto-hides, and the memory saver. Reached from the Appearance index and folds
 * back to it on the back chevron or an empty click. Dock settings live on their
 * own 泊 DOCK sub-surface.
 */
SettingsSurface {
    id: root

    backSurface: "appearance"
    implicitHeight: content.implicitHeight

    rows: [
        { item: scaleRow, kind: "seg", vals: [0.9, 1.0, 1.1, 1.25], get: function () { return Flags.uiScale; }, set: function (v) { Flags.uiScale = v; } },
        { item: pillWRow, kind: "scrub", bump: function (dir) {
            wPill.value = Math.max(wPill.from, Math.min(wPill.to, wPill.value + dir * 0.05));
            Flags.pillW = wPill.value;
        } },
        { item: pillHRow, kind: "scrub", bump: function (dir) {
            hPill.value = Math.max(hPill.from, Math.min(hPill.to, hPill.value + dir * 0.05));
            Flags.pillH = hPill.value;
        } },
        { item: motionRow, kind: "toggle", get: function () { return Flags.reduceMotion; }, set: function (v) { Flags.reduceMotion = v; } },
        { item: autoHideRow, kind: "toggle", get: function () { return Flags.autoHide; }, set: function (v) { Flags.autoHide = v; } },
        { item: saverRow, kind: "toggle", get: function () { return Flags.memorySaver; }, set: function (v) { Flags.memorySaver = v; } }
    ]

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "面"
            title: "INTERFACE"
            showBack: true
        }

        Item { width: 1; height: 12 * root.s }

        SettingsRow {
            id: scaleRow
            surface: root
            name: "UI scale"
            icon: "scaling"

            SettingsSeg {
                s: root.s
                options: [{ label: "90%", value: 0.9 }, { label: "100%", value: 1.0 }, { label: "110%", value: 1.1 }, { label: "125%", value: 1.25 }]
                value: Flags.uiScale
                onPicked: (v) => Flags.uiScale = v
            }
        }

        /**
         * Resting pill sizing, independent of the global UI scale. The resting face
         * is a fixed 160x38px grid scaled by the monitor factor, so these are
         * plain multipliers around 100%; the pill resizes live as the slider drags.
         * The reserve band under a non-auto-hide pill follows the height factor.
         */
        SettingsRow {
            id: pillWRow
            surface: root
            name: "Pill width"
            icon: "scaling"
            sub: "Resting width · " + Math.round(Flags.pillW * 100) + "%"

            Item {
                width: wPct.width + 10 * root.s + 120 * root.s
                height: 52 * root.s

                Row {
                    anchors.top: parent.top
                    anchors.topMargin: 8 * root.s
                    spacing: 10 * root.s

                    Text {
                        id: wPct
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30 * root.s
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(Flags.pillW * 100) + "%"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.features: { "tnum": 1 }
                    }

                    Slider {
                        id: wPill
                        width: 120 * root.s
                        height: 26 * root.s
                        from: 0.8
                        to: 1.5
                        stepSize: 0.05
                        onMoved: Flags.pillW = value
                        Component.onCompleted: value = Flags.pillW

                        background: Rectangle {
                            y: wPill.availableHeight / 2 - 2 * root.s
                            width: wPill.availableWidth
                            height: 4 * root.s
                            radius: 2 * root.s
                            color: Theme.tileBg
                            border.width: 1
                            border.color: Theme.hairSoft
                        }
                        handle: Rectangle {
                            x: wPill.leftPadding + wPill.visualPosition * (wPill.availableWidth - width)
                            y: wPill.availableHeight / 2 - height / 2
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

                // Live feedback while the panel covers the bar: the miniature
                // resting pill morphs with the slider.
                RestPill {
                    s: root.s
                    wFactor: Flags.pillW
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6 * root.s
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        SettingsRow {
            id: pillHRow
            surface: root
            name: "Pill height"
            icon: "scaling"
            sub: "Resting height · " + Math.round(Flags.pillH * 100) + "%"

            Item {
                width: hPct.width + 10 * root.s + 120 * root.s
                height: 52 * root.s

                Row {
                    anchors.top: parent.top
                    anchors.topMargin: 8 * root.s
                    spacing: 10 * root.s

                    Text {
                        id: hPct
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30 * root.s
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(Flags.pillH * 100) + "%"
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                        font.features: { "tnum": 1 }
                    }

                    Slider {
                        id: hPill
                        width: 120 * root.s
                        height: 26 * root.s
                        from: 0.8
                        to: 1.5
                        stepSize: 0.05
                        onMoved: Flags.pillH = value
                        Component.onCompleted: value = Flags.pillH

                        background: Rectangle {
                            y: hPill.availableHeight / 2 - 2 * root.s
                            width: hPill.availableWidth
                            height: 4 * root.s
                            radius: 2 * root.s
                            color: Theme.tileBg
                            border.width: 1
                            border.color: Theme.hairSoft
                        }
                        handle: Rectangle {
                            x: hPill.leftPadding + hPill.visualPosition * (hPill.availableWidth - width)
                            y: hPill.availableHeight / 2 - height / 2
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

                // Live feedback while the panel covers the bar: the miniature
                // resting pill morphs with the slider.
                RestPill {
                    s: root.s
                    hFactor: Flags.pillH
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6 * root.s
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        SettingsRow {
            id: motionRow
            surface: root
            name: "Reduce motion"
            icon: "waves"

            LinkToggle {
                s: root.s
                on: Flags.reduceMotion
                onToggled: Flags.reduceMotion = !Flags.reduceMotion
            }
        }

        SettingsRow {
            id: autoHideRow
            surface: root
            name: "Auto hide"
            icon: "eye-off"

            LinkToggle {
                s: root.s
                on: Flags.autoHide
                onToggled: Flags.autoHide = !Flags.autoHide
            }
        }

        SettingsRow {
            id: saverRow
            surface: root
            name: "Memory saver"
            icon: "stopwatch"
            last: true

            LinkToggle {
                s: root.s
                on: Flags.memorySaver
                onToggled: Flags.memorySaver = !Flags.memorySaver
            }
        }
    }
}
