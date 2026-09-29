pragma Singleton
import QtQuick

// Stands in for the types that live in the quickshell binary. Every stub
// process registers here so a test can find the one it wants by the argv it
// was given, and answer for it.
QtObject {
    property var detached: []
    property var processes: []
    property var files: []

    function execDetached(spec) {
        detached = detached.concat([spec]);
    }

    // Only the call log resets between tests. The process and file lists are
    // the objects themselves, and they outlive any one test.
    function forget() {
        detached = [];
    }

    function file(fragment) {
        for (var i = files.length - 1; i >= 0; i--) {
            if (String(files[i].path).indexOf(fragment) >= 0)
                return files[i];
        }
        return null;
    }

    // Matched on the subcommand itself, so asking for "play" cannot hand back
    // the process that was asked for "players".
    function running(subcommand) {
        for (var i = processes.length - 1; i >= 0; i--) {
            var p = processes[i];
            if (p.running && p.command.indexOf(subcommand) >= 0)
                return p;
        }
        return null;
    }
}
