import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "io.github.fihuza.omani"
    ipcTarget: "io.github.fihuza.omani"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root
    property var service: null

    property string view: "history"
    property var keyState: Model.initialKeyState()
    property bool cursorActive: false

    readonly property bool ready: service ? service.ready : false
    readonly property bool busy: service ? service.busy : false
    readonly property bool launching: service ? service.launching : false
    property string notice: ""
    property bool noticeUnseen: false

    Connections {
        target: root.service
        function onFailed(message) {
            root.notice = message;
            root.noticeUnseen = !root.opened;
        }
        function onLaunchingChanged() {
            if (root.service.launching)
                root.notice = "";
        }
        function onBusyChanged() {
            if (root.service.busy)
                root.notice = "";
        }
    }
    readonly property var playerProgress: service ? Model.progressFor(service.progress, service.playingId) : null
    readonly property var heroState: ({
            ready: root.ready,
            tracking: service ? service.tracking : true,
            missing: root.missing,
            notice: root.notice,
            quality: root.quality,
            mode: root.mode
        })
    readonly property bool countVisible: keyState.pendingCount !== "" || keyState.pendingG
    readonly property string liveSeries: service ? Model.seriesOf(service.players, service.playingId, service.playingSeries) : ""
    readonly property string liveEpisode: service ? Model.episodeOf(service.players, service.playingId, service.playingEpisode) : ""
    readonly property string missing: service ? service.missing : ""
    readonly property string seriesTitle: service ? service.selectedTitle : ""
    readonly property string quality: service ? service.quality : "best"
    readonly property string mode: service ? service.mode : "sub"
    readonly property string watched: service ? service.watched : "90"

    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property color dim: Qt.darker(foreground, 1.55)
    readonly property color urgent: bar ? bar.urgent : Color.urgent
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

    readonly property int pageSize: 6
    readonly property real listGap: Style.space(16)
    readonly property var viewRows: ({
            "history": service ? Model.historyView(service.rows, service.players) : [],
            "results": service ? service.results : [],
            "episodes": service ? service.episodes : [],
            "settings": service ? Model.settingRows(root.quality, root.mode, root.watched, service.version, service.repo) : [],
            "player": service ? Model.playerRows(liveSeries, liveEpisode, service.paused, service.playingQuality || root.quality, service.muted) : [],
            "quality": service ? Model.qualityRows(Model.qualitiesOf(service.players, service.playingId), service.playingQuality) : [],
            "shortcuts": []
        })
    readonly property var rows: viewRows[view]
    readonly property var headings: ({
            "history": "Continue watching",
            "results": "Results",
            "episodes": seriesTitle,
            "settings": "Settings",
            "quality": "Quality for this episode",
            "player": liveSeries !== "" ? liveSeries : "Playing",
            "shortcuts": "Shortcuts"
        })

    readonly property var rowActions: ({
            "history": function (i) {
                var row = root.rows[i];
                var open = root.historyRowActions[row.kind];
                if (open)
                    open(row);
            },
            "results": function (i) {
                root.service.openSeries(root.rows[i].animeId, root.rows[i].title);
                root.setView("episodes");
            },
            "episodes": function (i) {
                root.service.play(root.service.selectedId, root.service.selectedTitle, root.rows[i].number);
                root.showPlayer();
            },
            "quality": function (i) {
                root.service.playAtQuality(root.rows[i].key);
                root.showPlayer();
            },
            "settings": function (i) {
                var action = Model.settingAction(root.rows[i]);
                var run = action ? root.settingActions[action.type] : null;
                if (run)
                    run(action);
            },
            "player": function (i) {
                var action = root.playerActions[root.rows[i].key];
                if (action)
                    action();
            }
        })

    readonly property var settingActions: ({
            "clear": function () {
                confirmClear.opened = true;
            },
            "open": function (action) {
                root.service.openLink(action.url);
            },
            "set": function (action) {
                root.applySetting(action.key, action.value);
            }
        })

    readonly property var historyRowActions: ({
            "playing": function (row) {
                root.selectPlayer(row);
                root.showPlayer();
            },
            "series": function (row) {
                root.service.resume(row);
                root.showPlayer();
            }
        })

    readonly property var playerActions: ({
            "pause": function () {
                root.service.togglePaused();
            },
            "mute": function () {
                root.service.toggleMuted();
            },
            "next": function () {
                root.service.playNext();
            },
            "replay": function () {
                root.service.replayCurrent();
            },
            "previous": function () {
                root.service.playPrevious();
            },
            "select": function () {
                root.service.openSeries(root.service.playingId, root.service.playingSeries);
                root.setView("episodes");
            },
            "quality": function () {
                root.setView("quality");
            },
            "stop": function () {
                root.service.stopPlayer({
                    pid: "",
                    title: root.service.playingTitle,
                    animeId: root.service.playingId
                });
                root.setView("history");
            }
        })

    readonly property var commandHandlers: ({
            "play": function (c) {
                var action = root.rowActions[root.view];
                if (action)
                    action(c.index);
            },
            "focusSearch": function () {
                searchField.forceActiveFocus();
            },
            "forget": function (c) {
                var row = root.rows[c.index];
                if (Model.forgettable(root.view, row))
                    root.service.forget(row.animeId);
            },
            "clearHistory": function () {
                confirmClear.opened = true;
            },
            "refresh": function () {
                root.service.refresh();
            },
            "toggleSettings": function () {
                root.toggleView("settings");
            },
            "toggleShortcuts": function () {
                root.toggleView("shortcuts");
            },
            "close": function () {
                root.goBack();
            }
        })

    readonly property int wheelRows: 5

    property var viewStack: ["history"]

    function setView(next) {
        viewStack = Model.pushView(viewStack, next);
        view = next;
        keyState = Model.initialKeyState();
        cursorActive = false;
    }

    function resetViews() {
        viewStack = ["history"];
        view = "history";
        keyState = Model.initialKeyState();
        cursorActive = false;
    }

    function toggleView(name) {
        if (view === name)
            goBack();
        else
            setView(name);
    }

    function goBack() {
        var back = Model.popView(viewStack);
        if (back.view === "close") {
            root.close();
            return;
        }
        viewStack = back.stack;
        view = back.view;
        keyState = Model.initialKeyState();
        cursorActive = false;
    }

    function dispatch(key) {
        if (key === "" || !service)
            return;
        var result = Model.reduceKey(keyState, key, {
            rowCount: rows.length,
            pageSize: pageSize,
            searchable: Model.searchable(view)
        });
        keyState = result.state;
        if (!result.command)
            return;
        var handler = commandHandlers[result.command.type];
        if (handler)
            handler(result.command);
    }

    // Asks only about the player. Including the view made setView, which this
    // handler calls, feed back into the property it is reacting to.
    readonly property bool watchedPlayerGone: service && !service.launching && !Model.isPlayingSeries(service.players, service.playingId)

    onWatchedPlayerGoneChanged: {
        if (watchedPlayerGone && view === "player")
            setView("history");
    }

    function selectPlayer(row) {
        service.playingId = row.animeId;
        service.playingEpisode = row.episode;
        service.playingTitle = row.title;
        service.playingSeries = Model.seriesTitle(row.title);
    }

    function showPlayer() {
        setView("player");
        cursorActive = true;
    }

    property var scrollItem: null
    property int scrollIndex: -1

    function scrollIntoView(item, index) {
        scrollItem = item;
        scrollIndex = index;
        Qt.callLater(applyScroll);
    }

    function applyScroll() {
        if (!scrollItem || !panelFlick || !cursorActive)
            return;
        panelFlick.contentY = Model.scrollTarget({
            current: panelFlick.contentY,
            viewport: panelFlick.height,
            content: panelFlick.contentHeight,
            rowTop: scrollItem.mapToItem(panelFlick.contentItem, 0, 0).y,
            rowHeight: scrollItem.height,
            index: scrollIndex,
            lastIndex: rows.length - 1,
            margin: Style.space(6)
        });
    }

    function activateCursor() {
        cursorActive = true;
        keyState = Object.assign({}, keyState, {
            index: Model.startIndex(rows)
        });
    }

    function selectRow(index) {
        cursorActive = true;
        keyState = Object.assign({}, keyState, {
            index: index
        });
    }

    function activateRow(index) {
        selectRow(index);
        var action = rowActions[view];
        if (action)
            action(index);
    }

    function submitSearch() {
        service.search(searchField.text);
        setView("results");
        keyCatcher.forceActiveFocus();
    }

    function applySetting(key, value) {
        var source = service ? service.settings : root.settings;
        var entry = Model.withSetting(source, root.moduleName, key, value);
        root.settings = entry;
        if (service)
            service.settings = entry;
        if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
            bar.shell.updateEntryInline(root.moduleName, entry);
    }

    onOpenedChanged: {
        if (!opened || !service)
            return;
        searchField.text = "";
        notice = Model.noticeOnOpen(notice, noticeUnseen);
        noticeUnseen = false;
        service.results = [];
        resetViews();
        service.refresh();
        var adopt = Model.adoptable(service.players, service.playingId);
        if (adopt)
            selectPlayer(adopt);
        if (service.playing)
            showPlayer();
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(380))
        contentHeight: panel.fittedContentHeight(headerBox.implicitHeight + root.listGap + column.implicitHeight, Style.space(560))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent

            blocked: searchField.activeFocus || confirmClear.opened

            onMoveRequested: function (dx, dy) {
                if (!root.cursorActive) {
                    root.activateCursor();
                    return;
                }
                root.dispatch(dy > 0 ? "j" : dy < 0 ? "k" : "");
            }
            onActivateRequested: if (root.cursorActive)
                root.dispatch("enter")
            onCloseRequested: root.dispatch("escape")
            onDeleteRequested: root.dispatch("d")
            onTabRequested: function (direction) {
                if (root.bar && typeof root.bar.switchPanelFrom === "function")
                    root.bar.switchPanelFrom(root.barIdentity, direction);
            }
            onTextKey: function (t) {
                root.cursorActive = true;
                root.dispatch(Model.normalizeKey(t));
            }

            Item {
                id: shell
                anchors.fill: parent

                Column {
                    id: headerBox
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: Style.space(10)

                    PanelHero {
                        width: parent.width
                        title: "Omani"
                        meta: Model.heroMeta(root.heroState)
                        foreground: root.ready ? root.foreground : root.urgent
                        fontFamily: root.fontFamily
                        iconComponent: Component {
                            AnimeIcon {
                                iconSize: Style.font.display
                                playing: root.service ? root.service.playing : false
                                color: root.ready ? root.foreground : root.urgent
                            }
                        }
                        trailingControl: Component {
                            Row {
                                visible: root.ready
                                spacing: Style.space(4)

                                Button {
                                    iconText: "󰌌"
                                    tooltipText: root.view === "shortcuts" ? "Back" : "Keyboard shortcuts (?)"
                                    foreground: root.foreground
                                    fontFamily: root.fontFamily
                                    iconSize: Style.font.subtitle * 1.5
                                    horizontalPadding: Style.space(5)
                                    verticalPadding: Style.space(2)
                                    onClicked: root.toggleView("shortcuts")
                                }

                                Button {
                                    iconText: "󰒓"
                                    tooltipText: root.view === "settings" ? "Back" : "Settings (s)"
                                    foreground: root.foreground
                                    fontFamily: root.fontFamily
                                    iconSize: Style.font.subtitle * 1.5
                                    horizontalPadding: Style.space(5)
                                    verticalPadding: Style.space(2)
                                    onClicked: root.toggleView("settings")
                                }
                            }
                        }
                    }

                    PanelSeparator {
                        width: parent.width
                        foreground: root.foreground
                    }

                    Item {
                        width: parent.width
                        visible: root.ready && Model.searchable(root.view)
                        implicitHeight: searchField.implicitHeight + Style.space(4)

                        TextField {
                            id: searchField
                            anchors.bottom: parent.bottom
                            width: parent.width
                            placeholderText: "Search anime\u2026   (/ to focus)"
                            foreground: root.foreground
                            onAccepted: root.submitSearch()
                            Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                        }
                    }

                    Item {
                        width: parent.width
                        visible: root.ready && root.view !== "history" && headingLabel.text !== ""
                        implicitHeight: headingLabel.implicitHeight

                        SectionLabel {
                            id: headingLabel
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: Model.heading(root.headings, root.view, root.busy, root.launching)
                        }
                    }

                    Item {
                        width: parent.width
                        visible: root.view === "player" && root.playerProgress !== null && episodeCaption.text !== ""
                        implicitHeight: episodeCaption.implicitHeight

                        Text {
                            id: episodeCaption
                            anchors.left: parent.left
                            anchors.right: episodeClock.left
                            anchors.rightMargin: Style.space(8)
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: Model.episodeCaption(root.liveEpisode)
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }

                        Text {
                            id: episodeClock
                            anchors.right: parent.right
                            anchors.verticalCenter: episodeCaption.verticalCenter
                            textFormat: Text.PlainText
                            text: root.playerProgress ? root.playerProgress.clock : ""
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Style.space(4)
                        visible: root.view === "player" && root.playerProgress !== null

                        Rectangle {
                            id: playerTrack
                            width: parent.width
                            height: Math.max(3, Math.round(Style.spacing.controlHeight * 0.08))
                            radius: height / 2
                            color: Style.selectedFillFor(root.foreground, Color.accent)

                            Rectangle {
                                width: playerTrack.width * (root.playerProgress ? root.playerProgress.fraction : 0)
                                height: playerTrack.height
                                radius: playerTrack.radius
                                color: root.foreground
                                opacity: root.playerProgress && root.playerProgress.paused ? 0.45 : 1.0

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 220
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: panelFlick
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: headerBox.bottom
                    anchors.bottom: parent.bottom
                    anchors.topMargin: root.listGap
                    contentWidth: width
                    contentHeight: column.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    interactive: contentHeight > height
                    // Re-applied because a position computed before the column
                    // finishes laying out clamps against a height still growing.
                    onContentHeightChanged: root.applyScroll()
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    WheelHandler {
                        onWheel: function (event) {
                            if (event.angleDelta.y === 0)
                                return;
                            panelFlick.contentY = Model.wheelTarget(panelFlick.contentY, event.angleDelta.y * root.wheelRows, panelFlick.contentHeight, panelFlick.height);
                            event.accepted = true;
                        }
                    }

                    Column {
                        id: column
                        width: panelFlick.width
                        spacing: Style.space(10)

                        Text {
                            visible: root.ready && root.rows.length === 0 && !root.busy && !root.launching && root.view !== "shortcuts"
                            width: parent.width
                            textFormat: Text.PlainText
                            text: root.view === "history" ? "Nothing watched yet — search for something." : "Nothing here."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: root.rows

                            delegate: Column {
                                id: rowItem

                                required property int index
                                required property var modelData

                                readonly property bool selected: root.cursorActive && root.keyState.index === index
                                readonly property string section: modelData.section !== undefined ? modelData.section : ""

                                onSelectedChanged: if (selected)
                                    root.scrollIntoView(rowItem, index)

                                onYChanged: if (selected)
                                    root.scrollIntoView(rowItem, index)

                                onHeightChanged: if (selected)
                                    root.scrollIntoView(rowItem, index)

                                Component.onCompleted: if (selected)
                                    root.scrollIntoView(rowItem, index)

                                width: column.width
                                spacing: Style.space(10)

                                PanelSeparator {
                                    visible: rowItem.index > 0 && rowItem.section !== ""
                                    height: visible ? implicitHeight : 0
                                    width: parent.width
                                    foreground: root.foreground
                                }

                                SectionLabel {
                                    visible: rowItem.section !== ""
                                    height: visible ? implicitHeight : 0
                                    width: parent.width
                                    text: rowItem.section
                                }

                                CursorSurface {
                                    width: parent.width
                                    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX
                                    hasCursor: rowItem.selected
                                    foreground: root.foreground

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.selectRow(rowItem.index)
                                        onClicked: root.activateRow(rowItem.index)
                                    }

                                    Item {
                                        id: rowContent
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: Style.space(10)
                                        anchors.rightMargin: Style.space(10)
                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitHeight: Math.max(titleBox.implicitHeight, rowMeta.implicitHeight, rowForget.implicitHeight)

                                        Text {
                                            id: rowIcon
                                            visible: text !== ""
                                            width: visible ? implicitWidth : 0
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            textFormat: Text.PlainText
                                            text: rowItem.modelData.icon !== undefined ? rowItem.modelData.icon : ""
                                            color: root.dim
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.heading
                                        }

                                        Item {
                                            id: titleBox
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: rowIcon.right
                                            anchors.leftMargin: rowIcon.visible ? Style.space(10) : 0
                                            anchors.right: rowMeta.left
                                            anchors.rightMargin: Style.space(8)
                                            implicitHeight: rowTitle.implicitHeight
                                            clip: true

                                            readonly property real overflow: Math.max(0, rowTitle.implicitWidth - width)
                                            readonly property bool scrolling: rowItem.selected && overflow > 0

                                            Text {
                                                id: rowTitle
                                                width: titleBox.scrolling ? implicitWidth : titleBox.width
                                                textFormat: Text.PlainText
                                                text: rowItem.modelData.title
                                                color: root.foreground
                                                elide: titleBox.scrolling ? Text.ElideNone : Text.ElideRight
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.body
                                            }

                                            SequentialAnimation {
                                                running: titleBox.scrolling
                                                loops: Animation.Infinite
                                                onRunningChanged: if (!running)
                                                    rowTitle.x = 0

                                                PauseAnimation {
                                                    duration: 1200
                                                }
                                                NumberAnimation {
                                                    target: rowTitle
                                                    property: "x"
                                                    to: -titleBox.overflow
                                                    duration: Math.max(500, titleBox.overflow * 22)
                                                }
                                                PauseAnimation {
                                                    duration: 1600
                                                }
                                                NumberAnimation {
                                                    target: rowTitle
                                                    property: "x"
                                                    to: 0
                                                    duration: 350
                                                }
                                                PauseAnimation {
                                                    duration: 400
                                                }
                                            }
                                        }

                                        Text {
                                            id: rowMeta
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.right: rowForget.visible ? rowForget.left : parent.right
                                            anchors.rightMargin: rowForget.visible ? Style.space(8) : 0
                                            width: Math.min(implicitWidth, parent.width * 0.45)
                                            horizontalAlignment: Text.AlignRight
                                            elide: Text.ElideRight
                                            textFormat: Text.PlainText
                                            text: Model.rowLabel(rowItem.modelData, root.service ? root.service.progress : [])
                                            color: root.dim
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                        }

                                        PanelActionButton {
                                            id: rowForget
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.right: parent.right
                                            visible: rowItem.selected && Model.forgettable(root.view, rowItem.modelData)
                                            iconText: "󰅙"
                                            tooltipText: "Forget this series (d)"
                                            foreground: root.foreground
                                            hoverColor: root.urgent
                                            fontFamily: root.fontFamily
                                            onClicked: root.service.forget(rowItem.modelData.animeId)
                                        }
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: root.view === "shortcuts" ? Model.shortcuts() : []

                            delegate: Item {
                                id: shortcutRow

                                required property var modelData

                                width: column.width
                                implicitHeight: shortcutKeys.implicitHeight + Style.space(8)

                                Text {
                                    id: shortcutKeys
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: Style.space(10)
                                    textFormat: Text.PlainText
                                    text: shortcutRow.modelData.keys
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right
                                    anchors.rightMargin: Style.space(10)
                                    textFormat: Text.PlainText
                                    text: shortcutRow.modelData.action
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }
                        }
                    }
                }

                Text {
                    id: countText
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: root.countVisible
                    textFormat: Text.PlainText
                    text: root.keyState.pendingCount + (root.keyState.pendingG ? "g" : "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }
            }

            ConfirmDialog {
                id: confirmClear
                anchors.fill: parent
                z: 20
                focus: opened
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function (event) {
                    if (confirmClear.handleKey(event))
                        event.accepted = true;
                }
                onOpenedChanged: opened ? forceActiveFocus() : keyCatcher.forceActiveFocus()
                message: "Clear watch history?"
                confirmText: "Clear"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onConfirmed: {
                    root.service.clearHistory();
                    opened = false;
                }
                onCanceled: opened = false
            }
        }
    }

    component SectionLabel: PanelSectionHeader {
        elide: Text.ElideRight
        topPadding: Style.space(4)
        bottomPadding: Style.space(4)
        foreground: root.foreground
        fontFamily: root.fontFamily
    }
}
