"use strict"

const { test } = require("node:test")
const assert = require("node:assert/strict")

const Model = require("../Model.js")

test("treats an empty or absent history as no rows", () => {
  assert.deepEqual(Model.parseHistory(""), [])
  assert.deepEqual(Model.parseHistory(null), [])
  assert.deepEqual(Model.parseHistory(undefined), [])
  assert.deepEqual(Model.parseHistory("\n\n  \n"), [])
})

test("going back from a view lands where it came from", () => {
  assert.equal(Model.backFrom("episodes"), "results")
  assert.equal(Model.backFrom("results"), "history")
  assert.equal(Model.backFrom("settings"), "history")
  assert.equal(Model.backFrom("shortcuts"), "history")
  assert.equal(Model.backFrom("player"), "history")
})

test("going back from the history closes the panel", () => {
  assert.equal(Model.backFrom("history"), "close")
  assert.equal(Model.backFrom("nonsense"), "close")
})

test("following a series replaces the episode on screen", () => {
  assert.equal(Model.replaces("player", "A Episode 1"), "A Episode 1")
  assert.equal(Model.replaces("episodes", "A Episode 1"), "A Episode 1")
})

test("starting from the watch history adds a player instead", () => {
  assert.equal(Model.replaces("history", "A Episode 1"), "")
  assert.equal(Model.replaces("results", "A Episode 1"), "")
})

test("with nothing playing there is nothing to replace", () => {
  assert.equal(Model.replaces("player", ""), "")
  assert.equal(Model.replaces("episodes", undefined), "")
})

test("player records are read back with every field", () => {
  const [record] = Model.playerRecords("4242\tNaruto Episode 79\tnaruto-1335\t79\t1080 720\n")
  assert.deepEqual(record, { pid: "4242", title: "Naruto Episode 79", animeId: "naruto-1335", episode: "79", qualities: "1080 720" })
})

test("incomplete records are skipped", () => {
  assert.deepEqual(Model.playerRecords("4242\tonly-two\n\t\t\t\n"), [])
  assert.deepEqual(Model.playerRecords(""), [])
  assert.deepEqual(Model.playerRecords(null), [])
})

test("a playing episode is reported against the series it belongs to", () => {
  const records = [{ pid: "1", title: "Naruto Episode 4", animeId: "naruto-1335", episode: "4", qualities: "" }]
  const players = [{ title: "Naruto Episode 4", position: 600, duration: 1400 }]
  assert.deepEqual(Model.progressReports(records, players), [
    { animeId: "naruto-1335", episode: "4", position: 600, duration: 1400 }
  ])
})

test("the right record is found among several", () => {
  const records = [
    { title: "Other Episode 9", animeId: "other", episode: "9" },
    { title: "Naruto Episode 4", animeId: "naruto-1335", episode: "4" }
  ]
  const players = [{ title: "Naruto Episode 4", position: 10, duration: 100 }]
  assert.deepEqual(Model.progressReports(records, players), [
    { animeId: "naruto-1335", episode: "4", position: 10, duration: 100 }
  ])
})

test("a player omani did not start is reported for nothing", () => {
  const players = [{ title: "Holiday Video", position: 10, duration: 100 }]
  assert.deepEqual(Model.progressReports([], players), [])
})

test("a player with nothing worth reporting yet is skipped", () => {
  const records = [{ title: "A Episode 1", animeId: "a", episode: "1" }]
  assert.deepEqual(Model.progressReports(records, [{ title: "A Episode 1", position: 0, duration: 1400 }]), [])
  assert.deepEqual(Model.progressReports(records, [{ title: "A Episode 1", position: 5, duration: 0 }]), [])
  assert.deepEqual(Model.progressReports(records, [{ title: "", position: 5, duration: 10 }]), [])
})

test("fractional seconds are not reported", () => {
  const records = [{ title: "A Episode 1", animeId: "a", episode: "1" }]
  const [report] = Model.progressReports(records, [{ title: "A Episode 1", position: 600.9, duration: 1400.4 }])
  assert.equal(report.position, 600)
  assert.equal(report.duration, 1400)
})

test("only records with a player still on the bus count as live", () => {
  const records = Model.playerRecords("1\tA Episode 1\ta\t1\n2\tB Episode 2\tb\t2\n")
  const live = Model.livePlayers(records, ["B Episode 2"])
  assert.deepEqual(live.map((r) => r.title), ["B Episode 2"])
})

test("a player the plugin did not start is not adopted", () => {
  const records = Model.playerRecords("1\tA Episode 1\ta\t1\n")
  assert.deepEqual(Model.livePlayers(records, ["Holiday Video"]), [])
})

test("a launch is done when a player appears that was not there before", () => {
  const before = ["100"]
  assert.equal(Model.launchedPlayer([{ pid: "100" }, { pid: "200" }], before), true)
})

