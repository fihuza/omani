import QtQuick
import QtTest
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons
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
        Util.forget();
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
        service.livePids = null;
        service.settings = ({});
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
        compare(refused.signalArguments[0][0], "this player is not answering, so it cannot be paused from here");
    }

    function test_muting_a_player_we_cannot_reach_says_so() {
        refused.clear();
        service.toggleMuted();
        compare(refused.count, 1, "mute did nothing and said nothing");
        compare(refused.signalArguments[0][0], "this player is not answering, so it cannot be muted from here");
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

    function busPlayer(title, position, length, isPlaying, volume) {
        return {
            "trackTitle": title,
            "position": position,
            "length": length,
            "isPlaying": isPlaying,
            "volume": volume
        };
    }

    function playingDragonBall() {
        Quickshell.file("players").contents = record("153691", "Dragon Ball Episode 7", "dragon-ball-970", "7");
        service.reloadPlayers();
        answer("players", Quickshell.file("players").contents);
        service.playingId = "dragon-ball-970";
    }

    function test_the_bus_alone_decides_a_player_is_live_when_no_pids_came_back() {
        Quickshell.file("players").contents = record("153691", "Dragon Ball Episode 7", "dragon-ball-970", "7");
        Mpris.carry([busPlayer("Dragon Ball Episode 7", 0, 0, true, 1)]);
        service.applyPlayers();
        compare(service.players.length, 1, "the bus named the player and it still was not live");
    }

    function test_progress_is_reported_with_the_position_and_length_the_bus_gives() {
        Quickshell.file("players").contents = record("153691", "Dragon Ball Episode 7", "dragon-ball-970", "7");
        Mpris.carry([busPlayer("Dragon Ball Episode 7", 612, 1440, true, 1)]);
        Quickshell.forget();
        service.reportProgress();

        compare(Quickshell.detached.length, 1, "no progress was reported");
        var args = Quickshell.detached[0].command;
        compare(args[1], "progress");
        compare(args[2], "dragon-ball-970");
        compare(args[3], "7");
        compare(args[4], "612", "the position the bus gave was not the one reported");
        compare(args[5], "1440", "the length the bus gave was not the one reported");
    }

    function test_the_quality_setting_travels_with_every_command() {
        service.settings = {
            "quality": "720p"
        };
        Quickshell.forget();
        service.reportProgress();
        service.run(["status"]);
        compare(Quickshell.detached[Quickshell.detached.length - 1].environment.OMANI_QUALITY, "720p", "the command carried no quality");
    }

    function test_a_setting_that_is_set_is_the_one_used() {
        service.settings = {
            "quality": "1080p"
        };
        compare(service.quality, "1080p");
    }

    function test_a_setting_left_blank_falls_back() {
        service.settings = {
            "quality": ""
        };
        compare(service.quality, "best");
    }

    function test_a_setting_never_given_falls_back() {
        service.settings = {};
        compare(service.quality, "best");
        compare(service.mode, "sub");
        compare(service.watched, "90");
        compare(service.historyLimit, 8);
    }

    function test_a_player_the_bus_says_is_stopped_reads_as_paused() {
        playingDragonBall();
        Mpris.carry([busPlayer("Dragon Ball Episode 7", 10, 1400, false, 1)]);
        compare(service.paused, true, "a stopped player did not read as paused");

        Mpris.carry([busPlayer("Dragon Ball Episode 7", 10, 1400, true, 1)]);
        compare(service.paused, false, "a running player still read as paused");
    }

    function test_a_player_turned_all_the_way_down_reads_as_muted() {
        playingDragonBall();
        Mpris.carry([busPlayer("Dragon Ball Episode 7", 10, 1400, true, 0)]);
        compare(service.muted, true, "a player at zero volume did not read as muted");

        Mpris.carry([busPlayer("Dragon Ball Episode 7", 10, 1400, true, 0.4)]);
        compare(service.muted, false, "an audible player still read as muted");
    }

    function test_a_search_that_answers_becomes_rows() {
        service.search("dragon");
        var asking = Quickshell.running("search");
        verify(asking, "the search was never started");
        asking.finish(0, "dragon-ball-970\tDragon Ball\n");

        compare(service.busy, false, "the panel was left waiting");
        compare(service.results.length, 1, "the rows the script gave were thrown away");
        compare(service.results[0].animeId, "dragon-ball-970");
    }

    function test_a_search_that_fails_says_what_the_script_said() {
        refused.clear();
        service.search("dragon");
        var asking = Quickshell.running("search");
        verify(asking, "the search was never started");
        asking.finish(1, "", "the site refused us\nand said so twice\n");

        compare(service.busy, false, "the panel was left waiting");
        compare(refused.count, 1, "a failed search said nothing");
        compare(refused.signalArguments[0][0], "the site refused us", "the notice did not carry what the script said");
    }

    function test_an_episode_list_that_answers_becomes_rows() {
        service.openSeries("dragon-ball-970", "Dragon Ball");
        var asking = Quickshell.running("episodes");
        verify(asking, "the episode list was never asked for");
        asking.finish(0, "16381\t7\n");

        compare(service.busy, false, "the panel was left waiting");
        compare(service.episodes.length, 1, "the episodes the script gave were thrown away");
    }

    function test_an_episode_list_that_fails_says_what_the_script_said() {
        refused.clear();
        service.openSeries("dragon-ball-970", "Dragon Ball");
        var asking = Quickshell.running("episodes");
        verify(asking, "the episode list was never asked for");
        asking.finish(1, "", "that series is gone\n");

        compare(service.busy, false, "the panel was left waiting");
        compare(refused.count, 1, "a failed episode list said nothing");
        compare(refused.signalArguments[0][0], "that series is gone");
    }

    function test_a_launch_that_fails_says_what_the_script_said() {
        refused.clear();
        service.rows = [
            {
                "animeId": "dragon-ball-970",
                "title": "Dragon Ball",
                "episode": "7",
                "kind": "series"
            }
        ];
        service.resume(service.rows[0]);
        var launching = Quickshell.running("resume");
        verify(launching, "the launch never started");
        launching.finish(1, "", "mpv is not installed\n");

        compare(service.launching, false, "the service still thinks it is launching");
        compare(refused.count, 1, "a failed launch said nothing");
        compare(refused.signalArguments[0][0], "mpv is not installed");
    }

    function historyOf(animeId, title, episode) {
        var series = {};
        series[animeId] = {
            "title": title,
            "episode": episode,
            "updated": 1
        };
        return JSON.stringify({
            "series": series
        });
    }

    function test_a_series_no_longer_playing_is_read_back_from_the_history() {
        Quickshell.file("history").contents = historyOf("dragon-ball-970", "Dragon Ball", "8");
        service.playingId = "dragon-ball-970";
        service.playingEpisode = "";
        service.syncPlayingFromHistory();

        compare(service.playingEpisode, "8", "the history was never read back");
        compare(service.playingSeries, "Dragon Ball");
    }

    function test_a_series_still_playing_is_not_overwritten_by_the_history() {
        playingDragonBall();
        service.playingEpisode = "7";
        service.playingSeries = "Dragon Ball";
        Quickshell.file("history").contents = historyOf("dragon-ball-970", "Dragon Ball", "8");
        service.syncPlayingFromHistory();

        compare(service.playingEpisode, "7", "the history overwrote the episode that is actually playing");
    }

    function test_choosing_another_quality_replays_what_is_playing() {
        playingDragonBall();
        Quickshell.forget();
        service.playAtQuality("720p");

        compare(service.playingQuality, "720p");
        var launching = Quickshell.running("play");
        verify(launching, "nothing was replayed");
        compare(launching.command[2], "dragon-ball-970");
        compare(launching.command[4], "7", "the episode that is playing was not the one replayed");
    }

    function test_another_quality_is_refused_while_a_launch_is_in_flight() {
        playingDragonBall();
        service.launching = true;
        Quickshell.forget();
        service.playAtQuality("720p");

        compare(askedFor("play"), false, "a second launch started on top of one already in flight");
    }

    function test_another_quality_needs_an_episode_to_replay() {
        service.playingId = "dragon-ball-970";
        service.playingSeries = "Dragon Ball";
        service.playingEpisode = "";
        Quickshell.forget();
        service.playAtQuality("720p");

        compare(askedFor("play"), false, "a replay started without knowing which episode");
    }

    function test_the_next_episode_is_asked_for_by_name() {
        playingDragonBall();
        service.playNext();
        var asking = Quickshell.running("next");
        verify(asking, "next episode asked the script for nothing");
        compare(asking.command[1], "next");
        compare(asking.command[2], "dragon-ball-970");
    }

    function test_the_previous_episode_is_asked_for_by_name() {
        playingDragonBall();
        service.playPrevious();
        var asking = Quickshell.running("previous");
        verify(asking, "previous episode asked the script for nothing");
        compare(asking.command[1], "previous");
    }

    function test_stopping_asks_the_script_to_stop_everything() {
        Quickshell.forget();
        service.stop();
        compare(Quickshell.detached.length, 1, "stop asked for nothing");
        compare(Quickshell.detached[0].command[1], "stop");
        compare(Quickshell.detached[0].command[2], "all");
    }

    function test_forgetting_a_series_names_the_series() {
        Quickshell.forget();
        service.forget("dragon-ball-970");
        compare(Quickshell.detached.length, 1, "forget asked for nothing");
        compare(Quickshell.detached[0].command[1], "forget");
        compare(Quickshell.detached[0].command[2], "dragon-ball-970");
    }

    function test_clearing_the_history_asks_for_exactly_that() {
        Quickshell.forget();
        service.clearHistory();
        compare(Quickshell.detached.length, 1, "clearing the history asked for nothing");
        compare(Quickshell.detached[0].command[1], "history-clear");
    }

    function test_a_link_is_handed_to_the_browser() {
        service.openLink("https://example.test/anime");
        compare(Util.launched.length, 1, "the link reached no browser");
        compare(Util.launched[0][0], "omarchy-launch-browser");
        compare(Util.launched[0][1], "https://example.test/anime");
    }

    function test_what_is_playing_is_named_with_its_episode() {
        service.play("dragon-ball-970", "Dragon Ball", "7");
        compare(service.playingTitle, "Dragon Ball Episode 7");
    }

    function test_a_series_read_back_from_history_is_named_with_its_episode() {
        Quickshell.file("history").contents = historyOf("dragon-ball-970", "Dragon Ball", "8");
        service.playingId = "dragon-ball-970";
        service.syncPlayingFromHistory();
        compare(service.playingTitle, "Dragon Ball Episode 8");
    }

    function test_a_search_that_fails_without_saying_why_still_says_something() {
        refused.clear();
        service.search("dragon");
        Quickshell.running("search").finish(1, "", "");
        compare(refused.signalArguments[0][0], "the search failed");
    }

    function test_an_episode_list_that_fails_without_saying_why_still_says_something() {
        refused.clear();
        service.openSeries("dragon-ball-970", "Dragon Ball");
        Quickshell.running("episodes").finish(1, "", "");
        compare(refused.signalArguments[0][0], "the episode list could not be read");
    }

    function test_a_launch_that_fails_without_saying_why_still_says_something() {
        refused.clear();
        service.play("dragon-ball-970", "Dragon Ball", "7");
        Quickshell.running("play").finish(1, "", "");
        compare(refused.signalArguments[0][0], "the player could not be started");
    }
}
