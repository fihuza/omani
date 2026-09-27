// No `.pragma library`: that directive is not valid JavaScript, so Node cannot
// parse a file carrying it, and the tests would stop running what ships.

function parseHistory(raw) {
  if (!raw) return []
  var parsed
  try {
    parsed = JSON.parse(String(raw))
  } catch (e) {
    return []
  }
  var series = parsed && parsed.series
  if (!series) return []
  var rows = []
  for (var animeId in series) {
    var entry = series[animeId]
    if (!entry || !entry.title || !entry.episode) continue
    var episodes = entry.episodes || {}
    var current = episodes[String(entry.episode)] || {}
    rows.push({
      animeId: animeId,
      title: String(entry.title),
      episode: String(entry.episode),
      position: Number(current.position) || 0,
      duration: Number(current.duration) || 0,
      episodes: episodes,
      updated: Number(entry.updated) || 0
    })
  }
  rows.sort(function (a, b) {
    return b.updated - a.updated
  })
  return rows
}

function watchedFraction(row) {
  if (!row || !row.duration) return 0
  return Math.min(100, Math.round(row.position * 100 / row.duration))
}

function progressLabel(row) {
  var percent = watchedFraction(row)
  if (percent === 0) return "ep " + row.episode
  return "ep " + row.episode + " \u00b7 " + percent + "%"
}

var BACK_FROM = {
  episodes: "results",
  results: "history",
  settings: "history",
  shortcuts: "history",
  player: "history",
  quality: "player"
}

function backFrom(view, openedFrom) {
  if (view === "episodes" && openedFrom) return openedFrom
  return BACK_FROM[view] || "close"
}

function playerRecords(raw) {
  if (!raw) return []
  var records = []
  var lines = String(raw).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].replace(/\r$/, "").split("\t")
    if (fields.length < 4) continue
    if (fields[1].trim() === "") continue
    records.push({
      pid: fields[0].trim(),
      title: fields[1].trim(),
      animeId: fields[2].trim(),
      episode: fields[3].trim(),
      qualities: fields.length > 4 ? fields[4].trim() : ""
    })
  }
  return records
}

function progressReports(records, players) {
  var reports = []
  for (var i = 0; i < players.length; i++) {
    var title = String(players[i].title || "")
    var position = Math.floor(Number(players[i].position) || 0)
    var duration = Math.floor(Number(players[i].duration) || 0)
    if (title === "" || duration <= 0 || position <= 0) continue
    for (var r = 0; r < records.length; r++) {
      if (records[r].title !== title) continue
      reports.push({
        animeId: records[r].animeId,
        episode: records[r].episode,
        position: position,
        duration: duration
      })
      break
    }
  }
  return reports
}

function livePlayers(records, liveTitles, livePids) {
  var live = []
  for (var i = 0; i < records.length; i++) {
    if (liveTitles.indexOf(records[i].title) === -1) continue
    if (livePids && livePids.indexOf(records[i].pid) === -1) continue
    live.push(records[i])
  }
  return live
}

function launchPids(players) {
  if (!players) return []
  return players.map(function (p) {
    return p.pid
  })
}

function noticeOnOpen(notice, unseen) {
  return unseen ? String(notice || "") : ""
}

function launchDone(tracking, players, before, waitedTooLong) {
  if (!tracking || waitedTooLong) return true
  var running = players || []
  var started = before || []
  for (var i = 0; i < running.length; i++) {
    if (started.indexOf(running[i].pid) === -1) return true
  }
  return false
}

function resumeTarget(rows, players) {
  for (var i = 0; i < rows.length; i++) {
    var live = false
    for (var p = 0; p < players.length; p++) {
      if (players[p].animeId === rows[i].animeId) live = true
    }
    if (!live) return rows[i]
  }
  return null
}

function rowLabel(row, progress) {
  if (!row) return ""
  if (row.kind !== "playing") return row.label !== undefined ? row.label : ""
  return playingLabel(row.episode, progressOfPlayer(progress, row.title))
}

function remembered(fallback) {
  return fallback ? String(fallback) : ""
}

function adoptable(players, playingId) {
  if (!players || players.length === 0) return null
  for (var i = 0; i < players.length; i++) {
    if (players[i].animeId === playingId) return null
  }
  return players[0]
}

function qualitiesOf(players, animeId) {
  if (!animeId) return ""
  for (var i = 0; i < players.length; i++) {
    if (players[i].animeId === animeId) return players[i].qualities
  }
  return ""
}

function seriesTitle(title) {
  return String(title).replace(/ Episode [^ ]*$/, "")
}

