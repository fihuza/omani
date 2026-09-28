import QtQuick

Item {
    property string text: ""
    property string iconText: ""
    property string tooltipText: ""
    property bool selected: false
    property bool active: false
    property bool hasCursor: false
    property bool focusable: false
    property bool bordered: false
    property color foreground: "white"
    property color background: "transparent"
    property color accent: "#88c0d0"
    property string fontFamily: "monospace"
    property int iconSize: 12
    property int fontSize: 12
    property int horizontalPadding: 0
    property int verticalPadding: 0
    signal clicked
}
