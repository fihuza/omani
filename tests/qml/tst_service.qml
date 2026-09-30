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
        var pending = Quickshell.processes.slice();
        for (var i = 0; i < pending.length; i++) {
            if (pending[i].running)
                pending[i].finish(0, "");
        }
        var file = Quickshell.file("players");
        if (file)
            file.contents = "";
        service.launching = false;
        service.ready = true;
        service.results = [];
        service.episodes = [];
        service.playingId = "";
        service.playingTitle = "";
        service.playingEpisode = "";
        service.playingSeries = "";
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

    function test_a_failed_ask_does_not_forget_a_live_player() {
        Quickshell.file("players").contents = record("153691", "Dragon Ball Episode 7", "dragon-ball-970", "7");
        service.reloadPlayers();
        answer("players", Quickshell.file("players").contents);
        compare(service.players.length, 1, "the player never became live");

        var asking = Quickshell.running("players");
        if (!asking) {
            service.reloadPlayers();
            asking = Quickshell.running("players");
        }
        verify(asking, "the service never asked again");
        asking.finish(1, "");

        compare(service.players.length, 1, "a failed ask threw away what the service already knew");
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

    function resumedAndPlaying() {
        service.rows = [
            {
                "animeId": "rezero-1387",
                "title": "Re:ZERO",
                "episode": "7",
                "kind": "series"
            }
        ];
        service.resume(service.rows[0]);
        answer("resume", "");
        Quickshell.file("players").contents = record("153691", "Re:ZERO Episode 7", "rezero-1387", "7");
        service.reloadPlayers();
        answer("players", Quickshell.file("players").contents);
        Mpris.carry([
            {
                "trackTitle": "Re:ZERO Episode 7",
                "isPlaying": true,
                "position": 90,
                "length": 1466,
                "volume": 1
            }
        ]);
    }

    function test_replaying_after_a_resume_names_the_episode_that_is_playing() {
        resumedAndPlaying();
        compare(service.players.length, 1, "the resumed player never became live");

        Quickshell.forget();
        service.replayCurrent();

        var asked = Quickshell.running("play");
        verify(asked, "replay asked the script for nothing");
        verify(asked.command.indexOf("7") >= 0, "replay asked for episode '" + asked.command.join(" ") + "'");
    }

    function test_replaying_does_not_lose_the_player_it_is_replaying() {
        resumedAndPlaying();
        verify(service.playerReachable, "the player was not reachable even before replay");

        service.replayCurrent();

        verify(service.playerReachable, "replay left the panel unable to find the player, so pause and mute vanish");
    }

    function test_the_player_is_named_by_its_record_not_by_what_was_remembered() {
        resumedAndPlaying();
        service.playingTitle = "Re:ZERO Episode ";
        compare(service.playingNow, "Re:ZERO Episode 7", "a stale title outranked the record the script keeps");
    }

    function askedFor(subcommand) {
        return Quickshell.running(subcommand) !== null;
    }

    function test_nothing_is_asked_of_a_script_that_is_not_ready() {
        service.ready = false;
        Quickshell.forget();
        service.search("frieren");
        service.openSeries("frieren-1", "Frieren");
        service.play("frieren-1", "Frieren", "1", 0);
        service.resume({
            "animeId": "frieren-1",
            "title": "Frieren"
        });
        service.replayCurrent();
        verify(!askedFor("search"), "searched before the status said it was ready");
        verify(!askedFor("episodes"), "listed episodes before the status said it was ready");
        verify(!askedFor("play"), "played before the status said it was ready");
        verify(!askedFor("resume"), "resumed before the status said it was ready");
    }

    function test_a_blank_search_is_not_carried_to_the_script() {
        Quickshell.forget();
        service.search("   ");
        verify(!askedFor("search"), "a query of nothing but spaces was searched for");
    }

    function test_a_search_already_running_is_not_started_again() {
        service.search("frieren");
        verify(askedFor("search"), "the first search never started");
        var first = Quickshell.running("search");
        service.search("naruto");
        compare(Quickshell.running("search"), first, "a second search began while the first was running");
    }

    function test_a_play_is_refused_while_a_launch_is_in_flight() {
        service.play("frieren-1", "Frieren", "1", 0);
        verify(askedFor("play"), "the first play never started");
        answer("play", "");
        service.launching = true;
        Quickshell.forget();
        service.play("naruto-2", "Naruto", "3", 0);
        verify(!askedFor("play"), "a second play began while a launch was still in flight");
    }

    function test_resuming_needs_a_row_to_resume() {
        Quickshell.forget();
        service.resume(null);
        verify(!askedFor("resume"), "resumed with no row to resume");
    }

    function test_stepping_and_replaying_need_something_playing() {
        service.playingId = "";
        Quickshell.forget();
        service.playNext();
        service.playPrevious();
        service.replayCurrent();
        verify(!askedFor("next"), "stepped forward with nothing playing");
        verify(!askedFor("previous"), "stepped back with nothing playing");
        verify(!askedFor("play"), "replayed with nothing playing");
    }

    function test_an_episode_list_already_loading_is_not_asked_for_twice() {
        service.openSeries("frieren-1", "Frieren");
        verify(askedFor("episodes"), "the first episode list never started");
        var first = Quickshell.running("episodes");
        service.openSeries("naruto-2", "Naruto");
        compare(Quickshell.running("episodes"), first, "a second episode list began while the first was running");
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
