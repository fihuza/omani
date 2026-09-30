import QtQuick
import QtTest
import Quickshell
import "../.." as Plugin

TestCase {
    id: harness
    name: "BarWidget"
    when: windowShown

    Plugin.BarWidget {
        id: widget
    }

    function init() {
        failOnWarning(/.*/);
        Quickshell.forget();
        widget.close();
    }

    function test_the_script_is_found_beside_the_widget() {
        verify(widget.scriptPath.indexOf("/bin/omani") > 0, "the widget did not find its own script");
        verify(widget.scriptPath.indexOf("file://") === -1, "the script path kept its url scheme");
        verify(widget.pluginDir.charAt(widget.pluginDir.length - 1) !== "/", "the plugin directory kept a trailing slash");
    }

    function test_the_panel_opens_closes_and_toggles() {
        compare(widget.opened, false, "the panel began open");
        widget.open();
        compare(widget.opened, true, "opening did nothing");
        widget.close();
        compare(widget.opened, false, "closing did nothing");
        widget.toggle();
        compare(widget.opened, true, "toggling did not open");
        widget.toggle();
        compare(widget.opened, false, "toggling did not close");
    }

    function answerStatus() {
        var status = Quickshell.running("status");
        if (status)
            status.finish(0, JSON.stringify({
                "ready": true,
                "tracking": true,
                "watchedFraction": 90,
                "historyPath": "/nowhere/history.json",
                "playersPath": "/nowhere/players"
            }));
        return status !== null;
    }

    function test_refreshing_reaches_the_script_the_widget_found() {
        Quickshell.forget();
        widget.refresh();
        var asking = Quickshell.running("status");
        verify(asking, "refresh asked the script for nothing");
        compare(asking.command[0], widget.scriptPath, "the service was given a different script than the widget found");
    }

    function test_the_widget_reports_what_the_service_learned() {
        widget.refresh();
        verify(answerStatus(), "the status was never asked for");
        compare(widget.ready, true, "the widget did not follow the service");
        compare(widget.playing, false, "nothing is playing, yet the widget says otherwise");
    }

    function test_the_top_of_the_history_is_what_gets_resumed() {
        widget.refresh();
        verify(answerStatus(), "the status was never asked for");
        Quickshell.file("history").contents = JSON.stringify({
            "series": {
                "dragon-ball-970": {
                    "title": "Dragon Ball",
                    "episode": "7",
                    "updated": 2
                }
            }
        });
        widget.settings = {
            "historyLimit": 5
        };

        compare(widget.resumeTop(), true, "the widget had a row to continue and did not say so");
        var asking = Quickshell.running("resume");
        verify(asking, "nothing was asked of the script");
        compare(asking.command[2], "dragon-ball-970", "a different series was resumed");
    }

    function test_nothing_to_continue_is_reported_rather_than_guessed() {
        compare(widget.resumeTop(), false, "a widget with no history claimed it resumed something");
    }
}
