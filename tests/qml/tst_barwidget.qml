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

    QtObject {
        id: hostBar
        property color foreground: "#ffffff"
        property color urgent: "#ff0000"
        property string fontFamily: "monospace"
        property bool vertical: false
        property int barSize: 26
    }

    function init() {
        failOnWarning(/.*/);
        Quickshell.forget();
        widget.close();
    }

    function panel() {
        var found = findChild(widget, "omaniPanel");
        verify(found, "the widget loaded no panel");
        return found;
    }

    function test_the_panel_is_given_everything_it_needs_to_work() {
        var settings = {
            "quality": "720p"
        };
        widget.bar = hostBar;
        widget.settings = settings;

        compare(panel().bar, hostBar, "the panel was not given the bar it lives in");
        compare(panel().settings.quality, "720p", "the panel was not given its settings");
        verify(panel().anchorItem, "the panel has nothing to anchor to");
        compare(panel().hostWidget, widget, "the panel does not know which widget hosts it");
        verify(panel().service, "the panel was given no service");
    }

    function test_the_widget_answers_to_the_name_the_bar_knows_it_by() {
        compare(widget.moduleName, "io.github.fihuza.omani");
        compare(panel().moduleName, "io.github.fihuza.omani");
    }

    function test_closing_for_a_popout_switch_closes_the_panel() {
        widget.open();
        compare(widget.opened, true, "the panel never opened");
        widget.closeForPopoutSwitch();
        compare(widget.opened, false, "the panel stayed open through a popout switch");
    }

    function test_the_script_is_found_beside_the_widget() {
        compare(widget.scriptPath, widget.pluginDir + "/bin/omani", "the script is not beside the widget");
        compare(widget.pluginDir.charAt(0), "/", "the plugin directory is not an absolute path");
        verify(widget.pluginDir.indexOf("file://") === -1, "the plugin directory kept its url scheme");
        var here = Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "");
        compare(here, widget.pluginDir + "/tests/qml/", "the plugin directory is not the one these tests live under");
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