function seriesOf(players, animeId, fallback) {
  if (!animeId) return remembered(fallback)
  for (var i = 0; i < players.length; i++) {
    if (players[i].animeId === animeId) return seriesTitle(players[i].title)
  }
  return remembered(fallback)
}

function episodeOf(players, animeId, fallback) {
  if (!animeId) return remembered(fallback)
  for (var i = 0; i < players.length; i++) {
    if (players[i].animeId === animeId) return String(players[i].episode)
  }
  return remembered(fallback)
}

function isPlayingSeries(players, animeId) {
  if (!animeId) return false
  for (var i = 0; i < players.length; i++) {
    if (players[i].animeId === animeId) return true
  }
  return false
}

function startIndex(rows) {
  if (!rows) return 0
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].kind !== "playing") return i
  }
  return 0
}

function progressOfPlayer(progress, title) {
  if (!progress) return 0
  for (var i = 0; i < progress.length; i++) {
    if (progress[i].title === title) return progress[i].fraction
  }
  return 0
}

function playingLabel(episode, fraction) {
  var percent = Math.round((Number(fraction) || 0) * 100)
  if (percent <= 0) return "ep " + episode
  return "ep " + episode + " \u00b7 " + percent + "%"
}

function historyView(rows, players) {
  var view = []
  var live = {}
  for (var p = 0; p < players.length; p++) {
    live[players[p].animeId] = true
    view.push({
      kind: "playing",
      section: p === 0 ? "PLAYING" : "",
      icon: "\u{f040a}",
      title: players[p].title,
      label: "",
      animeId: players[p].animeId,
      episode: players[p].episode,
      pid: players[p].pid
    })
  }
  var kept = 0
  for (var i = 0; i < rows.length; i++) {
    if (live[rows[i].animeId]) continue
    var row = {}
    for (var field in rows[i]) row[field] = rows[i][field]
    row.kind = "series"
    row.icon = "\u{f02da}"
    row.section = kept === 0 ? "CONTINUE WATCHING" : ""
    kept++
    view.push(row)
  }
  return view
}

function historyEntry(raw, animeId) {
  var rows = parseHistory(raw)
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].animeId === animeId) return rows[i]
  }
  return null
}

function historyRows(raw, limit) {
  var rows = parseHistory(raw)
  var count = Number(limit)
  if (isFinite(count) && count > 0) rows = rows.slice(0, count)
  return rows.map(function (row) {
    return {
      episode: row.episode,
      animeId: row.animeId,
      title: row.title,
      label: progressLabel(row)
    }
  })
}

function scrollTarget(list) {
  var limit = Math.max(0, list.content - list.viewport)
  if (list.index <= 0) return 0
  if (list.index >= list.lastIndex) return limit
  var above = list.rowTop - list.margin
  if (above < list.current) return Math.max(0, Math.min(limit, above))
  var below = list.rowTop + list.rowHeight + list.margin
  if (below > list.current + list.viewport) return Math.min(limit, below - list.viewport)
  return Math.max(0, Math.min(limit, list.current))
}

function shortcuts() {
  return [
    { keys: "j / k", action: "Move down / up" },
    { keys: "3j", action: "Repeat a motion" },
    { keys: "gg / G", action: "First / last row" },
    { keys: "Ctrl-d / Ctrl-u", action: "Half a page" },
    { keys: "Enter", action: "Open or play the row" },
    { keys: "/ or i", action: "Search field" },
    { keys: "s", action: "Settings" },
    { keys: "?", action: "This list" },
    { keys: "d or x", action: "Forget the series" },
    { keys: "c", action: "Clear history" },
    { keys: "r", action: "Refresh" },
    { keys: "Esc", action: "Back, then close" },
    { keys: "q", action: "Close" }
  ]
}

var QUALITIES = ["best", "1080", "720", "480", "360", "worst"]
var MODES = ["sub", "dub"]

function nextInRing(values, current) {
  var at = values.indexOf(current)
  return values[(at + 1) % values.length]
}

var WATCHED = ["80", "85", "90", "95"]

var RINGS = { quality: QUALITIES, mode: MODES, watched: WATCHED }

function withSetting(source, moduleName, key, value) {
  var entry = { id: moduleName }
  for (var existing in source)
    if (existing !== "id") entry[existing] = source[existing]
  entry[key] = value
  return entry
}

function nextSetting(key, current) {
  var ring = RINGS[key]
  return ring ? nextInRing(ring, current) : current
}

function qualityRows(available, current) {
  var rows = []
  var heights = String(available || "").split(/\s+/)
  for (var i = 0; i < heights.length; i++) {
    if (heights[i] === "") continue
    rows.push({
      key: heights[i],
      title: heights[i] + "p",
      label: heights[i] === current ? "playing" : ""
    })
  }
  return rows
}

