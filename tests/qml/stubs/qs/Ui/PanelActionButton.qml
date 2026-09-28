import QtQuick

Item {
    property color foreground: "white"
    property color hoverColor: "white"
    property string fontFamily: "monospace"
    property string iconText: ""
    property string tooltipText: ""
    property int iconSize: 12
    property int horizontalPadding: 0
    property int verticalPadding: 0
    signal clicked
}
