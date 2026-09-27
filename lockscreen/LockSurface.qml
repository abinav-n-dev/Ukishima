import M3Shapes
// Ukishima lockscreen — matches reference image:
// blurred desktop, date + big time top, avatar + bryly + pill bottom.
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Rectangle {
    id: root

    required property LockContext context
    // WlSessionLockSurface passed from shell.qml for per-screen screencopy
    required property var lockSurface
    readonly property string home: Quickshell.env("HOME")
    readonly property string userName: context.userName
    readonly property string facePath: home + "/.face"
    // grim pre-capture from lock.sh (hyprlock screenshot equivalent),
    // then live ukishima wallpaper, then static fallback
    readonly property string lockShot: "/tmp/ukishima-lock.png"
    readonly property string stateWallpaper: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/ukishima-wallpaper"
    readonly property string wallpaperFallback: home + "/Pictures/Wallpapers/current_wallpaper.jpg"
    //* The wallpaper the shell is actually showing, read from the same state
    //* file Singletons/Walls.qml writes (ukishima-wallpaper holds the current
    //* wallpaper's path, one line). The lockscreen runs as its own process and
    //* cannot import Singletons, so it re-reads the file itself. Falls back to
    //* the legacy current_wallpaper.jpg only when that state file is missing.
    property string currentWallpaper: ""
    readonly property string wallpaperSource: currentWallpaper.length > 0 ? currentWallpaper : wallpaperFallback

    //* lock.sh redirects the lock's stderr into /tmp/ukishima-lock.log, so one
    //* console.log per lock says exactly which file the backdrop resolved to and
    //* whether it came from the state file or the legacy fallback. Without it,
    //* "the lock shows the wrong wallpaper" is unanswerable from outside the
    //* session.
    function reportWallpaper(how) {
        console.log("[lock] wallpaper " + how + ": mode=" + background
            + " state=" + stateWallpaper
            + " current=" + (currentWallpaper || "<empty>")
            + " using=" + wallpaperSource
            + " fallbackUsed=" + (currentWallpaper.length === 0));
    }

    // Shuffled dot-morph queue, like polkit's shapeQueue: each typed char
    // pops in as a random shape then settles into a dot.
    readonly property list<int> shapeQueue: {
        const shapes = [MaterialShape.Slanted, MaterialShape.Arch, MaterialShape.Fan, MaterialShape.Arrow, MaterialShape.SemiCircle, MaterialShape.Triangle, MaterialShape.Diamond, MaterialShape.ClamShell, MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Sunny, MaterialShape.VerySunny, MaterialShape.Cookie4Sided, MaterialShape.Ghostish, MaterialShape.SoftBurst];
        for (let i = shapes.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [shapes[i], shapes[j]] = [shapes[j], shapes[i]];
        }
        return shapes;
    }
    readonly property bool fieldInError: context.showFailure
    //* Clock format follows the desktop General setting (DisplaySurface timeRow
    //* -> Flags.time12h), and the lock battery shimmer follows the Battery
    //* surface toggle (Flags.batteryShimmer && !reduceMotion). Read-only: the
    //* lockscreen runs as a separate process that cannot import ../Singletons,
    //* and a partial JsonAdapter must never write back to the shared
    //* flags.json (writeAdapter would clobber every other key) — so this only
    //* parses the file and never writes it.
    property bool use12h: false
    property bool batteryShimmerOn: true
    //* Lock-specific settings, written by the pill's LOCK surface (surfaces/
    //* LockSettings.qml -> Flags -> flags.json) and read back here. Defaults
    //* match the Flags adapter so a missing or partial file keeps today's look.
    property bool showAvatar: true
    property bool showWifi: true
    property bool showBattery: true
    property int blurMax: 64
    //* "capture" grim-captures the desktop at lock time, "wallpaper" uses the
    //* live wallpaper, "solid" paints the opaque backdrop colour.
    property string background: "capture"

    function syncSharedFlags() {
        try {
            var shared = JSON.parse(sharedFlags.text());
            if (shared && typeof shared.time12h === "boolean")
                root.use12h = shared.time12h;

            root.batteryShimmerOn = (!shared || shared.batteryShimmer !== false) && (!shared || shared.reduceMotion !== true);

            if (shared && typeof shared.lockShowAvatar === "boolean")
                root.showAvatar = shared.lockShowAvatar;

            if (shared && typeof shared.lockShowWifi === "boolean")
                root.showWifi = shared.lockShowWifi;

            if (shared && typeof shared.lockShowBattery === "boolean")
                root.showBattery = shared.lockShowBattery;

            if (shared && typeof shared.lockBlur === "number")
                root.blurMax = shared.lockBlur;

            if (shared && ["capture", "wallpaper", "solid"].indexOf(shared.lockBackground) >= 0)
                root.background = shared.lockBackground;
        } catch (e) {
        }
    }

    FileView {
        id: sharedFlags

        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ukishima/flags.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.syncSharedFlags()
        onFileChanged: reload()
        onLoadFailed: {
            root.use12h = false;
            root.batteryShimmerOn = true;
            root.showAvatar = true;
            root.showWifi = true;
            root.showBattery = true;
            root.blurMax = 64;
            root.background = "capture";
        }
    }

    FileView {
        id: wallpaperState

        path: root.stateWallpaper
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.currentWallpaper = text.trim();
            root.reportWallpaper("loaded");
        }
        onFileChanged: reload()
        onLoadFailed: {
            root.currentWallpaper = "";
            root.reportWallpaper("load-failed");
        }
    }

    color: "#0b0d0c"
    focus: true
    Keys.onEscapePressed: context.currentText = ""
    Keys.onEnterPressed: context.tryUnlock()
    Keys.onReturnPressed: context.tryUnlock()
    // exit fade on successful unlock (shell sets closing, then quits)
    opacity: context.closing ? 0 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }

    }

    // entrance choreography, Caelestia initAnim style:
    // backdrop settles (fade + zoom + focus pull), clock drifts down,
    // auth cluster rises — staggered so the lock "assembles" smoothly
    Component.onCompleted: {
        showAnim.start();
        Qt.callLater(() => reportWallpaper("startup"));
    }

    ParallelAnimation {
        id: showAnim

        NumberAnimation {
            target: bgLayer
            property: "opacity"
            from: 0
            to: 1
            duration: 450
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: bgLayer
            property: "scale"
            from: 1.05
            to: 1
            duration: 750
            easing.type: Easing.OutCubic
        }
        //* No blurMax animation here any more. It used to run 64 -> 32 as part
        //* of the entrance, which was fine while blurMax was a literal — but it
        //* is now bound to the user's Blur setting, and an animation assigns
        //* imperatively, which tears that binding out. Every lock landed on 32
        //* regardless of what LOCK says. The backdrop fade and zoom carry the
        //* entrance on their own.

        SequentialAnimation {
            PauseAnimation {
                duration: 90
            }

            ParallelAnimation {
                NumberAnimation {
                    target: clockCol
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 500
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: clockShift
                    property: "y"
                    from: -22
                    to: 0
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }

        }

        SequentialAnimation {
            PauseAnimation {
                duration: 180
            }

            ParallelAnimation {
                NumberAnimation {
                    target: authCol
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 500
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: authShift
                    property: "y"
                    from: 26
                    to: 0
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }

        }

        SequentialAnimation {
            PauseAnimation {
                duration: 140
            }

            ParallelAnimation {
                NumberAnimation {
                    target: lockBattery
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 500
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: lockWifi
                    property: "opacity"
                    from: 0
                    to: 0.9
                    duration: 500
                    easing.type: Easing.OutCubic
                }
            }

        }

    }

    // ── Background ──
    // grim file first (real desktop, captured pre-lock), then ScreencopyView,
    // then wallpaper file. Matches hyprlock `path = screenshot` + Caelestia useWallpaper.
    Item {
        id: bgLayer

        anchors.fill: parent
        opacity: 0
        scale: 1.05

        // 1) grim pre-capture — most reliable, no ext-session-lock race
        Image {
            id: grimShot

            anchors.fill: parent
            source: "file://" + root.lockShot
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            cache: false
            visible: root.background === "capture"
        }

        // 2) Per-screen live capture when grim missing (Caelestia screencopyBackground).
        // live:false = single frame, avoids DPMS/wake crash loop.
        ScreencopyView {
            id: bgShot

            anchors.fill: parent
            captureSource: root.lockSurface ? root.lockSurface.screen : null
            live: false
            visible: root.background === "capture" && !grimShot.visible && hasContent
        }

        // One blurred layer over whichever source is live.
        MultiEffect {
            id: bgBlur

            anchors.fill: parent
            source: grimShot.status === Image.Ready ? grimShot : bgShot
            visible: root.background === "capture" && (grimShot.status === Image.Ready || bgShot.hasContent)
            autoPaddingEnabled: false
            blurEnabled: root.blurMax > 0
            blur: 1
            blurMax: root.blurMax
            blurMultiplier: 1
            saturation: -0.08
            brightness: -0.06
        }

        // 3) Wallpaper — the explicit "wallpaper" choice, and the fallback when
        //    "capture" is on but no capture came back.
        Image {
            id: wallpaperShot

            anchors.fill: parent
            visible: root.background === "wallpaper"
                || (root.background === "capture" && grimShot.status !== Image.Ready && !bgShot.hasContent)
            source: "file://" + root.wallpaperSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }

        // Dark veil for text contrast — lighter than before so wallpaper
        // stays visible like the reference (was 0.38/0.52 washing to gray)
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.3
        }

        // subtle top/bottom vignette so status icons + pill read like reference
        Rectangle {
            anchors.fill: parent

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(0, 0, 0, 0.18)
                }

                GradientStop {
                    position: 0.3
                    color: Qt.rgba(0, 0, 0, 0)
                }

                GradientStop {
                    position: 0.72
                    color: Qt.rgba(0, 0, 0, 0)
                }

                GradientStop {
                    position: 1
                    color: Qt.rgba(0, 0, 0, 0.3)
                }

            }

        }

    }

    // ── Center clock — upper third like reference ──
    ColumnLayout {
        id: clockCol

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.13
        spacing: 4
        opacity: 0

        transform: Translate {
            id: clockShift
            y: -22
        }

        Label {
            id: dateLabel

            property var now: new Date()

            Layout.alignment: Qt.AlignHCenter
            text: now.toLocaleDateString(Qt.locale(), "dddd, MMMM d")
            color: "#ffffff"
            opacity: 0.88
            font.family: "Adwaita Sans"
            font.pointSize: 12
            font.weight: Font.Medium
            renderType: Text.NativeRendering

            Timer {
                running: true
                interval: 15000
                repeat: true
                onTriggered: dateLabel.now = new Date()
            }

        }

        Label {
            id: timeLabel

            property var now: new Date()

            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatTime(timeLabel.now, root.use12h ? "h:mm AP" : "HH:mm")
            color: "#f2f2f2"
            opacity: 0.96
            font.family: "Adwaita Sans"
            font.pointSize: 92
            font.weight: Font.Bold
            // tight tracking like reference 23:49
            font.letterSpacing: -4
            lineHeight: 0.95
            scale: 1
            renderType: Text.NativeRendering

            Timer {
                running: true
                interval: 1000
                repeat: true
                onTriggered: timeLabel.now = new Date()
            }

        }

    }

    // ── Battery pill — top-right status like the reference ──
    LockBattery {
        id: lockBattery

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 26
        anchors.rightMargin: 28
        opacity: 0
        // The component decides whether it has anything to show; showBattery
        // (LOCK surface) is the user's master switch on top of that.
        visible: root.showBattery && present
        shimmerOn: root.batteryShimmerOn
    }

    // ── Wifi — top-left status, mirrors the battery corner ──
    LockWifi {
        id: lockWifi

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 26
        anchors.leftMargin: 28
        opacity: 0
        // Same arrangement as the battery: its own presence check, gated by the
        // showWifi flag.
        visible: root.showWifi && wifiDev !== null
    }

    // per-char morphing dot, ported from polkit CharItem:
    // each keystroke pops in as a random shape, settles into a dot
    component DotItem: Item {
        id: dot

        required property int index
        property real nonAnimWidthScale: 1

        implicitHeight: dotList.implicitHeight

        ListView.onRemove: {
            initAnim.stop();
            removeAnim.start();
        }

        MaterialShape {
            id: dotShape

            anchors.centerIn: parent
            implicitSize: dotList.implicitHeight * 1.5
            shape: root.shapeQueue[dot.index % root.shapeQueue.length] ?? MaterialShape.Circle
            color: "#ffffff"

            SequentialAnimation {
                id: initAnim

                running: true

                ParallelAnimation {
                    NumberAnimation {
                        target: dotShape
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: dotShape
                        property: "scale"
                        from: 0
                        to: 1
                        duration: 220
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        target: dot
                        property: "implicitWidth"
                        from: dotList.implicitHeight
                        to: dotList.implicitHeight * 1.3
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                    PropertyAction {
                        target: dot
                        property: "nonAnimWidthScale"
                        value: 1.5
                    }
                }
                PauseAnimation {
                    duration: 170
                }
                PropertyAction {
                    target: dotShape
                    property: "shape"
                    value: MaterialShape.Circle
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: dotShape
                        property: "scale"
                        to: 2 / 3
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: dot
                        property: "implicitWidth"
                        to: dotList.implicitHeight
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                    PropertyAction {
                        target: dot
                        property: "nonAnimWidthScale"
                        value: 1
                    }
                }
            }

            SequentialAnimation {
                id: removeAnim

                PropertyAction {
                    target: dot
                    property: "ListView.delayRemove"
                    value: true
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: dotShape
                        property: "opacity"
                        to: 0
                        duration: 130
                        easing.type: Easing.InCubic
                    }
                    NumberAnimation {
                        target: dotShape
                        property: "scale"
                        to: 0.5
                        duration: 130
                    }
                }
                PropertyAction {
                    target: dot
                    property: "ListView.delayRemove"
                    value: false
                }
            }
        }
    }

    // ── Bottom auth cluster ──
    ColumnLayout {
        id: authCol

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 72
        spacing: 9
        opacity: 0

        transform: Translate {
            id: authShift
            y: 26
        }

        // avatar — ClippingRectangle clips to radius (plain clip ignores it)
        Item {
            id: avatarBox

            Layout.alignment: Qt.AlignHCenter
            width: 64
            height: 64
            visible: root.showAvatar

            ClippingRectangle {
                anchors.fill: parent
                radius: 32
                color: "#232323"

                Image {
                    id: faceImg

                    anchors.fill: parent
                    source: "file://" + root.facePath
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status !== Image.Error
                }

                Label {
                    id: fallback

                    anchors.centerIn: parent
                    visible: faceImg.status === Image.Error
                    text: ""
                    color: "#d8d8d8"
                    font.pointSize: 20
                }

            }

            Rectangle {
                anchors.fill: parent
                radius: 32
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.35)
                border.width: 1
            }

        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.userName
            color: "#ffffff"
            opacity: 0.9
            font.family: "Adwaita Sans"
            font.pointSize: 10
            font.weight: Font.Medium
        }

        // password pill
        Rectangle {
            id: pillBg

            Layout.alignment: Qt.AlignHCenter
            // polkit-style: pill breathes wider while typing
            implicitWidth: context.currentText.length > 0 ? 268 : 208
            implicitHeight: 40
            Behavior on implicitWidth {
                NumberAnimation {
                    duration: 450
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.05, 0.7, 0.1, 1]
                }
            }
            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
            radius: 19
            color: context.showFailure ? Qt.rgba(1, 0.42, 0.42, 0.16) : Qt.rgba(1, 1, 1, 0.14)
            border.color: context.showFailure ? "#ff7a7a" : (passwordBox.activeFocus ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.18))
            border.width: 1

            // polkit failShake: -12 / 10 / -6 / 0 with quad easings
            SequentialAnimation {
                id: shake

                NumberAnimation {
                    target: pillBg
                    property: "x"
                    to: -12
                    duration: 60
                    easing.type: Easing.OutQuad
                }

                NumberAnimation {
                    target: pillBg
                    property: "x"
                    to: 10
                    duration: 80
                    easing.type: Easing.InOutQuad
                }

                NumberAnimation {
                    target: pillBg
                    property: "x"
                    to: -6
                    duration: 80
                    easing.type: Easing.InOutQuad
                }

                NumberAnimation {
                    target: pillBg
                    property: "x"
                    to: 0
                    duration: 80
                    easing.type: Easing.OutQuad
                }

            }

            Connections {
                function onShowFailureChanged() {
                    if (root.context.showFailure)
                        shake.start();

                }

                target: root.context
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 4

                // lock icon — reddens on error like polkit
                Item {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    Layout.alignment: Qt.AlignVCenter

                    Label {
                        anchors.centerIn: parent
                        visible: !context.unlockInProgress
                        text: ""
                        color: root.fieldInError ? "#ff7a7a" : Qt.rgba(1, 1, 1, 0.6)
                        font.family: "JetBrainsMono NFM"
                        font.pointSize: 11

                        Behavior on color {
                            ColorAnimation {
                                duration: 180
                            }

                        }

                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        visible: context.unlockInProgress
                        running: visible
                        implicitWidth: 15
                        implicitHeight: 15
                    }

                }

                // middle: animated placeholder + morphing dots over invisible capture field
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Label {
                        id: pillPlaceholder

                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 1
                        text: root.fieldInError ? "Incorrect password" : "Enter password"
                        color: root.fieldInError ? "#ff7a7a" : Qt.rgba(1, 1, 1, 0.5)
                        font.family: "Adwaita Sans"
                        font.pointSize: 9
                        opacity: context.currentText.length > 0 || context.unlockInProgress ? 0 : 1

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }

                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 180
                            }

                        }

                    }

                    ListView {
                        id: dotList
                        // simple width math (avoids `as` cast on inline type — crashes qmllint)
                        readonly property int fullWidth: count * (implicitHeight + spacing)

                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: implicitWidth > parent.width ? -(implicitWidth - parent.width) / 2 : 0
                        implicitWidth: fullWidth
                        implicitHeight: 12
                        orientation: Qt.Horizontal
                        spacing: 6
                        interactive: false
                        visible: !context.unlockInProgress

                        model: ScriptModel {
                            values: context.currentText.split("")
                        }

                        delegate: DotItem {
                        }

                    }

                    // invisible capture field — dots above render the state.
                    // opacity 0 (not just transparent text) so the caret
                    // can never blink through on any style.
                    TextField {
                        id: passwordBox

                        anchors.fill: parent
                        opacity: 0
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: ""
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData
                        enabled: !context.unlockInProgress
                        focus: true
                        cursorVisible: false
                        Component.onCompleted: forceActiveFocus()
                        color: "transparent"
                        selectionColor: "transparent"
                        selectedTextColor: "transparent"
                        onTextChanged: {
                            if (context.currentText !== text)
                                context.currentText = text;

                        }
                        onAccepted: context.tryUnlock()

                        Connections {
                            function onCurrentTextChanged() {
                                if (passwordBox.text !== root.context.currentText)
                                    passwordBox.text = root.context.currentText;

                            }

                            target: root.context
                        }

                        background: Item {
                        }

                    }

                }

                // enter button — circle morphs into arrow while typing like polkit
                Item {
                    id: enterButton

                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    Layout.alignment: Qt.AlignVCenter
                    visible: !context.unlockInProgress

                    MaterialShape {
                        anchors.fill: parent
                        color: context.currentText.length > 0 ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(1, 1, 1, 0.22)
                        shape: context.currentText.length > 0 ? MaterialShape.Arrow : MaterialShape.Circle
                        scale: context.currentText.length === 0 ? 0.62 : enterMouse.pressed ? 0.6 : enterMouse.containsMouse ? 0.8 : 0.7
                        rotation: 90

                        Behavior on scale {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }

                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }

                        }

                        MouseArea {
                            id: enterMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: context.currentText.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (context.currentText.length > 0)
                                    context.tryUnlock();

                            }
                        }

                    }

                }

            }

            // centered in the whole pill (not the middle row — siblings
            // hide/show while checking and would offset a row-centered label)
            // shimmer "Authenticating" (shadcn-style: dim base + bright sweep,
            // 2s linear loop). Self-contained: no shared imports allowed here.
            Item {
                id: authShimmer

                anchors.centerIn: parent
                width: authBase.implicitWidth
                height: authBase.implicitHeight
                opacity: context.unlockInProgress ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }

                }

                Label {
                    id: authBase

                    anchors.centerIn: parent
                    text: "Authenticating"
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.family: "Adwaita Sans"
                    font.pointSize: 9
                    renderType: Text.NativeRendering
                }

                Item {
                    id: sheenMover

                    width: Math.max(60, authShimmer.width * 0.5)
                    height: authShimmer.height

                    readonly property real coreWidth: Math.max(24, authShimmer.width * 0.22)

                    Item {
                        anchors.fill: parent
                        clip: true

                        Label {
                            anchors.verticalCenter: authShimmer.verticalCenter
                            x: (authShimmer.width - implicitWidth) / 2 - sheenMover.x
                            width: implicitWidth
                            height: implicitHeight
                            text: "Authenticating"
                            color: "#ffffff"
                            opacity: 0.45
                            font.family: "Adwaita Sans"
                            font.pointSize: 9
                            renderType: Text.NativeRendering
                        }

                    }

                    Item {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: sheenMover.coreWidth
                        clip: true

                        Label {
                            anchors.verticalCenter: authShimmer.verticalCenter
                            x: (authShimmer.width - implicitWidth) / 2 - sheenMover.x - (sheenMover.width - sheenMover.coreWidth) / 2
                            width: implicitWidth
                            height: implicitHeight
                            text: "Authenticating"
                            color: "#ffffff"
                            font.family: "Adwaita Sans"
                            font.pointSize: 9
                            renderType: Text.NativeRendering
                        }

                    }

                    SequentialAnimation on x {
                        loops: Animation.Infinite
                        running: authShimmer.visible
                        PauseAnimation {
                            duration: 250
                        }

                        NumberAnimation {
                            from: -sheenMover.width
                            to: authShimmer.width
                            duration: 2000
                            easing.type: Easing.Linear
                        }

                    }

                }

            }

            Behavior on border.color {
                ColorAnimation {
                    duration: 180
                }

            }

            Behavior on color {
                ColorAnimation {
                    duration: 180
                }

            }

        }

    }

    // keep focus on password (Hyprland unfocuses on wake — Noctalia workaround)
    Timer {
        interval: 300
        running: true
        repeat: true
        onTriggered: {
            if (!passwordBox.activeFocus && !context.unlockInProgress)
                passwordBox.forceActiveFocus();

        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onEntered: {
            if (!passwordBox.activeFocus && !context.unlockInProgress)
                passwordBox.forceActiveFocus();

        }
    }

}