test("the player being replaced does not end its own replacement", () => {
  const before = ["100"]
  assert.equal(Model.launchedPlayer([{ pid: "100" }], before), false)
})

test("no players at all is not a finished launch", () => {
  assert.equal(Model.launchedPlayer([], ["100"]), false)
})

test("a record with no anime id is never mistaken for the one playing", () => {
  const players = [{ pid: "1", title: "Someone Else Episode 2", animeId: "", episode: "2" }]
  assert.equal(Model.seriesOf(players, "", "remembered"), "remembered")
  assert.equal(Model.episodeOf(players, "", "7"), "7")
  assert.equal(Model.seriesOf(players, "", ""), "")
  assert.equal(Model.episodeOf(players, "", null), "")
})

test("the series name comes from the player that is actually running", () => {
  const players = [{ pid: "1", title: "Naruto Episode 34", animeId: "naruto-1335", episode: "34" }]
  assert.equal(Model.seriesOf(players, "naruto-1335", ""), "Naruto")
  assert.equal(Model.episodeOf(players, "naruto-1335", ""), "34")
})

test("the series is the title without the episode suffix", () => {
  assert.equal(Model.seriesTitle("Naruto Episode 79"), "Naruto")
  assert.equal(Model.seriesTitle("Re:ZERO -Starting Life- Episode 2"), "Re:ZERO -Starting Life-")
  assert.equal(Model.seriesTitle("Naruto"), "Naruto")
})

test("a title with no episode suffix is left whole", () => {
  const players = [{ title: "Naruto", animeId: "naruto-1335", episode: "1" }]
  assert.equal(Model.seriesOf(players, "naruto-1335", ""), "Naruto")
})

test("with no matching player the remembered value is used", () => {
  assert.equal(Model.seriesOf([], "naruto-1335", "Naruto"), "Naruto")
  assert.equal(Model.episodeOf([], "naruto-1335", "12"), "12")
  assert.equal(Model.seriesOf([], "naruto-1335", ""), "")
  assert.equal(Model.episodeOf([], "naruto-1335", ""), "")
})

test("nothing known leaves the label empty rather than undefined", () => {
  assert.equal(Model.seriesOf([], "", ""), "")
  assert.equal(Model.episodeOf([], "", null), "")
})

test("a series already playing names the player to replace", () => {
  const players = [
    { pid: "1", title: "Other Episode 2", animeId: "other", episode: "2" },
    { pid: "2", title: "Naruto Episode 8", animeId: "naruto-1335", episode: "8" }
  ]
  assert.equal(Model.playingTitleOf(players, "naruto-1335"), "Naruto Episode 8")
})

test("a series not playing names nothing to replace", () => {
  assert.equal(Model.playingTitleOf([{ animeId: "other", title: "Other Episode 2" }], "naruto-1335"), "")
  assert.equal(Model.playingTitleOf([], "naruto-1335"), "")
  assert.equal(Model.playingTitleOf([{ animeId: "a", title: "A" }], ""), "")
})

test("a series is playing when a live player carries its id", () => {
  const players = [{ pid: "1", title: "Naruto Episode 22", animeId: "naruto-1335", episode: "22" }]
  assert.equal(Model.isPlayingSeries(players, "naruto-1335"), true)
})

test("the episode may change without the series stopping", () => {
  const players = [{ pid: "1", title: "Naruto Episode 23", animeId: "naruto-1335", episode: "23" }]
  assert.equal(Model.isPlayingSeries(players, "naruto-1335"), true)
})

test("another series playing does not count", () => {
  const players = [{ pid: "1", title: "Frieren Episode 1", animeId: "frieren-1", episode: "1" }]
  assert.equal(Model.isPlayingSeries(players, "naruto-1335"), false)
})

test("no series selected is never playing", () => {
  assert.equal(Model.isPlayingSeries([{ animeId: "a" }], ""), false)
  assert.equal(Model.isPlayingSeries([], "naruto-1335"), false)
})

test("every playing episode leads the history, under one section", () => {
  const players = [
    { pid: "1", title: "A Episode 1", animeId: "a", episode: "1" },
    { pid: "2", title: "B Episode 2", animeId: "b", episode: "2" },
  ]
  const view = Model.historyView([{ animeId: "c", title: "C", label: "ep 3" }], players)
  assert.deepEqual(view.map((r) => r.kind), ["playing", "playing", "series"])
  assert.deepEqual(view.map((r) => r.section), ["PLAYING", "", "CONTINUE WATCHING"])
})

test("a series with a player of its own is not repeated below it", () => {
  const view = Model.historyView([{ animeId: "a", title: "A", label: "ep 2" }, { animeId: "b", title: "B", label: "ep 9" }], [{ pid: "1", title: "A Episode 2", animeId: "a", episode: "2" }])
  assert.deepEqual(view.map(r => r.kind), ["playing", "series"])
  assert.deepEqual(view.map(r => r.animeId), ["a", "b"])
})

