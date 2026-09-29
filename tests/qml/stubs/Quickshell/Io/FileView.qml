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

    // The file changed underneath, the way a rename by the script does.
    function rewrite(next) {
        contents = next;
        fileChanged();
    }
}
