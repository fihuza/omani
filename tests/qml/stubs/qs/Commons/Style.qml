pragma Singleton
import QtQuick

QtObject {
    readonly property QtObject font: QtObject {
        readonly property string family: "monospace"
        readonly property int display: 20
        readonly property int heading: 16
        readonly property int subtitle: 14
        readonly property int body: 13
        readonly property int bodySmall: 12
        readonly property int caption: 11
    }
    readonly property QtObject spacing: QtObject {
        readonly property int controlHeight: 34
        readonly property int rowPaddingX: 10
    }
    function space(n) {
        return n;
    }
    function selectedFillFor(foreground, accent) {
        return accent;
    }
}
