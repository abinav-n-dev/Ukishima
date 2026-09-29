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

    /**
     * Whether the leading mark is on screen, which decides where the title
     * sits. Mirrors SettingsRow: a row with no icon puts its label at 12, and
     * one with an icon puts it at 44, so the header has to move with it or the
     * two columns stop lining up the moment glyphs are switched off.
     */
    readonly property bool glyphShown: Flags.showGlyphs && head.glyph.length > 0

    // Where the title sits, in SettingsRow's units. Not free choices — they are
    // that component's insets, read off its anchors:
    //   with an icon: icon left 14, width 17 -> right edge 31, label at 31 + 13 -> 44
    //   with neither: label at 12
    // If the icon width, or the icon-to-label gap, changes in SettingsRow, these
    // two numbers have to move with it or every settings surface goes crooked
    // again. Kept as literals rather than a shared constant because the two
    // components deliberately do not know about each other.
    readonly property real labelInset: 44
    readonly property real bareLabelInset: 12

    Text {
        id: headTitle
        //* On the label's guide, so the header word and the row words share a
        //* left edge. This is what a Row could not do: inside a Row the title
        //* follows the glyph by a fixed gap, which lands it at ~24 — between
        //* the icons and the labels, aligned with neither, which is how it read
        //* before.
        anchors.left: parent.left
        anchors.leftMargin: (head.glyphShown ? head.labelInset : head.bareLabelInset) * head.s
        anchors.verticalCenter: parent.verticalCenter
        text: head.title
        color: head.subInk
        font.family: Theme.font
        font.pixelSize: 10 * head.s
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.6 * head.s
    }

    Text {
        //* Hanging off the title's left edge rather than sitting on the icon
        //* guide, so the kanji and the word keep the 8*s gap they always had
        //* and still read as one mark. Putting it on the icon guide instead
        //* would leave a 30*s hole between the two and split the header in
        //* half — the word is what has to line up, not the kanji.
        anchors.right: headTitle.left
        anchors.rightMargin: 8 * head.s
        anchors.verticalCenter: parent.verticalCenter
        visible: head.glyphShown
        text: head.glyph
        color: head.ink
        font.family: Theme.fontJp
        font.weight: Font.Medium
        font.pixelSize: 16 * head.s
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
