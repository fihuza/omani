import QtQuick
import QtTest
import "../.." as Plugin
import "../../Model.js" as Model
import "stubs"

// The panel is driven the way a key drives it: dispatch() is what the key
// catcher calls, so these exercise the reducer, the command table and the view
// changes together. Calling setView directly would only re-test Model.js.
TestCase {
    id: harness
    name: "Panel"
    when: windowShown

    FakeService {
        id: fake
    }

    Plugin.Panel {
        id: panel
        service: fake
    }

    function init() {
        panel.viewStack = ["history"];
        panel.view = "history";
        panel.cursorActive = false;
        panel.keyState = Model.initialKeyState();
    }

    function test_question_mark_opens_the_shortcut_list_and_closes_it() {
        panel.dispatch("?");
        compare(panel.view, "shortcuts");
        panel.dispatch("?");
        compare(panel.view, "history");
    }

    function test_the_shortcut_list_returns_to_the_player_menu_it_was_opened_from() {
        panel.setView("player");
        panel.dispatch("?");
        compare(panel.view, "shortcuts");
        panel.dispatch("escape");
        compare(panel.view, "player", "and not the watch history");
    }

    function test_settings_and_the_shortcut_list_do_not_trap_escape() {
        panel.setView("player");
        panel.dispatch("s");
        panel.dispatch("?");
        compare(panel.view, "shortcuts");
        panel.dispatch("escape");
        compare(panel.view, "settings");
        panel.dispatch("escape");
        compare(panel.view, "player");
    }

    function test_a_motion_moves_the_cursor_through_the_reducer() {
        panel.setView("player");
        panel.activateCursor();
        var first = panel.keyState.index;
        panel.dispatch("j");
        compare(panel.keyState.index, first + 1);
        panel.dispatch("k");
        compare(panel.keyState.index, first);
    }

    function test_a_count_prefix_reaches_the_reducer() {
        panel.setView("player");
        panel.activateCursor();
        panel.dispatch("3");
        panel.dispatch("j");
        compare(panel.keyState.index, 3);
    }

    function test_going_back_always_reaches_the_end() {
        var views = ["results", "episodes", "player", "settings", "shortcuts", "quality"];
        for (var i = 0; i < views.length; i++) {
            for (var j = 0; j < views.length; j++) {
                panel.viewStack = ["history"];
                panel.view = "history";
                panel.setView(views[i]);
                panel.setView(views[j]);
                var steps = 0;
                while (panel.view !== "history" && steps <= views.length + 2) {
                    panel.dispatch("escape");
                    steps++;
                }
                compare(panel.view, "history", views[i] + " then " + views[j] + " never ends");
            }
        }
    }
}
