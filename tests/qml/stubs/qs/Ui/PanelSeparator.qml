import QtQuick

Item {
    property var bar: null
    property color foreground: "white"
    property color color: "white"
    property color hoverColor: "white"
    property string fontFamily: "monospace"
    property string text: ""
    property string title: ""
    property string meta: ""
    property string iconText: ""
    property string tooltipText: ""
    property var iconComponent: null
    property int iconSize: 12
    property bool playing: false
    property bool hasCursor: false
    property bool hoverEnabled: false
    property int cursorShape: 0
    signal clicked(int button)
    signal entered
    signal pressed(int button)
}
