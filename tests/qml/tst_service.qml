import QtQuick
import QtTest
import Quickshell
import Quickshell.Services.Mpris
import "../.." as Plugin

TestCase {
    id: harness
    name: "Service"
    when: windowShown

    Plugin.Service {
        id: service
        scriptPath: "/nowhere/omani"
    }

    function init() {
        failOnWarning(/.*/);
        Quickshell.forget();
        Mpris.carry([]);
        ready();
        answer("players", "");
    }

    function answer(subcommand, out) {
        var p = Quickshell.running(subcommand);
        if (p)
            p.finish(0, out);
        return p !== null;
    }

    function ready() {
        var status = Quickshell.running("status");
        if (status)
            status.finish(0, JSON.stringify({
                "ready": true,
                "tracking": true,
                "watchedFraction": 90,
                "historyPath": "/nowhere/history.json",
                "playersPath": "/nowhere/players"
            }));
    }

    function record(pid, title, id, episode) {
        return pid + "\t" + title + "\t" + id + "\t" + episode + "\t1080\t999\n";
    }

    function test_the_service_answers_once_its_status_is_read() {
        compare(service.ready, true);
        compare(service.watchedFraction, 90);
    }

    function test_a_player_that_went_away_is_noticed_without_being_told() {
        Quickshell.file("players").contents = record("153691", "Dragon Ball Episode 7", "dragon-ball-970", "7");
        service.reloadPlayers();
        answer("players", Quickshell.file("players").contents);
        compare(service.players.length, 1, "the player never became live");
        compare(service.playing, true);

        Quickshell.file("players").contents = "";

        tryVerify(function () {
            return Quickshell.running("players") !== null;
        }, 4000, "the service stopped asking once a player was live, so a closed player stays on screen");

        answer("players", "");
        tryCompare(service, "playing", false, 2000);
    }

    SignalSpy {
        id: refused
        target: service
        signalName: "failed"
    }

    function test_pausing_a_player_we_cannot_reach_says_so() {
        refused.clear();
        service.togglePaused();
        compare(refused.count, 1, "pause did nothing and said nothing");
    }

    function test_muting_a_player_we_cannot_reach_says_so() {
        refused.clear();
        service.toggleMuted();
        compare(refused.count, 1, "mute did nothing and said nothing");
    }

    function test_stopping_a_player_asks_the_script_to_stop_it() {
        Quickshell.file("players").contents = record("153691", "Dragon Ball Episode 5", "dragon-ball-970", "5");
        service.reloadPlayers();
        answer("players", Quickshell.file("players").contents);

        service.stopPlayer(service.players[0]);
        compare(Quickshell.detached.length, 1, "nothing was asked to stop the player");
        verify(Quickshell.detached[0].command.indexOf("stop") >= 0, "the script was asked for something other than a stop");
    }

    function test_a_player_the_script_reports_is_live_even_when_mpris_says_nothing() {
        service.play("dragon-ball-970", "Dragon Ball", "5", 0);
        compare(service.launching, true, "a play should be waiting for its player");
        verify(answer("play", ""), "nothing was asked to start a player");

        Quickshell.file("players").contents = record("153691", "Dragon Ball Episode 5", "dragon-ball-970", "5");

        tryVerify(function () {
            return Quickshell.running("players") !== null;
        }, 3000, "the service never asked the script which players are alive");

        answer("players", Quickshell.file("players").contents);
        tryCompare(service, "launching", false, 2000);
        compare(service.players.length, 1, "the player the script reported is not among the live ones");
    }
}