test("the continue watching header lands on the first row that is kept", () => {
  const view = Model.historyView([{ animeId: "a", title: "A" }, { animeId: "b", title: "B" }], [{ pid: "1", title: "A Episode 2", animeId: "a", episode: "2" }])
  assert.equal(view[1].section, "CONTINUE WATCHING")
})

test("a playing row carries what the player menu needs to act", () => {
  const view = Model.historyView([], [{ pid: "7", title: "A Episode 1", animeId: "a", episode: "1" }])
  assert.equal(view[0].animeId, "a")
  assert.equal(view[0].episode, "1")
  assert.equal(view[0].pid, "7")
})

test("a playing row reads as the current one, a history row does not", () => {
  const view = Model.historyView([{ animeId: "b", title: "B" }], [{ pid: "7", title: "A Episode 1", animeId: "a", episode: "1" }])
  assert.equal(view[0].current, true)
  assert.equal(view[1].current, undefined)
})

test("nothing playing leaves only the watch history", () => {
  const view = Model.historyView([{ animeId: "a", title: "A", label: "ep 3" }], [])
  assert.deepEqual(view.map((r) => r.kind), ["series"])
  assert.equal(view[0].section, "CONTINUE WATCHING")
})

test("only the first series row opens the section", () => {
  const view = Model.historyView([{ animeId: "a", title: "A" }, { animeId: "b", title: "B" }], [])
  assert.deepEqual(view.map((r) => r.section), ["CONTINUE WATCHING", ""])
})

test("sectioning does not mutate the rows it was given", () => {
  const rows = [{ animeId: "a", title: "A" }]
  Model.historyView(rows, [])
  assert.equal(rows[0].kind, undefined)
})

const HISTORY = JSON.stringify({
  version: 1,
  series: {
    "naruto-1335": {
      title: "Naruto", episode: "4", updated: 200,
      episodes: {
        "1": { position: 1400, duration: 1400 },
        "3": { position: 700, duration: 1400 },
        "4": { position: 600, duration: 1400 }
      }
    },
    "frieren-1": { title: "Frieren", episode: "2", updated: 300, episodes: {} }
  }
})

test("the most recently watched series comes first", () => {
  assert.deepEqual(Model.parseHistory(HISTORY).map(r => r.animeId), ["frieren-1", "naruto-1335"])
})

test("a history that is not json is no history rather than a crash", () => {
  assert.deepEqual(Model.parseHistory("4\tnaruto\tNaruto"), [])
  assert.deepEqual(Model.parseHistory("{}"), [])
  assert.deepEqual(Model.parseHistory(""), [])
})

test("an entry missing its optional fields still reads", () => {
  const raw = JSON.stringify({ series: { a: { title: "A", episode: "1" } } })
  const [row] = Model.parseHistory(raw)
  assert.deepEqual(row.episodes, {})
  assert.equal(row.updated, 0)
  assert.equal(row.position, 0)
  assert.equal(row.duration, 0)
})

test("an entry with no title or episode is skipped", () => {
  const raw = JSON.stringify({ series: { a: { title: "", episode: "1" }, b: { title: "B" } } })
  assert.deepEqual(Model.parseHistory(raw), [])
})

test("how far through an episode is a whole percent", () => {
  assert.equal(Model.watchedFraction({ position: 600, duration: 1400 }), 43)
  assert.equal(Model.watchedFraction({ position: 0, duration: 1400 }), 0)
  assert.equal(Model.watchedFraction({ position: 2000, duration: 1400 }), 100)
  assert.equal(Model.watchedFraction({ position: 10, duration: 0 }), 0)
  assert.equal(Model.watchedFraction(null), 0)
})

test("a row part way through says so, one at the start does not", () => {
  assert.equal(Model.progressLabel({ episode: "4", position: 600, duration: 1400 }), "ep 4 \u00b7 43%")
  assert.equal(Model.progressLabel({ episode: "4", position: 0, duration: 1400 }), "ep 4")
})

test("each episode carries its own progress", () => {
  const rows = Model.episodeRows("9\t1\n8\t2\n7\t3\n", {
    "1": { position: 1400, duration: 1400 },
    "3": { position: 700, duration: 1400 }
  }, 90)
  assert.deepEqual(rows.map(r => r.label), ["watched", "", "50%"])
})

test("an episode near its end reads as watched rather than a number", () => {
  assert.equal(Model.episodeLabel({ position: 1260, duration: 1400 }, 90), "watched")
  assert.equal(Model.episodeLabel({ position: 1252, duration: 1400 }, 90), "89%")
  assert.equal(Model.episodeLabel({ position: 1120, duration: 1400 }, 80), "watched")
})

test("an episode with nothing recorded says nothing", () => {
  assert.equal(Model.episodeLabel(undefined, 90), "")
  assert.equal(Model.episodeLabel({ position: 10, duration: 0 }, 90), "")
  assert.deepEqual(Model.episodeRows("9\t1\n", {}, 90).map(r => r.label), [""])
  assert.deepEqual(Model.episodeRows("9\t1\n").map(r => r.label), [""])
})

