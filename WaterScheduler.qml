import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null

  // The one knob to adjust: body weight in kilograms. The daily target and
  // per-slot amount below are derived from it. (QML forbids property names
  // starting with an upper-case letter, hence camelCase here.)
  readonly property int weightKg: 75

  readonly property int dailyTargetMl: weightKg * 33
  readonly property int slotMl: Math.round((dailyTargetMl / 8) / 10) * 10

  readonly property var slots: ["09:00", "10:30", "12:00", "13:30", "15:00", "16:30", "18:00", "19:30"]

  // A slot missed by more than this is skipped instead of fired late (e.g.
  // the machine was asleep or the shell just started after the slot).
  readonly property int missGraceMs: 2 * 60 * 1000

  // > 0: fire the popup every N seconds instead of the real slot schedule,
  // for unattended verification. 0: normal slot schedule.
  property int debugEverySeconds: 0

  property double nextFireAtMs: 0
  property string nextSlotLabel: ""

  function slotTimeMs(label, day) {
    var parts = String(label).split(":")
    var d = new Date(day.getTime())
    d.setHours(Number(parts[0]), Number(parts[1]), 0, 0)
    return d.getTime()
  }

  function findNextSlot(nowMs) {
    var day = new Date(nowMs)
    day.setHours(0, 0, 0, 0)
    for (var i = 0; i < slots.length; i++) {
      var t = slotTimeMs(slots[i], day)
      if (t + missGraceMs >= nowMs) return { label: slots[i], ms: t }
    }
    var tomorrow = new Date(day.getTime() + 24 * 60 * 60 * 1000)
    return { label: slots[0], ms: slotTimeMs(slots[0], tomorrow) }
  }

  function scheduleNext() {
    if (debugEverySeconds > 0) {
      fireTimer.interval = Math.max(1, debugEverySeconds) * 1000
      fireTimer.restart()
      console.log("kenkyung.water: scheduled debug fire in", fireTimer.interval, "ms")
      return
    }
    var now = Date.now()
    var next = findNextSlot(now)
    nextFireAtMs = next.ms
    nextSlotLabel = next.label
    // Aim straight at the slot. A timer that expires during a suspend fires
    // once on wake, and fire() decides via the grace window whether it still
    // counts.
    fireTimer.interval = Math.max(1000, next.ms - now)
    fireTimer.restart()
  }

  function summon(slotLabel, ml) {
    if (!shell || typeof shell.summon !== "function") return
    shell.summon("kenkyung.water", JSON.stringify({ slot: slotLabel, ml: ml }))
  }

  function fire() {
    if (debugEverySeconds > 0) {
      console.log("kenkyung.water: debug fire", new Date().toISOString(), debugLabel(), slotMl, "ml")
      summon(debugLabel(), slotMl)
      scheduleNext()
      return
    }
    var late = Date.now() - nextFireAtMs
    if (late > missGraceMs) {
      console.warn("kenkyung.water: missed slot", nextSlotLabel, "by",
                   Math.round(late / 1000), "s; skipping")
    } else {
      summon(nextSlotLabel, slotMl)
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
      : findNextSlot(now)
    return JSON.stringify({
      nextSlot: next.label,
      nextAt: debugEverySeconds > 0 ? "debug mode" : new Date(next.ms).toISOString(),
      amountMl: slotMl,
      dailyTargetMl: dailyTargetMl,
      weightKg: weightKg,
      debugEverySeconds: debugEverySeconds
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
      root.summon("preview", root.slotMl)
      return "ok"
    }

    function status(): string {
      return root.statusJson()
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

  Component.onCompleted: root.scheduleNext()
}
