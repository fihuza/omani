import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import "Model.js" as Model

Item {
    id: root

    property var settings: ({})
    property string scriptPath: ""

    property bool ready: false
    property bool tracking: true
    property int watchedFraction: 100
    property string missing: ""
    property string version: ""
    property string repo: ""
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
    signal failed(string message)

    readonly property int historyLimit: intSetting("historyLimit", 8, 1, 20)
    readonly property string quality: String(setting("quality", "best"))
    readonly property string mode: String(setting("mode", "sub"))

    readonly property var playerList: Mpris.players ? Mpris.players.values : []
    readonly property var liveTitles: playerList.map(function (p) {
        return String(p.trackTitle || "");
    })

    function livePositions() {
        return playerList.map(function (p) {
            return {
                title: String(p.trackTitle || ""),
                position: Number(p.position) || 0,
                duration: Number(p.length) || 0,
                playing: p.isPlaying === true
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

    readonly property var currentPlayer: Model.playerFor(playerList, playingTitle)
    readonly property bool paused: currentPlayer ? currentPlayer.isPlaying !== true : false

    function togglePaused() {
        if (currentPlayer)
            currentPlayer.togglePlaying();
    }

    // mpris position is not a notifying property: quickshell reads it fresh
    // every time, but nothing tells a binding to look again. The tick is what
    // makes the clock move.
    property int clockTick: 0
    readonly property var progress: {
        clockTick;
        return Model.progressRows(players, livePositions());
    }

    Timer {
        id: clockTicks
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

    function command(args, qualityOverride) {
        return ["env", "OMANI_QUALITY=" + (qualityOverride || quality), "OMANI_MODE=" + mode, scriptPath].concat(args);
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
        watchedFraction = Number(parsed.watchedFraction) || watchedFraction;
        missing = String(parsed.missing || "");
        version = String(parsed.version || "");
        repo = String(parsed.repo || "");
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
        var target = Model.stopTarget(record);
        if (target === "")
            return;
        cancelLaunch();
        Quickshell.execDetached(command(["stop", target]));
    }

    property bool cancelled: false

    function cancelLaunch() {
        if (!launching)
            return;
        // Only a process still running will report an exit to swallow; one that
        // has already finished would leave the flag set for the next launch.
        cancelled = launchProcess.running;
        launchProcess.running = false;
        launching = false;
    }

    function syncPlayingFromHistory() {
        if (playingId === "" || Model.isPlayingSeries(players, playingId))
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

    function play(id, title, episode) {
        if (!ready || launching)
            return;
        beginLaunch();
        playingQuality = "";
        playingId = String(id);
        playingSeries = String(title);
        playingEpisode = String(episode);
        playingTitle = title + " Episode " + episode;
        launch(command(["play", id, title, String(episode)]));
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
        launch(command(["resume", row.animeId]));
    }

    function playNext() {
        step("next");
    }

    function playPrevious() {
        step("previous");
    }

    function step(action) {
        if (!ready || playingId === "" || launching)
            return;
        beginLaunch();
        playingQuality = "";
        playingEpisode = "";
        playingTitle = "";
        launch(command([action, playingId]));
    }

    property string playingQuality: ""

    function playAtQuality(value) {
        if (!ready || playingId === "" || launching)
            return;
        var series = Model.seriesOf(players, playingId, playingSeries);
        var episode = Model.episodeOf(players, playingId, playingEpisode);
        if (series === "" || episode === "")
            return;
        beginLaunch();
        playingQuality = String(value);
        launch(command(["play", playingId, series, episode], playingQuality));
    }

    function replayCurrent() {
        if (!ready || playingId === "")
            return;
        play(playingId, playingSeries, playingEpisode);
    }

    function stop() {
        cancelLaunch();
        playingQuality = "";
        playingId = "";
        playingSeries = "";
        playingEpisode = "";
        playingTitle = "";
        Quickshell.execDetached(command(["stop", "all"]));
    }

    function forget(animeId) {
        Quickshell.execDetached(command(["forget", animeId]));
    }

    function openLink(url) {
        Util.execArgv(["omarchy-launch-browser", String(url)]);
    }

    function clearHistory() {
        Quickshell.execDetached(command(["history-clear"]));
    }

    onHistoryLimitChanged: reloadHistory()
    onPlayersChanged: {
        if (Model.launchDone(tracking, players, launchPids))
            launching = false;
    }

    function launch(argv) {
        launchProcess.command = argv;
        launchProcess.running = true;
    }

    function beginLaunch() {
        cancelled = false;
        launchPids = Model.launchPids(players);
        launching = true;
    }

    onLiveTitlesChanged: reloadPlayers()

    Timer {
        id: historySample
        interval: 5000
        running: root.playing
        repeat: true
        onTriggered: root.reportProgress()
    }

    Process {
        id: launchProcess
        running: false
        command: []
        stderr: StdioCollector {
            id: launchErr
            waitForEnd: true
        }
        onExited: function (exitCode) {
            if (root.cancelled) {
                root.cancelled = false;
                return;
            }
            if (exitCode === 0) {
                if (Model.launchDone(root.tracking, root.players, root.launchPids))
                    root.launching = false;
                return;
            }
            root.launching = false;
            root.failed(Model.firstLine(String(launchErr.text || "the player could not be started")));
        }
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
        stderr: StdioCollector {
            id: searchErr
            waitForEnd: true
        }
        onExited: function (exitCode) {
            root.busy = false;
            if (exitCode === 0)
                root.results = Model.seriesRows(String(searchOut.text || ""));
            else
                root.failed(Model.firstLine(String(searchErr.text || "the search failed")));
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
        stderr: StdioCollector {
            id: episodesErr
            waitForEnd: true
        }
        onExited: function (exitCode) {
            root.busy = false;
            if (exitCode === 0)
                root.episodes = Model.episodeRows(String(episodesOut.text || ""), Model.progressOf(historyFile.text(), root.selectedId), root.watchedFraction);
            else
                root.failed(Model.firstLine(String(episodesErr.text || "the episode list could not be read")));
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
