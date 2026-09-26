pragma Singleton
import QtQuick
import Quickshell

/**
 * Pill palette. Two sources: the curated light/dark hex below is the identity
 * and the default, used whenever the theme is on Light or Dark. On Dynamic the
 * surfaces and the whole accent ramp follow the wallpaper through the matugen-fed
 * `Dyn` singleton (Manual feeds it a user-picked hue through wallcolors.py), while
 * the text family, light veils and shadow stay locked here so copy keeps its
 * contrast on any generated background. Each token is a single ternary, so the
 * static modes render byte-identical to the fixed themes and only the colours
 * that should breathe with the wallpaper do.
 */
Singleton {
    /** Legacy "static" (the old warm-brown theme) maps onto the black pill. */
    readonly property string mode: Flags.paletteMode === "static" ? "dark" : Flags.paletteMode
    readonly property bool dyn: mode === "dynamic" || mode === "manual"
    readonly property bool light: mode === "light"

    /**
     * User accent override: a "#rrggbb" hex, empty to follow the scheme. When set
     * it wins for every warm token below (verm ramps, flame ink, charging glow,
     * today cell) no matter what the palette mode derives, and the container pair
     * is rebuilt with darker/lighter math since an arbitrary accent has no
     * material container colours of its own.
     */
    readonly property string customHex: Flags.accentOverride
    readonly property bool customAccent: customHex.length > 0
    /** Effective accent base — the override, else the wallpaper/hue accent, else the warm default. */
    readonly property color accent: customAccent ? customHex : (dyn ? Dyn.primary : "#ff9a64")
    /** Deep pair, standing in where the scheme has a matugen container colour. */
    readonly property color accentDeep: customAccent ? Qt.darker(accent, 1.45) : (dyn ? Dyn.primaryContainer : "#a3371f")

    /**
     * User text-colour override: a "#rrggbb" hex, empty to follow the scheme.
     * When set it wins for the primary text (cream) and the brightest token
     * (bright) on every surface. The muted secondaries (dim, faint, iconDim,
     * subtle, tickRest) keep their own scheme values so sub-copy stays legible
     * beside a custom colour, and the alpha-derived veils (hair, sheen, frame*)
     * follow cream automatically.
     */
    readonly property string customTextHex: Flags.textOverride
    readonly property bool customText: customTextHex.length > 0

    /**
     * Literal "#rrggbb" serialization for the flame canvas ramp, which reads raw
     * hex strings (a color property would serialize to #aarrggbb and corrupt the
     * gradient). The dynamic branch passes matugen's own hex through untouched.
     */
    function hexOf(c) {
        function h(x) { return ("0" + Math.round(x * 255).toString(16)).slice(-2); }
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    /**
     * Bright warm pop shared by the flame glow, charging glyphs, the recording
     * countdown, the unread inbox dot, the calendar's today cell and the held
     * power tile. The dynamic branch uses the wallpaper accent (Dyn.primary):
     * matugen's on-primary-container does not populate here and collapses the
     * token to black, while the accent always loads and contrasts the pill
     * surface. The static branches keep the fixed warm hex.
     */
    readonly property color onGlow: customAccent ? accent : (dyn ? Dyn.primary : "#ff9a64")

    readonly property color verm:     customAccent ? Qt.darker(accent, 1.18) : (dyn ? Qt.darker(Dyn.primary, 1.18) : "#c0442b")
    readonly property color vermLit:  customAccent ? accent : (dyn ? Dyn.primary : "#e0563b")
    readonly property color vermDeep: customAccent ? accentDeep : (dyn ? Dyn.primaryContainer : "#a3371f")
    readonly property color cream:    customText ? customTextHex : (dyn ? Dyn.cream : (light ? "#2a241f" : "#ececec"))
    readonly property color bright:   customText ? customTextHex : (dyn ? Dyn.bright : (light ? "#1d1814" : "#ffffff"))
    readonly property color dim:      dyn ? Dyn.dim : (light ? "#6b635c" : "#8c8c8c")
    readonly property color cardTop:  dyn ? Dyn.surfaceContainerHigh : (light ? "#f6f2ec" : "#171717")
    readonly property color cardBot:  dyn ? Dyn.surfaceContainerLow : (light ? "#ece6df" : "#0c0c0c")
    readonly property color border:   dyn ? Dyn.outlineVariant : (light ? "#d9d1c8" : "#2b2b2b")
    readonly property color shadow:     Qt.rgba(0, 0, 0, 0.55)
    readonly property color tileBg:   dyn ? Dyn.surface : (light ? "#e9e3dc" : "#141414")
    readonly property color subtle:   dyn ? Dyn.subtle : (light ? "#5f574f" : "#a8a8a8")
    readonly property color faint:    dyn ? Dyn.faint : (light ? "#8a8078" : "#6a6a6a")
    readonly property color iconDim:  dyn ? Dyn.iconDim : (light ? "#5a524b" : "#bdbdbd")
    readonly property color hair:     Qt.alpha(cream, 0.13)
    readonly property color hairSoft: Qt.alpha(cream, 0.08)
    readonly property color sheen:    Qt.alpha(cream, 0.07)
    readonly property color vermDim:   customAccent ? Qt.darker(accent, 1.5) : (dyn ? Qt.darker(Dyn.primary, 1.5) : "#8a5440")
    readonly property color vermDimDeep: customAccent ? Qt.darker(accent, 2.2) : (dyn ? Qt.darker(Dyn.primary, 2.2) : "#5a3526")
    readonly property color vermBurn:  customAccent ? Qt.darker(accentDeep, 1.1) : (dyn ? Qt.darker(Dyn.primaryContainer, 1.1) : "#8a2c14")
    readonly property color tickRest:  dyn ? Dyn.tickRest : (light ? "#4a423c" : "#c2c2c2")
    readonly property color threadBg:  Qt.alpha(cream, 0.13)
    readonly property color flameCore: customAccent ? Qt.lighter(accent, 1.03) : (dyn ? Qt.lighter(onGlow, 1.03) : "#ffd9c2")
    readonly property color flameGlow: customAccent ? accent : (dyn ? onGlow : "#ff9a64")

    /**
     * Flame canvas ramp: literal hex strings (color type won't work), fed
     * directly to Canvas addColorStop/strokeStyle. A color property serializes
     * to #aarrggbb and corrupts the gradient render, so the dynamic branch passes
     * matugen's raw hex strings through untouched rather than any Qt.darker math.
     */
    readonly property string flameInk:   customAccent ? customHex : (dyn ? Dyn.primary : "#f0795a")
    readonly property string flameEmber: customAccent ? hexOf(accentDeep) : (dyn ? Dyn.primaryContainer : "#7e2812")
    readonly property string flameBurn:  customAccent ? hexOf(accentDeep) : (dyn ? Dyn.primaryContainer : "#8a2c14")
    readonly property string flameTip:   customAccent ? hexOf(Qt.lighter(accent, 1.2)) : (dyn ? Dyn.onPrimaryContainer : "#ffb38a")
    readonly property color todayWarm: customAccent ? accent : (dyn ? onGlow : "#ffb38a")
    readonly property color ghost:     dyn ? Dyn.surfaceContainerHighest : (light ? "#e3ddd5" : "#242424")
    readonly property color frameBg:      Qt.alpha(cream, 0.055)
    readonly property color frameBorder:  Qt.alpha(cream, 0.10)
    readonly property color creamMenu:     Qt.alpha(cream, 0.82)
    readonly property real shadowOpacity: 0.5
    /**
     * Snapshot of the system families, not a binding: Qt.fontFamilies() is not
     * notifiable, so a font dropped onto the pill re-registers through
     * refreshFonts() once its FontLoader is ready.
     */
    property var fontFamilies: Qt.fontFamilies()
    function refreshFonts() { fontFamilies = Qt.fontFamilies(); }
    readonly property string font: (Flags.uiFont.length > 0 && fontFamilies.indexOf(Flags.uiFont) >= 0) ? Flags.uiFont : "Inter"
    readonly property string fontJp: "Zen Kaku Gothic New"

    /**
     * MPRIS trackArtists arrives as a JS array from some players and as a
     * plain string from others (Spotify); calling join on the string throws
     * and kills the whole binding. Handles both, falls back to trackArtist.
     */
    function joinArtists(artists, single) {
        if (artists && typeof artists.join === "function" && artists.length > 0)
            return artists.join(", ");
        if (artists && String(artists).length > 0)
            return String(artists);
        return single ? String(single) : "";
    }
}