test("the per-episode progress comes from the series in history", () => {
  assert.equal(Model.progressOf(HISTORY, "naruto-1335")["3"].position, 700)
  assert.deepEqual(Model.progressOf(HISTORY, "nothing"), {})
})

test("finds the history entry for a series", () => {
  const entry = Model.historyEntry(HISTORY, "naruto-1335")
  assert.equal(entry.episode, "4")
  assert.equal(entry.title, "Naruto")
})

test("reports nothing for a series not in history", () => {
  assert.equal(Model.historyEntry("12\tre-zero-123\tRe:Zero", "absent"), null)
  assert.equal(Model.historyEntry("", "re-zero-123"), null)
})

test("the limit keeps the most recently watched", () => {
  const raw = JSON.stringify({version: 1, series: {"a": {title: "A", episode: "1", position: 0, duration: 0, watched: [], updated: 1}, "b": {title: "B", episode: "2", position: 0, duration: 0, watched: [], updated: 2}, "c": {title: "C", episode: "3", position: 0, duration: 0, watched: [], updated: 3}}})
  assert.deepEqual(Model.historyRows(raw, 2).map((r) => r.title), ["C", "B"])
})

test("a non-positive or missing limit falls back to showing everything", () => {
  const raw = JSON.stringify({version: 1, series: {"a": {title: "A", episode: "1", position: 0, duration: 0, watched: [], updated: 1}, "b": {title: "B", episode: "2", position: 0, duration: 0, watched: [], updated: 2}}})
  assert.equal(Model.historyRows(raw, 0).length, 2)
  assert.equal(Model.historyRows(raw, -5).length, 2)
  assert.equal(Model.historyRows(raw).length, 2)
})

test("a row says which episode, and how far in when that is known", () => {
  const [row] = Model.historyRows(HISTORY, 1)
  assert.equal(row.label, "ep 2")
  const [naruto] = Model.historyRows(HISTORY, 2).slice(1)
  assert.equal(naruto.label, "ep 4 \u00b7 43%")
})

function list(over) {
  const base = { current: 0, viewport: 300, content: 1000, rowTop: 0, rowHeight: 40, index: 5, lastIndex: 20, margin: 6 }
  return Object.assign(base, over)
}

test("the first row shows the header above it rather than just itself", () => {
  assert.equal(Model.scrollTarget(list({ index: 0, current: 500 })), 0)
})

test("the last row goes to the very bottom", () => {
  assert.equal(Model.scrollTarget(list({ index: 20, lastIndex: 20 })), 700)
})

test("a list shorter than the viewport never scrolls", () => {
  assert.equal(Model.scrollTarget(list({ content: 120, index: 20, lastIndex: 20 })), 0)
})

test("a row above the viewport scrolls up to it, with a margin", () => {
  assert.equal(Model.scrollTarget(list({ current: 400, rowTop: 380 })), 374)
})

test("a row below the viewport scrolls down just far enough", () => {
  assert.equal(Model.scrollTarget(list({ current: 0, rowTop: 320 })), 66)
})

test("a row already in view leaves the list where it is", () => {
  assert.equal(Model.scrollTarget(list({ current: 100, rowTop: 150 })), 100)
})

test("a position left beyond the end still lands on the row", () => {
  assert.equal(Model.scrollTarget(list({ current: 5000, rowTop: 120, content: 1000 })), 114)
})

test("a stale position with the row already in view is pulled back into range", () => {
  assert.equal(Model.scrollTarget(list({ current: 5000, rowTop: 5100, content: 1000 })), 700)
})

test("scrolling never goes past the end to reach a row", () => {
  assert.equal(Model.scrollTarget(list({ current: 0, rowTop: 990, content: 1000 })), 700)
})

test("the shortcut list is non-empty and fully labelled", () => {
  const rows = Model.shortcuts()
  assert.ok(rows.length > 0)
  for (const row of rows) {
    assert.ok(row.keys.length > 0)
    assert.ok(row.action.length > 0)
  }
})

test("a panel that has nothing selected takes the player that is running", () => {
  const players = [{ pid: "1", title: "A Episode 1", animeId: "a", episode: "1" }, { pid: "2", title: "B Episode 2", animeId: "b", episode: "2" }]
  assert.equal(Model.adoptable(players, "").animeId, "a")
})

test("a selection that is still playing is left alone", () => {
  const players = [{ pid: "1", title: "A Episode 1", animeId: "a", episode: "1" }, { pid: "2", title: "B Episode 2", animeId: "b", episode: "2" }]
  assert.equal(Model.adoptable(players, "b"), null)
})

test("a selection whose player has gone is replaced by one that is live", () => {
  const players = [{ pid: "1", title: "A Episode 1", animeId: "a", episode: "1" }]
  assert.equal(Model.adoptable(players, "gone").animeId, "a")
})

