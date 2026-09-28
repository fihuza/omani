import QtQuick

Item {
    property color foreground: "white"
    property color color: "white"
    property string fontFamily: "monospace"
    property string title: ""
    property string meta: ""
    property string detail: ""
    property var iconComponent: null
    property var trailingControl: null
    property int iconSize: 12
    property bool playing: false
}
