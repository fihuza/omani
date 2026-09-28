import QtQuick
import QtTest
import "../.." as Plugin

TestCase {
    id: harness
    name: "Panel"
    when: windowShown

    Plugin.Panel {
        id: panel
    }

    function init() {
        panel.setView("history");
        panel.viewStack = ["history"];
        panel.view = "history";
    }

    function test_a_panel_opens_on_the_watch_history() {
        compare(panel.view, "history");
    }

    function test_the_shortcut_list_returns_where_it_was_opened() {
        panel.setView("player");
        panel.toggleView("shortcuts");
        compare(panel.view, "shortcuts");
        panel.toggleView("shortcuts");
        compare(panel.view, "player", "and not the watch history");
    }

    function test_two_overlays_do_not_send_each_other_back() {
        panel.setView("player");
        panel.toggleView("settings");
        panel.toggleView("shortcuts");
        compare(panel.view, "shortcuts");

        // Each step back undoes one, and the walk ends at the player menu
        // rather than bouncing between the two overlays for ever.
        panel.goBack();
        compare(panel.view, "settings");
        panel.goBack();
        compare(panel.view, "player");
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
                    panel.goBack();
                    steps++;
                }
                compare(panel.view, "history", views[i] + " then " + views[j] + " never ends");
            }
        }
    }

    function test_the_episode_list_returns_to_the_view_that_opened_it() {
        panel.setView("player");
        panel.setView("episodes");
        panel.goBack();
        compare(panel.view, "player");

        panel.viewStack = ["history"];
        panel.view = "history";
        panel.setView("results");
        panel.setView("episodes");
        panel.goBack();
        compare(panel.view, "results");
    }

    function test_settings_opened_over_the_episode_list_return_to_it() {
        panel.setView("results");
        panel.setView("episodes");
        panel.toggleView("settings");
        panel.goBack();
        compare(panel.view, "episodes");
    }

    function test_reaching_a_view_already_open_does_not_stack_a_second_copy() {
        panel.setView("player");
        panel.setView("episodes");
        panel.setView("player");
        compare(panel.viewStack.length, 2);
        compare(panel.view, "player");
    }
}
