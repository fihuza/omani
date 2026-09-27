import QtQuick
import Quickshell.Io
import qs.Ui
import "Model.js" as Model

BarWidget {
    id: root
    moduleName: "io.github.fihuza.omani"

    readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
    readonly property string scriptPath: pluginDir + "/bin/omani"

    readonly property bool playing: omani.playing
    readonly property bool ready: omani.ready

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    function open() {
        if (panelLoader.item)
            panelLoader.item.open();
    }

    function close() {
        if (panelLoader.item)
            panelLoader.item.close();
    }

    function toggle() {
        if (panelLoader.item)
            panelLoader.item.toggle();
    }

    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function closeForPopoutSwitch() {
        if (panelLoader.item)
            panelLoader.item.closeForPopoutSwitch();
    }

    function refresh() {
        omani.refresh();
    }

    function resumeTop() {
        omani.resume(Model.resumeTarget(omani.rows, omani.players));
    }

    function injectPanel() {
        var target = panelLoader.item;
        if (!target)
            return;
        if ("bar" in target)
            target.bar = root.bar;
        if ("settings" in target)
            target.settings = root.settings;
        if ("anchorItem" in target)
            target.anchorItem = button;
        if ("hostWidget" in target)
            target.hostWidget = root;
        if ("service" in target)
            target.service = omani;
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Service {
        id: omani
        settings: root.settings
        scriptPath: root.scriptPath
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel();
            Qt.callLater(root.injectPanel);
        }
    }

    IpcHandler {
        target: "io.github.fihuza.omani"

        function open(): void {
            root.open();
        }
        function close(): void {
            root.close();
        }
        function show(): void {
            root.open();
        }
        function hide(): void {
            root.close();
        }
        function toggle(): void {
            root.toggle();
        }
        function refresh(): string {
            root.refresh();
            return "ok";
        }
        function resumeTop(): string {
            root.resumeTop();
            return Model.resumeTarget(omani.rows, omani.players) ? "ok" : "nothing to continue";
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconComponent: Component {
            Item {
                AnimeIcon {
                    anchors.centerIn: parent
                    playing: root.playing
                    color: root.ready ? button.foreground : Qt.darker(button.foreground, 1.55)
                    opacity: root.ready ? 1.0 : 0.6
                }
            }
        }
        onPressed: function (buttonCode) {
            if (buttonCode === Qt.RightButton)
                root.resumeTop();
            else if (buttonCode === Qt.MiddleButton)
                root.open();
            else
                root.toggle();
        }
    }
}
