import QtQuick
import Quickshell

QtObject {
    id: proc

    property var command: []
    property var environment: ({})
    property QtObject stdout: null
    property QtObject stderr: null
    property bool running: false

    signal exited(int exitCode, int exitStatus)

    onRunningChanged: if (running)
        Quickshell.processes = Quickshell.processes.concat([proc])

    function finish(exitCode, out, err) {
        if (stdout)
            stdout.text = out === undefined ? "" : out;
        if (stderr)
            stderr.text = err === undefined ? "" : err;
        running = false;
        exited(exitCode, 0);
    }
}
