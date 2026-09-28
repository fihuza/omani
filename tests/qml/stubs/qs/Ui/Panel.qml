import QtQuick

Item {
    id: base

    property QtObject bar: null
    property string moduleName: ""
    property var settings: ({})
    property string ipcTarget: ""
    property bool manageIpc: true
    property bool popoutSwitching: false
    property bool popoutSwitchClosing: false
    property alias controller: panelController
    readonly property bool opened: panelController.open

    function open() {
        panelController.show();
    }
    function close() {
        panelController.hide();
    }
    function toggle() {
        opened ? close() : open();
    }
    function closeForPopoutSwitch() {
        panelController.hide();
    }
    function switchPanel(direction) {
    }
    PanelController {
        id: panelController
    }

    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        return value === undefined || value === null || value === "" ? fallback : value;
    }
}
