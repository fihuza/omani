import QtQuick

Item {
    property var anchorItem: null
    property var owner: null
    property var bar: null
    property bool open: false
    property var focusTarget: null
    property int contentWidth: 0
    property int contentHeight: 0
    width: 420
    height: 700
    property bool popoutSwitchClosing: false
    readonly property bool opened: open
    function fittedContentWidth(cap) {
        return cap;
    }
    function fittedContentHeight(desired, cap) {
        return Math.min(desired, cap);
    }
}
