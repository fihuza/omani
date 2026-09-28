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

test("a record whose process is gone is not live, however the bus still names it", () => {
  const records = Model.playerRecords("220332\tNaruto Episode 4\tnaruto-1335\t4\t800\n")
  assert.deepEqual(Model.livePlayers(records, ["Naruto Episode 4"], ["2906198"]), [],
    "an orphan player keeps the title on the bus; the dead record must not ride on it")
})

test("a record is live when the script still reports its pid", () => {
  const records = Model.playerRecords("2906198\tNaruto Episode 4\tnaruto-1335\t4\t800\n")
  const live = Model.livePlayers(records, ["Naruto Episode 4"], ["2906198"])
  assert.deepEqual(live.map((r) => r.pid), ["2906198"])
})

test("with no pid list the bus alone decides, as it did before", () => {
  const records = Model.playerRecords("1\tA Episode 1\ta\t1\n")
  assert.deepEqual(Model.livePlayers(records, ["A Episode 1"]).map((r) => r.pid), ["1"])
})

test("a player the plugin did not start is not adopted", () => {
  const records = Model.playerRecords("1\tA Episode 1\ta\t1\n")
  assert.deepEqual(Model.livePlayers(records, ["Holiday Video"]), [])
})

test("a launch is over once a player appears that was not running when it began", () => {
  const before = Model.launchPids([{ pid: "1" }])
  assert.deepEqual(before, ["1"])
  assert.equal(Model.launchDone(true, [{ pid: "1" }], before), false)
  assert.equal(Model.launchDone(true, [], before), false)
  assert.equal(Model.launchDone(true, [{ pid: "2" }], before), true)
  assert.equal(Model.launchDone(true, [{ pid: "1" }, { pid: "2" }], before), true)
})

test("the snapshot of what was running is taken from the players themselves", () => {
  assert.deepEqual(Model.launchPids([{ pid: "7", title: "A" }, { pid: "9" }]), ["7", "9"])
  assert.deepEqual(Model.launchPids([]), [])
  assert.deepEqual(Model.launchPids(null), [])
})

test("a failure that arrived while the panel was shut is still shown when it opens", () => {
  assert.equal(Model.noticeOnOpen("the player could not be started", true), "the player could not be started")
})

test("a failure the panel already showed is cleared when it opens again", () => {
  assert.equal(Model.noticeOnOpen("the player could not be started", false), "")
})

test("opening with nothing to report says nothing", () => {
  assert.equal(Model.noticeOnOpen("", true), "")
  assert.equal(Model.noticeOnOpen("", false), "")
})

test("a launch stops waiting once it has waited too long", () => {
  const before = ["1"]
  const unchanged = [{ pid: "1", title: "A Episode 1", animeId: "a", episode: "1" }]
  assert.equal(Model.launchDone(true, unchanged, before, false), false,
    "still waiting for the player to appear")
  assert.equal(Model.launchDone(true, unchanged, before, true), true,
    "a player that never appears must not block every later launch")
})

test("waiting too long is not needed once a player has appeared", () => {
  const before = ["1"]
  const appeared = [{ pid: "2", title: "B Episode 1", animeId: "b", episode: "1" }]
  assert.equal(Model.launchDone(true, appeared, before, false), true)
})

test("a launch with nothing to watch for is over when the script exits", () => {
  assert.equal(Model.launchDone(false, [], []), true)
  assert.equal(Model.launchDone(true, [], []), false)
  assert.equal(Model.launchDone(true), false)
  assert.equal(Model.launchDone(true, [{ pid: "2" }], ["1"]), true)
  assert.equal(Model.launchDone(true, [{ pid: "1" }], ["1"]), false)
})

test("the row under the bar icon is one that is not already playing", () => {
  const rows = [{ animeId: "a", title: "A" }, { animeId: "b", title: "B" }]
  const players = [{ pid: "1", title: "A Episode 1", animeId: "a", episode: "1" }]
  assert.equal(Model.resumeTarget(rows, players).animeId, "b")
  assert.equal(Model.resumeTarget(rows, []).animeId, "a")
  assert.equal(Model.resumeTarget([], players), null)
  assert.equal(Model.resumeTarget(rows, [{ pid: "1", animeId: "b" }]).animeId, "a")
  assert.equal(Model.resumeTarget(rows, [{ pid: "1", animeId: "a" }, { pid: "2", animeId: "b" }]), null)
})

