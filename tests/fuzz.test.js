"use strict"

const { test } = require("node:test")
const assert = require("node:assert/strict")

const Model = require("../Model.js")

const HOSTILE = [
  undefined,
  null,
  "",
  0,
  -1,
  1.5,
  NaN,
  Infinity,
  -Infinity,
  true,
  false,
  [],
  {},
  "\t",
  "\n",
  "\\",
  '"',
  "0",
  "-0",
  "7.5",
  "1e400",
  "9".repeat(400),
  "../../etc/passwd",
  "file:///etc/passwd",
  "Episode \u0000 1",
  "日本語",
  "a".repeat(5000),
]

const SEED = Number(process.env.OMANI_FUZZ_SEED || 0x9e3779b9)
const ROUNDS = Number(process.env.OMANI_FUZZ_ROUNDS || 400)

function makeRandom(seed) {
  let state = seed >>> 0
  return function random() {
    state = (state + 0x6d2b79f5) >>> 0
    let drawn = Math.imul(state ^ (state >>> 15), 1 | state)
    drawn = (drawn + Math.imul(drawn ^ (drawn >>> 7), 61 | drawn)) ^ drawn
    return ((drawn ^ (drawn >>> 14)) >>> 0) / 4294967296
  }
}

const ODD_CHARS = ["\t", "\n", "\\", '"', "\u0000", "\u00e9", "\u65e5", "\u{1f600}", " ", "-", ".", "0", "9"]

function anyValue(random, depth) {
  const pick = Math.floor(random() * 10)
  if (pick === 0) return undefined
  if (pick === 1) return null
  if (pick === 2) return [NaN, Infinity, -Infinity, 0, -0][Math.floor(random() * 5)]
  if (pick === 3) return (random() - 0.5) * 1e6
  if (pick === 4) return random() < 0.5
  if (pick === 5) {
    let text = ""
    const length = Math.floor(random() * 40)
    for (let i = 0; i < length; i++) {
      text += random() < 0.3 ? ODD_CHARS[Math.floor(random() * ODD_CHARS.length)] : String.fromCharCode(32 + Math.floor(random() * 95))
    }
    return text
  }
  if (pick === 6) return String(Math.floor((random() - 0.5) * 1e9))
  if (pick === 7 && depth > 0) {
    const list = []
    const length = Math.floor(random() * 4)
    for (let i = 0; i < length; i++) list.push(anyValue(random, depth - 1))
    return list
  }
  if (pick === 8 && depth > 0) {
    return {
      pid: anyValue(random, 0),
      title: anyValue(random, 0),
      animeId: anyValue(random, 0),
      episode: anyValue(random, 0),
    }
  }
  return ""
}

function someRecords(random) {
  const list = []
  const length = Math.floor(random() * 4)
  for (let i = 0; i < length; i++) {
    list.push({
      pid: String(Math.floor(random() * 99999)),
      title: String(anyValue(random, 0)),
      animeId: String(anyValue(random, 0)),
      episode: String(anyValue(random, 0)),
    })
  }
  return list
}

function rounds(name, fn) {
  const random = makeRandom(SEED)
  for (let round = 0; round < ROUNDS; round++) {
    const generated = [anyValue(random, 2), anyValue(random, 2), anyValue(random, 2)]
    try {
      fn(generated[0], generated[1], generated[2])
    } catch (whatBroke) {
      whatBroke.message =
        name + " broke on round " + round + " with " + JSON.stringify(generated) +
        " (rerun with OMANI_FUZZ_SEED=" + SEED + ")\n" + whatBroke.message
      throw whatBroke
    }
  }
}

function everyShape(fn) {
  for (const a of HOSTILE) for (const b of HOSTILE) fn(a, b)
}

test("parsing a history never throws and always yields rows", () => {
  for (const raw of HOSTILE) {
    const rows = Model.parseHistory(raw)
    assert.ok(Array.isArray(rows), `parseHistory(${JSON.stringify(raw)}) gave ${typeof rows}`)
  }
})

