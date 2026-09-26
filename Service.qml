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

    readonly property int historyLimit: intSetting("historyLimit", 8, 1, 20)
    readonly property string quality: String(setting("quality", "best"))
    readonly property string mode: String(setting("mode", "sub"))
    readonly property bool showNowPlaying: setting("showNowPlaying", true) === true

    readonly property var playerList: Mpris.players ? Mpris.players.values : []
    readonly property var liveTitles: playerList.map(function (p) {
        return String(p.trackTitle || "");
    })
    readonly property bool playing: players.length > 0
    readonly property string nowPlaying: players.length > 0 ? players[0].title : ""

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

    function command(args, replacing) {
        return ["env", "OMANI_QUALITY=" + quality, "OMANI_MODE=" + mode, "OMANI_REPLACE=" + (replacing || ""), scriptPath].concat(args);
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
        launching = true;
        playingId = String(id);
        playingSeries = String(title);
        playingEpisode = String(episode);
        playingTitle = title + " Episode " + episode;
        Quickshell.execDetached(command(["play", id, title, String(episode)], replacing));
    }

    function resume(row) {
        if (!ready || !row || launching)
            return;
        launching = true;
        playingId = String(row.animeId);
        playingSeries = String(row.title);
        playingEpisode = "";
        playingTitle = "";
        Quickshell.execDetached(command(["resume", row.animeId]));
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
        launching = true;
        var replacing = playingTitle;
        playingEpisode = "";
        playingTitle = "";
        Quickshell.execDetached(command([action, playingId], replacing));
    }

    function replayCurrent() {
        if (!ready || playingId === "")
            return;
        play(playingId, playingSeries, playingEpisode, playingTitle);
    }

    function stop() {
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
    // A detached launch has no process to watch, so the player set changing is
    // the only evidence the request took effect.
    onPlayersChanged: launching = false

    onLiveTitlesChanged: reloadPlayers()

    Timer {
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
                root.episodes = Model.episodeRows(String(episodesOut.text || ""));
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