test("with nothing playing there is nothing to adopt", () => {
  assert.equal(Model.adoptable([], ""), null)
  assert.equal(Model.adoptable(null, ""), null)
})

test("the variants come from the player that is running", () => {
  const players = [{ pid: "1", title: "A Episode 1", animeId: "a", episode: "1", qualities: "1080 720" }]
  assert.equal(Model.qualitiesOf(players, "a"), "1080 720")
  assert.equal(Model.qualitiesOf(players, "other"), "")
  assert.equal(Model.qualitiesOf(players, ""), "")
})

test("the quality list offers only what the episode has", () => {
  const rows = Model.qualityRows("1080 720 360", "720")
  assert.deepEqual(rows.map(r => r.key), ["1080", "720", "360"])
  assert.deepEqual(rows.map(r => r.title), ["1080p", "720p", "360p"])
  assert.equal(rows.find(r => r.key === "720").label, "playing")
  assert.equal(rows.filter(r => r.label === "playing").length, 1)
})

test("an episode reporting no variants offers nothing to choose", () => {
  assert.deepEqual(Model.qualityRows("", "720"), [])
  assert.deepEqual(Model.qualityRows(null, ""), [])
})

test("a quality nothing is playing at marks nothing", () => {
  assert.equal(Model.qualityRows("1080 720", "").filter(r => r.label !== "").length, 0)
})

test("a record carries the variants the episode was resolved with", () => {
  const rows = Model.playerRecords("9\tA Episode 1\ta\t1\t1080 720 480\n")
  assert.equal(rows[0].qualities, "1080 720 480")
})

test("a record written before variants were tracked still parses", () => {
  const rows = Model.playerRecords("9\tA Episode 1\ta\t1\n")
  assert.equal(rows[0].qualities, "")
})

test("leaving the quality list returns to the player it was opened from", () => {
  assert.equal(Model.backFrom("quality"), "player")
})

test("the player menu leads with the control for what is playing", () => {
  assert.deepEqual(Model.playerRows("Naruto", "5", false, "best").map(r => r.key),
    ["pause", "next", "replay", "previous", "select", "quality", "stop"])
})

test("the control says what pressing it does", () => {
  assert.equal(Model.playerRows("A", "1", false, "")[0].title, "Pause")
  assert.equal(Model.playerRows("A", "1", true, "")[0].title, "Resume")
})

test("the quality row says which one is playing", () => {
  const row = Model.playerRows("A", "1", false, "720").find(r => r.key === "quality")
  assert.equal(row.label, "720")
  assert.equal(Model.playerRows("A", "1", false, "").find(r => r.key === "quality").label, "")
})

test("replay names the episode it would repeat", () => {
  assert.equal(Model.playerRows("Naruto", "79").find(r => r.key === "replay").label, "episode 79")
})

test("replay says nothing when no episode is known", () => {
  assert.equal(Model.playerRows("Naruto", "").find(r => r.key === "replay").label, "")
})

test("select names the series it would list", () => {
  assert.equal(Model.playerRows("Naruto", "79").find(r => r.key === "select").label, "Naruto")
})

test("quality cycles through the offered values and wraps", () => {
  assert.equal(Model.nextSetting("quality", "best"), "1080")
  assert.equal(Model.nextSetting("quality", "worst"), "best")
})

test("mode toggles between sub and dub", () => {
  assert.equal(Model.nextSetting("mode", "sub"), "dub")
  assert.equal(Model.nextSetting("mode", "dub"), "sub")
})

test("an unrecognised value lands on the first option rather than nothing", () => {
  assert.equal(Model.nextSetting("quality", "nonsense"), "best")
  assert.equal(Model.nextSetting("mode", ""), "sub")
})

test("a setting row renders sub as subbed", () => {
  const [, audio] = Model.settingRows("best", "sub", "1.0.0")
  assert.equal(audio.label, "subbed")
})

test("an unknown setting is left alone rather than guessed at", () => {
  assert.equal(Model.nextSetting("nosuch", "value"), "value")
})

test("settings are rows like every other view, so the same keys drive them", () => {
  const rows = Model.settingRows("720", "dub", "1.0.0")
  assert.deepEqual(rows.map((r) => r.title), ["Quality", "Audio", "Version"])
  assert.deepEqual(rows.map((r) => r.label), ["720", "dubbed", "1.0.0"])
  assert.deepEqual(rows.map((r) => r.key), ["quality", "mode", "version"])
})

test("choosing a cycling row yields the next value", () => {
  const [quality] = Model.settingRows("best", "sub", "1.0.0")
  assert.deepEqual(Model.settingChange(quality), { key: "quality", value: "1080" })
})

test("choosing the version row writes nothing", () => {
  const [, , version] = Model.settingRows("best", "sub", "1.0.0")
  assert.equal(Model.settingChange(version), null)
})

