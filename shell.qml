//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Singletons"
import "components"
import "surfaces"

/**
 * Ukishima top shell. Each monitor carries two layer-shell windows:
 *
 *  - `reserve` is a zero-content strip that only claims an exclusive zone the
 *    height of the rest pill, so tiled windows always sit below the pill even
 *    while it is expanded or a surface is open.
 *  - `overlay` is a full-screen transparent Overlay layer hosting the single
 *    morphing pill anchored at top-centre. The pill never moves windows and is
 *    never re-parented; it just grows in place, so every surface grows out of
 *    the rest pill instead of popping up as a separate panel.
 *
 * Input is routed by the window mask. While the pill is collapsed the mask is
 * the pill rect only, so the rest of the screen clicks through to windows.
 * While the pill is expanded (hovered/pinned) or a surface is open the mask is
 * cleared so the whole layer catches clicks. A backdrop press dismisses, and
 * keyboard focus is taken on demand so Escape closes the open surface.
 */
ShellRoot {
    id: root

    property string openMon: ""
    property string openSurface: ""
    property string peekMon: ""

    /**
     * Battery notification latches, change-triggered by UPower (never polled).
     * Low battery escalates down the levels — 25% then 20% fire once each as a
     * normal warning, and 15% opens a critical announcement that repeats every
     * ten minutes until the battery is plugged in. The latch re-arms when the
     * battery charges or rises back above 25%. Full fires once when the battery
     * reports fully charged, so charge-limited systems (e.g. an 80% cut-off)
     * announce at their actual full point.
     */
    property int battNotifiedBelow: 100
    property bool fullBattNotified: false

    function battNote(urgency, summary, body) {
        battNoteProc.command = urgency.length > 0
            ? ["notify-send", "-a", "Ukishima", "-u", urgency, summary, body]
            : ["notify-send", "-a", "Ukishima", summary, body];
        battNoteProc.running = true;
    }

    /**
     * One-shot level crossings on the way down, lowest threshold first, so a
     * battery already below several levels (e.g. booting at 18%) only announces
     * the most urgent one it has passed — 20% there, never 25% and 20% together.
     * At or below the critical level the repeat timer takes over.
     */
    function battCheck() {
        if (!Battery.present)
            return;
        if (!Battery.discharging || Battery.pct > 25) {
            root.battNotifiedBelow = 100;
            if (root.battRepeatTimer)
                root.battRepeatTimer.stop();
            return;
        }
        var levels = [[15, "critical"], [20, "normal"], [25, "normal"]];
        for (var i = 0; i < levels.length; i++) {
            if (Battery.pct <= levels[i][0] && levels[i][0] < root.battNotifiedBelow) {
                root.battNotifiedBelow = levels[i][0];
                var critical = levels[i][1] === "critical";
                root.battNote(critical ? "critical" : "normal",
                    critical ? "Battery critical" : "Low battery",
                    Battery.pct + "% remaining — plug in your charger"
                    + (critical ? " now." : " soon."));
                break;
            }
        }
        if (Battery.pct <= 15 && root.battRepeatTimer && !root.battRepeatTimer.running)
            root.battRepeatTimer.start();
    }

    function refresh() {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
    }

    Component.onCompleted: {
        refresh();
        Devices.restore();
        void GameMode.active;
        root.battCheck();
    }

    Process {
        id: battNoteProc
    }

    Timer {
        id: battRepeatTimer
        interval: 10 * 60 * 1000
        repeat: true
        onTriggered: {
            if (!Battery.present || !Battery.discharging || Battery.pct > 15) {
                stop();
                return;
            }
            root.battNote("critical", "Battery critical",
                Battery.pct + "% remaining — plug in your charger now.");
        }
    }

    Connections {
        target: Battery
        function onPctChanged() { root.battCheck(); }
        function onDischargingChanged() { root.battCheck(); }
        function onFullChanged() {
            if (!Battery.present)
                return;
            if (Battery.full && !root.fullBattNotified) {
                root.fullBattNotified = true;
                root.battNote("normal", "Battery full",
                    Battery.pct + "% — you can unplug.");
            } else if (!Battery.full) {
                root.fullBattNotified = false;
            }
        }
    }

    /**
     * After an update relaunches the shell, raise a one-shot toast naming what
     * landed, so the apply ends in a confirmation instead of a silent restart. The
     * updater drops the marker just before it restarts; the short delay lets the
     * notification server own the bus before we post to it, and the marker is
     * removed as it is read so the toast only ever fires once.
     */
    Timer {
        interval: 2500
        running: true
        onTriggered: updatedToast.running = true
    }
    Process {
        id: updatedToast
        command: ["sh", "-c",
            "m=\"${XDG_STATE_HOME:-$HOME/.local/state}/ukishima/updated\"; [ -f \"$m\" ] || exit 0; "
            + "b=$(cat \"$m\"); rm -f \"$m\"; "
            + "gdbus call --session --dest org.freedesktop.Notifications "
            + "--object-path /org/freedesktop/Notifications "
            + "--method org.freedesktop.Notifications.Notify "
            + "Pill 0 '' 'Pill updated' \"$b\" '[]' '{}' 5000 >/dev/null 2>&1"]
    }

    PanelWindow {
        id: inhibitWin
        visible: Flags.keepAwake
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "ukishima-inhibit"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; left: true }
        IdleInhibitor { window: inhibitWin; enabled: Flags.keepAwake }
    }

    /**
     * The Wayland IdleInhibitor above only pauses the compositor's own idle
     * (DPMS); hypridle runs its own timer and never sees it, so the lock still
     * fired with keep-awake on. A logind idle inhibitor is the wire hypridle
     * does respect, so hold one for as long as the flag is set.
     */
    Process {
        running: Flags.keepAwake
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=Ukishima",
                  "--why=keep awake", "--mode=block", "sleep", "infinity"]
    }

    /**
     * Only these raw events can change what the pill renders (per-monitor
     * active workspace, minimized toplevels, monitor hotplug). Everything
     * else (window drags, resizes, title spam) must not trigger the triple
     * model refresh, which costs three Hyprland IPC round-trips.
     */
    readonly property var refreshEvents: ({
        workspace: true, workspacev2: true,
        createworkspace: true, createworkspacev2: true,
        destroyworkspace: true, destroyworkspacev2: true,
        moveworkspace: true, moveworkspacev2: true,
        renameworkspace: true, activespecial: true,
        focusedmon: true, focusedmonv2: true,
        openwindow: true, closewindow: true,
        movewindow: true, movewindowv2: true,
        fullscreen: true,
        monitoradded: true, monitoraddedv2: true, monitorremoved: true
    })

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.refreshEvents[event.name])
                root.refresh();
        }
    }

    /**
     * An empty monitor argument resolves to the focused monitor here, so the
     * keybind scripts skip their hyprctl+jq round trip and a surface open costs
     * one IPC call instead of three process spawns.
     */
    function toggleSurface(mon, surface) {
        if (!mon || mon.length === 0)
            mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        if (root.openMon === mon && root.openSurface === surface) {
            root.close();
            return;
        }
        root.openMon = mon;
        root.openSurface = surface;
    }

    function close() {
        root.openMon = "";
        root.openSurface = "";
    }

    function peek(mon) {
        root.peekMon = root.peekMon === mon ? "" : mon;
    }

    IpcHandler {
        target: "ukishima"
        function mixer(mon: string): void { root.toggleSurface(mon, "mixer"); }
        function calendar(mon: string): void { root.toggleSurface(mon, "calendar"); }
        function launcher(mon: string): void { root.toggleSurface(mon, "launcher"); }
        function power(mon: string): void { root.toggleSurface(mon, "power"); }
        function link(mon: string): void { root.toggleSurface(mon, "link"); }
        function battery(mon: string): void { root.toggleSurface(mon, "battery"); }
        function recorder(mon: string): void { root.toggleSurface(mon, "recorder"); }
        function screenrec(mon: string): void { root.toggleSurface(mon, "recorder"); }
        function record(mon: string): void { root.toggleSurface(mon, "recorder"); }

        /**
         * Quick-record keybind (SUPER+D): one button cycles the whole flow with no
         * surface. Recording → stop. Counting down → cancel. A chooser already up
         * on this monitor → dismiss. Otherwise open the standalone source chooser on
         * the focused monitor `mon`, so only that pill renders it.
         */
        function quickRecord(mon: string): void {
            if (ScreenRec.recording) {
                ScreenRec.stop();
            } else if (ScreenRec.counting) {
                ScreenRec.cancel();
            } else if (ScreenRec.quickChoosing) {
                ScreenRec.quickChoosing = false;
                ScreenRec.quickScreenChoosing = false;
            } else {
                ScreenRec.quickMon = mon;
                ScreenRec.quickScreenChoosing = false;
                ScreenRec.quickChoosing = true;
            }
        }
        function gameMode(mon: string): void { Flags.gameMode = !Flags.gameMode; }
        function sysmon(mon: string): void { root.toggleSurface(mon, "sysmon"); }
        function system(mon: string): void { root.toggleSurface(mon, "sysmon"); }
        function clipboard(mon: string): void { root.toggleSurface(mon, "clipboard"); }
        function wallpaper(mon: string): void { root.toggleSurface(mon, "wallpaper"); }
        function media(mon: string): void {
            if (Players.list.length > 0)
                root.toggleSurface(mon, "media");
        }
        function peek(mon: string): void { root.peek(mon); }
        function hide(): void { root.close(); }

        /**
         * Memory saver door: drop every closed surface on every monitor right
         * away, regardless of how much of its 30s tail is left. The open
         * surface is never touched; reopening a dropped surface rebuilds it.
         */
        function unloadAll(): void { Surfaces.unloadClosed(); }

        /** Opens any surface by name, settings sub-pages included; dev and scripting door. */
        function page(mon: string, name: string): void { root.toggleSurface(mon, name); }

        /**
         * The two halves of the SUPER+M minimize toggle, driven by the
         * minimize-toggle script which has already read the focused window. A
         * desktop window drops into the minimized stash; a window already stashed
         * comes back to the workspace it is handed, so the same key hides and
         * restores. Both target the window by address so they act on the one the
         * user pressed on, not whatever the compositor calls active afterwards.
         */
        function minimizeWindow(addr: string): void {
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:' + addr + '" })');
        }
        function restoreWindow(arg: string): void {
            var p = arg.split("|");
            if (p.length < 2 || p[0].length === 0)
                return;
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + p[1] + '", window = "address:' + p[0] + '" })');
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: reserve
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
            readonly property real topGap: 8 * Flags.topGap * s
            /**
             * Reserved-band ceiling with auto-hide off. A full-footprint reserve
             * (hover 58, quick-record 76) cost too much window space, so this is
             * just the resting face plus the transient OSD ring (44): the flashes
             * that actually cover windows (workspace/volume/brightness/record)
             * stay clear, while the cursor-driven hover (58) may still dip past
             * the band by a few pixels.
             */
            readonly property real restFaceH: 44 * s

                        /** Trimming the reserved band below the pill's bottom lets windows climb, so App gap sets the pill-to-window air without touching the desktop gaps_out. The strip face docks flush to the screen top (its own topGap is zero), so it never adds the margin. */
            readonly property real reservedH: Flags.mainDisplay === "strip"
                ? Math.max(0, restFaceH - 12 * (1 - Flags.appGap) * s)
                : Math.max(0, restFaceH + topGap - 12 * (1 - Flags.appGap) * s)

            readonly property real gameBarH: 34 * s

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: Flags.gameMode ? gameBarH : (Flags.autoHide ? 0 : reservedH)
            aboveWindows: true

            anchors { top: true; left: true; right: true }
            implicitHeight: Flags.gameMode ? gameBarH : (Flags.autoHide ? 0 : reservedH)

            mask: emptyReserve
            Region { id: emptyReserve }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockReserve
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
            /**
             * Bottom band the dock sits in: just the bar's footprint plus its
             * float gap, so tiled windows climb above the resting dock but the
             * strips on either side stay usable. With dock auto-hide on nothing
             * is reserved at all and the dock floats over the desktop until the
             * edge is touched; while the dock is retracted empty (no pins, no
             * running apps, no usage-history shelf — DockState.empty) the band
             * is released too, so windows may tile all the way down. Kept in
             * step with DockBar.dockH (components/DockBar.qml): minimal chips
             * are shorter than titled ones, and the float lip mirrors the
             * pill's topGap at half scale.
             */
            readonly property real dockH: (Flags.dockMinimal ? 58 : 68) * s
            readonly property real dockGap: 4 * Flags.topGap * s
            readonly property real reservedH: dockH + dockGap

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: (Flags.dockEnabled && !Flags.dockAutoHide && !DockState.empty) ? reservedH : 0
            aboveWindows: true

            anchors { bottom: true; left: true; right: true }
            implicitHeight: (Flags.dockEnabled && !Flags.dockAutoHide && !DockState.empty) ? reservedH : 0

            mask: emptyDockReserve
            Region { id: emptyDockReserve }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
            readonly property real topGap: 8 * Flags.topGap * s
            readonly property string surface: root.openMon === modelData.name ? root.openSurface : ""
            readonly property bool surfaceOpen: surface.length > 0
            readonly property bool modal: surfaceOpen || pill.held || pill.quickChoosing || pill.expandLatch

            /**
             * True while this monitor's active workspace reports a fullscreen
             * client. The pill then retracts off the top edge and the whole
             * layer becomes click-through so fullscreen content owns the screen.
             */
            readonly property bool monFullscreen: {
                var mons = Hyprland.monitors.values;
                for (var i = 0; i < mons.length; i++) {
                    if (mons[i].name === modelData.name) {
                        var ws = mons[i].activeWorkspace;
                        var o = ws ? ws.lastIpcObject : null;
                        return o ? !!o.hasfullscreen : false;
                    }
                }
                return false;
            }

            onMonFullscreenChanged: if (monFullscreen) {
                if (root.openMon === modelData.name) root.close();
                if (root.peekMon === modelData.name) root.peekMon = "";
                pill.pinned = false;
                pill.expandLatch = false;
            }

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: ((surfaceOpen || pill.quickChoosing)) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "ukishima"

            anchors { top: true; left: true; right: true; bottom: true }

            mask: monFullscreen ? hiddenRegion : (modal ? fullRegion : (pill.mode === "game" ? pillRegion : (Flags.autoHide ? (pill.revealSession || pill.transientLive ? revealPillRegion : (pill.expanded ? pillRegion : revealRegion)) : pillRegion)))
            Region { id: hiddenRegion }

            /**
             * The only input left alive while the pill is auto-hidden: a thin
             * top-centre edge strip the pointer can always find. Hovering it
             * slides the pill back in, whether it is resting on a focused
             * monitor or retracted off a non-focused one. Kept to a few pixels
             * so the pill only ever appears when the cursor actually touches the
             * screen edge — passing through the top area deeper down triggers
             * nothing, and (because the strip doubles as the reveal input mask)
             * no invisible click-blocking band lingers below the visible pill.
             */
            Region {
                id: revealRegion
                readonly property real revealW: pill.stripBar ? Math.max(420 * pill.s, pill.stripFaceW) : 420 * pill.s
                readonly property real revealH: 10 * pill.s
                x: Math.max(0, overlay.width / 2 - revealW / 2)
                y: 0
                width: revealW
                height: revealH
            }
            Region {
                id: pillRegion
                readonly property real baseW: Math.max(pill.width, pill.targetW)
                x: pill.x + (pill.width - baseW) / 2
                y: pill.y
                width: baseW + pill.inputPadRight
                height: Math.max(pill.height, pill.targetH)
            }

            /**
             * Mask while the pill is being pulled in from the reveal strip. The
             * plain pillRegion alone would flicker: it follows the pill's morphing
             * geometry, so a cursor waiting in the strip below the still-growing
             * pill slips out of the mask, drops the hover, and re-triggers the
             * reveal in a loop. Unioning the fixed strip keeps the cursor covered
             * for the whole pull-in; the pill part grows to catch it on the way up.
             */
            Region {
                id: revealPillRegion
                x: revealRegion.x
                y: revealRegion.y
                width: revealRegion.width
                height: revealRegion.height

                Region {
                    x: pillRegion.x
                    y: pillRegion.y
                    width: pillRegion.width
                    height: pillRegion.height
                }
            }
            Region {
                id: fullRegion
                width: overlay.width
                height: overlay.height
            }

            MouseArea {
                anchors.fill: parent
                enabled: overlay.modal
                acceptedButtons: Qt.AllButtons
                onPressed: (mouse) => {
                    if (pill.quickChoosing) {
                        ScreenRec.quickChoosing = false;
                        ScreenRec.quickScreenChoosing = false;
                    } else if (overlay.surfaceOpen) {
                        var inside = mouse.x >= pillRegion.x && mouse.x <= pillRegion.x + pillRegion.width
                            && mouse.y >= pillRegion.y && mouse.y <= pillRegion.y + pillRegion.height;
                        if (!inside)
                            root.close();
                        else if (mouse.y <= pillRegion.y + 40 * pill.s)
                            pill.surfaceBack();
                    } else {
                        pill.pinned = false;
                        pill.expandLatch = false;
                        root.peekMon = "";
                    }
                }
            }

            Connections {
                target: Flags
                function onAutoHideChanged() {
                    if (!Flags.autoHide) {
                        pill.revealSession = false;
                        pill.hovered = false;
                        pill.hoverLatch = false;
                    } else {
                        pill.pinned = false;
                    }
                }
            }

            FocusScope {
                id: focusScope
                anchors.fill: parent
                focus: overlay.surfaceOpen || pill.quickChoosing

                HoverHandler {
                    enabled: !overlay.surfaceOpen && !pill.pinned
                    onHoveredChanged: if (enabled) pill.hovered = hovered
                }
                Keys.onEscapePressed: {
                    if (pill.wallpaperMenuOpen) {
                        pill.wallpaperMenuClose();
                    } else if (pill.quickChoosing) {
                        ScreenRec.quickChoosing = false;
                        ScreenRec.quickScreenChoosing = false;
                    } else {
                        root.close();
                    }
                }
                Keys.onUpPressed: (e) => {
                    if (pill.wallpaperMenuOpen) { pill.wallpaperMenuMove(-1); e.accepted = true; }
                    else e.accepted = pill.mixerStep(1) || pill.recorderStep(5) || pill.settingsMove(-1);
                }
                Keys.onDownPressed: (e) => {
                    if (pill.wallpaperMenuOpen) { pill.wallpaperMenuMove(1); e.accepted = true; }
                    else e.accepted = pill.mixerStep(-1) || pill.recorderStep(-5) || pill.settingsMove(1);
                }
                Keys.onLeftPressed: (e) => {
                    if (pill.wallpaperMenuOpen) { e.accepted = true; }
                    else if (pill.mixerOpen) { pill.mixerFocusMove(-1); e.accepted = true; }
                    else if (pill.wallpaperOpen) { pill.wallpaperMove(-1); e.accepted = true; }
                    else if (pill.powerOpen) { pill.powerMove(-1); e.accepted = true; }
                    else if (pill.recorderOpen) { e.accepted = pill.recorderStep(-5); }
                    else if (pill.settingsLike) { pill.settingsAdjust(-1); e.accepted = true; }
                }
                Keys.onRightPressed: (e) => {
                    if (pill.wallpaperMenuOpen) { e.accepted = true; }
                    else if (pill.mixerOpen) { pill.mixerFocusMove(1); e.accepted = true; }
                    else if (pill.wallpaperOpen) { pill.wallpaperMove(1); e.accepted = true; }
                    else if (pill.powerOpen) { pill.powerMove(1); e.accepted = true; }
                    else if (pill.recorderOpen) { e.accepted = pill.recorderStep(5); }
                    else if (pill.settingsLike) { pill.settingsAdjust(1); e.accepted = true; }
                }

                /**
                 * Return/Enter/Space: the wallpaper strip applies its focused
                 * thumb on every press; the power surface fires a safe tile on
                 * the first press and, for a destructive tile, holds the heat
                 * fill across autorepeat presses (drained on release). Autorepeat
                 * is swallowed for everything else so a held key never re-fires.
                 */
                Keys.onPressed: (e) => {
                    if (pill.wallpaperMenuOpen) {
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                            if (!e.isAutoRepeat) pill.wallpaperMenuPick();
                            e.accepted = true;
                        } else if (e.text.length === 1) {
                            e.accepted = true;
                        }
                        return;
                    }
                    if (pill.wallpaperWh && !pill.wallpaperWhTyping) {
                        if (e.key === Qt.Key_Backspace) {
                            pill.wallpaperWhBackspace();
                            e.accepted = true;
                            return;
                        }
                        if (e.text.length === 1 && e.text > " ") {
                            pill.wallpaperWhType(e.text);
                            e.accepted = true;
                            return;
                        }
                    }
                    if (pill.wallpaperOpen && !pill.wallpaperSearching && !pill.wallpaperWh
                        && e.text.length === 1 && e.text > " ") {
                        pill.wallpaperType(e.text);
                        e.accepted = true;
                        return;
                    }
                    if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space)
                        return;
                    if (pill.wallpaperOpen) {
                        if (!e.isAutoRepeat) pill.wallpaperActivate();
                        e.accepted = true;
                    } else if (pill.powerOpen) {
                        if (!e.isAutoRepeat) pill.powerPress();
                        e.accepted = true;
                    } else if (pill.settingsLike) {
                        if (!e.isAutoRepeat) pill.settingsActivate();
                        e.accepted = true;
                    }
                }
                Keys.onReleased: (e) => {
                    if (e.isAutoRepeat)
                        return;
                    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)
                        && pill.powerOpen) {
                        pill.powerRelease();
                        e.accepted = true;
                    }
                }

                /**
                 * Drag-and-drop gateway for the auto-hidden pill. The reveal
                 * strip keeps its input while the pill is retracted, but drops
                 * are routed to drop targets, not to the passive HoverHandler
                 * that opens the strip — so a hidden pill would never see a
                 * dragged file. This target shadows the strip's geometry, pulls
                 * the pill in on drag enter and hands the drop to the same
                 * install flow as the resting pill. Sits below the pill in the
                 * scene so drops on the visible pill itself keep winning.
                 */
                DropArea {
                    id: stripDrop
                    width: pill.stripBar ? Math.max(420 * overlay.s, pill.width) : 420 * overlay.s
                    height: 8 * overlay.s
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    enabled: Flags.autoHide && !pill.surfaceOpen && !pill.quickChoosing
                        && !pill.quickCounting && !Flags.gameMode
                    visible: enabled
                    keys: ["text/uri-list"]
                    onEntered: (drag) => {
                        drag.acceptProposedAction();
                        pill.revealSession = true;
                        pill.dropEntered(drag.urls);
                    }
                    onExited: {
                        pill.dropExited();
                        pill.revealSession = false;
                    }
                    onDropped: (drop) => {
                        drop.acceptProposedAction();
                        pill.dropDropped(drop.urls);
                        pill.revealSession = false;
                    }
                }

                Pill {
                    id: pill
                    anchors.top: parent.top
                    anchors.topMargin: (pill.stripBar || pill.mode === "game") ? 0 : overlay.topGap
                    anchors.horizontalCenter: parent.horizontalCenter

                    Behavior on anchors.topMargin {
                        NumberAnimation {
                            duration: Motion.morph
                            easing.type: Motion.easeMorph
                            easing.bezierCurve: Motion.morphCurve
                        }
                    }
                    s: overlay.s
                    screenName: overlay.modelData.name
                    barWindow: overlay
                    surface: overlay.surface
                    forcePinned: root.peekMon === overlay.modelData.name

                    opacity: (overlay.monFullscreen && !pill.transientLive) ? 0 : (osdPopup.active ? 0 : 1)
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.morph
                            easing.type: Motion.easeMorph
                            easing.bezierCurve: Motion.morphCurve
                        }
                    }
                    transform: Translate {
                        y: ((overlay.monFullscreen && !pill.transientLive) || pill.hidden) ? -(pill.height + overlay.topGap) : 0
                        Behavior on y {
                            NumberAnimation {
                                duration: Motion.morph
                                easing.type: Motion.easeMorph
                                easing.bezierCurve: Motion.morphCurve
                            }
                        }
                    }

                    onRequestSurface: (name) => root.toggleSurface(overlay.modelData.name, name)
                    onRequestClose: root.close()
                }

                OsdPopup {
                    id: osdPopup
                    anchors.top: parent.top
                    anchors.topMargin: (pill.stripBar || pill.mode === "game") ? 0 : overlay.topGap
                    anchors.horizontalCenter: parent.horizontalCenter
                    s: overlay.s
                    screenName: overlay.modelData.name
                    expanded: pill.expanded
                    topFlat: (pill.mode === "game" || pill.stripBar) ? 1 : 0
                    suppressed: overlay.surfaceOpen || pill.held || pill.quickChoosing
                        || pill.quickCounting || pill.mode === "game" || (pill.toastActive && Notifs.toastCritical)
                }
            }

            onSurfaceOpenChanged: if (surfaceOpen) focusScope.forceActiveFocus()

            Connections {
                target: pill
                function onQuickChoosingChanged() {
                    if (pill.quickChoosing)
                        focusScope.forceActiveFocus();
                }
                function onWallpaperSearchingChanged() {
                    if (!pill.wallpaperSearching && overlay.surfaceOpen)
                        focusScope.forceActiveFocus();
                }
            }
        }
    }

    /**
     * Per-monitor dock, mirroring the pill's two-window split: `dockReserve`
     * claims the bottom band as an exclusive zone while the dock is persistent
     * (enabled and not auto-hiding), and this full-screen overlay hosts the
     * `DockBar` pinned to the bottom edge. Its mask is the bar rect while the
     * dock is shown; with auto-hide on, a thin bottom-centre strip stays live
     * so the pointer can always pull the bar back in, and the whole layer goes
     * click-through while the monitor runs fullscreen or game mode is active
     * (surfaces do not suppress it: opening the launcher or a settings page
     * keeps the dock on screen and usable). Keyboard focus is never taken, so
     * the dock can not steal focus from a tiled window below.
     */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockWin
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
            /** Float gap between the resting dock and the screen's bottom edge: a subtle lip, smaller than the pill's topGap float. */
            readonly property real dockGap: 4 * Flags.topGap * s
            readonly property string surface: root.openMon === modelData.name ? root.openSurface : ""
            readonly property bool surfaceOpen: surface.length > 0

            /**
             * True while this monitor's active workspace reports a fullscreen
             * client; the dock then retracts off the bottom edge.
             */
            readonly property bool monFullscreen: {
                var mons = Hyprland.monitors.values;
                for (var i = 0; i < mons.length; i++) {
                    if (mons[i].name === modelData.name) {
                        var ws = mons[i].activeWorkspace;
                        var o = ws ? ws.lastIpcObject : null;
                        return o ? !!o.hasfullscreen : false;
                    }
                }
                return false;
            }

            readonly property bool suppressed: !Flags.dockEnabled || monFullscreen || Flags.gameMode

            /**
             * The one state where suppression must NOT take the panel with it.
             *
             * The dock's settings panel carries its own "Dock" switch, and that
             * switch turns off the very bar whose gear opened the panel. Hosting
             * the panel here, as a sibling of the bar rather than a child of it,
             * is what makes that survivable: the panel stays put while the bar
             * goes, so the panel is still a way back for the few seconds it takes
             * to change your mind.
             *
             * The pill's Display surface also carries a "Dock" switch
             * (`dockRow` there), which is the real way back and needs none of
             * this. This is the belt to that pair of braces, so switching the
             * dock off from the dock's own settings never becomes a one-way door
             * — and it is scoped narrowly, so fullscreen and game mode still
             * hide everything and nothing else can pin a panel to the screen.
             */
            readonly property bool dockForcedOpen: dock.settingsOpen && !Flags.dockEnabled

            /**
             * Click-away dismissal: a sentinel OUTLINE, not a hover watch.
             *
             * The first version of this watched hover and asked "is the pointer
             * still over the panel or the bar?". It worked sometimes, and the
             * reason is the thing that makes the whole approach wrong.
             *
             * A layer-shell surface is only sent pointer events for points inside
             * its input region. So when the pointer leaves the dock's region, the
             * dock simply stops hearing about it — and "the pointer left" is the
             * ABSENCE of an event, not an event. Whether the compositor bothers to
             * synthesise a leave when the pointer crosses out of an input region
             * is not something this code can rely on, and it evidently does not
             * always: `dock.hovered` and the panel's `pointerInside` are both
             * passive hover flags that can be frozen at their last value. A frozen
             * `true` is not a neutral reading, it is a permanent veto — and the
             * old predicate was built out of exactly those two flags as vetoes.
             * That is the whole bug: dismissal depended on a state the system was
             * under no obligation to update, and one that can only ever say "I
             * think it left", never "it left".
             *
             * The sentinel inverts that. It is a thin outline drawn just outside
             * the block the panel owns, added to the input region, so crossing it
             * is an ordinary motion event that IS delivered — a positive signal,
             * with no inference and no veto. Every path off the panel crosses it,
             * because it is a closed outline around the whole thing.
             *
             * Two bands of geometry, and the difference between them matters:
             *
             *  - `dismissBand` is the outline itself: thin, because it is real
             *    screen area this window now keeps to itself, and a click landing
             *    in it is consumed by this window rather than reaching whatever
             *    is underneath.
             *  - `dismissSlack` is the neutral strip INSIDE that outline and
             *    OUTSIDE the panel's own region. Hovering it does nothing at all,
             *    so drifting a few pixels off the dock's edge does not dismiss;
             *    a click in it still dismisses, because the click floor covers it.
             *    Without it the outline would butt straight against the bar's end,
             *    and the gear lives there — a two-pixel wobble while reaching for
             *    it would close the panel it just opened.
             */
            readonly property real dismissBand: 5 * dock.s
            readonly property real dismissSlack: 8 * dock.s

            /**
             * The rect the outline is drawn around: the panel plus the bar as one
             * block, or the panel alone once the dock has been switched off from
             * inside this very panel (the bar is off-screen and translating, so
             * its resting rect would just block clicks on the desktop behind it).
             */
            readonly property rect dismissBase: dockForcedOpen
                ? Qt.rect(dockPanelRegion.x, dockPanelRegion.y, dockPanelRegion.width, dockPanelRegion.height)
                : Qt.rect(dockSettingsUnion.x, dockSettingsUnion.y, dockSettingsUnion.width, dockSettingsUnion.height)

            /** The outline's outer edge, which is also how far the region grows. */
            readonly property rect dismissBox: Qt.rect(
                dismissBase.x - dismissSlack - dismissBand,
                dismissBase.y - dismissSlack - dismissBand,
                dismissBase.width + (dismissSlack + dismissBand) * 2,
                dismissBase.height + (dismissSlack + dismissBand) * 2)

            /**
             * Written imperatively by the settle timer below, so this must stay
             * writable: making it `readonly` compiles cleanly, throws a TypeError
             * on every assignment, and pins it at false — which silently disables
             * the sentinel bands, because their `enabled` requires it. That is
             * the whole of click-away, gone, with nothing in the log but a
             * warning nobody reads.
             */
            property bool dockPanelSettled: false

            /**
             * The four outline bands, as rects, 0 top / 1 bottom / 2 left /
             * 3 right.
             *
             * A function rather than four sets of bindings so the outline's
             * completeness is something that can be CHECKED: a harness can walk
             * the perimeter of `dismissBox` and assert that every step of it is
             * inside one of these, which is the property that makes the sentinel
             * a closed loop. Four hand-written bindings can be verified only by
             * looking at them, and looking is what missed this before.
             */
            function dismissBandRect(i) {
                const b = dismissBox;
                const t = dismissBand;
                if (i === 0)
                    return Qt.rect(b.x, b.y, b.width, t);
                if (i === 1)
                    return Qt.rect(b.x, b.y + b.height - t, b.width, t);
                if (i === 2)
                    return Qt.rect(b.x, b.y, t, b.height);
                return Qt.rect(b.x + b.width - t, b.y, t, b.height);
            }

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "ukishima-dock"

            anchors { top: true; left: true; right: true; bottom: true }

            /**
             * The dock's settings panel floats above the bar, so it needs its own
             * region or it draws without taking clicks. Unioned with the bar
             * itself: the gear that opened it stays clickable to close it, and the
             * chips stay live underneath.
             */
            Region {
                id: dockSettingsUnion
                readonly property real l: Math.min(dockRegion.x, dockPanelRegion.x)
                readonly property real t: Math.min(dockRegion.y, dockPanelRegion.y)
                x: l
                y: t
                width: Math.max(dockRegion.x + dockRegion.width, dockPanelRegion.x + dockPanelRegion.width) - l
                height: Math.max(dockRegion.y + dockRegion.height, dockPanelRegion.y + dockPanelRegion.height) - t
            }

            Region {
                id: dockPanelRegion
                x: dockPanel.x
                y: dockPanel.y
                width: dockPanel.width
                height: dockPanel.height
            }

            /**
             * The panel is a sibling of the bar, not a child, so it is NOT
             * translated when the bar slides away. That is deliberate and is what
             * `dockForcedOpen` above exists for: switching the dock off from
             * inside its own settings must not strand the user.
             *
             * While the panel is open the region is `dockDismissRegion`, which is
             * `dismissBox`: one rect enclosing the panel, the bar and the sentinel
             * outline. It is a single rect rather than the three it stands in
             * for, which is what the click floor exists to cover — the dead space
             * this over-generous shape adds is exactly the space where a click
             * would be delivered to this window and hit nothing at all.
             *
             * The outline has to be INSIDE the region, or its motion events are
             * never delivered and the whole dismissal mechanism — which is those
             * events and nothing else — never fires.
             *
             * The rest of the mask, and what each state needs to keep reachable:
             *
             *  - Suppressed or empty: nothing, so the screen is entirely free.
             *  - Auto-hide on: the reveal strip alone while retracted, so the
             *    pointer can always find the bar again; the strip unioned with
             *    the pop band once it is up, so the pull-in cannot flicker.
             *  - Auto-hide off: the bar can never retract, so no reveal strip is
             *    needed at any point. Naming the pop band alone covers the bar
             *    plus the space above it — it already contains the bar, whose
             *    width it spans and whose bottom edge it stops at.
             */
            mask: dock.settingsOpen
                ? dockDismissRegion
                : (suppressed || dock.empty ? dockHiddenRegion
                    : (Flags.dockAutoHide ? ((dock.revealSession || dock.hovered) ? dockRevealUnion : dockRevealRegion)
                        : (dock.hovered || dock.previewOpen ? dockPopBand : dockRegion)))
            Region { id: dockHiddenRegion }

            /**
             * The region behind the panel: the sentinel outline plus everything
             * it encloses. Its outer edge is `dismissBox`, so the bands declared
             * alongside the panel below are inside it.
             */
            Region {
                id: dockDismissRegion
                x: dockWin.dismissBox.x
                y: dockWin.dismissBox.y
                width: dockWin.dismissBox.width
                height: dockWin.dismissBox.height
            }

            /**
             * A thin bottom-centre strip kept in the input mask while the dock
             * is retracted, so the pointer can always find it; hovering slides
             * the bar back up. Mirrors the pill's top reveal strip.
             */
            Region {
                id: dockRevealRegion
                readonly property real revealW: Math.max(420 * dock.s, dock.width)
                readonly property real revealH: 10 * dock.s
                x: Math.max(0, dockWin.width / 2 - revealW / 2)
                y: dockWin.height - revealH
                width: revealW
                height: revealH
            }

            /**
             * Mask while the bar is up: the dock's own footprint, so the rest
             * of the screen clicks through to windows.
             */
            Region {
                id: dockRegion
                x: dock.x
                y: dock.y
                width: dock.width
                height: dock.height
            }

            /**
             * The area above the bar that has to stay live while the bar is up.
             *
             * This is the distance the pointer must travel before the dock will
             * let go, so it is not decoration — it IS the hide threshold, and it
             * was set for the tallest thing that can float above the bar (a
             * window preview, ~190px) and then applied unconditionally. With
             * nothing floating, that meant 190px of screen stayed hot and the
             * dock hung around long after the pointer had clearly left it.
             *
             * So the band is sized to what is actually there:
             *
             *  - A preview is open: the full 190, and 100px past each end,
             *    because the cursor genuinely walks up into it and clicks a
             *    window row. That needs input, and the preview is wider than
             *    the bar.
             *  - Otherwise: just past the tallest chip tooltip (~44px, and
             *    non-interactive, so this is about the dock not blinking out
             *    from under a tooltip rather than about taking clicks). The
             *    side margin is near zero for the same reason — a tooltip is
             *    centred on a chip, so it can overhang the bar's end, but it
             *    never needs to be clicked.
             *
             * `previewOpen` rather than "is the pointer over a chip", because
             * the deep band exists for the preview's benefit alone; claiming it
             * while merely hovering a chip would reinstate the long threshold
             * for the most common interaction there is.
             */
            Region {
                id: dockPopBand
                readonly property bool deep: dock.previewOpen
                readonly property real bandH: (deep ? 190 : 44) * dock.s
                readonly property real sideW: (deep ? 100 : 6) * dock.s
                x: Math.max(0, dock.x - sideW)
                y: Math.max(0, dock.y - bandH)
                width: dock.width + sideW * 2
                height: bandH + dock.height
            }

            /**
             * Mask while the bar is up with auto-hide ON, which is the only case
             * that needs the reveal strip: the bar retracts, so the strip is what
             * keeps the pointer able to find and re-reveal it.
             *
             * The plain dockRegion alone would flicker: the strip is wider than
             * the empty bar, so a cursor resting on the strip's outer edge would
             * slip out of the mask mid-slide and re-trigger the reveal. Unioning
             * the fixed strip keeps the cursor covered for the whole pull-in.
             */
            Region {
                id: dockRevealUnion
                x: dockRevealRegion.x
                y: dockRevealRegion.y
                width: dockRevealRegion.width
                height: dockRevealRegion.height

                Region {
                    x: dockPopBand.x
                    y: dockPopBand.y
                    width: dockPopBand.width
                    height: dockPopBand.height
                }
            }

            DockBar {
                id: dock

                /**
                 * Above the settings panel, which sits at z 200.
                 *
                 * This inverts the popover relationship, and deliberately. The
                 * panel is anchored to the bar's TOP, so the two never overlap
                 * — nothing the bar paints in its own rectangle can cover the
                 * panel. What DOES overlap is what the bar floats UP out of
                 * itself: the chip tooltips and the multi-window preview, both
                 * anchored above their chip, which is to say inside the panel.
                 *
                 * As siblings those were unreachable whenever the panel was open:
                 * hovering a chip to read its name showed a tooltip painted
                 * behind an opaque panel, so it simply was not there. A z value
                 * is per-branch and there is no "escape to the window root", so
                 * the bar has to come above the panel as a whole to lift its own
                 * decorations with it.
                 *
                 * The tooltips are the reason this is right rather than merely
                 * convenient: the panel being open must not cost the user the
                 * names of the apps they are pointing at. Input is unaffected —
                 * a tooltip is non-interactive by design, so it never claims a
                 * click from a panel row underneath it.
                 */
                z: 250
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: dockWin.dockGap
                s: dockWin.s
                suppressed: suppressed
                screenName: dockWin.modelData.name

                /**
                 * Slide the bar below the screen edge while the dock is
                 * retracted (monitor fullscreen, game mode, disabled, or
                 * auto-hidden after the pointer leaves) and while it has
                 * nothing to show — no pins, no running apps and no usage
                 * history for a frequent-app shelf (`empty`). The translate
                 * covers the bar plus its float gap, so nothing peeks back
                 * above the edge while hidden.
                 */
                transform: Translate {
                    y: dock.hidden || dock.empty || suppressed ? dock.height + dockWin.dockGap : 0
                    Behavior on y {
                        NumberAnimation {
                            duration: Motion.morph
                            easing.type: Motion.easeMorph
                            easing.bezierCurve: Motion.morphCurve
                        }
                    }
                }
            }

            /**
             * The dock's OWN settings panel, hosted here rather than inside
             * DockBar for one reason: it must survive the bar being translated
             * off the bottom edge, because the panel holds the "Dock" switch and
             * the bar holds the gear. Two things make that work.
             *
             * It is a SIBLING of the bar, and it anchors to the bar's layout
             * position — a Transform moves the painting, not `x`/`y`, so
             * anchoring here reads the untranslated position and the panel holds
             * still while the bar slides away.
             *
             * And the shell, not the dock, decides the panel's palette input and
             * its input-mask region, because the mask has to cover the panel
             * alone in `dockForcedOpen` — the bar is gone, so the union would be
             * wrong.
             *
             * Loaded, not instantiated, so the app list's desktop-entry scan is
             * not paid for while the panel is closed. Its size is left entirely
             * to the Loader's own implicit sizing, which follows the page's
             * `implicitWidth`/`implicitHeight`: binding `width` to `item.width`
             * looks equivalent and is not — the Loader resizes a loaded item to
             * its own width, so on the tick the item appears the width reads 0,
                 * the Loader resizes the page to 0, and the two pin each other at
             * zero. That is the panel's own input-mask region, so a silent zero
             * there is a panel that draws and takes no clicks.
             */
            Loader {
                id: dockPanel
                active: dock.settingsOpen
                visible: dock.settingsOpen
                z: 200
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: dock.top
                /* A POSITIVE bottom margin lifts the panel clear of the bar, as
                 * it does for every other margin: the item's bottom sits that
                 * many pixels above the anchor line. */
                anchors.bottomMargin: dock.panelGap
                onActiveChanged: if (active) {
                    dockWin.dockPanelSettled = false;
                    dockPanelSettle.restart();
                }

                sourceComponent: Component {
                    DockSurface {
                        s: dock.s
                        pal: dock.dockPal
                        open: true
                        onRequestClose: dock.closeSettings()
                    }
                }
            }

            /**
             * The settle period, as a timer rather than a condition.
             *
             * 300ms is long enough that a hover event still in flight from the
             * gear click cannot be read as the pointer having already left, and
             * short enough that a deliberate dismissal is not noticeably delayed.
             *
             * This is a guard against the instant of opening and nothing else.
             * It is NOT a precondition for being allowed to dismiss — an earlier
             * "arm once the pointer has been over the panel" gate was, and that
             * suppressed the exact case it was written to guard: the panel is
             * opened from the GEAR, so on the ordinary path the pointer is on the
             * bar and never crosses the panel at all.
             */
            Timer {
                id: dockPanelSettle
                interval: 300
                repeat: false
                onTriggered: if (dock.settingsOpen)
                    dockWin.dockPanelSettled = true
            }

            /**
             * The sentinel: a thin closed outline around the panel's block, and
             * the whole of click-away.
             *
             * Four bands rather than one outline item, because an item covering
             * the outline's interior would overlap the panel and the bar and
             * compete with them for hover. As separate bands the only thing that
             * can claim a point in any of them is the band itself, so "the
             * pointer is in a band" is a fact and not a race.
             *
             * Top and bottom span the full width, so the corners are covered by
             * them rather than left as gaps.
             *
             * Each band is a real Item with a HoverHandler attached, because a
             * pointer handler is not an Item and carries no geometry of its own
             * — it is delivered events for the item it hangs off. So the Item is
             * the band and the handler is what watches it.
             *
             * The geometry comes from `dismissBandRect` rather than being written
             * out here, because the SHAPE is the part that has to be right: a gap
             * in the outline is a direction the pointer can leave without
             * anything noticing, which is exactly the failure being fixed. Rects
             * in a function can be walked and tested for coverage; four sets of
             * arithmetic written inline can only be eyeballed, and eyeballing is
             * what missed this the first time.
             *
             * z is the floor's, and it is below the bar (0) and the panel (200):
             * these are empty Items, so nothing is painted, and being underneath
             * means they cannot intercept a click meant for a chip or a row.
             */
            Repeater {
                model: 4
                Item {
                    id: band
                    required property int index
                    z: -1
                    readonly property rect r: dockWin.dismissBandRect(index)
                    x: r.x
                    y: r.y
                    width: r.width
                    height: r.height

                    HoverHandler {
                        /* Held off until the panel has settled, and while a window
                         * preview is up: the preview floats out of the bar over
                         * the top band, and dismissing the settings because the
                         * pointer travelled into it would not be a dismissal the
                         * user asked for. */
                        enabled: dock.settingsOpen && dockWin.dockPanelSettled && !dock.previewOpen
                        onHoveredChanged: if (hovered)
                            dock.closeSettings()
                    }
                }
            }

            /**
             * The other half of click-away: a click that lands on THIS window but
             * on neither the panel nor the bar.
             *
             * The region while the panel is open is one rect that encloses both,
             * which leaves dead space beside the panel, in the gap between panel
             * and bar, and all the way out to the sentinel. A click in any of it
             * is delivered to this window and hits nothing, so it deserves a
             * direct answer rather than waiting on a hover that may not come.
             *
             * The sentinel only covers the OUTER edge, so this is what covers the
             * slack strip and the interior dead space. Between them every click
             * that can be seen is answered.
             *
             * z is BELOW the bar (which is 0) and far below the panel (200), so
             * this never sees a click meant for a chip or a row — it is a floor,
             * not a lid.
             */
            MouseArea {
                z: -1
                anchors.fill: parent
                visible: dock.settingsOpen
                onClicked: dock.closeSettings()
            }

            HoverHandler {
                enabled: !suppressed
                onHoveredChanged: if (enabled) dock.hovered = hovered
            }

            Connections {
                target: Flags
                function onDockAutoHideChanged() {
                    if (!Flags.dockAutoHide) {
                        dock.revealSession = false;
                        dock.hovered = false;
                    }
                }
                function onDockEnabledChanged() {
                    if (!Flags.dockEnabled) {
                        dock.revealSession = false;
                        dock.hovered = false;
                    }
                }
            }
        }
    }
}
