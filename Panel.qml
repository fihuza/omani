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
    property string replaceTarget: ""
    property var keyState: Model.initialKeyState()
    property bool cursorActive: false

    readonly property bool ready: service ? service.ready : false
    readonly property bool busy: service ? service.busy : false
    readonly property bool launching: service ? service.launching : false
    readonly property bool countVisible: keyState.pendingCount !== "" || keyState.pendingG
    readonly property string liveSeries: service ? Model.seriesOf(service.players, service.playingId, service.playingSeries) : ""
    readonly property string liveEpisode: service ? Model.episodeOf(service.players, service.playingId, service.playingEpisode) : ""
    readonly property string missing: service ? service.missing : ""
    readonly property string seriesTitle: service ? service.selectedTitle : ""
    readonly property string quality: service ? service.quality : "best"
    readonly property string mode: service ? service.mode : "sub"

    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property color dim: Qt.darker(foreground, 1.55)
    readonly property color urgent: bar ? bar.urgent : Color.urgent
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

    readonly property int pageSize: 6
    readonly property var viewRows: ({
            "history": service ? Model.historyView(service.rows, service.players) : [],
            "results": service ? service.results : [],
            "episodes": service ? service.episodes : [],
            "settings": service ? Model.settingRows(root.quality, root.mode, service.version) : [],
            "player": service ? Model.playerRows(liveSeries, liveEpisode) : [],
            "shortcuts": []
        })
    readonly property var rows: viewRows[view]
    readonly property var keyContext: ({
            rowCount: rows.length,
            pageSize: root.pageSize
        })

    readonly property var headings: ({
            "history": "Continue watching",
            "results": "Results",
            "episodes": seriesTitle,
            "settings": "Settings",
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
                root.service.play(root.service.selectedId, root.service.selectedTitle, root.rows[i].number, root.replaceTarget);
                root.replaceTarget = "";
                root.showPlayer();
            },
            "settings": function (i) {
                var change = Model.settingChange(root.rows[i]);
                if (change)
                    root.applySetting(change.key, change.value);
            },
            "player": function (i) {
                var action = root.playerActions[root.rows[i].key];
                if (action)
                    action();
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
                root.replaceTarget = Model.replaces("player", root.service.playingTitle);
                root.service.openSeries(root.service.playingId, root.service.playingSeries);
                root.view = "episodes";
                root.keyState = Model.initialKeyState();
                root.cursorActive = false;
            },
            "quality": function () {
                root.setView("settings");
            },
            "stop": function () {
                root.service.stopPlayer({
                    pid: "",
                    title: root.service.playingTitle
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
            "clearHistory": function () {
                confirmClear.opened = true;
            },
            "refresh": function () {
                root.service.refresh();
            },
            "toggleSettings": function () {
                root.setView(root.view === "settings" ? "history" : "settings");
            },
            "toggleShortcuts": function () {
                root.setView(root.view === "shortcuts" ? "history" : "shortcuts");
            },
            "close": function () {
                root.goBack();
            }
        })

    function setView(next) {
        if (next === "history")
            replaceTarget = "";
        view = next;
        keyState = Model.initialKeyState();
        cursorActive = false;
    }

    readonly property var backActions: ({
            "close": function () {
                root.close();
            }
        })

    function goBack() {
        var next = Model.backFrom(view);
        var action = backActions[next];
        if (action)
            action();
        else
            setView(next);
    }

    function dispatch(key) {
        if (key === "" || !service)
            return;
        var result = Model.reduceKey(keyState, key, keyContext);
        keyState = result.state;
        if (!result.command)
            return;
        var handler = commandHandlers[result.command.type];
        if (handler)
            handler(result.command);
    }

    readonly property bool watchedPlayerGone: view === "player" && service && !service.launching && !Model.isPlayingSeries(service.players, service.playingId)

    onWatchedPlayerGoneChanged: {
        if (watchedPlayerGone)
            setView("history");
    }

    function selectPlayer(row) {
        service.playingId = row.animeId;
        service.playingEpisode = row.episode;
        service.playingTitle = row.title;
        service.playingSeries = row.title.replace(/ Episode [^ ]*$/, "");
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
        var entry = {
            id: root.moduleName
        };
        for (var existing in source)
            if (existing !== "id")
                entry[existing] = source[existing];
        entry[key] = value;
        root.settings = entry;
        if (service)
            service.settings = entry;
        if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
            bar.shell.updateEntryInline(root.moduleName, entry);
    }

    onOpenedChanged: {
        if (!opened) {
            setView("history");
            return;
        }
        if (!service)
            return;
        service.refresh();
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
        contentHeight: panel.fittedContentHeight(shell.implicitHeight, Style.space(560))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent

            blocked: searchField.activeFocus || confirmClear.opened

            onMoveRequested: function (dx, dy) {
                if (!root.cursorActive) {
                    root.cursorActive = true;
                    return;
                }
                root.dispatch(dy > 0 ? "j" : dy < 0 ? "k" : "");
            }
            onActivateRequested: if (root.cursorActive)
                root.dispatch("enter")
            onCloseRequested: root.dispatch("escape")
            onDeleteRequested: root.dispatch("x")
            onTabRequested: function (direction) {
                if (root.bar && typeof root.bar.switchPanelFrom === "function")
                    root.bar.switchPanelFrom(root.barIdentity, direction);
            }
            onTextKey: function (t) {
                root.cursorActive = true;
                root.dispatch(Model.normalizeKey(t));
            }

            Column {
                id: shell
                anchors.fill: parent
                spacing: Style.space(10)

                PanelHero {
                    width: parent.width
                    title: "Omani"
                    meta: root.ready ? (root.service && root.service.playing ? root.service.nowPlaying : root.quality + " · " + root.mode) : "missing: " + root.missing
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
                            spacing: Style.space(6)

                            PanelActionButton {
                                iconText: "󰒓"
                                tooltipText: root.view === "settings" ? "Back" : "Settings (s)"
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                                onClicked: root.setView(root.view === "settings" ? "history" : "settings")
                            }

                            PanelActionButton {
                                iconText: "󰌌"
                                tooltipText: root.view === "shortcuts" ? "Back" : "Keyboard shortcuts (?)"
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                                onClicked: root.setView(root.view === "shortcuts" ? "history" : "shortcuts")
                            }

                            PanelActionButton {
                                iconText: "󰃢"
                                tooltipText: "Clear history (x)"
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                                onClicked: confirmClear.opened = true
                            }
                        }
                    }
                }

                PanelSeparator {
                    width: parent.width
                    foreground: root.foreground
                }

                TextField {
                    id: searchField
                    visible: root.ready && root.view !== "settings" && root.view !== "shortcuts" && root.view !== "player"
                    width: parent.width
                    placeholderText: "Search anime…   (/ to focus)"
                    foreground: root.foreground
                    onAccepted: root.submitSearch()
                    Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                }

                PanelSectionHeader {
                    visible: root.ready && root.view !== "history" && text !== ""
                    width: parent.width
                    text: Model.heading(root.headings, root.view, root.busy, root.launching)
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }

                Flickable {
                    id: panelFlick
                    width: parent.width
                    height: Math.min(column.implicitHeight, Style.space(400))
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

                                Component.onCompleted: if (selected)
                                    root.scrollIntoView(rowItem, index)

                                width: column.width
                                spacing: Style.space(4)

                                PanelSectionHeader {
                                    visible: rowItem.section !== ""
                                    width: parent.width
                                    text: rowItem.section
                                    foreground: root.foreground
                                    fontFamily: root.fontFamily
                                }

                                Rectangle {
                                    width: parent.width
                                    implicitHeight: rowTitle.implicitHeight + Style.space(10)
                                    radius: Style.cornerRadius
                                    color: rowItem.selected ? Util.alpha(root.foreground, 0.1) : "transparent"

                                    Text {
                                        id: rowTitle
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: Style.space(8)
                                        anchors.right: rowMeta.left
                                        anchors.rightMargin: Style.space(8)
                                        textFormat: Text.PlainText
                                        text: rowItem.modelData.title
                                        color: root.foreground
                                        elide: Text.ElideRight
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.body
                                    }

                                    Text {
                                        id: rowMeta
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.right: parent.right
                                        anchors.rightMargin: Style.space(8)
                                        textFormat: Text.PlainText
                                        text: rowItem.modelData.label !== undefined ? rowItem.modelData.label : ""
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.selectRow(rowItem.index)
                                        onClicked: root.activateRow(rowItem.index)
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
                                    anchors.leftMargin: Style.space(8)
                                    textFormat: Text.PlainText
                                    text: shortcutRow.modelData.keys
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right
                                    anchors.rightMargin: Style.space(8)
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

                PanelSeparator {
                    visible: root.countVisible
                    width: parent.width
                    foreground: root.foreground
                }

                Row {
                    visible: root.countVisible
                    width: parent.width
                    spacing: Style.space(8)

                    Item {
                        width: parent.width - countText.implicitWidth
                        height: 1
                    }

                    Text {
                        id: countText
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: root.keyState.pendingCount + (root.keyState.pendingG ? "g" : "")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
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
}
