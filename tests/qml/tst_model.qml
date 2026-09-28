import QtQuick
import QtTest
import "../../Model.js" as Model

// node proves what Model.js decides; this proves the engine that ships it can
// read and run the same file. A directive node rejects, or syntax this engine
// does not have, passes every other gate and fails only here.
TestCase {
    name: "ModelInTheQmlEngine"

    function test_the_file_loads_and_answers() {
        compare(Model.seriesTitle("Naruto Episode 4"), "Naruto");
        compare(Model.episodeCaption("4"), "Episode 4");
        compare(Model.restoredVolume(0), 1);
    }

    function test_the_key_reducer_runs_here() {
        var down = Model.reduceKey(Model.initialKeyState(), "j", {
            rowCount: 5,
            pageSize: 2,
            searchable: true
        });
        compare(down.state.index, 1);
        compare(Model.reduceKey(down.state, "q", {}).command.type, "close");
    }

    function test_the_view_stack_runs_here() {
        var stack = Model.pushView(["history"], "player");
        stack = Model.pushView(stack, "settings");
        compare(Model.popView(stack).view, "player");
    }

    function test_rows_are_built_here() {
        var rows = Model.playerRows("Naruto", "4", false, "best", false);
        compare(rows[0].key, "pause");
        compare(rows[1].key, "mute");
    }
}
