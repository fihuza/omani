import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "Model.js" as Model

Item {
    id: root

    property var settings: ({})
    property string scriptPath: ""

    property bool ready: false
    property bool tracking: true
    property string missing: ""
    property string version: ""
    property string historyPath: ""

    property var rows: []
    property var results: []
    property var episodes: []

    property string selectedId: ""
    property string selectedTitle: ""
    property string playersPath: ""
    property var players: []

    property string playingId: ""
    property string playingSeries: ""
    property string playingEpisode: ""
    property string playingTitle: ""
    property bool busy: false
    property bool launching: false
    property var launchPids: []

    readonly property int historyLimit: intSetting("historyLimit", 8, 1, 20)
    readonly property string quality: String(setting("quality", "best"))
    readonly property string mode: String(setting("mode", "sub"))
    readonly property bool showNowPlaying: setting("showNowPlaying", true) === true

    readonly property var playerList: Mpris.players ? Mpris.players.values : []
    readonly property var liveTitles: playerList.map(function (p) {
        return String(p.trackTitle || "");
    })

    function livePositions() {
        return playerList.map(function (p) {
            return {
                title: String(p.trackTitle || ""),
                position: Number(p.position) || 0,
                duration: Number(p.length) || 0
            };
        });
    }

    function reportProgress() {
        if (!ready)
            return;
        var reports = Model.progressReports(Model.playerRecords(playersFile.text()), livePositions());
        for (var i = 0; i < reports.length; i++)
            Quickshell.execDetached(command(["progress", reports[i].animeId, reports[i].episode, String(reports[i].position), String(reports[i].duration)]));
    }
    readonly property bool playing: players.length > 0
    readonly property string nowPlaying: players.length > 0 ? players[0].title : ""

    readonly property var currentPlayer: Model.playerFor(playerList, nowPlaying)

    // mpris position is not a notifying property: quickshell reads it fresh
    // every time, but nothing tells a binding to look again. The tick is what
    // makes the clock move.
    property int clockTick: 0
    readonly property string elapsed: {
        clockTick;
        return currentPlayer ? Model.elapsed(currentPlayer.position, currentPlayer.length) : "";
    }

    Timer {
        interval: 1000
        running: root.playing
        repeat: true
        onTriggered: root.clockTick++
    }

    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        return value === undefined || value === null || value === "" ? fallback : value;
    }

    function intSetting(name, fallback, min, max) {
        var n = parseInt(String(setting(name, fallback)), 10);
        if (!isFinite(n))
            n = fallback;
        return Math.max(min, Math.min(max, n));
    }

    function command(args, replacing, qualityOverride) {
        return ["env", "OMANI_QUALITY=" + (qualityOverride || quality), "OMANI_MODE=" + mode, "OMANI_REPLACE=" + (replacing || ""), scriptPath].concat(args);
    }

    function refresh() {
        if (scriptPath === "" || statusProcess.running)
            return;
        statusProcess.command = command(["status"]);
        statusProcess.running = true;
    }

    function applyStatus(raw) {
        var parsed = JSON.parse(raw);
        ready = parsed.ready === true;
        tracking = parsed.tracking !== false;
        missing = String(parsed.missing || "");
        version = String(parsed.version || "");
        historyPath = String(parsed.historyPath || "");
        playersPath = String(parsed.playersPath || "");
    }

    function reloadHistory() {
        rows = Model.historyRows(historyFile.text(), historyLimit);
        syncPlayingFromHistory();
    }

    function reloadPlayers() {
        players = Model.livePlayers(Model.playerRecords(playersFile.text()), liveTitles);
    }

    function stopPlayer(record) {
        if (!record)
            return;
        var target = record.pid ? record.pid : record.title;
        if (!target)
            return;
        Quickshell.execDetached(command(["stop", target]));
    }

    function syncPlayingFromHistory() {
        if (playingId === "")
            return;
        var entry = Model.historyEntry(historyFile.text(), playingId);
        if (!entry)
            return;
        playingSeries = entry.title;
        playingEpisode = entry.episode;
        playingTitle = entry.title + " Episode " + entry.episode;
    }

    function search(query) {
        if (!ready || searchProcess.running || String(query).trim() === "")
            return;
        results = [];
        busy = true;
        searchProcess.command = command(["search", String(query)]);
        searchProcess.running = true;
    }

    function openSeries(id, title) {
        if (!ready || episodesProcess.running)
            return;
        selectedId = String(id);
        selectedTitle = String(title);
        episodes = [];
        busy = true;
        episodesProcess.command = command(["episodes", selectedId]);
        episodesProcess.running = true;
    }

    function play(id, title, episode, replacing) {
        if (!ready || launching)
            return;
        beginLaunch();
        playingQuality = "";
        playingId = String(id);
        playingSeries = String(title);
        playingEpisode = String(episode);
        playingTitle = title + " Episode " + episode;
        Quickshell.execDetached(command(["play", id, title, String(episode)], replacing));
    }

    function resume(row) {
        if (!ready || !row || launching)
            return;
        beginLaunch();
        playingQuality = "";
        playingId = String(row.animeId);
        playingSeries = String(row.title);
        playingEpisode = "";
        playingTitle = "";
        Quickshell.execDetached(command(["resume", row.animeId], Model.playingTitleOf(players, row.animeId)));
    }

    function playNext() {
        step("resume");
    }

    function playPrevious() {
        step("previous");
    }

    // The episode being left is always the one the menu was opened for, so the
    // replacement target is captured here rather than tracked as panel state
    // that a path into the menu could forget to set.
    function step(action) {
        if (!ready || playingId === "" || launching)
            return;
        beginLaunch();
        playingQuality = "";
        var replacing = playingTitle;
        playingEpisode = "";
        playingTitle = "";
        Quickshell.execDetached(command([action, playingId], replacing));
    }

    // Per play: it goes into the command, never into the stored settings.
    property string playingQuality: ""

    function playAtQuality(value) {
        if (!ready || playingId === "" || launching)
            return;
        var series = Model.seriesOf(players, playingId, playingSeries);
        var episode = Model.episodeOf(players, playingId, playingEpisode);
        if (series === "" || episode === "")
            return;
        var replacing = playingTitle;
        beginLaunch();
        playingQuality = String(value);
        Quickshell.execDetached(command(["play", playingId, series, episode], replacing, playingQuality));
    }

    function replayCurrent() {
        if (!ready || playingId === "")
            return;
        play(playingId, playingSeries, playingEpisode, playingTitle);
    }

    function stop() {
        launching = false;
        playingQuality = "";
        playingId = "";
        playingSeries = "";
        playingEpisode = "";
        playingTitle = "";
        Quickshell.execDetached(command(["stop", "all"]));
    }

    function clearHistory() {
        Quickshell.execDetached(command(["history-clear"]));
    }

    onHistoryLimitChanged: reloadHistory()
    // A step replaces a player of the same series, so the series cannot say
    // whether the new one has arrived. A pid that was not there when the launch
    // started can.
    onPlayersChanged: {
        if (Model.launchedPlayer(players, launchPids))
            launching = false;
    }

    function beginLaunch() {
        launchPids = players.map(function (p) {
            return p.pid;
        });
        launching = true;
    }

    onLiveTitlesChanged: reloadPlayers()

    // Sampled rather than read on exit: a player that has gone is no longer on
    // the bus to ask, so the last sample is what a resume has to go on.
    Timer {
        interval: 10000
        running: root.playing
        repeat: true
        onTriggered: root.reportProgress()
    }

    // A detached launch reports no exit status, so a launch that never produces
    // a player would otherwise hold every later one out for good.
    Timer {
        id: launchGivesUp
        interval: 20000
        running: root.launching
        onTriggered: root.launching = false
    }

    Process {
        id: statusProcess
        running: false
        command: []
        stdout: StdioCollector {
            id: statusOut
            waitForEnd: true
        }
        onExited: function (exitCode) {
            if (exitCode === 0)
                root.applyStatus(String(statusOut.text || "{}"));
            else
                root.ready = false;
        }
    }

    Process {
        id: searchProcess
        running: false
        command: []
        stdout: StdioCollector {
            id: searchOut
            waitForEnd: true
        }
        onExited: function (exitCode) {
            root.busy = false;
            if (exitCode === 0)
                root.results = Model.seriesRows(String(searchOut.text || ""));
        }
    }

    Process {
        id: episodesProcess
        running: false
        command: []
        stdout: StdioCollector {
            id: episodesOut
            waitForEnd: true
        }
        onExited: function (exitCode) {
            root.busy = false;
            if (exitCode === 0)
                root.episodes = Model.episodeRows(String(episodesOut.text || ""), Model.progressOf(historyFile.text(), root.selectedId));
        }
    }

    FileView {
        id: playersFile
        path: root.playersPath
        watchChanges: true
        printErrors: false
        onLoaded: root.reloadPlayers()
        onFileChanged: reload()
    }

    FileView {
        id: historyFile
        path: root.historyPath
        watchChanges: true
        printErrors: false
        onLoaded: root.reloadHistory()
        onFileChanged: reload()
    }

    Component.onCompleted: refresh()
}