test("a row's label reads the progress of the player it belongs to", () => {
  const progress = [{ animeId: "a", title: "A Episode 3", fraction: 0.45 }]
  assert.equal(Model.rowLabel({ kind: "playing", title: "A Episode 3", episode: "3", label: "" }, progress), "ep 3 \u00b7 45%")
  assert.equal(Model.rowLabel({ kind: "playing", title: "B Episode 1", episode: "1", label: "" }, progress), "ep 1")
  assert.equal(Model.rowLabel({ kind: "series", label: "ep 9 \u00b7 12%" }, progress), "ep 9 \u00b7 12%")
  assert.equal(Model.rowLabel({ title: "x" }, progress), "")
  assert.equal(Model.rowLabel(null, progress), "")
})

test("a launch is done when a player appears that was not there before", () => {
  assert.equal(Model.launchDone(true, [{ pid: "100" }, { pid: "200" }], ["100"]), true)
})

test("the player being replaced does not end its own replacement", () => {
  const before = ["100"]
  assert.equal(Model.launchDone(true, [{ pid: "100" }], before), false)
})

test("no players at all is not a finished launch", () => {
  assert.equal(Model.launchDone(true, [], ["100"]), false)
})

test("a record with no anime id is never mistaken for the one playing", () => {
  const players = [{ pid: "1", title: "Someone Else Episode 2", animeId: "", episode: "2" }]
  assert.equal(Model.seriesOf(players, "", "remembered"), "remembered")
  assert.equal(Model.episodeOf(players, "", "7"), "7")
  assert.equal(Model.seriesOf(players, "", ""), "")
  assert.equal(Model.episodeOf(players, "", null), "")
})

test("a series whose own name ends in an episode is not cut short", () => {
  const [record] = Model.playerRecords("42\tPtolemaic Episode 0 Episode 3\tp-1\t3\t1080\tPtolemaic Episode 0\n")
  assert.equal(Model.seriesOf([record], "p-1", ""), "Ptolemaic Episode 0")
})

