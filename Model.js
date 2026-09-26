// No `.pragma library`: that directive is not valid JavaScript, so Node cannot
// parse a file carrying it, and the tests would stop running what ships.

function parseHistory(raw) {
  if (!raw) return []
  var rows = []
  var lines = String(raw).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var fields = lines[i].replace(/\r$/, "").split("\t")
    if (fields.length < 3) continue
    var episode = fields[0].trim()
    var animeId = fields[1].trim()
    var title = fields[2].trim()
    if (!episode || !animeId || !title) continue
    rows.push({ episode: episode, animeId: animeId, title: title })
  }
  return rows
}

var BACK_FROM = {
  episodes: "results",
  results: "history",
  settings: "history",
  shortcuts: "history",
  player: "history"
}

function backFrom(view) {
  return BACK_FROM[view] || "close"
}

// Following a series replaces what is on screen; starting one from the watch
// history adds to it. Decided here so no path into the player menu can forget.
function replaces(view, playingTitle) {
  if (view !== "player" && view !== "episodes") return ""
  return playingTitle || ""
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
      episode: fields[3].trim()
    })
  }
  return records
}

function livePlayers(records, liveTitles) {
  var live = []
  for (var i = 0; i < records.length; i++) {
    if (liveTitles.indexOf(records[i].title) === -1) continue
    live.push(records[i])
  }
  return live
}

function isPlaying(players, title) {
  if (!title) return false
  for (var i = 0; i < players.length; i++) {
    if (players[i].title === title) return true
  }
  return false
}

function isPlayingSeries(players, animeId) {
  if (!animeId) return false
  for (var i = 0; i < players.length; i++) {
    if (players[i].animeId === animeId) return true
  }
  return false
}

function historyView(rows, players) {
  var view = []
  for (var p = 0; p < players.length; p++) {
    view.push({
      kind: "playing",
      section: p === 0 ? "Playing" : "",
      title: players[p].title,
      label: "",
      animeId: players[p].animeId,
      episode: players[p].episode,
      pid: players[p].pid
    })
  }
  for (var i = 0; i < rows.length; i++) {
    var row = {}
    for (var field in rows[i]) row[field] = rows[i][field]
    row.kind = "series"
    row.section = i === 0 ? "Continue watching" : ""
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
      label: "ep " + row.episode
    }
  })
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
    { keys: "r", action: "Refresh" },
    { keys: "x", action: "Clear history" },
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

var RINGS = { quality: QUALITIES, mode: MODES }

function nextSetting(key, current) {
  var ring = RINGS[key]
  return ring ? nextInRing(ring, current) : current
}

function playerRows(title, episode) {
  return [
    { key: "next", title: "Next episode", label: "" },
    { key: "replay", title: "Replay", label: episode === "" ? "" : "episode " + episode },
    { key: "previous", title: "Previous episode", label: "" },
    { key: "select", title: "Select episode", label: title },
    { key: "quality", title: "Change quality", label: "" },
    { key: "stop", title: "Stop", label: "" }
  ]
}

// The version row is shown, not chosen: yielding no change is what keeps
// activating it from writing to the stored settings.
function settingChange(row) {
  var next = nextSetting(row.key, row.value)
  if (next === row.value) return null
  return { key: row.key, value: next }
}

function settingRows(quality, mode, version) {
  return [
    { key: "quality", value: quality, title: "Quality", label: quality },
    { key: "mode", value: mode, title: "Audio", label: mode === "dub" ? "dubbed" : "subbed" },
    { key: "version", value: version, title: "Version", label: version }
  ]
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

function episodeRows(raw) {
  return tabRows(raw).map(function (fields) {
    return { episodeId: fields[0], number: fields[1], title: "Episode " + fields[1] }
  })
}

function heading(labels, view, busy, launching) {
  if (launching) return "Starting\u2026"
  if (busy) return "Loading\u2026"
  return labels && labels[view] ? labels[view] : ""
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
  if (key === "x") return done({ type: "clearHistory" })
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
    backFrom: backFrom,
    replaces: replaces,
    playerRecords: playerRecords,
    livePlayers: livePlayers,
    isPlaying: isPlaying,
    isPlayingSeries: isPlayingSeries,
    historyView: historyView,
    historyEntry: historyEntry,
    historyRows: historyRows,
    shortcuts: shortcuts,
    nextSetting: nextSetting,
    settingChange: settingChange,
    playerRows: playerRows,
    settingRows: settingRows,
    seriesRows: seriesRows,
    episodeRows: episodeRows,
    heading: heading,
    normalizeKey: normalizeKey,
    initialKeyState: initialKeyState,
    reduceKey: reduceKey
  }
}