test("parsing player records never throws and always yields records", () => {
  for (const raw of HOSTILE) {
    const records = Model.playerRecords(raw)
    assert.ok(Array.isArray(records), `playerRecords(${JSON.stringify(raw)}) gave ${typeof records}`)
  }
})

test("a status that is not a status is refused rather than half read", () => {
  for (const raw of HOSTILE) {
    const status = Model.statusFields(raw, 90)
    assert.ok(status === null || typeof status.ready === "boolean")
  }
})

test("naming the playing player always yields a string", () => {
  everyShape((id, title) => {
    const named = Model.playingTitleOf([{ pid: "1", title: "x", animeId: "a", episode: "1" }], id, title)
    assert.equal(typeof named, "string", `playingTitleOf(${JSON.stringify(id)}, ${JSON.stringify(title)})`)
  })
})

test("a progress report never describes an episode shorter than a minute", () => {
  everyShape((position, duration) => {
    const records = [{ pid: "1", title: "T", animeId: "a", episode: "1" }]
    for (const report of Model.progressReports(records, [{ title: "T", position, duration }])) {
      assert.ok(report.duration >= 60, `let through ${report.position}/${report.duration}`)
      assert.ok(report.position <= report.duration, `position past the end: ${report.position}/${report.duration}`)
    }
  })
})

test("the cursor never leaves the list, whatever is pressed", () => {
  const keys = ["j", "k", "g", "G", "ctrl+d", "ctrl+u", "0", "3", "9", "enter", "d", "c", "r", "s", "?", "/", "escape", "", "z"]
  for (const rowCount of [0, 1, 2, 7, 200]) {
    let state = Model.initialKeyState()
    for (const key of keys) {
      for (const pageSize of [0, 1, 5]) {
        const result = Model.reduceKey(state, key, { rowCount, pageSize, searchable: true })
        state = result.state
        assert.ok(Number.isFinite(state.index), `index went to ${state.index} on '${key}'`)
        assert.ok(state.index >= 0, `index went negative on '${key}'`)
        assert.ok(state.index < Math.max(1, rowCount), `index ${state.index} outside ${rowCount} rows on '${key}'`)
      }
    }
  }
})

test("a scroll target is always a usable position", () => {
  for (const content of [0, 100, 5000]) {
    for (const viewport of [0, 50, 400]) {
      for (const index of [-1, 0, 3, 999]) {
        for (const rowTop of [-10, 0, 4800]) {
          const target = Model.scrollTarget({
            content,
            viewport,
            index,
            lastIndex: 10,
            rowTop,
            rowHeight: 40,
            margin: 8,
            current: 0,
          })
          assert.ok(Number.isFinite(target), `target ${target}`)
          assert.ok(target >= 0, `target went negative: ${target}`)
        }
      }
    }
  }
})

test("generated input never breaks what reads from outside", () => {
  rounds("parseHistory", (raw) => assert.ok(Array.isArray(Model.parseHistory(raw))))
  rounds("playerRecords", (raw) => assert.ok(Array.isArray(Model.playerRecords(raw))))
  rounds("statusFields", (raw, n) => {
    const status = Model.statusFields(raw, n)
    assert.ok(status === null || typeof status.ready === "boolean")
  })
  const naming = makeRandom(SEED)
  for (let round = 0; round < ROUNDS; round++) {
    const records = someRecords(naming)
    const named = Model.playingTitleOf(records, anyValue(naming, 0), anyValue(naming, 0))
    assert.equal(typeof named, "string", "playingTitleOf gave " + typeof named + " on round " + round)
  }
  rounds("historyRows", (raw, limit) => assert.ok(Array.isArray(Model.historyRows(raw, limit))))
  rounds("seriesTitle", (title) => assert.equal(typeof Model.seriesTitle(String(title)), "string"))
})

test("generated players never yield a report that cannot describe an episode", () => {
  rounds("progressReports", (position, duration) => {
    const records = [{ pid: "1", title: "T", animeId: "a", episode: "1" }]
    for (const report of Model.progressReports(records, [{ title: "T", position, duration }])) {
      assert.ok(report.duration >= 60)
      assert.ok(report.position <= report.duration)
    }
  })
})