test("a record with no qualities still names its series", () => {
  const [record] = Model.playerRecords("42\tNaruto Episode 79\tnaruto-1335\t79\n")
  assert.equal(Model.seriesOf([record], "naruto-1335", ""), "Naruto")
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

test("two episodes of one series both lead the list, and it is not repeated", () => {
  const players = [{ pid: "1", title: "A Episode 1", animeId: "a", episode: "1" }, { pid: "2", title: "A Episode 2", animeId: "a", episode: "2" }]
  const view = Model.historyView([{ animeId: "a", title: "A", label: "ep 2" }, { animeId: "b", title: "B", label: "ep 1" }], players)
  assert.deepEqual(view.map(r => r.kind), ["playing", "playing", "series"])
  assert.deepEqual(view.map(r => r.animeId), ["a", "a", "b"])
  assert.equal(view[2].section, "CONTINUE WATCHING")
})

test("a playing row says which episode and how far in", () => {
  const players = [{ pid: "7", title: "A Episode 3", animeId: "a", episode: "3" }]
  const progress = Model.progressRows(players, [{ title: "A Episode 3", position: 450, duration: 1000, playing: true }])
  const row = Model.historyView([], players)[0]
  assert.equal(Model.rowLabel(row, progress), "ep 3 \u00b7 45%")
})

test("a playing row with nothing reported yet says only the episode", () => {
  const players = [{ pid: "7", title: "A Episode 3", animeId: "a", episode: "3" }]
  const row = Model.historyView([], players)[0]
  assert.equal(Model.rowLabel(row, Model.progressRows(players, [])), "ep 3")
  assert.equal(Model.rowLabel(row, []), "ep 3")
  assert.equal(Model.rowLabel(row, undefined), "ep 3")
})

test("a player whose series was forgotten still leads the list", () => {
  const players = [{ pid: "7", title: "A Episode 3", animeId: "a", episode: "3" }]
  const view = Model.historyView([{ animeId: "b", title: "B", label: "ep 1" }], players)
  assert.deepEqual(view.map(r => r.kind), ["playing", "series"])
  assert.equal(view[0].animeId, "a")
})

test("a playing row carries what the player menu needs to act", () => {
  const view = Model.historyView([], [{ pid: "7", title: "A Episode 1", animeId: "a", episode: "1" }])
  assert.equal(view[0].animeId, "a")
  assert.equal(view[0].episode, "1")
  assert.equal(view[0].pid, "7")
})

test("the cursor starts below whatever is playing", () => {
  const view = Model.historyView([{ animeId: "b", title: "B" }], [{ pid: "7", title: "A Episode 1", animeId: "a", episode: "1" }])
  assert.equal(Model.startIndex(view), 1)
  assert.equal(Model.startIndex(Model.historyView([{ animeId: "b", title: "B" }], [])), 0)
})

test("with nothing but players the cursor starts at the top", () => {
  assert.equal(Model.startIndex(Model.historyView([], [{ pid: "7", title: "A Episode 1", animeId: "a", episode: "1" }])), 0)
  assert.equal(Model.startIndex([]), 0)
  assert.equal(Model.startIndex(null), 0)
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

test("an episode number carrying a decimal is kept as written", () => {
  const raw = JSON.stringify({ version: 1, series: { a: { title: "A", episode: "7.5", updated: 2, episodes: { "7.5": { position: 60, duration: 1200 } } } } })
  const rows = Model.parseHistory(raw)
  assert.equal(rows[0].episode, "7.5")
  assert.equal(rows[0].position, 60)
  assert.equal(Model.progressLabel(rows[0]), "ep 7.5 \u00b7 5%")
})

test("an entry whose episodes are not an object is still readable", () => {
  const raw = JSON.stringify({ version: 1, series: { a: { title: "A", episode: "2", updated: 1, episodes: "nonsense" } } })
  const rows = Model.parseHistory(raw)
  assert.equal(rows.length, 1)
  assert.equal(rows[0].position, 0)
  assert.equal(rows[0].duration, 0)
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

test("the last row is reached even while the content height lags behind it", () => {
  const at = Model.scrollTarget({
    current: 0, viewport: 400, content: 5000, rowTop: 5200, rowHeight: 50,
    index: 219, lastIndex: 219, margin: 30
  })
  assert.equal(at, 4850, "the last row sits against the bottom of the viewport")
})

test("a content taller than the last row still ends at the content", () => {
  const at = Model.scrollTarget({
    current: 0, viewport: 400, content: 6000, rowTop: 5200, rowHeight: 50,
    index: 219, lastIndex: 219, margin: 30
  })
  assert.equal(at, 5600, "trailing space below the last row is still scrolled to")
})

test("the last row goes to the very bottom", () => {
  assert.equal(Model.scrollTarget(list({ index: 20, lastIndex: 20 })), 700)
})

test("the last row of a list that fits does not scroll", () => {
  assert.equal(Model.scrollTarget({ current: 0, viewport: 400, content: 400, rowTop: 360, rowHeight: 30, index: 9, lastIndex: 9, margin: 6 }), 0)
  assert.equal(Model.scrollTarget({ current: 0, viewport: 400, content: 380, rowTop: 340, rowHeight: 30, index: 9, lastIndex: 9, margin: 6 }), 0)
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

test("a margin wider than the viewport lands on the end rather than past it", () => {
  const at = Model.scrollTarget({ current: 0, viewport: 40, content: 400, rowTop: 200, rowHeight: 30, index: 5, lastIndex: 9, margin: 200 })
  assert.equal(at, 360, "the furthest the list can scroll, not beyond it")
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

test("the caption names the episode under the series heading", () => {
  assert.equal(Model.episodeCaption("4"), "Episode 4")
  assert.equal(Model.episodeCaption("7.5"), "Episode 7.5")
})

test("nothing is captioned when the episode is not known yet", () => {
  assert.equal(Model.episodeCaption(""), "")
  assert.equal(Model.episodeCaption(null), "")
  assert.equal(Model.episodeCaption(undefined), "")
})

test("unmuting restores the level the player had", () => {
  assert.equal(Model.restoredVolume(0.54), 0.54)
})

test("a player muted from silence comes back audible", () => {
  assert.equal(Model.restoredVolume(0), 1)
  assert.equal(Model.restoredVolume(null), 1)
  assert.equal(Model.restoredVolume(undefined), 1)
  assert.equal(Model.restoredVolume(-1), 1)
})

test("mute sits right after the control for what is playing", () => {
  const rows = Model.playerRows("Naruto", "4", false, "best", false)
  assert.deepEqual(rows.slice(0, 2).map((r) => r.key), ["pause", "mute"])
  assert.equal(rows[1].title, "Mute")
  assert.equal(Model.playerRows("Naruto", "4", false, "best", true)[1].title, "Unmute")
})

test("stepping rows name the episode they would reach, as replay does", () => {
  const rows = Model.playerRows("Naruto", "4", false, "best", false)
  const by = {}
  for (const row of rows) by[row.key] = row.label
  assert.equal(by.previous, "episode 3")
  assert.equal(by.replay, "episode 4")
  assert.equal(by.next, "episode 5")
})

test("the first episode has nothing before it to name", () => {
  const by = {}
  for (const row of Model.playerRows("Naruto", "1", false, "best", false)) by[row.key] = row.label
  assert.equal(by.previous, "")
  assert.equal(by.next, "episode 2")
})

test("an episode that is not a whole number names no neighbour", () => {
  const by = {}
  for (const row of Model.playerRows("Naruto", "7.5", false, "best", false)) by[row.key] = row.label
  assert.equal(by.next, "", "the real list decides, and 8.5 would be a guess")
  assert.equal(by.previous, "")
  assert.equal(by.replay, "episode 7.5", "replay names the one in hand, so it stays")
})

test("choosing an episode does not repeat the series name", () => {
  const by = {}
  for (const row of Model.playerRows("Naruto", "4", false, "best", false)) by[row.key] = row.label
  assert.equal(by.select, "", "the heading already says which series this is")
})

test("the player menu leads with the control for what is playing", () => {
  assert.deepEqual(Model.playerRows("Naruto", "5", false, "best", false).map(r => r.key),
    ["pause", "mute", "next", "replay", "previous", "select", "quality", "stop"])
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

test("select says only what it does, the heading having named the series", () => {
  assert.equal(Model.playerRows("Naruto", "79").find(r => r.key === "select").title, "Select episode")
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

test("the threshold that counts an episode as watched is a setting", () => {
  const rows = Model.settingRows("best", "sub", "90", "1.1.0", "")
  const watched = rows.find(r => r.key === "watched")
  assert.equal(watched.title, "Counts as watched")
  assert.equal(watched.label, "90%")
  assert.deepEqual(Model.settingAction(watched), { type: "set", key: "watched", value: "95" })
})

test("the threshold cycles through the values worth having", () => {
  assert.equal(Model.nextSetting("watched", "80"), "85")
  assert.equal(Model.nextSetting("watched", "95"), "80")
  assert.equal(Model.nextSetting("watched", "nonsense"), "80")
})

test("a setting row renders sub as subbed", () => {
  const [, audio] = Model.settingRows("best", "sub", "90", "1.0.0", "")
  assert.equal(audio.label, "subbed")
})

test("an unknown setting is left alone rather than guessed at", () => {
  assert.equal(Model.nextSetting("nosuch", "value"), "value")
})

test("settings are rows like every other view, so the same keys drive them", () => {
  const rows = Model.settingRows("720", "dub", "90", "1.0.0", "")
  assert.deepEqual(rows.map((r) => r.title), ["Quality", "Audio", "Counts as watched", "Version", "Clear watch history", "About"])
  assert.deepEqual(rows.map((r) => r.label), ["720", "dubbed", "90%", "1.0.0", "", ""])
  assert.deepEqual(rows.map((r) => r.key), ["quality", "mode", "watched", "version", "clear", "about"])
})

test("clearing the history is a settings row, not a button in the header", () => {
  const rows = Model.settingRows("best", "sub", "90", "1.1.0", "")
  const clear = rows.find(r => r.key === "clear")
  assert.equal(clear.title, "Clear watch history")
  assert.deepEqual(Model.settingAction(clear), { type: "clear" })
})

test("the version row points at its own release, not the repository", () => {
  const rows = Model.settingRows("best", "sub", "90", "1.2.0", "https://github.com/fihuza/omani")
  const version = rows.find((r) => r.key === "version")
  assert.equal(version.link, "https://github.com/fihuza/omani/releases/tag/v1.2.0")
})

test("a version with nowhere to point still renders", () => {
  const rows = Model.settingRows("best", "sub", "90", "1.2.0", "")
  assert.equal(rows.find((r) => r.key === "version").link, "")
})

test("about comes last and opens the repository", () => {
  const rows = Model.settingRows("best", "sub", "90", "1.2.0", "https://github.com/fihuza/omani")
  const last = rows[rows.length - 1]
  assert.equal(last.key, "about")
  assert.equal(last.link, "https://github.com/fihuza/omani")
  assert.deepEqual(Model.settingAction(last), { type: "open", url: "https://github.com/fihuza/omani" })
})

test("a view opened is a view you can come back from", () => {
  assert.deepEqual(Model.pushView(["history"], "results"), ["history", "results"])
  assert.deepEqual(Model.pushView(["history", "results"], "episodes"), ["history", "results", "episodes"])
})

test("going back leaves the one you came from showing", () => {
  assert.deepEqual(Model.popView(["history", "results", "episodes"]), { stack: ["history", "results"], view: "results" })
  assert.deepEqual(Model.popView(["history", "player"]), { stack: ["history"], view: "history" })
})

test("going back from the first view closes the panel", () => {
  assert.deepEqual(Model.popView(["history"]), { stack: ["history"], view: "close" })
  assert.deepEqual(Model.popView([]), { stack: [], view: "close" })
  assert.deepEqual(Model.popView(undefined), { stack: [], view: "close" },
    "a panel asked to go back before it has a stack closes rather than throwing")
})

test("returning to a view already open comes back to it rather than stacking", () => {
  assert.deepEqual(Model.pushView(["history", "player", "episodes"], "player"), ["history", "player"],
    "the episode list is left behind, not remembered twice")
  assert.deepEqual(Model.pushView(["history", "results"], "results"), ["history", "results"])
})

test("the shortcut list opened over the episode list goes back to it, once", () => {
  let stack = ["history", "player", "episodes"]
  stack = Model.pushView(stack, "shortcuts")
  assert.deepEqual(stack, ["history", "player", "episodes", "shortcuts"])
  let back = Model.popView(stack)
  assert.equal(back.view, "episodes")
  back = Model.popView(back.stack)
  assert.equal(back.view, "player", "and on to the player menu, never back to the shortcuts")
})

test("no sequence of views can be walked back forever", () => {
  const views = ["history", "results", "episodes", "player", "settings", "shortcuts", "quality"]
  for (const a of views) {
    for (const b of views) {
      let stack = Model.pushView(Model.pushView(["history"], a), b)
      let steps = 0
      let out = { stack: stack, view: "" }
      while (out.view !== "close" && steps <= views.length + 2) {
        out = Model.popView(out.stack)
        steps++
      }
      assert.ok(out.view === "close", a + " then " + b + " never closes")
    }
  }
})

test("choosing the version row opens the release it names", () => {
  const rows = Model.settingRows("best", "sub", "90", "1.0.4", "https://github.com/fihuza/omani")
  const version = rows.find(r => r.key === "version")
  assert.deepEqual(Model.settingAction(version),
    { type: "open", url: "https://github.com/fihuza/omani/releases/tag/v1.0.4" })
})

test("a version row with nowhere to point does nothing when chosen", () => {
  const version = Model.settingRows("best", "sub", "90", "1.0.4", "").find(r => r.key === "version")
  assert.equal(version.link, "")
  assert.equal(Model.settingAction(version), null)
})

test("choosing any other row moves its value on", () => {
  const rows = Model.settingRows("720", "sub", "90", "1.0.4", "https://example.test")
  assert.deepEqual(Model.settingAction(rows[0]), { type: "set", key: "quality", value: "480" })
  assert.deepEqual(Model.settingAction(rows[1]), { type: "set", key: "mode", value: "dub" })
  assert.equal(Model.settingAction(null), null)
})

test("choosing a cycling row yields the next value", () => {
  const [quality] = Model.settingRows("best", "sub", "90", "1.0.0", "")
  assert.deepEqual(Model.settingChange(quality), { key: "quality", value: "1080" })
})

test("choosing the version row writes nothing", () => {
  const [, , , version] = Model.settingRows("best", "sub", "90", "1.0.0", "")
  assert.equal(Model.settingChange(version), null)
})

test("a row whose value cannot move writes nothing", () => {
  assert.equal(Model.settingChange({ key: "unknown", value: "x" }), null)
})

test("the version row shows what it is and changes nothing when chosen", () => {
  const [, , , version] = Model.settingRows("best", "sub", "90", "1.0.0", "")
  assert.equal(version.label, "1.0.0")
  assert.equal(Model.nextSetting(version.key, version.value), "1.0.0")
})

test("a setting row carries the raw value, not just its label", () => {
  const [, audio] = Model.settingRows("best", "dub", "90", "1.0.0", "")
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

test("every player gets a line of its own, with how far in it is", () => {
  const records = [{ animeId: "a", title: "A Episode 1" }, { animeId: "b", title: "B Episode 2" }]
  const positions = [{ title: "B Episode 2", position: 300, duration: 1200, playing: true }, { title: "A Episode 1", position: 600, duration: 1200, playing: false }]
  const rows = Model.progressRows(records, positions)
  assert.deepEqual(rows.map(r => r.animeId), ["a", "b"])
  assert.equal(rows[0].fraction, 0.5)
  assert.equal(rows[0].clock, "10:00 / 20:00")
  assert.equal(rows[0].paused, true)
  assert.equal(rows[1].fraction, 0.25)
  assert.equal(rows[1].paused, false)
})

test("two episodes of one series are told apart by title", () => {
  const records = [{ animeId: "a", title: "A Episode 1" }, { animeId: "a", title: "A Episode 2" }]
  const rows = Model.progressRows(records, [{ title: "A Episode 2", position: 60, duration: 120, playing: true }, { title: "A Episode 1", position: 30, duration: 120, playing: false }])
  assert.equal(rows[0].fraction, 0.25)
  assert.equal(rows[1].fraction, 0.5)
  assert.equal(Model.rowLabel({ kind: "playing", title: "A Episode 2", episode: "2" }, rows), "ep 2 \u00b7 50%")
})

test("a player the bus has not reported yet reads as no progress", () => {
  const rows = Model.progressRows([{ animeId: "a", title: "A Episode 1" }], [])
  assert.equal(rows[0].fraction, 0)
  assert.equal(rows[0].clock, "")

  const opened = Model.progressRows([{ animeId: "a", title: "A Episode 1" }], [{ title: "A Episode 1", playing: true }])
  assert.equal(opened[0].fraction, 0)
  assert.equal(opened[0].clock, "")
})

test("a position past the end never overfills the bar", () => {
  const rows = Model.progressRows([{ animeId: "a", title: "A Episode 1" }], [{ title: "A Episode 1", position: 1300, duration: 1200, playing: true }])
  assert.equal(rows[0].fraction, 1)
})

test("a stop names something the script can match, even mid-step", () => {
  assert.equal(Model.stopTarget({ pid: "42", title: "A Episode 1", animeId: "a" }), "42")
  assert.equal(Model.stopTarget({ pid: "", title: "A Episode 1", animeId: "a" }), "A Episode 1")
  assert.equal(Model.stopTarget({ pid: "", title: "", animeId: "a" }), "a")
  assert.equal(Model.stopTarget({ pid: "", title: "", animeId: "" }), "")
  assert.equal(Model.stopTarget(null), "")
})

test("the pane takes the progress of the episode it controls", () => {
  const rows = Model.progressRows([{ animeId: "a", title: "A" }, { animeId: "b", title: "B" }], [{ title: "B", position: 30, duration: 60, playing: true }])
  assert.equal(Model.progressFor(rows, "b").fraction, 0.5)
  assert.equal(Model.progressFor(rows, "gone"), null)
  assert.equal(Model.progressFor(rows, ""), null)
  assert.equal(Model.progressFor(null, "a"), null)
})

test("only the first line of a failure is shown", () => {
  assert.equal(Model.firstLine("omani: no episode after 12\nstack\ntrace"), "no episode after 12")
  assert.equal(Model.firstLine("omani-provider: episode 9999 not found"), "episode 9999 not found")
  assert.equal(Model.firstLine("no prefix here"), "no prefix here")
  assert.equal(Model.firstLine(""), "")
  assert.equal(Model.firstLine(null), "")
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

const ctx = { rowCount: 10, pageSize: 4, searchable: true }
const start = () => Model.initialKeyState()

test("changing one setting keeps the rest and the module id", () => {
  const source = { id: "old.id", quality: "best", mode: "sub", historyLimit: 8 }
  assert.deepEqual(Model.withSetting(source, "io.github.fihuza.omani", "quality", "720"), {
    id: "io.github.fihuza.omani",
    quality: "720",
    mode: "sub",
    historyLimit: 8
  })
})

test("a setting can be added to settings that do not carry it yet", () => {
  assert.deepEqual(Model.withSetting({ id: "x" }, "x", "watched", "85"), { id: "x", watched: "85" })
})

test("absent settings still yield an entry the shell can store", () => {
  assert.deepEqual(Model.withSetting(null, "x", "mode", "dub"), { id: "x", mode: "dub" })
  assert.deepEqual(Model.withSetting(undefined, "x", "mode", "dub"), { id: "x", mode: "dub" })
})

test("changing a setting does not mutate the settings it was given", () => {
  const source = { id: "x", quality: "best" }
  Model.withSetting(source, "x", "quality", "360")
  assert.deepEqual(source, { id: "x", quality: "best" })
})

test("every setting the panel cycles offers exactly what the manifest declares", () => {
  const manifest = require("../manifest.json")
  const declared = {}
  for (const entry of manifest.barWidget.schema) {
    if (entry.type === "enum") declared[entry.key] = entry.options
  }

  for (const [key, options] of Object.entries(declared)) {
    const seen = []
    let value = options[0]
    do {
      seen.push(value)
      value = Model.nextSetting(key, value)
    } while (value !== options[0] && seen.length <= options.length)
    assert.deepEqual(seen, options, key + " cycles through the declared options, in order")
  }

  assert.deepEqual(
    Object.keys(declared).sort(),
    ["mode", "quality", "watched"],
    "a new enum setting in the manifest needs a ring in Model.js"
  )
})

test("a row still reads before any progress has been reported", () => {
  const row = { kind: "playing", title: "A Episode 3", episode: "3", label: "" }
  assert.equal(Model.rowLabel(row, null), "ep 3")
  assert.equal(Model.rowLabel(row, undefined), "ep 3")
})

test("a history row carries what choosing it needs, not just a title", () => {
  const raw = JSON.stringify({version: 1, series: {"a-1": {title: "A", episode: "7", position: 0, duration: 0, watched: [], updated: 1}}})
  assert.deepEqual(Model.historyRows(raw, 1), [
    { episode: "7", animeId: "a-1", title: "A", label: "ep 7" }
  ])
})

test("one series is reported once however many records name it", () => {
  const records = [
    { pid: "1", title: "A Episode 1", animeId: "a", episode: "1", qualities: "" },
    { pid: "2", title: "A Episode 1", animeId: "a", episode: "1", qualities: "" }
  ]
  const players = [{ title: "A Episode 1", position: 600, duration: 1400 }]
  assert.deepEqual(Model.progressReports(records, players), [
    { animeId: "a", episode: "1", position: 600, duration: 1400 }
  ])
})

test("a row takes the first position reported for its title", () => {
  const records = [{ pid: "1", title: "A Episode 1", animeId: "a", episode: "1", qualities: "" }]
  const rows = Model.progressRows(records, [
    { title: "A Episode 1", position: 100, duration: 1000 },
    { title: "A Episode 1", position: 900, duration: 1000 }
  ])
  assert.equal(rows[0].clock, Model.elapsed(100, 1000))
  assert.equal(rows[0].fraction, 0.1)
})

test("a playing row and a series row each carry their own icon", () => {
  const view = Model.historyView(
    [{ animeId: "b", title: "B", label: "ep 1" }],
    [{ pid: "1", title: "A Episode 2", animeId: "a", episode: "2" }]
  )
  assert.equal(view[0].kind, "playing")
  assert.equal(view[1].kind, "series")
  assert.ok(view[0].icon, "a playing row has an icon")
  assert.ok(view[1].icon, "a series row has an icon")
  assert.notEqual(view[0].icon, view[1].icon, "the two are told apart by their icon")
  assert.equal(view[0].label, "", "a playing row is labelled by the progress rows, not here")
})

test("a digit cancels a pending g rather than arming it further", () => {
  const after = press(["g", "3"])
  assert.equal(after.state.pendingG, false)
  assert.equal(press(["g", "3", "g"]).state.index, 0, "the second g arms rather than jumping")
})

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

test("slash does nothing where there is no search field to focus", () => {
  const noSearch = { rowCount: 10, pageSize: 4, searchable: false }
  assert.equal(press("/", noSearch).command, null,
    "focusing a field that is not there swallows every key after it")
  assert.equal(press("i", noSearch).command, null)
})

test("slash still moves nothing, so the cursor is where it was", () => {
  const noSearch = { rowCount: 10, pageSize: 4, searchable: false }
  const after = press(["3", "j", "/"], noSearch)
  assert.equal(after.state.index, 3)
})

test("the views with a search field are the ones that list something to search", () => {
  assert.equal(Model.searchable("history"), true)
  assert.equal(Model.searchable("results"), true)
  assert.equal(Model.searchable("episodes"), false,
    "the episode list is a list of episodes; the field above it searches anime")
  assert.equal(Model.searchable("player"), false)
  assert.equal(Model.searchable("settings"), false)
  assert.equal(Model.searchable("shortcuts"), false)
  assert.equal(Model.searchable("quality"), false)
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
  const stale = { index: 8, pendingCount: "", pendingG: false }
  assert.equal(Model.reduceKey(stale, "j", { rowCount: 3, pageSize: 4 }).state.index, 2)
})

test("the status the script reports is read field by field", () => {
  const raw = JSON.stringify({
    ready: true,
    tracking: false,
    watchedFraction: 75,
    missing: "mpv",
    version: "1.2.0",
    repo: "https://example.invalid/omani",
    historyPath: "/h",
    playersPath: "/p",
  })
  assert.deepEqual(Model.statusFields(raw, 90), {
    ready: true,
    tracking: false,
    watchedFraction: 75,
    missing: "mpv",
    version: "1.2.0",
    repo: "https://example.invalid/omani",
    historyPath: "/h",
    playersPath: "/p",
  })
})

test("output that is not json reports no status at all", () => {
  assert.equal(Model.statusFields("bash: line 1: warning\n{}", 90), null)
  assert.equal(Model.statusFields("", 90), null)
  assert.equal(Model.statusFields(null, 90), null)
})

test("json that is not an object reports no status", () => {
  assert.equal(Model.statusFields("[1,2]", 90), null)
  assert.equal(Model.statusFields("null", 90), null)
  assert.equal(Model.statusFields('"ready"', 90), null)
})

test("nothing is ready until the script says so, and tracking stays on", () => {
  const status = Model.statusFields("{}", 90)
  assert.equal(status.ready, false)
  assert.equal(status.tracking, true)
})

test("an unusable watched fraction keeps the one already in use", () => {
  assert.equal(Model.statusFields('{"watchedFraction":"x"}', 90).watchedFraction, 90)
  assert.equal(Model.statusFields('{"watchedFraction":0}', 90).watchedFraction, 90)
  assert.equal(Model.statusFields('{"watchedFraction":75}', 90).watchedFraction, 75)
})

test("every name and path comes back as a string", () => {
  const status = Model.statusFields('{"missing":null,"version":12,"repo":false}', 90)
  assert.equal(status.missing, "")
  assert.equal(status.version, "12")
  assert.equal(status.repo, "")
})
