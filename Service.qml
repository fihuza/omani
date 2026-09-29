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
    readonly property string watched: String(setting("watched", "90"))

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
            run(["progress", reports[i].animeId, reports[i].episode, String(reports[i].position), String(reports[i].duration)]);
    }
    readonly property bool playing: players.length > 0

    readonly property var currentPlayer: Model.playerFor(playerList, playingTitle)
    readonly property bool paused: currentPlayer ? currentPlayer.isPlaying !== true : false

    readonly property bool playerReachable: currentPlayer !== null

    function togglePaused() {
        if (!playerReachable) {
            failed("this player is not answering, so it cannot be paused from here");
            return;
        }
        currentPlayer.togglePlaying();
    }

    property real volumeBeforeMute: 1.0
    readonly property bool muted: currentPlayer ? currentPlayer.volume <= 0 : false

    function toggleMuted() {
        if (!playerReachable) {
            failed("this player is not answering, so it cannot be muted from here");
            return;
        }
        if (muted) {
            currentPlayer.volume = Model.restoredVolume(volumeBeforeMute);
            return;
        }
        volumeBeforeMute = currentPlayer.volume;
        currentPlayer.volume = 0;
    }

    property int mprisPositionTick: 0
    readonly property var progress: {
        mprisPositionTick;
        return Model.progressRows(players, livePositions());
    }

    Timer {
        id: mprisPositionPoll
        interval: 1000
        running: root.playing
        repeat: true
        onTriggered: root.mprisPositionTick++
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

    function command(args) {
        return [scriptPath].concat(args);
    }

    function settingsEnv(qualityOverride) {
        return {
            OMANI_QUALITY: qualityOverride || quality,
            OMANI_MODE: mode,
            OMANI_WATCHED_FRACTION: watched
        };
    }

    function run(args) {
        Quickshell.execDetached({
            command: command(args),
            environment: settingsEnv("")
        });
    }

    function refresh() {
        if (scriptPath === "" || statusProcess.running)
            return;
        statusProcess.command = command(["status"]);
        statusProcess.running = true;
    }

    function applyStatus(raw) {
        var status = Model.statusFields(raw, watchedFraction);
        if (!status) {
            ready = false;
            return;
        }
        ready = status.ready;
        tracking = status.tracking;
        watchedFraction = status.watchedFraction;
        missing = status.missing;
        version = status.version;
        repo = status.repo;
        historyPath = status.historyPath;
        playersPath = status.playersPath;
    }

    function reloadHistory() {
        rows = Model.historyRows(historyFile.text(), historyLimit);
        syncPlayingFromHistory();
    }

    property var livePids: null

    function reloadPlayers() {
        applyPlayers();
        if (scriptPath !== "" && !playersProcess.running) {
            playersProcess.command = command(["players"]);
            playersProcess.running = true;
        }
    }

    function applyPlayers() {
        players = Model.livePlayers(Model.playerRecords(playersFile.text()), liveTitles, livePids);
    }

    function stopPlayer(record) {
        var target = Model.stopTarget(record);
        if (target === "")
            return;
        cancelLaunch();
        run(["stop", target]);
    }

    property bool swallowNextExit: false

    function cancelLaunch() {
        if (!launching)
            return;
        launchWait.stop();
        swallowNextExit = launchProcess.running;
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

    function play(id, title, episode, start) {
        if (!ready || launching)
            return;
        var args = ["play", id, title, String(episode)];
        if (start !== undefined)
            args.push(String(start));
        beginLaunch();
        playingQuality = "";
        playingId = String(id);
        playingSeries = String(title);
        playingEpisode = String(episode);
        playingTitle = title + " Episode " + episode;
        launch(command(args));
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
        launch(command(["play", playingId, series, episode]), playingQuality);
    }

    function replayCurrent() {
        if (!ready || playingId === "")
            return;
        play(playingId, playingSeries, playingEpisode, 0);
    }

    function stop() {
        cancelLaunch();
        playingQuality = "";
        playingId = "";
        playingSeries = "";
        playingEpisode = "";
        playingTitle = "";
        run(["stop", "all"]);
    }

    function forget(animeId) {
        run(["forget", animeId]);
    }

    function openLink(url) {
        Util.execArgv(["omarchy-launch-browser", String(url)]);
    }

    function clearHistory() {
        run(["history-clear"]);
    }

    onHistoryLimitChanged: reloadHistory()
    onPlayersChanged: settleLaunch()

    property bool waitedTooLong: false

    function settleLaunch() {
        if (launching && Model.launchDone(tracking, players, launchPids, waitedTooLong)) {
            launching = false;
            launchWait.stop();
        }
    }

    function abandonLaunch(message) {
        launching = false;
        launchWait.stop();
        failed(message);
    }

    Timer {
        id: launchWait
        interval: 10000
        onTriggered: {
            root.waitedTooLong = true;
            root.settleLaunch();
        }
    }

    function launch(argv, qualityOverride) {
        launchProcess.environment = settingsEnv(qualityOverride);
        launchProcess.command = argv;
        launchProcess.running = true;
    }

    function beginLaunch() {
        swallowNextExit = false;
        waitedTooLong = false;
        launchWait.stop();
        launchPids = Model.launchPids(players);
        launching = true;
    }

    onLiveTitlesChanged: reloadPlayers()

    Timer {
        id: playersPoll
        interval: root.launching ? 700 : 2000
        running: root.launching || root.playing
        repeat: true
        onTriggered: root.reloadPlayers()
    }

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
            if (root.swallowNextExit) {
                root.swallowNextExit = false;
                return;
            }
            if (exitCode === 0) {
                launchWait.restart();
                root.settleLaunch();
                return;
            }
            root.abandonLaunch(Model.firstLine(String(launchErr.text || "the player could not be started")));
        }
    }

    Process {
        id: playersProcess
        running: false
        command: []
        environment: root.settingsEnv("")
        stdout: StdioCollector {
            id: playersOut
            waitForEnd: true
        }
        onExited: function (exitCode) {
            if (exitCode === 0)
                root.livePids = Model.launchPids(Model.playerRecords(String(playersOut.text || "")));
            root.applyPlayers();
        }
    }

    Process {
        id: statusProcess
        running: false
        command: []
        environment: root.settingsEnv("")
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
        environment: root.settingsEnv("")
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
        environment: root.settingsEnv("")
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
