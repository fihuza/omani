import QtQuick

QtObject {
    signal failed(string message)

    property bool ready: true
    property bool busy: false
    property bool launching: false
    property bool playing: false
    property bool paused: false
    property bool muted: false
    property bool playerReachable: true
    property bool tracking: true
    property string missing: ""
    property string version: "1.2.0"
    property string repo: "https://example.invalid/omani"
    property string quality: "best"
    property string mode: "sub"
    property string watched: "90"
    property var settings: ({})

    property var rows: []
    property var players: []
    property var results: []
    property var episodes: []
    property var progress: []

    property string playingId: ""
    property string playingSeries: ""
    property string playingEpisode: ""
    property string playingTitle: ""
    property string playingNow: ""
    property string playingQuality: ""
    property string selectedId: ""
    property string selectedTitle: ""

    property var asked: []
    function note(what) {
        var seen = asked.slice();
        seen.push(what);
        asked = seen;
    }

    function refresh() {
        note("refresh");
    }

    function reloadHistory() {
        note("history");
    }
    function reloadPlayers() {
        note("players");
    }
    function search(query) {
        note("search:" + query);
    }
    function openSeries(id, title) {
        note("openSeries:" + id);
    }
    function play(id, title, episode, start) {
        note("play:" + id + ":" + episode);
    }
    function resume(row) {
        note("resume");
    }
    function playNext() {
        note("next");
    }
    function playPrevious() {
        note("previous");
    }
    function replayCurrent() {
        note("replay");
    }
    function playAtQuality(value) {
        note("quality:" + value);
    }
    function stopPlayer(record) {
        note("stop");
    }
    function togglePaused() {
        note("pause");
    }
    function toggleMuted() {
        note("mute");
    }
    function forget(id) {
        note("forget:" + id);
    }
    function clearHistory() {
        note("clear");
    }
    function openLink(url) {
        note("open:" + url);
    }
}
