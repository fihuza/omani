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
