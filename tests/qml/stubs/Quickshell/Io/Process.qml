import QtQuick
import Quickshell

QtObject {
    id: proc

    property var command: []
    property var environment: ({})
    property QtObject stdout: null
    property QtObject stderr: null
    property bool running: false
    property bool stdinEnabled: false

    // What the real Process gives whoever writes to stdin: a started signal to
    // write on, and write() itself. The words the plugin sends are kept so a
    // test can read back what the command was actually told.
    property string written: ""

    // The words the plugin sent on stdin, as a list. bin/omani reads them one
    // per line, so a test reads them back the same way.
    readonly property var words: written === "" ? [] : String(written).replace(/\n+$/, "").split("\n")

    signal exited(int exitCode, int exitStatus)
    signal started

    function write(text) {
        written += text;
    }

    onRunningChanged: {
        if (!running)
            return;
        Quickshell.processes = Quickshell.processes.concat([proc]);
        written = "";
        started();
    }

    function finish(exitCode, out, err) {
        if (stdout)
            stdout.text = out === undefined ? "" : out;
        if (stderr)
            stderr.text = err === undefined ? "" : err;
        running = false;
        exited(exitCode, 0);
    }
}
