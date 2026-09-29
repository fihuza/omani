import QtQuick
import QtTest
import "../../Model.js" as Model
import "../.." as Plugin
import "stubs"

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
        failOnWarning(/.*/);
        fake.asked = [];
        fake.episodes = [];
        fake.rows = [];
        fake.results = [];
        fake.players = [];
        fake.playingId = "";
        fake.launching = false;
        panel.close();
        panel.resetViews();
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

    function test_a_launch_failure_becomes_a_notice() {
        panel.open();
        fake.failed("mpv could not start");
        compare(panel.notice, "mpv could not start");
        verify(!panel.noticeUnseen, "the panel is open, so it was seen");
    }

    function test_a_failure_while_the_panel_is_shut_waits_to_be_seen() {
        panel.close();
        fake.failed("the episode list could not be read");
        compare(panel.notice, "the episode list could not be read");
        verify(panel.noticeUnseen, "nobody saw it yet");
    }

    function test_a_new_launch_clears_the_last_failure() {
        panel.open();
        fake.failed("mpv could not start");
        fake.launching = true;
        compare(panel.notice, "");
    }

    function test_a_player_that_dies_sends_the_panel_back() {
        fake.playingId = "naruto";
        fake.players = [
            {
                "animeId": "naruto",
                "episode": "4",
                "title": "Naruto"
            }
        ];
        panel.setView("player");
        fake.players = [];
        compare(panel.view, "history");
    }

    function test_a_launch_in_flight_keeps_the_player_view() {
        fake.playingId = "naruto";
        fake.launching = true;
        panel.setView("player");
        compare(panel.view, "player", "no player is on the bus yet, and that is expected");
        fake.launching = false;
        compare(panel.view, "history", "once the launch is over, nothing is playing");
    }

    function test_a_live_player_keeps_the_player_view() {
        fake.playingId = "naruto";
        fake.players = [
            {
                "animeId": "naruto",
                "episode": "4",
                "title": "Naruto"
            }
        ];
        panel.setView("player");
        compare(panel.view, "player");
    }

    function test_a_key_reaches_the_service() {
        panel.dispatch("r");
        compare(fake.asked, ["refresh"]);
    }

    function test_choosing_an_episode_asks_the_service_to_play_it() {
        fake.selectedId = "naruto";
        fake.selectedTitle = "Naruto";
        fake.episodes = Model.episodeRows("e6\t6\ne7\t7\n", {}, 0.9);
        panel.setView("episodes");
        panel.activateCursor();
        panel.dispatch("j");
        panel.dispatch("enter");
        compare(fake.asked, ["play:naruto:7"]);
    }

    readonly property var everyKey: ["j", "k", "g", "g", "G", "ctrl+d", "ctrl+u", "0", "3", "j", "enter", "d", "c", "r", "s", "?", "/", "i", "x", "q", " ", "z", "escape"]

    function test_no_key_breaks_a_view_data() {
        return [
            {
                "tag": "an empty list",
                "rows": false
            },
            {
                "tag": "a list with rows",
                "rows": true
            }
        ];
    }

    function test_no_key_breaks_a_view(data) {
        var views = ["history", "results", "episodes", "player", "settings", "shortcuts", "quality"];
        if (data.rows) {
            fake.rows = [
                {
                    "animeId": "naruto",
                    "episode": "4",
                    "title": "Naruto",
                    "kind": "series"
                }
            ];
            fake.results = [
                {
                    "animeId": "naruto",
                    "title": "Naruto"
                }
            ];
            fake.episodes = Model.episodeRows("e4\t4\n", {}, 0.9);
            fake.playingId = "naruto";
            fake.players = [
                {
                    "animeId": "naruto",
                    "episode": "4",
                    "title": "Naruto",
                    "quality": "1080p"
                }
            ];
        }
        for (var v = 0; v < views.length; v++) {
            for (var k = 0; k < everyKey.length; k++) {
                panel.resetViews();
                panel.setView(views[v]);
                panel.activateCursor();
                panel.dispatch(everyKey[k]);
                var where = views[v] + " + " + everyKey[k];
                verify(views.indexOf(panel.view) >= 0, where + " left the view at " + panel.view);
                var index = panel.keyState.index;
                verify(index >= 0 && index < Math.max(1, panel.rows.length), where + " left the cursor at " + index + " of " + panel.rows.length);
            }
        }
    }

    function test_every_player_row_reaches_the_service_data() {
        return [
            {
                "tag": "pause",
                "row": "pause",
                "asked": "pause"
            },
            {
                "tag": "mute",
                "row": "mute",
                "asked": "mute"
            },
            {
                "tag": "next episode",
                "row": "next",
                "asked": "next"
            },
            {
                "tag": "replay",
                "row": "replay",
                "asked": "replay"
            },
            {
                "tag": "previous episode",
                "row": "previous",
                "asked": "previous"
            },
            {
                "tag": "select episode",
                "row": "select",
                "asked": "openSeries:naruto",
                "view": "episodes"
            },
            {
                "tag": "change quality",
                "row": "quality",
                "asked": "",
                "view": "quality"
            },
            {
                "tag": "stop",
                "row": "stop",
                "asked": "stop",
                "view": "history"
            }
        ];
    }

    function test_every_player_row_reaches_the_service(data) {
        fake.playingId = "naruto";
        fake.playingSeries = "Naruto";
        fake.players = [
            {
                "animeId": "naruto",
                "episode": "4",
                "title": "Naruto",
                "quality": "1080p"
            }
        ];
        panel.setView("player");
        var keys = panel.rows.map(function (row) {
            return row.key;
        });
        var index = keys.indexOf(data.row);
        verify(index >= 0, data.row + " is not a row of the player menu: " + keys.join(", "));
        panel.activateRow(index);
        compare(fake.asked, data.asked === "" ? [] : [data.asked]);
        if (data.view !== undefined)
            compare(panel.view, data.view);
    }

    function test_going_back_always_reaches_the_end_data() {
        var views = ["results", "episodes", "player", "settings", "shortcuts", "quality"];
        var rows = [];
        for (var i = 0; i < views.length; i++)
            for (var j = 0; j < views.length; j++)
                rows.push({
                    "tag": views[i] + " then " + views[j],
                    "first": views[i],
                    "second": views[j]
                });
        return rows;
    }

    function test_going_back_always_reaches_the_end(data) {
        panel.setView(data.first);
        panel.setView(data.second);
        var steps = 0;
        while (panel.view !== "history" && steps <= 8) {
            panel.dispatch("escape");
            steps++;
        }
        compare(panel.view, "history");
    }
}
