import QtQuick
import QtQuick.Shapes

/**
 * Self-contained replacement for import M3Shapes.
 *
 * The password dot-morph (each typed char pops in as a random
 * shape, then settles to a dot) and the enter button both used
 * MaterialShape, a compiled AUR git package (qt6-m3shapes-git).
 * On any machine without that package LockSurface.qml failed to
 * load and quickshell exited 255, making the session-lock
 * fallback unreachable and leaving the screen unlocked. Baking
 * the 16 shapes here removes that dependency entirely.
 *
 * The enum values and the order of the 16 shape names mirror
 * MaterialShape exactly, so the shapeQueue and the enter-button
 * logic that reference them stay byte-identical; only the
 * backing path data changed.
 */
QtObject {
    property int shapeType: ShapeType.Circle
    property color shapeColor: "white"

    readonly property string circle: "M20.13,10.26 Q20.60,12.00 19.91,14.56 Q19.45,16.30 17.57,18.18 Q16.30,19.45 13.74,20.13 Q12.00,20.60 9.44,19.91 Q7.70,19.45 5.82,17.57 Q4.55,16.30 3.87,13.74 Q3.40,12.00 4.09,9.44 Q4.55,7.70 6.43,5.82 Q7.70,4.55 10.26,3.87 Q12.00,3.40 14.56,4.09 Q16.30,4.55 18.18,6.43 Q19.45,7.70 20.13,10.26 Z"
    readonly property string slanted: "M5.00,10.80 Q5.00,9.00 19.20,9.00 Q21.00,9.00 21.00,13.20 Q21.00,15.00 6.80,15.00 Q5.00,15.00 5.00,10.80 Z"
    readonly property string arch: "M4.80,23.00 Q3.00,23.00 3.00,12.80 Q3.00,11.00 19.20,11.00 Q21.00,11.00 21.00,21.20 Q21.00,23.00 4.80,23.00 Z"
    readonly property string diamond: "M10.73,3.27 Q12.00,2.00 20.73,10.73 Q22.00,12.00 13.27,20.73 Q12.00,22.00 3.27,13.27 Q2.00,12.00 10.73,3.27 Z"
    readonly property string triangle: "M19.84,11.10 Q21.40,12.00 8.86,19.24 Q7.30,20.14 7.30,5.66 Q7.30,3.86 19.84,11.10 Z"
    readonly property string pentagon: "M19.54,10.54 Q20.60,12.00 15.72,18.72 Q14.66,20.18 6.75,17.61 Q5.04,17.05 5.04,8.75 Q5.04,6.95 12.95,4.38 Q14.66,3.82 19.54,10.54 Z"
    readonly property string gem: "M10.80,3.34 Q12.00,2.00 19.80,10.66 Q21.00,12.00 13.20,20.66 Q12.00,22.00 4.20,13.34 Q3.00,12.00 10.80,3.34 Z"
    readonly property string clamShell: "M10.86,4.39 Q12.00,3.00 19.86,12.61 Q21.00,14.00 13.42,19.89 Q12.00,21.00 4.42,15.11 Q3.00,14.00 10.86,4.39 Z"
    readonly property string cookie4Sided: "M4.00,6.20 Q4.00,4.00 17.80,4.00 Q20.00,4.00 20.00,17.80 Q20.00,20.00 6.20,20.00 Q4.00,20.00 4.00,6.20 Z"
    readonly property string ghostish: "M9.14,3.58 Q10.00,2.00 18.33,5.33 Q20.00,6.00 20.78,12.21 Q21.00,14.00 17.05,19.54 Q16.00,21.00 8.79,20.20 Q7.00,20.00 4.71,14.65 Q4.00,13.00 9.14,3.58 Z"
    readonly property string fan: "M12,12 L4,12 A8,8 0 0,1 20,12 Z"
    readonly property string arrow: "M12,3 L21,14 L17,14 L17,21 L7,21 L7,14 L3,14 Z"
    readonly property string semiCircle: "M4,24 A8,8 0 0,1 20,24 Z"
    readonly property string sunny: "M12.00,0.50 L13.27,5.62 L16.40,1.38 L15.61,6.60 L20.13,3.87 L17.40,8.39 L22.62,7.60 L18.38,10.73 L23.50,12.00 L18.38,13.27 L22.62,16.40 L17.40,15.61 L20.13,20.13 L15.61,17.40 L16.40,22.62 L13.27,18.38 Z"
    readonly property string verySunny: "M12.00,-0.50 L12.85,5.56 L15.24,-0.07 L14.49,5.99 L18.25,1.17 L15.96,6.84 L20.84,3.16 L17.16,8.04 L22.83,5.75 L18.01,9.51 L24.07,8.76 L18.44,11.15 L24.50,12.00 L18.44,12.85 L24.07,15.24 L18.01,14.49 L22.83,18.25 L17.16,15.96 L20.84,20.84 L15.96,17.16 L18.25,22.83 L14.49,18.01 L15.24,24.07 L12.85,18.44 Z"
    readonly property string softBurst: "M12.00,1.00 L13.37,5.13 L16.21,1.84 L15.89,6.18 L19.78,4.22 L17.82,8.11 L22.16,7.79 L18.87,10.63 L23.00,12.00 L18.87,13.37 L22.16,16.21 L17.82,15.89 L19.78,19.78 L15.89,17.82 L16.21,22.16 L13.37,18.87 Z"

    function pathString(int shape) {
        switch (shape) {
            case Shape.Circle: return circle
            case Shape.Slanted: return slanted
            case Shape.Arch: return arch
            case Shape.Fan: return fan
            case Shape.Arrow: return arrow
            case Shape.SemiCircle: return semiCircle
            case Shape.Triangle: return triangle
            case Shape.Diamond: return diamond
            case Shape.ClamShell: return clamShell
            case Shape.Pentagon: return pentagon
            case Shape.Gem: return gem
            case Shape.Sunny: return sunny
            case Shape.VerySunny: return verySunny
            case Shape.Cookie4Sided: return cookie4Sided
            case Shape.Ghostish: return ghostish
            case Shape.SoftBurst: return softBurst
            default: return Circle
        }
    }
}