function playerRows(title, episode, paused, quality) {
  return [
    { key: "pause", title: paused ? "Resume" : "Pause", label: "" },
    { key: "next", title: "Next episode", label: "" },
    { key: "replay", title: "Replay", label: episode === "" ? "" : "episode " + episode },
    { key: "previous", title: "Previous episode", label: "" },
    { key: "select", title: "Select episode", label: title },
    { key: "quality", title: "Change quality", label: quality || "" },
    { key: "stop", title: "Stop", label: "" }
  ]
}

function settingChange(row) {
  var next = nextSetting(row.key, row.value)
  if (next === row.value) return null
  return { key: row.key, value: next }
}


function settingRows(quality, mode, watched, version, repo) {
  return [
    { key: "quality", value: quality, title: "Quality", label: quality, link: "" },
    { key: "mode", value: mode, title: "Audio", label: mode === "dub" ? "dubbed" : "subbed", link: "" },
    { key: "watched", value: watched, title: "Counts as watched", label: watched + "%", link: "" },
    { key: "version", value: version, title: "Version", label: version, link: repo || "" },
    { key: "clear", value: "", title: "Clear watch history", label: "", link: "" }
  ]
}

function settingAction(row) {
  if (!row) return null
  if (row.key === "clear") return { type: "clear" }
  if (row.link) return { type: "open", url: row.link }
  var change = settingChange(row)
  return change ? { type: "set", key: change.key, value: change.value } : null
}

function tabRows(raw) {
  if (!raw) return []
  var rows = []
  var lines = String(raw).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].replace(/\r$/, "").split("\t")
    if (fields.length < 2) continue
    if (fields[0].trim() === "" || fields[1].trim() === "") continue
    rows.push([fields[0].trim(), fields[1].trim()])
  }
  return rows
}

function seriesRows(raw) {
  return tabRows(raw).map(function (fields) {
    return { animeId: fields[0], title: fields[1] }
  })
}

function episodeLabel(progress, fraction) {
  if (!progress || !progress.duration) return ""
  var percent = watchedFraction(progress)
  return percent >= fraction ? "watched" : percent + "%"
}

function episodeRows(raw, progress, fraction) {
  var seen = progress || {}
  return tabRows(raw).map(function (fields) {
    return {
      episodeId: fields[0],
      number: fields[1],
      title: "Episode " + fields[1],
      label: episodeLabel(seen[fields[1]], fraction)
    }
  })
}

function forgettable(view, row) {
  return view === "history" && !!row && row.kind === "series"
}

function progressOf(raw, animeId) {
  var entry = historyEntry(raw, animeId)
  return entry ? entry.episodes : {}
}

function sectionLabel(text) {
  return String(text === null || text === undefined ? "" : text).toUpperCase()
}

function clock(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var rest = total % 60
  var padded = (rest < 10 ? "0" : "") + rest
  if (hours === 0) return minutes + ":" + padded
  return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + padded
}

function elapsed(position, duration) {
  if (!duration || duration <= 0) return ""
  return clock(position) + " / " + clock(duration)
}

function playerFor(players, title) {
  if (!title) return null
  for (var i = 0; i < players.length; i++) {
    if (String(players[i].trackTitle || "") === title) return players[i]
  }
  return null
}

function stopTarget(record) {
  if (!record) return ""
  return String(record.pid || record.title || record.animeId || "")
}

function progressFor(rows, animeId) {
  if (!animeId || !rows) return null
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].animeId === animeId) return rows[i]
  }
  return null
}

function heroMeta(state) {
  if (state.notice) return state.notice
  if (!state.ready) return "missing: " + state.missing
  if (!state.tracking) return "mpv-mpris missing \u00b7 players are not tracked"
  return state.quality + " \u00b7 " + state.mode
}

function progressRows(records, positions) {
  var rows = []
  for (var i = 0; i < records.length; i++) {
    var live = null
    for (var p = 0; p < positions.length; p++) {
      if (positions[p].title === records[i].title) {
        live = positions[p]
        break
      }
    }
    var position = live ? Math.floor(Number(live.position) || 0) : 0
    var duration = live ? Math.floor(Number(live.duration) || 0) : 0
    rows.push({
      animeId: records[i].animeId,
      title: records[i].title,
      clock: elapsed(position, duration),
      fraction: duration > 0 ? Math.min(1, position / duration) : 0,
      paused: live ? live.playing !== true : false
    })
  }
  return rows
}

function heading(labels, view, busy, launching) {
  if (launching) return sectionLabel("Starting\u2026")
  if (busy) return sectionLabel("Loading\u2026")
  return sectionLabel(labels && labels[view] ? labels[view] : "")
}

