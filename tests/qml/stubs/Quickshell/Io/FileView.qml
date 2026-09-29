import QtQuick
import Quickshell

QtObject {
    id: view

    property string path: ""
    property bool watchChanges: false
    property bool printErrors: true
    property string contents: ""

    onPathChanged: if (path !== "")
        Quickshell.files = Quickshell.files.concat([view])

    signal loaded
    signal fileChanged

    function text() {
        return contents;
    }

    function reload() {
        loaded();
    }
}
