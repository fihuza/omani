import QtQuick

Item {
    property bool opened: false
    property string message: ""
    property string cancelText: "Cancel"
    property string confirmText: "Confirm"
    property int selectedIndex: 1
    property color background: "black"
    property color foreground: "white"
    property string fontFamily: "monospace"
    property int cornerRadius: 4
    signal confirmed
    signal canceled
    function handleKey(key) {
        return false;
    }
}
