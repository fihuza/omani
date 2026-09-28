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
    property bool opened: false

    function open() {
        opened = true;
    }
    function close() {
        opened = false;
    }
    function toggle() {
        opened = !opened;
    }
    function closeForPopoutSwitch() {
        opened = false;
    }
    function switchPanel(direction) {
    }
    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        return value === undefined || value === null || value === "" ? fallback : value;
    }
}