test("a row whose value cannot move writes nothing", () => {
  assert.equal(Model.settingChange({ key: "unknown", value: "x" }), null)
})

test("the version row shows what it is and changes nothing when chosen", () => {
  const [, , version] = Model.settingRows("best", "sub", "1.0.0")
  assert.equal(version.label, "1.0.0")
  assert.equal(Model.nextSetting(version.key, version.value), "1.0.0")
})

test("a setting row carries the raw value, not just its label", () => {
  const [, audio] = Model.settingRows("best", "dub", "1.0.0")
  assert.equal(audio.label, "dubbed")
  assert.equal(audio.value, "dub")
  assert.equal(Model.nextSetting(audio.key, audio.value), "sub")
})

test("turns provider search output into series rows", () => {
  assert.deepEqual(Model.seriesRows("a-1\tAlpha\nb-2\tBeta\n"), [
    { animeId: "a-1", title: "Alpha" },
    { animeId: "b-2", title: "Beta" },
  ])
})

test("turns provider episode output into numbered rows", () => {
  assert.deepEqual(Model.episodeRows("9001\t1\n", {}, 90), [
    { episodeId: "9001", number: "1", title: "Episode 1", label: "" },
  ])
})

test("skips rows the provider could not fill", () => {
  assert.deepEqual(Model.seriesRows("a-1\tAlpha\nbroken\n\t\n\tOnlyTitle\n"), [
    { animeId: "a-1", title: "Alpha" },
  ])
})

test("treats no provider output as no rows", () => {
  assert.deepEqual(Model.seriesRows(""), [])
  assert.deepEqual(Model.seriesRows(null), [])
  assert.deepEqual(Model.episodeRows(undefined), [])
})

test("keeps a title containing spaces and punctuation intact", () => {
  assert.equal(Model.seriesRows("x-9\tCowboy Bebop: The Movie")[0].title, "Cowboy Bebop: The Movie")
})

test("tolerates carriage returns from the provider", () => {
  assert.equal(Model.seriesRows("a-1\tAlpha\r\n")[0].title, "Alpha")
})

test("a series title heads its own view in the platform's shape", () => {
  assert.equal(Model.heading({ player: "Naruto" }, "player", false, false), "NARUTO")
  assert.equal(Model.sectionLabel("Re:ZERO -Starting Life in Another World-"), "RE:ZERO -STARTING LIFE IN ANOTHER WORLD-")
})

test("a label that is missing heads nothing rather than the word undefined", () => {
  assert.equal(Model.sectionLabel(undefined), "")
  assert.equal(Model.sectionLabel(null), "")
})

function hero(over) {
  const base = { ready: true, tracking: true, missing: "", playing: false, nowPlaying: "", quality: "best", mode: "sub" }
  return Object.assign(base, over)
}

test("seconds read as a clock", () => {
  assert.equal(Model.clock(0), "0:00")
  assert.equal(Model.clock(9), "0:09")
  assert.equal(Model.clock(252), "4:12")
  assert.equal(Model.clock(1402), "23:22")
  assert.equal(Model.clock(3725), "1:02:05")
  assert.equal(Model.clock(4500), "1:15:00")
  assert.equal(Model.clock(-5), "0:00")
  assert.equal(Model.clock(null), "0:00")
})

test("elapsed is empty until the length is known", () => {
  assert.equal(Model.elapsed(252, 1402), "4:12 / 23:22")
  assert.equal(Model.elapsed(252, 0), "")
  assert.equal(Model.elapsed(0, 0), "")
})

test("the player on the bus is found by the title it reports", () => {
  const players = [{}, { trackTitle: "Other" }, { trackTitle: "Naruto Episode 5" }]
  assert.equal(Model.playerFor(players, "Naruto Episode 5").trackTitle, "Naruto Episode 5")
  assert.equal(Model.playerFor(players, "Nothing"), null)
  assert.equal(Model.playerFor(players, ""), null)
})

test("the hero says how far into what is playing", () => {
  const state = { ready: true, tracking: true, missing: "", playing: true, nowPlaying: "Naruto Episode 5", elapsed: "4:12 / 23:22", quality: "best", mode: "sub" }
  assert.equal(Model.heroMeta(state), "Naruto Episode 5")
  assert.equal(Model.heroDetail(state), "4:12 / 23:22")
  assert.equal(Model.heroDetail(Object.assign({}, state, { elapsed: "" })), "")
})

test("only the first line of a failure is shown", () => {
  assert.equal(Model.firstLine("omani: no episode after 12\nstack\ntrace"), "no episode after 12")
  assert.equal(Model.firstLine("omani-provider: episode 9999 not found"), "episode 9999 not found")
  assert.equal(Model.firstLine("no prefix here"), "no prefix here")
  assert.equal(Model.firstLine(""), "")
  assert.equal(Model.firstLine(null), "")
})

