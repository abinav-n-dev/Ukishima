import QtQuick
import "../Singletons"

/**
 * Miniature of the resting pill for the settings sliders. The real bar is
 * hidden behind the settings panel while a surface is open, so sliders that
 * size the resting shape need this live morph as feedback: it tracks the
 * value in real time while the user drags.
 */
Rectangle {
    id: root

    property real s: 1
    property real wFactor: 1
    property real hFactor: 1

    width: 46 * root.s * wFactor
    height: 11 * root.s * hFactor
    radius: Math.min(width, height) / 2
    color: Qt.alpha(Theme.verm, 0.82)
    border.width: 1
    border.color: Qt.alpha(Theme.cream, 0.28)
    Behavior on width { NumberAnimation { duration: Motion.fast } }
    Behavior on height { NumberAnimation { duration: Motion.fast } }
}