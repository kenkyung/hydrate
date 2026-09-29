import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  // Persistent user state (weight, per-day counts), following the same
  // ~/.local/state/omarchy convention as the notifications service.
  readonly property string stateDir: home + "/.local/state/omarchy/"
  readonly property string statePath: stateDir + "kenkyung.water.json"

  // ------------------------------------------------------- persisted state

  property int weightKg: 75
  // { "YYYY-MM-DD": ["09:00", "12:00", ...] } — slot labels counted as drunk.
  property var countedByDay: ({})
  // True once the user has entered a weight (setup finished).
  property bool configured: false
  // False while reminders are disabled from the settings card. Manual opens
  // (bar widget click) still work so the person can re-enable them.
  property bool enabled: true

  property bool stateLoaded: false
  property string lastDayKey: ""

  // ----------------------------------------------------------- derived

  readonly property int dailyTargetMl: weightKg * 33
  readonly property int slotMl: Math.max(10, Math.round((dailyTargetMl / 8) / 10) * 10)
  readonly property int slotsPerDay: 8
  readonly property var slots: ["09:00", "10:30", "12:00", "13:30", "15:00", "16:30", "18:00", "19:30"]
  readonly property int defaultSnoozeMinutes: 10

  // A slot missed by more than this is skipped instead of fired late (e.g.
  // the machine was asleep or the shell just started after the slot).
  readonly property int missGraceMs: 2 * 60 * 1000

  // > 0: fire the popup every N seconds instead of the real slot schedule,
  // for unattended verification. 0: normal slot schedule.
  property int debugEverySeconds: 0

  property double nextFireAtMs: 0
  property string nextSlotLabel: ""
  // Timestamp of the last slot the schedule targeted. Slots at or before it
  // are never offered again this session, which keeps fire()/scheduleNext()
  // from re-arming on the same slot once it is inside its grace window.
  property double lastSlotTargetMs: 0
  property bool snoozePending: false
  property double snoozeFireAtMs: 0
  property string snoozeLabel: ""

  // Live snapshot for bar widgets to bind to. Reassigned as a whole object so
  // QML bindings re-evaluate on every change.
  property var progress: ({
    drank: 0,
    slots: slotsPerDay,
    ml: slotMl,
    targetMl: dailyTargetMl,
    weightKg: weightKg,
    nextSlot: "",
    nextAt: "",
    counted: []
  })

  function dayKey(ms) {
    return Qt.formatDateTime(new Date(ms === undefined ? Date.now() : ms), "yyyy-MM-dd")
  }

  function countedToday() {
    var list = countedByDay[dayKey()]
    return Array.isArray(list) ? list : []
  }

  function drankToday() {
    return countedToday().length
  }

  function slotTimeMs(label, day) {
    var parts = String(label).split(":")
    var d = new Date(day.getTime())
    d.setHours(Number(parts[0]), Number(parts[1]), 0, 0)
    return d.getTime()
  }

  // Next slot at or after `afterMs`. A slot already targeted (or fired) this
  // session is never offered again, so a fire/skip always advances the
  // schedule instead of re-arming on the same slot every second.
  function findNextSlot(nowMs, afterMs) {
    var day = new Date(nowMs)
    day.setHours(0, 0, 0, 0)
    for (var i = 0; i < slots.length; i++) {
      var t = slotTimeMs(slots[i], day)
      if (afterMs !== undefined && t <= afterMs) continue
      if (t + missGraceMs >= nowMs) return { label: slots[i], ms: t }
    }
    var tomorrow = new Date(day.getTime() + 24 * 60 * 60 * 1000)
    return { label: slots[0], ms: slotTimeMs(slots[0], tomorrow) }
  }

  // ------------------------------------------------------------ state io

  property Process ensureDir: Process {
    command: ["bash", "-c", "mkdir -p \"$0\"", root.stateDir]
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    printErrors: false
    onLoaded: root.hydrateState(text())
    onLoadFailed: function() { root.hydrateState("") }
  }

  property Timer stateSaveTimer: Timer {
    interval: 250
    repeat: false
    onTriggered: root.flushState()
  }

  function hydrateState(raw) {
    if (root.stateLoaded) return
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    if (parsed && typeof parsed === "object") {
      var weight = Number(parsed.weightKg)
      if (isFinite(weight) && weight > 0) root.weightKg = clampWeight(weight)
      root.configured = parsed.configured === true
      root.enabled = parsed.enabled !== false
      if (parsed.days && typeof parsed.days === "object") {
        var cleaned = ({})
        var cutoff = dayKey(Date.now() - 14 * 24 * 60 * 60 * 1000)
        for (var day in parsed.days) {
          if (day >= cutoff && Array.isArray(parsed.days[day].counted))
            cleaned[day] = parsed.days[day].counted.slice()
        }
        root.countedByDay = cleaned
      }
    }
    root.stateLoaded = true
    root.lastDayKey = root.dayKey()
    root.updateProgress()
  }

  function clampWeight(value) {
    return Math.max(20, Math.min(400, Math.round(Number(value) || 0)))
  }

  function scheduleStateSave() {
    if (!root.stateLoaded) return
    stateSaveTimer.restart()
  }

  function flushState() {
    var payload = { version: 1, weightKg: root.weightKg, configured: root.configured, enabled: root.enabled, days: {} }
    var cutoff = dayKey(Date.now() - 14 * 24 * 60 * 60 * 1000)
    for (var day in root.countedByDay) {
      var list = root.countedByDay[day]
      if (day >= cutoff && Array.isArray(list) && list.length)
        payload.days[day] = { counted: list.slice() }
    }
    stateFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  // ------------------------------------------------------------ progress

  function updateProgress() {
    var now = Date.now()
    var next = debugEverySeconds > 0
      ? { label: "every-" + debugEverySeconds + "s", ms: now }
      : (snoozePending ? { label: snoozeLabel, ms: snoozeFireAtMs } : findNextSlot(now, lastSlotTargetMs))
    root.progress = {
      drank: root.drankToday(),
      slots: slotsPerDay,
      ml: slotMl,
      targetMl: dailyTargetMl,
      weightKg: weightKg,
      nextSlot: next.label,
      nextAt: debugEverySeconds > 0 ? "debug mode" : new Date(next.ms).toISOString(),
      counted: countedToday()
    }
  }

  // ------------------------------------------------------------ actions

  function setWeightKg(value) {
    var next = clampWeight(value)
    var changed = next !== root.weightKg
    root.weightKg = next
    if (!root.configured) {
      root.configured = true
      changed = true
    }
    if (changed) {
      scheduleStateSave()
      updateProgress()
    }
    return changed
  }

  function setEnabled(value) {
    var next = value !== false
    if (next === root.enabled) return false
    root.enabled = next
    scheduleStateSave()
    updateProgress()
    if (next) scheduleNext()
    console.log("kenkyung.water: reminders", next ? "enabled" : "disabled")
    return true
  }

  // Records a drink for the slot the popup was fired for. Counting is
  // deduplicated per slot label per day, so re-snoozing and drinking the same
  // slot only counts once. Previews and debug fires pass countable=false.
  function drink(slotLabel, countable) {
    var label = String(slotLabel || "")
    if (countable !== false && label) {
      var today = dayKey()
      var list = countedToday()
      if (list.indexOf(label) === -1) {
        var next = ({})
        for (var day in root.countedByDay) next[day] = root.countedByDay[day].slice()
        var nextList = list.slice()
        nextList.push(label)
        next[today] = nextList
        root.countedByDay = next
        scheduleStateSave()
        updateProgress()
        console.log("kenkyung.water: drank", label, "->", root.drankToday() + "/" + slotsPerDay)
      }
    }
  }

  function snooze(minutes) {
    var m = Math.max(1, Math.round(Number(minutes) || defaultSnoozeMinutes))
    root.snoozePending = true
    root.snoozeFireAtMs = Date.now() + m * 60 * 1000
    root.snoozeLabel = root.nextSlotLabel || "later"
    console.log("kenkyung.water: snoozed", root.snoozeLabel, "for", m, "min")
    scheduleNext()
  }

  // Clears today's counted glasses; handy when exercising the flow.
  function resetToday() {
    var today = dayKey()
    var next = ({})
    for (var day in root.countedByDay) {
      if (day !== today) next[day] = root.countedByDay[day].slice()
    }
    root.countedByDay = next
    scheduleStateSave()
    updateProgress()
  }

  function scheduleNext() {
    if (debugEverySeconds > 0) {
      fireTimer.interval = Math.max(1, debugEverySeconds) * 1000
      fireTimer.restart()
      console.log("kenkyung.water: scheduled debug fire in", fireTimer.interval, "ms")
      updateProgress()
      return
    }
    var now = Date.now()
    if (snoozePending) {
      var remaining = snoozeFireAtMs - now
      if (remaining > 0) {
        fireTimer.interval = Math.max(1000, remaining)
        fireTimer.restart()
        updateProgress()
        return
      }
      snoozePending = false
    }
    var next = findNextSlot(now, lastSlotTargetMs)
    lastSlotTargetMs = next.ms
    nextFireAtMs = next.ms
    nextSlotLabel = next.label
    // Aim straight at the slot. A timer that expires during a suspend fires
    // once on wake, and fire() decides via the grace window whether it still
    // counts.
    fireTimer.interval = Math.max(1000, next.ms - now)
    fireTimer.restart()
    updateProgress()
  }

  function summon(slotLabel, ml, countable, extra) {
    if (!shell || typeof shell.summon !== "function") return
    var payload = {
      slot: slotLabel,
      ml: ml,
      countable: countable !== false,
      drank: root.drankToday(),
      slots: slotsPerDay,
      targetMl: dailyTargetMl,
      snoozeMinutes: defaultSnoozeMinutes,
      mode: root.configured ? "normal" : "setup",
      weightKg: weightKg,
      enabled: enabled,
      configured: configured
    }
    if (extra && typeof extra === "object") {
      for (var key in extra) payload[key] = extra[key]
    }
    shell.summon("kenkyung.water", JSON.stringify(payload))
  }

  function fire() {
    if (debugEverySeconds > 0) {
      console.log("kenkyung.water: debug fire", new Date().toISOString(), debugLabel(), slotMl, "ml")
      summon(debugLabel(), slotMl, false)
      scheduleNext()
      return
    }
    if (snoozePending) {
      var label = snoozeLabel
      snoozePending = false
      snoozeFireAtMs = 0
      summon(label, slotMl, true)
      scheduleNext()
      return
    }
    var late = Date.now() - nextFireAtMs
    if (!enabled) {
      console.log("kenkyung.water: reminders disabled, slot", nextSlotLabel, "skipped")
    } else if (late > missGraceMs) {
      console.warn("kenkyung.water: missed slot", nextSlotLabel, "by",
                   Math.round(late / 1000), "s; skipping")
    } else {
      summon(nextSlotLabel, slotMl, true)
    }
    scheduleNext()
  }

  function debugLabel() {
    var d = new Date()
    function pad(n) { return n < 10 ? "0" + n : String(n) }
    return pad(d.getHours()) + ":" + pad(d.getMinutes())
  }

  function statusJson() {
    var now = Date.now()
    var next = debugEverySeconds > 0
      ? { label: "every-" + debugEverySeconds + "s", ms: now }
      : (snoozePending ? { label: snoozeLabel, ms: snoozeFireAtMs } : findNextSlot(now, lastSlotTargetMs))
    return JSON.stringify({
      weightKg: weightKg,
      dailyTargetMl: dailyTargetMl,
      slotMl: slotMl,
      drank: drankToday(),
      slots: slotsPerDay,
      counted: countedToday(),
      nextSlot: next.label,
      nextAt: debugEverySeconds > 0 ? "debug mode" : new Date(next.ms).toISOString(),
      snoozePending: snoozePending,
      enabled: enabled,
      configured: configured,
      debugEverySeconds: debugEverySeconds,
      statePath: statePath,
      stateLoaded: stateLoaded
    })
  }

  Timer {
    id: fireTimer
    repeat: false
    onTriggered: root.fire()
  }

  IpcHandler {
    target: "water-reminder"

    function trigger(): string {
      root.summon("preview", root.slotMl, false)
      return "ok"
    }

    function status(): string {
      return root.statusJson()
    }

    function setWeightKg(kg: string): string {
      return root.setWeightKg(kg) ? "ok" : "unchanged"
    }

    function setEnabled(enabled: string): string {
      return root.setEnabled(enabled === "true") ? "ok" : "unchanged"
    }

    function drink(label: string, countable: string): string {
      root.drink(label, countable !== "false")
      return "ok"
    }

    function snooze(minutes: string): string {
      root.snooze(minutes)
      return "ok"
    }

    function resetToday(): string {
      root.resetToday()
      return "ok"
    }

    function reset(): string {
      root.weightKg = 75
      root.configured = false
      root.enabled = true
      root.countedByDay = ({})
      root.snoozePending = false
      root.lastSlotTargetMs = 0
      scheduleStateSave()
      updateProgress()
      scheduleNext()
      return "ok"
    }

    function setDebugEverySeconds(seconds: string): string {
      var n = Number(seconds)
      root.debugEverySeconds = (isFinite(n) && n > 0) ? Math.max(1, Math.round(n)) : 0
      root.scheduleNext()
      return "ok"
    }

    function ping(): string {
      return "ok"
    }
  }

  Component.onCompleted: {
    ensureDir.running = true
    Qt.callLater(function() { stateFile.reload() })
    root.scheduleNext()
  }
}