test("the clock is not shown for anything but a player that is running", () => {
  assert.equal(Model.heroDetail(hero({ playing: true, elapsed: "1:00", notice: "boom" })), "")
  assert.equal(Model.heroDetail(hero({ playing: true, elapsed: "1:00", ready: false })), "")
  assert.equal(Model.heroDetail(hero({ playing: false, elapsed: "1:00" })), "")
})

test("a failure outranks everything else the hero could say", () => {
  const state = { ready: true, tracking: true, missing: "", playing: true, nowPlaying: "X", elapsed: "1:00 / 2:00", quality: "best", mode: "sub", notice: "no playable source" }
  assert.equal(Model.heroMeta(state), "no playable source")
})

test("a missing dependency is what the hero says", () => {
  assert.equal(Model.heroMeta(hero({ ready: false, missing: "mpv" })), "missing: mpv")
})

test("losing player tracking is said without claiming the plugin is broken", () => {
  assert.equal(Model.heroMeta(hero({ tracking: false })), "mpv-mpris missing \u00b7 players are not tracked")
})

test("what is playing outranks the settings summary", () => {
  assert.equal(Model.heroMeta(hero({ playing: true, nowPlaying: "Naruto Episode 3" })), "Naruto Episode 3")
})

test("with nothing playing the hero summarises the settings", () => {
  assert.equal(Model.heroMeta(hero({ quality: "1080", mode: "dub" })), "1080 \u00b7 dub")
})

test("a launch that has not produced a player yet says so", () => {
  const labels = { history: "Continue watching" }
  assert.equal(Model.heading(labels, "history", false, true), "STARTING\u2026")
})

test("a launch outranks a query still loading", () => {
  assert.equal(Model.heading({}, "history", true, true), "STARTING\u2026")
})

test("a query in flight reports loading", () => {
  assert.equal(Model.heading({}, "results", true, false), "LOADING\u2026")
})

test("with nothing in flight the view names itself", () => {
  assert.equal(Model.heading({ results: "Results" }, "results", false, false), "RESULTS")
})

test("a view with no label heads nothing rather than undefined", () => {
  assert.equal(Model.heading({}, "nowhere", false, false), "")
  assert.equal(Model.heading(null, "nowhere", false, false), "")
})

test("maps the control characters Qt reports for ctrl-d and ctrl-u", () => {
  // PanelKeyCatcher forwards any single character to onTextKey without
  // inspecting modifiers, so Ctrl-D arrives as the raw 0x04 byte.
  assert.equal(Model.normalizeKey("\u0004"), "ctrl+d")
  assert.equal(Model.normalizeKey("\u0015"), "ctrl+u")
})

test("passes ordinary characters through unchanged", () => {
  assert.equal(Model.normalizeKey("g"), "g")
  assert.equal(Model.normalizeKey("/"), "/")
})

test("normalizes nothing to an empty string", () => {
  assert.equal(Model.normalizeKey(null), "")
  assert.equal(Model.normalizeKey(undefined), "")
})

const ctx = { rowCount: 10, pageSize: 4 }
const start = () => Model.initialKeyState()

function press(keys, context = ctx, state = start()) {
  let command = null
  for (const key of [].concat(keys)) {
    const result = Model.reduceKey(state, key, context)
    state = result.state
    command = result.command
  }
  return { state, command }
}

test("starts with no selection and no pending input", () => {
  assert.deepEqual(start(), { index: 0, pendingCount: "", pendingG: false })
})

test("j and k move one row and clamp at both ends", () => {
  assert.equal(press("j").state.index, 1)
  assert.equal(press(["j", "j", "k"]).state.index, 1)
  assert.equal(press("k").state.index, 0, "does not move above the first row")
  assert.equal(press("jjjjjjjjjjjjjjj".split("")).state.index, 9, "stops at the last row")
})

test("a count prefix repeats a motion", () => {
  assert.equal(press(["3", "j"]).state.index, 3)
  assert.equal(press(["9", "j", "2", "k"]).state.index, 7)
})

test("a multi-digit count is accumulated", () => {
  assert.equal(press(["1", "2", "j"], { rowCount: 30, pageSize: 4 }).state.index, 12)
})

test("the count is consumed by the motion it applies to", () => {
  const after = press(["3", "j"])
  assert.equal(after.state.pendingCount, "")
  assert.equal(Model.reduceKey(after.state, "j", ctx).state.index, 4, "next j moves one, not three")
})

test("a pending count is visible so half-typed input is not invisible state", () => {
  assert.equal(press(["1", "2"]).state.pendingCount, "12")
})

test("gg jumps to the first row and G to the last", () => {
  const atBottom = press("G")
  assert.equal(atBottom.state.index, 9)
  assert.equal(Model.reduceKey(Model.reduceKey(atBottom.state, "g", ctx).state, "g", ctx).state.index, 0)
})

