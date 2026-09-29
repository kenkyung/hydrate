import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "kenkyung.water"

  // The live WaterScheduler service. The bar's scoped shell facade resolves
  // the plugin's own service, so the widget and the popup share one state.
  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("kenkyung.water") : null
  readonly property var progress: service && service.progress !== undefined ? service.progress : null
  readonly property int drank: progress && isFinite(progress.drank) ? progress.drank : 0
  readonly property int slotsTotal: progress && isFinite(progress.slots) ? progress.slots : 8
  readonly property int ml: progress && isFinite(progress.ml) ? progress.ml : 310
  readonly property int targetMl: progress && isFinite(progress.targetMl) ? progress.targetMl : 2475
  readonly property string nextSlot: progress && progress.nextSlot !== undefined ? String(progress.nextSlot) : ""
  readonly property bool complete: drank >= slotsTotal
  readonly property bool remindersEnabled: service ? service.enabled === true : true

  visible: service !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function tooltipText() {
    if (!root.remindersEnabled)
      return "Water reminders off\nClick to reopen"
    var lines = ["Water " + root.drank + "/" + root.slotsTotal + " · " + root.ml + " ml each",
                 "Daily goal " + (Math.round(root.targetMl / 1000 * 10) / 10) + " L"]
    if (root.nextSlot && root.nextSlot !== "debug mode") lines.push("Next " + root.nextSlot)
    return lines.join("\n")
  }

  function openPopup() {
    if (!service || !bar || !bar.shell) return
    var payload = JSON.stringify({
      slot: "manual",
      ml: service.slotMl,
      countable: false,
      drank: root.drank,
      slots: root.slotsTotal,
      targetMl: root.targetMl,
      snoozeMinutes: service.defaultSnoozeMinutes,
      // First-run users get the setup card, same as a scheduled fire would.
      mode: service.configured === false ? "setup" : "normal"
    })
    bar.shell.toggle("kenkyung.water", payload)
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.remindersEnabled ? (root.drank + "/" + root.slotsTotal) : "off"
    textRotation: root.vertical ? 90 : 0
    active: root.complete
    dimmed: !root.remindersEnabled
    tooltipText: root.tooltipText()
    onPressed: function(b) { root.openPopup() }
  }
}
