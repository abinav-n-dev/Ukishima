import QtQuick
import "../Singletons"

/**
 * Settings surface header: the surface kanji (gated by Flags.showGlyphs) and its
 * uppercase title on the left, with a cog at the index or a back chevron on a
 * sub-surface at the right. The header strip is the back target, but the click is
 * handled at the host level (a press anywhere on the top strip steps the surface
 * back), so this is a pure visual.
 *
 * `pal` is the host's SettingsPalette; null means the pill's own tokens, which
 * is every pill surface. The dock's settings panel passes the dock's palette.
 */
Item {
    id: head

    property real s: 1
    property string glyph: ""
    property string title: ""
    property bool showBack: false
    property var pal: null

    readonly property color ink: head.pal ? head.pal.ink : Theme.cream
    readonly property color subInk: head.pal ? head.pal.sub : Theme.subtle
    readonly property color iconInk: head.pal ? head.pal.sub : Theme.iconDim

    width: parent ? parent.width : 0
    height: 22 * head.s

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * head.s

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: Flags.showGlyphs && head.glyph.length > 0
            text: head.glyph
            color: head.ink
            font.family: Theme.fontJp
            font.weight: Font.Medium
            font.pixelSize: 16 * head.s
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: head.title
            color: head.subInk
            font.family: Theme.font
            font.pixelSize: 10 * head.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.6 * head.s
        }
    }

    GlyphIcon {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 16 * head.s
        height: 16 * head.s
        name: head.showBack ? "chevron-left" : "cog"
        color: head.iconInk
        stroke: head.showBack ? 2.2 : 1.7
    }
}
