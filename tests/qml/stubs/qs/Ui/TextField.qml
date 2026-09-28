import QtQuick

Item {
    property string text: ""
    property string placeholderText: ""
    property color foreground: "white"
    property bool focused: false
    implicitHeight: 28
    signal accepted
    function forceActiveFocus() {
        focused = true;
    }
}
