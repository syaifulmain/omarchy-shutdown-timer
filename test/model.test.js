const { test } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const Model = new Function(source + `
return {
  DEFAULT_PRESETS,
  MAX_PRESETS,
  normalizePresets,
  presetLabel,
  formatHoursMinutes,
  formatCompact,
  barGlyph,
  barStateGlyph,
  barLabel,
  splitDuration,
  normalizeDuration,
  nextOccurrence,
  secondsUntil,
  nextWholeSecond,
  calendarStamp,
  relativeDayLabel,
  makeUnit,
  parseActiveTimers,
  firstErrorLine,
  isPreset
}
`)()

test("default presets are 30 minutes and 1 hour", () => {
  assert.equal(Model.MAX_PRESETS, 10)
  assert.deepEqual(Model.DEFAULT_PRESETS, [1800, 3600])
  assert.deepEqual(Model.normalizePresets(undefined), [1800, 3600])
  assert.deepEqual(Model.normalizePresets([]), [])
})

test("presets are validated, deduplicated, and capped at ten", () => {
  assert.deepEqual(Model.normalizePresets([1800, 1800, 0, -1, 3600, 90000, "60", 90]),
    [1800, 3600, 90000, 60, 90])
  assert.equal(Model.normalizePresets([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]).length, 10)
  assert.deepEqual(Model.normalizePresets("bad"), [1800, 3600])
})

test("preset labels read naturally", () => {
  assert.equal(Model.presetLabel(30), "30 s")
  assert.equal(Model.presetLabel(90), "1 m 30 s")
  assert.equal(Model.presetLabel(1800), "30 m")
  assert.equal(Model.presetLabel(3600), "1 h")
  assert.equal(Model.presetLabel(5400), "1 h 30 m")
  assert.equal(Model.presetLabel(86400), "24 h")
  assert.equal(Model.presetLabel(90000), "25 h")
})

test("hour/minute clock drops seconds", () => {
  assert.equal(Model.formatHoursMinutes(0), "00:00")
  assert.equal(Model.formatHoursMinutes(45), "00:01")
  assert.equal(Model.formatHoursMinutes(60), "00:01")
  assert.equal(Model.formatHoursMinutes(1799), "00:29")
  assert.equal(Model.formatHoursMinutes(1800), "00:30")
  assert.equal(Model.formatHoursMinutes(3599), "00:59")
  assert.equal(Model.formatHoursMinutes(3600), "01:00")
  assert.equal(Model.formatHoursMinutes(5445), "01:30")
  assert.equal(Model.formatHoursMinutes(90000), "25:00")
})

test("compact bar label stays short and has no seconds", () => {
  assert.equal(Model.formatCompact(0), "0m")
  assert.equal(Model.formatCompact(45), "1m")
  assert.equal(Model.formatCompact(754), "12m")
  assert.equal(Model.formatCompact(3600), "1h 00m")
  assert.equal(Model.formatCompact(3930), "1h 05m")
})

test("bar keeps the timer glyph and adds a phase badge", () => {
  assert.equal(Model.barGlyph(), "󰔛")
  assert.equal(Model.barStateGlyph("idle"), "")
  assert.equal(Model.barStateGlyph("running"), "󰐊")
  assert.equal(Model.barStateGlyph("paused"), "󰏤")
})

test("bar label adds remaining time only while a horizontal timer is active", () => {
  assert.equal(Model.barLabel("idle", false, 1800), "󰔛")
  assert.equal(Model.barLabel("running", false, 1800), "󰔛 󰐊 30m")
  assert.equal(Model.barLabel("paused", false, 45), "󰔛 󰏤 1m")
  assert.equal(Model.barLabel("running", true, 1800), "󰔛 󰐊")
  assert.equal(Model.barLabel("paused", true, 1800), "󰔛 󰏤")
})

test("durations split into hours, minutes, and seconds", () => {
  assert.deepEqual(Model.splitDuration(0), { hours: 0, minutes: 0, seconds: 0 })
  assert.deepEqual(Model.splitDuration(90), { hours: 0, minutes: 1, seconds: 30 })
  assert.deepEqual(Model.splitDuration(3600), { hours: 1, minutes: 0, seconds: 0 })
  assert.deepEqual(Model.splitDuration(90000), { hours: 25, minutes: 0, seconds: 0 })
})

