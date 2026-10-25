var DEFAULT_PRESETS = [1800, 3600]
var MAX_PRESETS = 10
var MAX_HOURS = 999
var MAX_SECONDS = MAX_HOURS * 3600 + 59 * 60 + 59

function pad2(value) {
  var n = Math.max(0, Math.floor(Number(value) || 0))
  return (n < 10 ? "0" : "") + n
}

function clampInt(value, min, max) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
}

function normalizePresets(value) {
  if (!Array.isArray(value)) return DEFAULT_PRESETS.slice()

  var seen = {}
  var out = []
  for (var i = 0; i < value.length && out.length < MAX_PRESETS; i++) {
    var seconds = Math.round(Number(value[i]))
    if (!isFinite(seconds) || seconds <= 0 || seconds > MAX_SECONDS) continue
    if (seen[seconds]) continue
    seen[seconds] = true
    out.push(seconds)
  }
  return out
}

function presetLabel(seconds) {
  var total = clampInt(seconds, 0, MAX_SECONDS)
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var secs = total % 60
  var parts = []

  if (hours > 0) parts.push(hours + " h")
  if (minutes > 0) parts.push(minutes + " m")
  if (secs > 0) parts.push(secs + " s")
  if (parts.length === 0) parts.push("0 s")
  return parts.join(" ")
}

// Hours and minutes only, for the large countdown. Seconds are truncated, but
// the last incomplete minute still reads 00:01 instead of 00:00 so the clock
// never claims the shutdown has arrived before the timer fires.
function formatHoursMinutes(seconds) {
  var total = Math.max(0, Math.round(Number(seconds) || 0))
  var minutes = Math.floor(total / 60)
  if (total > 0 && minutes === 0) minutes = 1
  var hours = Math.floor(minutes / 60)
  return pad2(hours) + ":" + pad2(minutes % 60)
}

function formatCompact(seconds) {
  var total = Math.max(0, Math.round(Number(seconds) || 0))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)

  if (hours > 0) return hours + "h " + pad2(minutes) + "m"
  if (total > 0 && minutes === 0) minutes = 1
  return minutes + "m"
}

function barGlyph() {
  return "󰔛"
}

function barStateGlyph(phase) {
  if (phase === "running") return "󰐊"
  if (phase === "paused") return "󰏤"
  return ""
}

function barLabel(phase, vertical, seconds) {
  var glyph = barGlyph()
  if (phase !== "idle") glyph += " " + barStateGlyph(phase)
  if (phase === "idle" || vertical) return glyph
  return glyph + " " + formatCompact(seconds)
}

function splitDuration(seconds) {
  var total = clampInt(seconds, 0, MAX_SECONDS)
  return {
    hours: Math.floor(total / 3600),
    minutes: Math.floor((total % 3600) / 60),
    seconds: total % 60
  }
}

function normalizeDuration(hours, minutes, seconds) {
  var h = Math.max(0, Math.round(Number(hours) || 0))
  var m = Math.max(0, Math.round(Number(minutes) || 0))
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  var total = h * 3600 + m * 60 + s
  if (total > MAX_SECONDS) total = MAX_SECONDS
  return splitDuration(total)
}

function nextOccurrence(nowMs, hour, minute) {
  var now = new Date(nowMs)
  var target = new Date(now.getFullYear(), now.getMonth(), now.getDate(),
    clampInt(hour, 0, 23), clampInt(minute, 0, 59), 0, 0)
  if (target.getTime() <= nowMs) target.setDate(target.getDate() + 1)
  return target.getTime()
}

function secondsUntil(nowMs, targetMs) {
  return Math.max(0, Math.ceil((Number(targetMs) - Number(nowMs)) / 1000))
}

function nextWholeSecond(ms) {
  return Math.ceil(Number(ms) / 1000) * 1000
}

function calendarStamp(ms) {
  var date = new Date(ms)
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
    + " " + pad2(date.getHours()) + ":" + pad2(date.getMinutes()) + ":" + pad2(date.getSeconds())
}

function relativeDayLabel(nowMs, targetMs) {
  var now = new Date(nowMs)
  var target = new Date(targetMs)
  var start = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  var end = new Date(target.getFullYear(), target.getMonth(), target.getDate())
  var days = Math.round((end.getTime() - start.getTime()) / 86400000)
  if (days === 0) return "Today"
  if (days === 1) return "Tomorrow"
  return ""
}

function makeUnit(nowMs) {
  return "omarchy-shutdown-countdown-" + Math.floor(Number(nowMs) || Date.now())
}

function parseActiveTimers(raw, nowMs) {
  var parsed = null
  try {
    parsed = JSON.parse(String(raw || "[]"))
  } catch (e) {
    return { units: [], nextMs: 0, unit: "" }
  }
  if (!Array.isArray(parsed)) return { units: [], nextMs: 0, unit: "" }

  var found = []
  var seen = {}
  for (var i = 0; i < parsed.length; i++) {
    var entry = parsed[i] || {}
    var unit = String(entry.unit || "")
    var nextUs = Number(entry.next)
    if (!unit || !isFinite(nextUs) || nextUs <= 0) continue
    var nextMs = Math.round(nextUs / 1000)
    if (nextMs <= nowMs) continue
    if (seen[unit]) continue
    seen[unit] = true
    found.push({ unit: unit, nextMs: nextMs })
  }

  found.sort(function(a, b) { return a.nextMs - b.nextMs })
  var units = []
  for (var j = 0; j < found.length; j++) units.push(found[j].unit)

  return {
    units: units,
    nextMs: found.length > 0 ? found[0].nextMs : 0,
    unit: found.length > 0 ? found[0].unit : ""
  }
}

function firstErrorLine(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line !== "") return line.length > 220 ? line.slice(0, 220) + "…" : line
  }
  return ""
}

function isPreset(presets, seconds) {
  return Array.isArray(presets) && presets.indexOf(seconds) !== -1
}
