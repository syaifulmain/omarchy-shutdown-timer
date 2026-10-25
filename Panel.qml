pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "syaifulmain.shutdown-countdown"
  ipcTarget: "syaifulmain.shutdown-countdown"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color softFill: Util.alpha(foreground, 0.04)
  readonly property color clockFill: Util.alpha(foreground, 0.05)
  readonly property color hairline: Util.alpha(foreground, 0.09)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Keep every rounded surface tied to the user's Hyprland rounding so the
  // panel matches the rest of the Omarchy shell. Nested controls subtract the
  // inset to stay concentric instead of hard-coding a second radius.
  readonly property int radius: Style.cornerRadius
  readonly property int fieldHeight: Math.max(
    Style.spacing.controlHeight + Style.space(4),
    Style.font.body + Style.spacing.controlPaddingY * 2 + Style.space(2))
  readonly property int tabHeight: Math.max(
    Style.spacing.controlHeight + Style.space(10),
    Style.font.body + Style.spacing.controlPaddingY * 2 + Style.space(10))
  readonly property int actionHeight: Math.max(
    Style.spacing.controlHeight + Style.space(12),
    Style.font.body + Style.spacing.controlPaddingY * 2 + Style.space(12))
  readonly property int presetGap: Style.space(6)

  property string mode: "duration"
  property int selectedPreset: 1800
  property int durationSeconds: 1800
  property int customHours: 0
  property int customMinutes: 30
  property int untilHour: 0
  property int untilMinute: 0
  property bool untilTouched: false
  property bool userSelected: false
  property string cursorKey: ""

  readonly property bool fieldEditing: customHoursField.editing
    || customMinutesField.editing
    || untilHourField.editing
    || untilMinuteField.editing

  property double nowMs: Date.now()
  property string phase: "idle"
  property double deadlineMs: 0
  property int pausedRemaining: 0
  property var timerUnits: []
  property string timerUnit: ""
  property bool busy: false
  property string errorText: ""

  property string scheduleStderr: ""
  property string stopStderr: ""
  property string queryStdout: ""
  property string queryStderr: ""
  property double pendingDeadline: 0
  property string pendingUnit: ""
  property string preStartPhase: "idle"
  property string pendingStopAction: ""
  property int pendingRemaining: 0
  property int queryGeneration: 0
  property int activeQueryGeneration: -1

  readonly property var presets: Model.normalizePresets(root.settings ? root.settings.presets : undefined)
  readonly property int customSeconds: customHours * 3600 + customMinutes * 60
  readonly property bool customIsPreset: Model.isPreset(presets, customSeconds)
  readonly property bool presetLimitReached: presets.length >= Model.MAX_PRESETS
  readonly property bool saveAvailable: customSeconds > 0 && !customIsPreset
  readonly property double untilTargetMs: Model.nextOccurrence(nowMs, untilHour, untilMinute)
  readonly property int untilSeconds: Model.secondsUntil(nowMs, untilTargetMs)
  readonly property int selectedSeconds: mode === "until" ? untilSeconds : durationSeconds
  readonly property int remainingSeconds: {
    if (phase === "running") return Model.secondsUntil(nowMs, deadlineMs)
    if (phase === "paused") return pausedRemaining
    return selectedSeconds
  }
  readonly property bool controlsEnabled: phase === "idle" && !busy
  readonly property bool deleteEnabled: controlsEnabled && selectedPreset > 0
    && Model.isPreset(presets, selectedPreset)
  readonly property bool urgentTime: phase === "running" && remainingSeconds <= 60
  readonly property bool barActive: phase !== "idle"
  readonly property color barActiveColor: {
    if (phase === "running")
      return urgentTime ? (bar ? bar.urgent : urgent) : accent
    if (phase === "paused") return dim
    return barForeground
  }

  readonly property string saveTooltip: {
    if (customSeconds <= 0) return "Set a duration first"
    if (customIsPreset) return "Already saved as a preset"
    if (presetLimitReached)
      return "Maximum " + Model.MAX_PRESETS + " presets — remove one first"
    return "Save custom timer as a preset"
  }

  readonly property string untilHint: {
    var day = Model.relativeDayLabel(nowMs, untilTargetMs)
    var time = Qt.formatDateTime(new Date(untilTargetMs), "HH:mm")
    return day === "" ? time : day + " · " + time
  }

  readonly property string timeCaption: {
    if (phase === "paused") return "PAUSED"
    if (phase === "running") return remainingSeconds <= 0 ? "SHUTTING DOWN" : "SHUTDOWN IN"
    return "SHUTDOWN IN"
  }

  readonly property string timeDetail: {
    if (phase === "paused") return "Resume to continue"
    if (phase === "running") {
      if (remainingSeconds <= 0) return "Closing applications"
      return "Armed · " + targetText(deadlineMs)
    }
    if (mode === "until") return untilHint
    if (durationSeconds <= 0) return "Choose a duration"
    return "Ready to start"
  }

  readonly property bool verticalBar: bar ? bar.vertical === true : false

  readonly property string barLabel: Model.barLabel(phase, verticalBar, remainingSeconds)

  readonly property string barTooltip: {
    if (phase === "running") {
      if (remainingSeconds <= 0) return "Shutting down"
      return "Shutdown in " + Model.formatHoursMinutes(remainingSeconds)
        + " · right-click pause · middle-click cancel"
    }
    if (phase === "paused") return "Shutdown paused · " + Model.formatHoursMinutes(remainingSeconds)
      + " left · right-click resume · middle-click cancel"
    return "Shutdown timer"
  }

  function targetText(targetMs) {
    var day = Model.relativeDayLabel(root.nowMs, targetMs)
    var time = Qt.formatDateTime(new Date(targetMs), "HH:mm")
    if (day !== "") return day + " at " + time
    return Qt.formatDateTime(new Date(targetMs), "d MMM") + " at " + time
  }

  function syncCustomFields(seconds) {
    var parts = Model.splitDuration(seconds)
    root.customHours = parts.hours
    root.customMinutes = parts.minutes
  }

  function syncSelectionToPresets() {
    if (presets.length === 0) {
      selectedPreset = -1
      return
    }
    if (!userSelected && !Model.isPreset(presets, selectedPreset)) {
      selectedPreset = presets[0]
      durationSeconds = presets[0]
      syncCustomFields(durationSeconds)
      return
    }
    if (selectedPreset > 0 && !Model.isPreset(presets, selectedPreset))
      selectedPreset = -1
  }

  function resetUntilDefault() {
    var target = new Date(root.nowMs + 3600000)
    root.untilHour = target.getHours()
    root.untilMinute = target.getMinutes()
  }

  function presetKey(seconds) {
    return "preset:" + seconds
  }

  function cursorFieldName(prefix) {
    if (prefix === "customHours") return "Hours"
    if (prefix === "customMinutes") return "Minutes"
    if (prefix === "untilHour") return "Hour"
    if (prefix === "untilMinute") return "Minute"
    return ""
  }

  readonly property string cursorTitle: {
    var key = root.cursorKey
    if (key === "") return ""
    if (key === "tab:duration") return "Timer · preset duration"
    if (key === "tab:until") return "Set clock · target time"
    if (key.indexOf("preset:") === 0)
      return "Preset · " + Model.presetLabel(Number(key.slice(7)))
    if (key === "save") return "Save preset"
    if (key === "start") return "Start shutdown timer"
    if (key === "pause")
      return root.phase === "paused" ? "Resume countdown" : "Pause countdown"
    if (key === "cancel") return "Cancel shutdown timer"

    var parts = key.split(":")
    if (parts.length === 2) {
      var name = root.cursorFieldName(parts[0])
      if (name !== "") {
        var cell = parts[1] === "dec" ? "decrease"
          : parts[1] === "inc" ? "increase" : "value"
        return name + " · " + cell
      }
    }
    return ""
  }

  readonly property string cursorHint: {
    var key = root.cursorKey
    if (root.fieldEditing) return "type a number · enter commit"
    if (key.indexOf("preset:") === 0) return "space use · del remove"
    if (key === "save") return "space save"
    if (key === "start") return "space start"
    if (key === "pause") return root.phase === "paused" ? "space resume" : "space pause"
    if (key === "cancel") return "space cancel"
    if (key.indexOf(":dec") > 0 || key.indexOf(":inc") > 0) return "space step"
    if (key.indexOf(":value") > 0) return "space edit"
    if (key === "tab:duration" || key === "tab:until") return "space choose"
    return "arrows move · space select"
  }

  function cursorCellFor(prefix) {
    if (root.cursorKey === prefix + ":dec") return "dec"
    if (root.cursorKey === prefix + ":value") return "value"
    if (root.cursorKey === prefix + ":inc") return "inc"
    return ""
  }

  function fieldForPrefix(prefix) {
    if (prefix === "customHours") return customHoursField
    if (prefix === "customMinutes") return customMinutesField
    if (prefix === "untilHour") return untilHourField
    if (prefix === "untilMinute") return untilMinuteField
    return null
  }

  function keySelectable(key) {
    var cell = ""
    var index = key.indexOf(":dec")
    if (index > 0) cell = "dec"
    else {
      index = key.indexOf(":inc")
      if (index > 0) cell = "inc"
    }
    if (cell === "") return true

    var field = root.fieldForPrefix(key.slice(0, index))
    if (field === null) return true
    var item = cell === "dec" ? field.decrementItem : field.incrementItem
    return item ? item.enabled !== false : true
  }

  // A step button can disappear from the usable row right after it moved the
  // value to the minimum or maximum. Land back on the value cell instead of
  // leaving the cursor parked on a disabled +/−.
  function settleCursor() {
    if (root.keySelectable(root.cursorKey)) return
    var index = root.cursorKey.lastIndexOf(":")
    if (index <= 0) return
    root.cursorKey = root.cursorKey.slice(0, index) + ":value"
  }

  function defaultCursorKey() {
    if (root.phase !== "idle") return "pause"
    if (!root.controlsEnabled) return "start"
    if (root.mode === "until") return "untilHour:value"
    if (root.presets.length > 0) {
      var seconds = Model.isPreset(root.presets, root.selectedPreset)
        ? root.selectedPreset : root.presets[0]
      return root.presetKey(seconds)
    }
    return "customMinutes:value"
  }

  function resetCursor() {
    root.cursorKey = root.defaultCursorKey()
  }

  function setHoverCursor(key) {
    if (!root.opened) return
    if (root.fieldEditing) return
    root.cursorKey = key
  }

  function reclaimKeyboard() {
    if (!root.opened) return
    if (customHoursField.editing) customHoursField.commit()
    if (customMinutesField.editing) customMinutesField.commit()
    if (untilHourField.editing) untilHourField.commit()
    if (untilMinuteField.editing) untilMinuteField.commit()
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  // Navigation is row based: Left/Right walks one visible row, Up/Down moves
  // to the row above or below. The old nearest-rectangle search could jump
  // across the panel when a Flow rewrapped, which made the cursor feel
  // unpredictable; this mirrors what the eye reads on screen.
  function navigationRows() {
    var rows = []

    if (root.controlsEnabled) {
      rows.push({ kind: "tabs", keys: ["tab:duration", "tab:until"] })

      if (root.mode === "duration") {
        var presetKeys = []
        for (var i = 0; i < root.presets.length; i++)
          presetKeys.push(root.presetKey(root.presets[i]))
        if (presetKeys.length > 0)
          rows.push({ kind: "presets", keys: presetKeys })

        rows.push({
          kind: "custom",
          keys: ["customHours:dec", "customHours:value", "customHours:inc",
            "customMinutes:dec", "customMinutes:value", "customMinutes:inc", "save"]
        })
      } else {
        rows.push({
          kind: "until",
          keys: ["untilHour:dec", "untilHour:value", "untilHour:inc",
            "untilMinute:dec", "untilMinute:value", "untilMinute:inc"]
        })
      }
    }

    rows.push({
      kind: "actions",
      keys: root.phase === "idle" ? ["start"] : ["pause", "cancel"]
    })
    return rows
  }

  function cursorLocation(rows) {
    for (var i = 0; i < rows.length; i++) {
      var col = rows[i].keys.indexOf(root.cursorKey)
      if (col >= 0)
        return { row: i, col: col, keys: rows[i].keys, kind: rows[i].kind }
    }
    return null
  }

  function presetCursorColumn(keys) {
    if (root.selectedPreset > 0) {
      var index = keys.indexOf(root.presetKey(root.selectedPreset))
      if (index >= 0) return index
    }
    return 0
  }

  function cursorColumnFor(target) {
    if (target.kind === "tabs") return root.mode === "until" ? 1 : 0
    if (target.kind === "presets") return root.presetCursorColumn(target.keys)
    if (target.kind === "custom")
      return Math.max(0, target.keys.indexOf("customMinutes:value"))
    if (target.kind === "until")
      return Math.max(0, target.keys.indexOf("untilMinute:value"))
    return 0
  }

  function normalizeCursor() {
    var rows = root.navigationRows()
    if (root.cursorLocation(rows) === null)
      root.cursorKey = root.defaultCursorKey()
  }

  function moveCursor(dx, dy) {
    var rows = root.navigationRows()
    if (rows.length === 0) return

    var loc = root.cursorLocation(rows)
    if (loc === null) {
      root.cursorKey = rows[0].keys[0]
      return
    }

    if (dx !== 0) {
      var step = dx > 0 ? 1 : -1
      var col = loc.col
      while (true) {
        col += step
        if (col < 0 || col >= loc.keys.length) return
        if (root.keySelectable(loc.keys[col])) {
          root.cursorKey = loc.keys[col]
          return
        }
      }
    }

    var nextRow = loc.row + dy
    if (nextRow < 0 || nextRow >= rows.length) return
    var target = rows[nextRow]
    var targetCol = root.cursorColumnFor(target)
    targetCol = Math.max(0, Math.min(target.keys.length - 1, targetCol))
    root.cursorKey = target.keys[targetCol]
  }

  function activateCursor() {
    var key = root.cursorKey

    if (key === "tab:duration" || key === "tab:until") {
      root.chooseMode(key === "tab:duration" ? "duration" : "until")
    } else if (key.indexOf("preset:") === 0) {
      root.selectPreset(Number(key.slice(7)))
    } else if (key === "customHours:dec") {
      customHoursField.step(-1)
    } else if (key === "customHours:value") {
      customHoursField.beginEdit()
    } else if (key === "customHours:inc") {
      customHoursField.step(1)
    } else if (key === "customMinutes:dec") {
      customMinutesField.step(-1)
    } else if (key === "customMinutes:value") {
      customMinutesField.beginEdit()
    } else if (key === "customMinutes:inc") {
      customMinutesField.step(1)
    } else if (key === "untilHour:dec") {
      untilHourField.step(-1)
    } else if (key === "untilHour:value") {
      untilHourField.beginEdit()
    } else if (key === "untilHour:inc") {
      untilHourField.step(1)
    } else if (key === "untilMinute:dec") {
      untilMinuteField.step(-1)
    } else if (key === "untilMinute:value") {
      untilMinuteField.beginEdit()
    } else if (key === "untilMinute:inc") {
      untilMinuteField.step(1)
    } else if (key === "save") {
      root.savePreset()
    } else if (key === "start") {
      root.start()
    } else if (key === "pause") {
      if (root.phase === "paused") root.start()
      else root.pause()
    } else if (key === "cancel") {
      root.cancel()
    }
  }

  function deleteTarget() {
    if (!root.controlsEnabled) return -1
    if (root.cursorKey.indexOf("preset:") === 0)
      return Number(root.cursorKey.slice(7))
    if (root.mode === "duration" && root.selectedPreset > 0
        && Model.isPreset(root.presets, root.selectedPreset))
      return root.selectedPreset
    return -1
  }

  function deleteCursor() {
    var seconds = root.deleteTarget()
    if (seconds <= 0) return

    var wasOnPreset = root.cursorKey.indexOf("preset:") === 0
    var rows = root.navigationRows()
    var loc = root.cursorLocation(rows)
    var index = loc ? loc.col : 0
    root.removePreset(seconds)

    if (!wasOnPreset) {
      if (root.cursorLocation(root.navigationRows()) === null)
        root.cursorKey = root.defaultCursorKey()
      return
    }

    var presetRow = null
    rows = root.navigationRows()
    for (var i = 0; i < rows.length; i++)
      if (rows[i].kind === "presets") presetRow = rows[i]

    if (presetRow !== null && presetRow.keys.length > 0) {
      root.cursorKey = presetRow.keys[Math.min(index, presetRow.keys.length - 1)]
    } else {
      root.cursorKey = root.defaultCursorKey()
    }
  }

  function setFieldCursor(prefix, cell) {
    root.cursorKey = prefix + ":" + cell
    if (cell !== "value") root.reclaimKeyboard()
  }

  function finishFieldEdit(prefix, direction) {
    root.cursorKey = prefix + ":value"
    if (keyCatcher) keyCatcher.forceActiveFocus()
    if (direction !== 0) root.switchPanel(direction)
  }

  function chooseMode(nextMode) {
    if (!root.controlsEnabled) return
    root.reclaimKeyboard()
    root.mode = nextMode
    root.cursorKey = "tab:" + nextMode
  }

  function selectPreset(seconds) {
    if (!controlsEnabled) return
    root.reclaimKeyboard()
    root.cursorKey = root.presetKey(seconds)
    root.mode = "duration"
    root.durationSeconds = seconds
    root.selectedPreset = seconds
    root.userSelected = true
    root.syncCustomFields(seconds)
    root.errorText = ""
  }

  function applyCustomSelection() {
    root.mode = "duration"
    root.durationSeconds = root.customSeconds
    root.selectedPreset = Model.isPreset(root.presets, root.customSeconds) ? root.customSeconds : -1
    root.userSelected = true
    root.errorText = ""
  }

  function setCustomPart(part, value) {
    if (!controlsEnabled) return
    var next = Math.max(0, Math.round(Number(value) || 0))
    if (part === "hours") root.customHours = next
    else root.customMinutes = next

    var parts = Model.normalizeDuration(root.customHours, root.customMinutes, 0)
    root.syncCustomFields(parts.hours * 3600 + parts.minutes * 60)
    root.applyCustomSelection()
    root.settleCursor()
  }

  function persistPresets(next) {
    var settings = Object.assign({}, root.settings, { presets: next })
    root.settings = settings
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, settings)
  }

  function savePreset() {
    if (!controlsEnabled) return
    root.reclaimKeyboard()
    if (!root.saveAvailable) return
    root.cursorKey = "save"
    if (presetLimitReached) {
      root.errorText = "Maximum " + Model.MAX_PRESETS + " presets. Remove one first."
      return
    }
    var next = root.presets.slice()
    next.push(root.customSeconds)
    root.userSelected = true
    root.mode = "duration"
    root.durationSeconds = root.customSeconds
    root.selectedPreset = root.customSeconds
    root.cursorKey = root.presetKey(root.customSeconds)
    root.errorText = ""
    root.persistPresets(next)
  }

  function removePreset(seconds) {
    if (!controlsEnabled || !Model.isPreset(root.presets, seconds)) return
    root.reclaimKeyboard()
    var wasSelected = root.selectedPreset === seconds
    var next = root.presets.filter(function(value) { return value !== seconds })
    root.userSelected = true
    root.errorText = ""

    if (wasSelected && next.length > 0) {
      root.durationSeconds = next[0]
      root.selectedPreset = next[0]
      root.syncCustomFields(next[0])
    } else if (wasSelected) {
      root.durationSeconds = seconds
      root.selectedPreset = -1
      root.syncCustomFields(seconds)
    }

    root.settleCursor()
    root.persistPresets(next)
  }

  function removeSelectedPreset() {
    if (!deleteEnabled) return
    root.removePreset(root.selectedPreset)
  }

  function currentTimerUnits() {
    if (root.timerUnits.length > 0) return root.timerUnits.slice()
    if (root.timerUnit !== "") return [root.timerUnit]
    return []
  }

  function scheduleTimer(seconds, fromPhase) {
    if (seconds <= 0) return
    var target = fromPhase === "idle" && root.mode === "until"
      ? root.untilTargetMs
      : Model.nextWholeSecond(root.nowMs + seconds * 1000)
    var unit = Model.makeUnit(Date.now())

    root.pendingDeadline = target
    root.pendingUnit = unit
    root.preStartPhase = fromPhase
    root.scheduleStderr = ""
    root.errorText = ""
    root.busy = true
    root.invalidateQueries()

    scheduleProc.command = [
      "systemd-run",
      "--user",
      "--quiet",
      "--collect",
      "--unit=" + unit,
      "--on-calendar=" + Model.calendarStamp(target),
      "--timer-property=AccuracySec=1s",
      "omarchy-system-shutdown"
    ]
    scheduleProc.running = true
  }

  function start() {
    if (root.busy || root.phase === "running") return
    root.reclaimKeyboard()

    if (root.phase === "paused") {
      root.cursorKey = "pause"
      if (root.pausedRemaining <= 0) {
        root.resetToIdle()
        root.focusDefault()
        return
      }
      root.scheduleTimer(root.pausedRemaining, "paused")
      return
    }

    root.cursorKey = "start"
    if (root.selectedSeconds <= 0) return
    root.scheduleTimer(root.selectedSeconds, "idle")
  }

  function pause() {
    if (root.phase !== "running" || root.busy) return
    root.cursorKey = "pause"
    root.reclaimKeyboard()
    var left = root.remainingSeconds
    if (left <= 0) return
    var units = root.currentTimerUnits()
    if (units.length === 0) {
      root.errorText = "The shutdown timer unit is unknown. Refreshing…"
      root.refreshTimerState()
      return
    }

    root.pendingRemaining = left
    root.pendingStopAction = "pause"
    root.stopStderr = ""
    root.errorText = ""
    root.busy = true
    root.invalidateQueries()
    root.stopUnits(units)
  }

  function cancel() {
    if (root.phase === "idle" || root.busy) return
    root.cursorKey = "cancel"
    root.reclaimKeyboard()

    if (root.phase === "paused") {
      root.errorText = ""
      root.resetToIdle()
      root.notifyPeers()
      root.focusDefault()
      return
    }

    var units = root.currentTimerUnits()
    if (units.length === 0) {
      root.errorText = "The shutdown timer unit is unknown. Refreshing…"
      root.refreshTimerState()
      return
    }

    root.pendingStopAction = "cancel"
    root.stopStderr = ""
    root.errorText = ""
    root.busy = true
    root.invalidateQueries()
    root.stopUnits(units)
  }

  function stopUnits(units) {
    var command = ["systemctl", "--user", "stop"]
    for (var i = 0; i < units.length; i++) command.push(units[i])
    stopProc.command = command
    stopProc.running = true
  }

  function resetToIdle() {
    root.phase = "idle"
    root.pausedRemaining = 0
    root.deadlineMs = 0
    root.timerUnits = []
    root.timerUnit = ""
  }

  function focusDefault() {
    Qt.callLater(function() {
      if (!root.opened) return
      root.normalizeCursor()
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function finishSchedule(code) {
    root.busy = false
    if (code === 0) {
      root.deadlineMs = root.pendingDeadline
      root.timerUnit = root.pendingUnit + ".timer"
      root.timerUnits = [root.timerUnit]
      root.pausedRemaining = 0
      root.phase = "running"
      root.errorText = ""
      root.notifyPeers()
      root.focusDefault()
      return
    }

    root.phase = root.preStartPhase
    root.errorText = root.scheduleStderr !== ""
      ? Model.firstErrorLine(root.scheduleStderr)
      : "Could not schedule the shutdown timer."
    root.scheduleStderr = ""
    root.focusDefault()
  }

  function finishStop(code) {
    root.busy = false
    var action = root.pendingStopAction
    root.pendingStopAction = ""

    if (code === 0) {
      root.timerUnits = []
      root.timerUnit = ""
      root.deadlineMs = 0
      if (action === "pause") {
        root.phase = "paused"
        root.pausedRemaining = root.pendingRemaining
      } else {
        root.resetToIdle()
      }
      root.errorText = ""
      root.notifyPeers()
      root.focusDefault()
      return
    }

    root.errorText = root.stopStderr !== ""
      ? Model.firstErrorLine(root.stopStderr)
      : "Could not cancel the scheduled shutdown."
    root.stopStderr = ""
    root.focusDefault()
    root.refreshTimerState()
  }

  function invalidateQueries() {
    root.queryGeneration++
  }

  function refreshTimerState() {
    if (root.busy || queryProc.running) return
    root.activeQueryGeneration = ++root.queryGeneration
    root.queryStdout = ""
    root.queryStderr = ""
    queryProc.command = [
      "systemctl",
      "--user",
      "list-timers",
      "--all",
      "--output=json",
      "omarchy-shutdown-countdown-*.timer"
    ]
    queryProc.running = true
  }

  function finishQuery(code) {
    if (root.activeQueryGeneration !== root.queryGeneration) return
    if (root.busy) return

    if (code !== 0) {
      if (root.opened) root.errorText = root.queryStderr !== ""
        ? Model.firstErrorLine(root.queryStderr)
        : "Could not read the scheduled shutdown."
      return
    }

    var result = Model.parseActiveTimers(root.queryStdout, root.nowMs)
    if (result.nextMs > 0) {
      root.timerUnits = result.units
      root.timerUnit = result.unit
      root.deadlineMs = result.nextMs
      root.pausedRemaining = 0
      root.phase = "running"
      return
    }

    if (root.phase === "running") {
      root.timerUnits = []
      root.timerUnit = ""
      root.deadlineMs = 0
      root.phase = "idle"
      if (root.opened) root.errorText = "The scheduled shutdown is no longer active."
    }
  }

  function notifyPeers() {
    var items = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName)
      : []
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      if (item && item !== root && typeof item.refreshTimerState === "function")
        item.refreshTimerState()
    }
  }

  onPresetsChanged: {
    root.syncSelectionToPresets()
    root.settleCursor()
    if (root.opened) root.normalizeCursor()
  }
  onModeChanged: {
    if (root.mode === "until" && !root.untilTouched) root.resetUntilDefault()
    if (root.opened) root.normalizeCursor()
    root.errorText = ""
  }
  onPhaseChanged: if (root.opened) root.normalizeCursor()
  onOpenedChanged: {
    if (!root.opened) return
    root.resetCursor()
    root.refreshTimerState()
    root.focusDefault()
  }

  Component.onCompleted: {
    root.syncSelectionToPresets()
    root.syncCustomFields(root.durationSeconds)
    root.resetUntilDefault()
    root.refreshTimerState()
  }

  SystemClock {
    id: wallClock
    precision: SystemClock.Seconds
    onDateChanged: root.nowMs = date.getTime()
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.phase === "running" && !root.busy
    onTriggered: root.refreshTimerState()
  }

  Process {
    id: scheduleProc
    onExited: function(code) { Qt.callLater(function() { root.finishSchedule(code) }) }
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.scheduleStderr = text
    }
  }

  Process {
    id: stopProc
    onExited: function(code) { Qt.callLater(function() { root.finishStop(code) }) }
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.stopStderr = text
    }
  }

  Process {
    id: queryProc
    onExited: function(code) { Qt.callLater(function() { root.finishQuery(code) }) }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.queryStdout = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.queryStderr = text
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function start(): string { root.start(); return "ok" }
    function pause(): string { root.pause(); return "ok" }
    function cancel(): string { root.cancel(); return "ok" }
    function status(): string {
      return JSON.stringify({
        phase: root.phase,
        busy: root.busy,
        remainingSeconds: root.remainingSeconds,
        deadlineMs: root.deadlineMs,
        timerUnits: root.timerUnits,
        error: root.errorText
      })
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    labelVisible: !root.verticalBar
    active: root.barActive
    activeColor: root.barActiveColor
    tooltipText: root.barTooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) {
        root.toggle()
      } else if (buttonCode === Qt.RightButton) {
        if (root.phase === "running") root.pause()
        else if (root.phase === "paused") root.start()
      } else if (buttonCode === Qt.MiddleButton) {
        if (root.phase !== "idle") root.cancel()
      }
    }

    Item {
      visible: root.verticalBar
      anchors.fill: parent

      Item {
        id: verticalGlyphPair
        anchors.centerIn: parent
        width: verticalTimerGlyph.implicitWidth
          + (verticalStateGlyph.visible
            ? verticalGlyphGap + verticalStateGlyph.implicitWidth : 0)
        height: Math.max(verticalTimerGlyph.implicitHeight,
          verticalStateGlyph.visible ? verticalStateGlyph.implicitHeight : 0)

        readonly property real verticalGlyphGap: Math.max(2, Math.round(button.fontSize * 0.16))

        Text {
          id: verticalTimerGlyph
          x: 0
          y: verticalGlyphPair.height - implicitHeight
          text: Model.barGlyph()
          color: root.barActiveColor
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          renderType: Text.NativeRendering
          textFormat: Text.PlainText
        }

        Text {
          id: verticalStateGlyph
          x: verticalTimerGlyph.implicitWidth + verticalGlyphPair.verticalGlyphGap
          y: verticalGlyphPair.height - implicitHeight
          visible: text !== ""
          text: Model.barStateGlyph(root.phase)
          color: root.barActiveColor
          font.family: button.fontFamily
          font.pixelSize: Math.max(1, Math.round(button.fontSize * 0.75))
          renderType: Text.NativeRendering
          textFormat: Text.PlainText
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.fieldEditing
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onDeleteRequested: root.deleteCursor()
      onTextKey: function(t) {
        if (root.fieldEditing) return
        if (t === "\b" || t === "\u007f") root.deleteCursor()
      }

      Keys.onDeletePressed: function(event) {
        if (root.fieldEditing) return
        root.deleteCursor()
        event.accepted = true
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Shutdown Countdown"
          meta: "Countdown to a clean shutdown"
          detail: root.phase === "running" ? "ARMED" : root.phase === "paused" ? "PAUSED" : ""
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              text: "󰔛"
              color: root.urgentTime ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              textFormat: Text.PlainText
            }
          }
        }

        BorderSurface {
          width: parent.width
          implicitHeight: timeColumn.implicitHeight + Style.space(42)
          radius: Math.min(root.radius, height / 2)
          color: root.clockFill
          borderSpec: Border.flat(root.hairline, Math.max(1, Style.normalBorderWidth))

          Column {
            id: timeColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(30)
            spacing: Style.space(3)

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.timeCaption
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.6
              textFormat: Text.PlainText
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: Model.formatHoursMinutes(root.remainingSeconds)
              color: root.urgentTime ? root.urgent : root.accent
              font.family: root.fontFamily
              font.pixelSize: Math.round(Style.font.displayLarge * 1.85)
              font.bold: true
              font.letterSpacing: Math.max(0, Style.space(1))
              textFormat: Text.PlainText
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.timeDetail
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
            }
          }
        }

        BorderSurface {
          id: tabTrack
          width: parent.width
          height: root.tabHeight
          radius: Math.min(root.radius, height / 2)
          color: root.softFill
          borderSpec: Border.none()
          readonly property int inset: Math.max(1, Style.space(2))
          readonly property int segmentRadius: Math.max(0, root.radius - inset)

          Row {
            anchors.fill: parent
            anchors.margins: tabTrack.inset
            spacing: tabTrack.inset

            TimerButton {
              id: durationTab
              width: (parent.width - parent.spacing) / 2
              height: parent.height
              text: "Timer"
              filled: root.mode === "duration"
              focusable: false
              hasCursor: root.cursorKey === "tab:duration"
              enabled: root.controlsEnabled
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              cornerRadius: tabTrack.segmentRadius
              onClicked: root.chooseMode("duration")
              onHovered: function(on) { if (on) root.setHoverCursor("tab:duration") }
            }

            TimerButton {
              id: untilTab
              width: (parent.width - parent.spacing) / 2
              height: parent.height
              text: "Set clock"
              filled: root.mode === "until"
              focusable: false
              hasCursor: root.cursorKey === "tab:until"
              enabled: root.controlsEnabled
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              cornerRadius: tabTrack.segmentRadius
              onClicked: root.chooseMode("until")
              onHovered: function(on) { if (on) root.setHoverCursor("tab:until") }
            }
          }
        }

        Column {
          id: durationSection
          visible: root.mode === "duration"
          width: parent.width
          spacing: Style.space(8)
          enabled: root.controlsEnabled
          opacity: enabled ? 1 : 0.55

          PanelSectionHeader {
            text: "PRESETS"
            foreground: root.foreground
            fontFamily: root.fontFamily
            font.letterSpacing: 1.0
          }

          Flow {
            width: parent.width
            spacing: root.presetGap

            Repeater {
              id: presetRepeater
              model: root.presets

              delegate: PresetChip {
                required property int modelData
                text: Model.presetLabel(modelData)
                selected: root.mode === "duration" && root.selectedPreset === modelData
                removable: selected && root.deleteEnabled
                focusable: false
                hasCursor: root.cursorKey === root.presetKey(modelData)
                enabled: root.controlsEnabled
                foreground: root.foreground
                accent: root.accent
                urgent: root.urgent
                fontFamily: root.fontFamily
                cornerRadius: root.radius
                onActivated: root.selectPreset(modelData)
                onRemoveRequested: root.removeSelectedPreset()
                onHovered: function(on) {
                  if (on) root.setHoverCursor(root.presetKey(modelData))
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.presets.length === 0
            text: "No presets yet. Save a custom timer below."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
          }

          PanelSectionHeader {
            text: "CUSTOM"
            foreground: root.foreground
            fontFamily: root.fontFamily
            font.letterSpacing: 1.0
          }

          Item {
            id: customSection
            width: parent.width
            height: customFields.height
            readonly property int saveWidth: Math.max(Style.space(74), Math.round(width * 0.24))
            readonly property int gap: root.presetGap
            readonly property int fieldWidth: Math.max(Style.space(64),
              Math.floor((width - saveWidth - gap * 2) / 2))

            Row {
              id: customFields
              width: parent.width
              spacing: customSection.gap

              StepperField {
                id: customHoursField
                width: customSection.fieldWidth
                label: "HOURS"
                from: 0
                to: Model.MAX_HOURS
                fieldHeight: root.fieldHeight
                value: root.customHours
                cursorCell: root.cursorCellFor("customHours")
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                cornerRadius: root.radius
                onModified: function(value) { root.setCustomPart("hours", value) }
                onCursorRequested: function(cell) { root.setFieldCursor("customHours", cell) }
                onCellHovered: function(cell) {
                  if (root.controlsEnabled) root.setHoverCursor("customHours:" + cell)
                }
                onEditFinished: function(direction) { root.finishFieldEdit("customHours", direction) }
                onEditCancelled: root.finishFieldEdit("customHours", 0)
              }

              StepperField {
                id: customMinutesField
                width: customSection.fieldWidth
                label: "MINUTES"
                from: 0
                to: 9999
                fieldHeight: root.fieldHeight
                value: root.customMinutes
                cursorCell: root.cursorCellFor("customMinutes")
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                cornerRadius: root.radius
                onModified: function(value) { root.setCustomPart("minutes", value) }
                onCursorRequested: function(cell) { root.setFieldCursor("customMinutes", cell) }
                onCellHovered: function(cell) {
                  if (root.controlsEnabled) root.setHoverCursor("customMinutes:" + cell)
                }
                onEditFinished: function(direction) { root.finishFieldEdit("customMinutes", direction) }
                onEditCancelled: root.finishFieldEdit("customMinutes", 0)
              }

              TimerButton {
                id: saveButton
                width: customSection.saveWidth
                height: root.fieldHeight
                y: customHoursField.height - root.fieldHeight
                text: "Save"
                filled: false
                bordered: true
                focusable: false
                hasCursor: root.cursorKey === "save"
                enabled: root.saveAvailable
                tooltipText: root.saveTooltip
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                cornerRadius: root.radius
                onClicked: root.savePreset()
                onHovered: function(on) { if (on) root.setHoverCursor("save") }
              }
            }
          }
        }

        Column {
          id: untilSection
          visible: root.mode === "until"
          width: parent.width
          spacing: Style.space(8)
          enabled: root.controlsEnabled
          opacity: enabled ? 1 : 0.55

          PanelSectionHeader {
            text: "SET CLOCK"
            foreground: root.foreground
            fontFamily: root.fontFamily
            font.letterSpacing: 1.0
          }

          Row {
            id: untilFields
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)
            readonly property int fieldWidth: Math.max(Style.space(84),
              Math.round(column.width * 0.34))

            StepperField {
              id: untilHourField
              width: untilFields.fieldWidth
              label: "HOUR"
              from: 0
              to: 23
              fieldHeight: root.fieldHeight
              value: root.untilHour
              cursorCell: root.cursorCellFor("untilHour")
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              cornerRadius: root.radius
              onModified: function(value) {
                root.untilHour = value
                root.untilTouched = true
                root.userSelected = true
                root.errorText = ""
                root.settleCursor()
              }
              onCursorRequested: function(cell) { root.setFieldCursor("untilHour", cell) }
              onCellHovered: function(cell) {
                if (root.controlsEnabled) root.setHoverCursor("untilHour:" + cell)
              }
              onEditFinished: function(direction) { root.finishFieldEdit("untilHour", direction) }
              onEditCancelled: root.finishFieldEdit("untilHour", 0)
            }

            StepperField {
              id: untilMinuteField
              width: untilFields.fieldWidth
              label: "MINUTE"
              from: 0
              to: 59
              fieldHeight: root.fieldHeight
              value: root.untilMinute
              cursorCell: root.cursorCellFor("untilMinute")
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              cornerRadius: root.radius
              onModified: function(value) {
                root.untilMinute = value
                root.untilTouched = true
                root.userSelected = true
                root.errorText = ""
                root.settleCursor()
              }
              onCursorRequested: function(cell) { root.setFieldCursor("untilMinute", cell) }
              onCellHovered: function(cell) {
                if (root.controlsEnabled) root.setHoverCursor("untilMinute:" + cell)
              }
              onEditFinished: function(direction) { root.finishFieldEdit("untilMinute", direction) }
              onEditCancelled: root.finishFieldEdit("untilMinute", 0)
            }
          }
        }

        Text {
          width: parent.width
          visible: root.errorText !== ""
          text: root.errorText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          TimerButton {
            id: startButton
            visible: root.phase === "idle"
            width: parent.width
            height: root.actionHeight
            text: root.busy ? "Starting…" : "Start shutdown"
            filled: true
            focusable: false
            hasCursor: root.cursorKey === "start"
            enabled: root.controlsEnabled && root.selectedSeconds > 0
            tooltipText: "Start the shutdown countdown"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.title
            cornerRadius: root.radius
            onClicked: root.start()
            onHovered: function(on) { if (on) root.setHoverCursor("start") }
          }

          TimerButton {
            id: pauseButton
            visible: root.phase !== "idle"
            width: (parent.width - parent.spacing) / 2
            height: root.actionHeight
            text: root.phase === "paused" ? "Resume" : "Pause"
            filled: true
            focusable: false
            hasCursor: root.cursorKey === "pause"
            enabled: !root.busy
            tooltipText: root.phase === "paused"
              ? "Resume the paused countdown"
              : "Pause the countdown and keep the time left"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.title
            cornerRadius: root.radius
            onClicked: root.phase === "paused" ? root.start() : root.pause()
            onHovered: function(on) { if (on) root.setHoverCursor("pause") }
          }

          TimerButton {
            id: cancelButton
            visible: root.phase !== "idle"
            width: (parent.width - parent.spacing) / 2
            height: root.actionHeight
            text: "Cancel"
            filled: false
            bordered: true
            destructive: true
            focusable: false
            hasCursor: root.cursorKey === "cancel"
            enabled: !root.busy
            tooltipText: "Cancel the scheduled shutdown"
            foreground: root.urgent
            accent: root.accent
            urgent: root.urgent
            fontFamily: root.fontFamily
            fontSize: Style.font.title
            cornerRadius: root.radius
            onClicked: root.cancel()
            onHovered: function(on) { if (on) root.setHoverCursor("cancel") }
          }
        }

        Item {
          width: parent.width
          implicitHeight: Math.max(statusTitle.implicitHeight, statusHint.implicitHeight)
          visible: root.cursorTitle !== ""

          Text {
            id: statusTitle
            text: root.cursorTitle
            color: root.accent
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
            width: Math.min(implicitWidth, parent.width * 0.55)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: statusHint
            text: root.cursorHint
            color: root.dim
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width - statusTitle.width - Style.space(8)
            horizontalAlignment: Text.AlignRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }
}