test("overflowing minutes and seconds roll upward", () => {
  assert.deepEqual(Model.normalizeDuration(0, 0, 120), { hours: 0, minutes: 2, seconds: 0 })
  assert.deepEqual(Model.normalizeDuration(0, 120, 0), { hours: 2, minutes: 0, seconds: 0 })
  assert.deepEqual(Model.normalizeDuration(0, 59, 120), { hours: 1, minutes: 1, seconds: 0 })
  assert.deepEqual(Model.normalizeDuration(25, 0, 0), { hours: 25, minutes: 0, seconds: 0 })
  assert.deepEqual(Model.normalizeDuration(1000, 0, 0),
    { hours: 999, minutes: 59, seconds: 59 })
})

test("until targets choose the next occurrence", () => {
  const now = new Date(2026, 9, 17, 21, 15, 0).getTime()
  const laterToday = Model.nextOccurrence(now, 22, 30)
  assert.equal(new Date(laterToday).getDate(), 17)
  assert.equal(new Date(laterToday).getHours(), 22)

  const passed = Model.nextOccurrence(now, 20, 0)
  assert.equal(new Date(passed).getDate(), 18)

  const sameMinute = Model.nextOccurrence(now, 21, 15)
  assert.equal(new Date(sameMinute).getDate(), 18)
})

test("relative day and duration math", () => {
  const now = new Date(2026, 9, 17, 22, 0, 0).getTime()
  const today = new Date(2026, 9, 17, 23, 0, 0).getTime()
  const tomorrow = new Date(2026, 9, 18, 1, 0, 0).getTime()
  assert.equal(Model.relativeDayLabel(now, today), "Today")
  assert.equal(Model.relativeDayLabel(now, tomorrow), "Tomorrow")
  assert.equal(Model.secondsUntil(now, today), 3600)
  assert.equal(Model.secondsUntil(today, now), 0)
  assert.equal(Model.nextWholeSecond(1001), 2000)
})

test("calendar stamps are local and zero padded", () => {
  const stamp = Model.calendarStamp(new Date(2026, 9, 17, 22, 30, 5).getTime())
  assert.equal(stamp, "2026-10-17 22:30:05")
})

test("unit names are prefixed and unique", () => {
  assert.equal(Model.makeUnit(1760712345678), "omarchy-shutdown-countdown-1760712345678")
})

test("active timers parse and sort by next elapse", () => {
  const now = new Date(2026, 9, 17, 22, 0, 0).getTime()
  const raw = JSON.stringify([
    { unit: "omarchy-shutdown-countdown-2.timer", next: (now + 60000) * 1000 },
    { unit: "omarchy-shutdown-countdown-1.timer", next: (now + 30000) * 1000 },
    { unit: "omarchy-shutdown-countdown-old.timer", next: (now - 1000) * 1000 },
    { unit: "omarchy-shutdown-countdown-null.timer", next: null }
  ])
  const parsed = Model.parseActiveTimers(raw, now)
  assert.deepEqual(parsed.units,
    ["omarchy-shutdown-countdown-1.timer", "omarchy-shutdown-countdown-2.timer"])
  assert.equal(parsed.unit, "omarchy-shutdown-countdown-1.timer")
  assert.equal(parsed.nextMs, now + 30000)
})

test("invalid timer JSON fails closed", () => {
  assert.deepEqual(Model.parseActiveTimers("not json", 1), { units: [], nextMs: 0, unit: "" })
  assert.deepEqual(Model.parseActiveTimers("{}", 1), { units: [], nextMs: 0, unit: "" })
})

test("errors keep the first useful line only", () => {
  assert.equal(Model.firstErrorLine("\n  failed to schedule\nmore\n"), "failed to schedule")
  assert.equal(Model.firstErrorLine(""), "")
})

test("preset membership is exact", () => {
  assert.equal(Model.isPreset([1800, 3600], 3600), true)
  assert.equal(Model.isPreset([1800], 3600), false)
  assert.equal(Model.isPreset(undefined, 1800), false)
})
