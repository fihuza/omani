pragma Singleton
import QtQuick

QtObject {
    property var detached: []
    property var processes: []
    property var files: []

    function execDetached(spec) {
        detached = detached.concat([spec]);
    }

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

    function running(subcommand) {
        for (var i = processes.length - 1; i >= 0; i--) {
            var p = processes[i];
            if (p.running && p.command.indexOf(subcommand) >= 0)
                return p;
        }
        return null;
    }
}
