import QtQuick
import QtTest
import Quickshell
import Quickshell.Services.Mpris
import "../.." as Plugin

// Service.qml reaches for Quickshell directly, so it is built against stubs for
// the types that live in the quickshell binary. What is under test is its
// bookkeeping: which players it believes are alive, and when a launch is over.
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

    // The real process ends; the stub waits to be told, which is what lets a
    // test decide what the script said.
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

    function test_a_player_the_script_reports_is_live_even_when_mpris_says_nothing() {
        service.play("dragon-ball-970", "Dragon Ball", "5", 0);
        compare(service.launching, true, "a play should be waiting for its player");
        verify(answer("play", ""), "nothing was asked to start a player");

        // The script wrote the record. Mpris says nothing, and no file
        // notification arrives, so the only way to learn is to ask.
        Quickshell.file("players").contents = record("153691", "Dragon Ball Episode 5", "dragon-ball-970", "5");

        tryVerify(function () {
            return Quickshell.running("players") !== null;
        }, 3000, "the service never asked the script which players are alive");

        answer("players", Quickshell.file("players").contents);
        tryCompare(service, "launching", false, 2000);
        compare(service.players.length, 1, "the player the script reported is not among the live ones");
    }
}