function firstLine(text) {
  return String(text || "").split("\n")[0].trim().replace(/^[a-z0-9-]+: /, "")
}

function normalizeKey(text) {
  if (!text) return ""
  if (text === "\u0004") return "ctrl+d"
  if (text === "\u0015") return "ctrl+u"
  return text
}

function initialKeyState() {
  return { index: 0, pendingCount: "", pendingG: false }
}

function clamp(value, max) {
  if (!(max > 0)) return 0
  if (value < 0) return 0
  if (value > max) return max
  return value
}

function reduceKey(state, key, ctx) {
  var rowCount = ctx && ctx.rowCount > 0 ? ctx.rowCount : 0
  var pageSize = ctx && ctx.pageSize > 0 ? ctx.pageSize : 1
  var last = rowCount > 0 ? rowCount - 1 : 0

  var next = {
    index: clamp(state.index, last),
    pendingCount: state.pendingCount,
    pendingG: state.pendingG
  }

  var count = parseInt(next.pendingCount, 10)
  var hasCount = isFinite(count) && count > 0
  var steps = hasCount ? count : 1
  var wasG = next.pendingG

  function done(command) {
    next.pendingCount = ""
    next.pendingG = false
    return { state: next, command: command || null }
  }

  if (key >= "1" && key <= "9") {
    next.pendingCount = next.pendingCount + key
    next.pendingG = false
    return { state: next, command: null }
  }

  if (key === "0") {
    if (next.pendingCount) {
      next.pendingCount = next.pendingCount + key
      return { state: next, command: null }
    }
    next.index = 0
    return done()
  }

  if (key === "g") {
    if (!wasG) {
      next.pendingG = true
      return { state: next, command: null }
    }
    next.index = hasCount ? clamp(count - 1, last) : 0
    return done()
  }

  if (key === "G") {
    next.index = hasCount ? clamp(count - 1, last) : last
    return done()
  }

  if (key === "j") {
    next.index = clamp(next.index + steps, last)
    return done()
  }

  if (key === "k") {
    next.index = clamp(next.index - steps, last)
    return done()
  }

  if (key === "ctrl+d") {
    next.index = clamp(next.index + pageSize, last)
    return done()
  }

  if (key === "ctrl+u") {
    next.index = clamp(next.index - pageSize, last)
    return done()
  }

  if (key === "enter") {
    return done(rowCount > 0 ? { type: "play", index: next.index } : null)
  }

  if (key === "s") return done({ type: "toggleSettings" })
  if (key === "?") return done({ type: "toggleShortcuts" })
  if (key === "/" || key === "i") return done({ type: "focusSearch" })
  if (key === "d") return done(rowCount > 0 ? { type: "forget", index: next.index } : null)
  if (key === "c") return done({ type: "clearHistory" })
  if (key === "r") return done({ type: "refresh" })
  if (key === "q") return done({ type: "close" })

  if (key === "escape") {
    if (next.pendingCount || wasG) return done()
    return done({ type: "close" })
  }

  return done()
}

if (typeof module !== "undefined") {
  module.exports = {
    parseHistory: parseHistory,
    watchedFraction: watchedFraction,
    progressLabel: progressLabel,
    backFrom: backFrom,
    playerRecords: playerRecords,
    livePlayers: livePlayers,
    progressReports: progressReports,
    isPlayingSeries: isPlayingSeries,
    launchPids: launchPids,
    noticeOnOpen: noticeOnOpen,
    launchDone: launchDone,
    resumeTarget: resumeTarget,
    rowLabel: rowLabel,
    adoptable: adoptable,
    qualitiesOf: qualitiesOf,
    seriesTitle: seriesTitle,
    seriesOf: seriesOf,
    episodeOf: episodeOf,
    historyView: historyView,
    startIndex: startIndex,
    historyEntry: historyEntry,
    historyRows: historyRows,
    scrollTarget: scrollTarget,
    shortcuts: shortcuts,
    withSetting: withSetting,
    nextSetting: nextSetting,
    settingChange: settingChange,
    playerRows: playerRows,
    qualityRows: qualityRows,
    settingRows: settingRows,
    settingAction: settingAction,
    seriesRows: seriesRows,
    episodeRows: episodeRows,
    forgettable: forgettable,
    progressOf: progressOf,
    episodeLabel: episodeLabel,
    heading: heading,
    heroMeta: heroMeta,
    progressRows: progressRows,
    progressFor: progressFor,
    stopTarget: stopTarget,
    clock: clock,
    elapsed: elapsed,
    playerFor: playerFor,
    sectionLabel: sectionLabel,
    firstLine: firstLine,
    normalizeKey: normalizeKey,
    initialKeyState: initialKeyState,
    reduceKey: reduceKey
  }
}