test("a single g arms the sequence without moving", () => {
  const armed = press(["5", "j", "g"])
  assert.equal(armed.state.index, 5, "still on the row it was on")
  assert.equal(armed.state.pendingG, true)
})

test("a count with G or gg goes to that row, as vim does", () => {
  assert.equal(press(["4", "G"]).state.index, 3, "4G is the fourth row, zero-indexed 3")
  assert.equal(press(["4", "g", "g"]).state.index, 3)
})

test("a count beyond the last row clamps instead of overshooting", () => {
  assert.equal(press(["99", "G"]).state.index, 9)
  assert.equal(press(["9", "9", "j"]).state.index, 9)
})

test("an unrecognized key cancels a pending g", () => {
  const after = press(["g", "z"])
  assert.equal(after.state.pendingG, false)
  assert.equal(after.command, null)
})

test("an unrecognized key cancels a pending count", () => {
  assert.equal(press(["3", "z"]).state.pendingCount, "")
})

test("ctrl-d and ctrl-u move by a page", () => {
  assert.equal(press("ctrl+d").state.index, 4)
  assert.equal(press(["G", "ctrl+u"]).state.index, 5)
})

test("a page move clamps at the ends", () => {
  assert.equal(press(["ctrl+u"]).state.index, 0)
  assert.equal(press(["ctrl+d", "ctrl+d", "ctrl+d"]).state.index, 9)
})

test("a page of zero rows never divides by nothing", () => {
  const empty = { rowCount: 0, pageSize: 0 }
  assert.equal(press("ctrl+d", empty).state.index, 0)
  assert.equal(press("j", empty).state.index, 0)
  assert.equal(press("G", empty).state.index, 0)
})

test("enter plays the selected row", () => {
  const { command } = press(["2", "j", "enter"])
  assert.deepEqual(command, { type: "play", index: 2 })
})

test("enter on an empty list asks for nothing", () => {
  assert.equal(press("enter", { rowCount: 0, pageSize: 4 }).command, null)
})

test("s toggles the settings view", () => {
  assert.deepEqual(press("s").command, { type: "toggleSettings" })
})

test("question mark toggles the shortcut list", () => {
  assert.deepEqual(press("?").command, { type: "toggleShortcuts" })
})

test("slash and i open the search field", () => {
  assert.deepEqual(press("/").command, { type: "focusSearch" })
  assert.deepEqual(press("i").command, { type: "focusSearch" })
})

test("d forgets the selected row", () => {
  assert.deepEqual(press(["2", "j", "d"]).command, { type: "forget", index: 2 })
})

test("d on an empty list forgets nothing", () => {
  assert.equal(press("d", { rowCount: 0, pageSize: 4 }).command, null)
})

test("only a series in the watch history can be forgotten", () => {
  assert.equal(Model.forgettable("history", { kind: "series" }), true)
  assert.equal(Model.forgettable("history", { kind: "playing" }), false)
  assert.equal(Model.forgettable("episodes", { kind: "series" }), false)
  assert.equal(Model.forgettable("history", undefined), false)
})

test("c clears the history and r refreshes", () => {
  assert.deepEqual(press("c").command, { type: "clearHistory" })
  assert.deepEqual(press("r").command, { type: "refresh" })
})

test("q closes the panel", () => {
  assert.deepEqual(press("q").command, { type: "close" })
})

test("escape cancels pending input before it closes anything", () => {
  const pending = press(["3", "escape"])
  assert.equal(pending.command, null, "the first escape only cancels the count")
  assert.equal(pending.state.pendingCount, "")
  assert.deepEqual(Model.reduceKey(pending.state, "escape", ctx).command, { type: "close" })
})

test("escape cancels a pending g before it closes anything", () => {
  assert.equal(press(["g", "escape"]).command, null)
})

test("escape with nothing pending closes the panel", () => {
  assert.deepEqual(press("escape").command, { type: "close" })
})

test("zero moves to the first row when no count is being typed", () => {
  assert.equal(press(["5", "j", "0"]).state.index, 0)
})

test("zero continues a count that is already being typed", () => {
  assert.equal(press(["1", "0", "j"], { rowCount: 30, pageSize: 4 }).state.index, 10)
})

test("the reducer never mutates the state it is given", () => {
  const before = start()
  const frozen = Object.freeze({ ...before })
  Model.reduceKey(frozen, "j", ctx)
  assert.deepEqual(frozen, before)
})

test("a missing context is treated as an empty list rather than crashing", () => {
  assert.equal(Model.reduceKey(start(), "j").state.index, 0)
  assert.equal(Model.reduceKey(start(), "G").state.index, 0)
})

test("an index left beyond a shrunken list is pulled back into range", () => {
  // The history file can change under the panel while it is open.
  const stale = { index: 8, pendingCount: "", pendingG: false }
  assert.equal(Model.reduceKey(stale, "j", { rowCount: 3, pageSize: 4 }).state.index, 2)
})
