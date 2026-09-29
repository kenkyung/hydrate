import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  // The matching WaterScheduler service, injected by the shell when a
  // service-kind entry point exists alongside the overlay.
  property var service: null

  property bool opened: false
  property string mode: "normal" // "normal" | "setup" | "settings" | "weight"

  property string slotLabel: "preview"
  property int ml: 310
  property bool countable: false
  property int drank: 0
  property int slots: 8
  property int targetMl: 2475
  property int snoozeMinutes: 10
  property string weightInput: ""
  property string weightError: ""

  readonly property int autoHideMs: 12000

  readonly property color cardBackground: Util.alpha(Color.popups.background, 0.97)
  readonly property color cardForeground: Color.popups.text
  // Themes define no blue role, so the water is a fixed blue that reads well
  // against any popup background. Same rationale for the validation red.
  readonly property color waterBlue: "#6cb2f2"
  readonly property color errorRed: "#e06c75"
  readonly property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  readonly property int glassStageWidth: Style.space(64)
  readonly property int glassStageHeight: Style.space(88)
  readonly property int columnGap: Style.space(14)

  // Live service state, falling back to the payload captured at summon time.
  readonly property var liveProgress: service && service.progress ? service.progress : null
  readonly property int drankNow: liveProgress && isFinite(liveProgress.drank) ? liveProgress.drank : root.drank
  readonly property int targetNow: liveProgress && isFinite(liveProgress.targetMl) ? liveProgress.targetMl : root.targetMl
  readonly property int weightNow: service && isFinite(service.weightKg) ? service.weightKg : 75
  readonly property bool enabledNow: service ? service.enabled === true : true
  // Glass fill mirrors today's progress, kept just above empty so the glass
  // still reads as a glass at 0/8.
  readonly property real fillRatio: Math.max(0.05, Math.min(1.0, root.drankNow / Math.max(1, root.slots)))

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    slotLabel = payload.slot !== undefined ? String(payload.slot) : "preview"
    ml = isFinite(Number(payload.ml)) ? Math.round(Number(payload.ml)) : 310
    countable = payload.countable === true
    drank = isFinite(Number(payload.drank)) ? Math.round(Number(payload.drank)) : 0
    slots = isFinite(Number(payload.slots)) ? Math.round(Number(payload.slots)) : 8
    targetMl = isFinite(Number(payload.targetMl)) ? Math.round(Number(payload.targetMl)) : 2475
    snoozeMinutes = isFinite(Number(payload.snoozeMinutes)) ? Math.max(1, Math.round(Number(payload.snoozeMinutes))) : 10
    weightInput = ""
    weightError = ""
    setMode(String(payload.mode) === "setup" ? "setup" : "normal")
    opened = true
    card.opacity = 0
    card.scale = 0.96
    enterAnim.restart()
    // Only real reminder fires make noise; bar clicks and IPC previews are
    // user-initiated and stay silent.
    if (countable)
      Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga"])
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
  }

  function dismiss() {
    opened = false
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "kenkyung.water")
  }

  function setMode(next) {
    mode = next
    if (next === "normal") hideTimer.restart()
    else hideTimer.stop()
  }

  function markDrunk() {
    var label = slotLabel
    var canCount = countable
    dismiss()
    if (service && typeof service.drink === "function")
      service.drink(label, canCount)
  }

  function snooze() {
    var minutes = snoozeMinutes
    var label = slotLabel
    var canCount = countable
    dismiss()
    if (service && typeof service.snooze === "function")
      service.snooze(minutes, label, canCount)
  }

  function editWeight(event) {
    if (Util.editsFilter(event, root.weightInput)) {
      weightInput = Util.editedFilter(event, root.weightInput)
      weightError = ""
      return true
    }
    if (event.text && /^[0-9]$/.test(event.text) && root.weightInput.length < 3) {
      weightInput = root.weightInput + event.text
      weightError = ""
      return true
    }
    return false
  }

  function submitWeight() {
    var parsed = parseInt(weightInput, 10)
    var weight = isFinite(parsed) && parsed >= 20 && parsed <= 400 ? parsed : 0
    if (!weight) {
      weightError = "Enter a weight from 20 to 400 kg"
      return false
    }
    weightError = ""
    if (service && typeof service.setWeightKg === "function")
      service.setWeightKg(weight)
    weightInput = ""
    if (mode === "setup") dismiss()
    else setMode("settings")
    return true
  }

  function useDefaultWeight() {
    if (service && typeof service.setWeightKg === "function")
      service.setWeightKg(75)
    weightInput = ""
    weightError = ""
    dismiss()
  }

  function toggleEnabled() {
    if (service && typeof service.setEnabled === "function")
      service.setEnabled(!root.enabledNow)
  }

  // Weight entry box plus its validation message, shared by the setup and
  // change-weight cards.
  component WeightField: Column {
    spacing: Style.space(4)

    BorderSurface {
      color: Util.alpha(root.cardForeground, 0.06)
      borderSpec: Border.controlSpec("normal", root.cardForeground, root.waterBlue)
      radius: Style.cornerRadius
      padding: Style.spacing.controlPaddingX
      width: Style.space(96)
      height: Style.space(34)

      Row {
        anchors.centerIn: parent

        Text {
          textFormat: Text.PlainText
          text: root.weightInput + "▌"
          color: root.weightError.length > 0 ? root.errorRed : root.cardForeground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
        }

        Text {
          textFormat: Text.PlainText
          text: " kg"
          color: root.cardForeground
          opacity: 0.4
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
        }
      }
    }

    Text {
      visible: root.weightError.length > 0
      textFormat: Text.PlainText
      text: root.weightError
      color: root.errorRed
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Timer {
    id: hideTimer
    interval: root.autoHideMs
    onTriggered: root.dismiss()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    color: "transparent"
    implicitWidth: card.width
    implicitHeight: card.height
    WlrLayershell.namespace: "omarchy-water"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      right: true
    }

    margins {
      top: (root.shell && root.shell.bar && root.shell.bar.position === "top"
            ? Math.max(0, root.shell.bar.barSize || 0) : 0)
           + Style.gapsOut + Style.space(6)
      right: Style.gapsOut + Style.space(6)
    }

    BorderSurface {
      id: card
      width: card.contentLeftInset
             + Math.max(normalRow.implicitWidth, setupColumn.implicitWidth,
                        settingsColumn.implicitWidth, weightColumn.implicitWidth)
             + card.contentRightInset
      height: card.contentTopInset
              + Math.max(normalRow.implicitHeight, setupColumn.implicitHeight,
                         settingsColumn.implicitHeight, weightColumn.implicitHeight)
              + card.contentBottomInset
      color: root.cardBackground
      borderSpec: root.borderSpec
      radius: Style.cornerRadius
      padding: Style.spacing.panelPadding

      ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation { target: card; property: "scale"; to: 1; duration: 200; easing.type: Easing.OutCubic }
      }

      MouseArea {
        // Swallow clicks so they don't fall through the overlay; the card
        // itself is dismissed by its buttons, Esc, or the auto-hide timer.
        // Hovering pauses the auto-hide so the card never vanishes mid-read.
        anchors.fill: parent
        hoverEnabled: true
        onEntered: hideTimer.stop()
        onExited: if (root.opened && root.mode === "normal") hideTimer.restart()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.mode === "weight") root.setMode("settings")
            else if (root.mode === "settings") root.setMode("normal")
            else root.dismiss()
            event.accepted = true
          } else if (root.mode === "setup" || root.mode === "weight") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (root.submitWeight()) event.accepted = true
            } else if (root.editWeight(event)) {
              event.accepted = true
            }
          } else if (root.mode === "normal") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.markDrunk()
              event.accepted = true
            } else if (event.key === Qt.Key_S) {
              root.snooze()
              event.accepted = true
            }
          }
        }
      }

      // --------------------------------------------------------- normal

      Row {
        id: normalRow
        visible: root.mode === "normal"
        anchors.centerIn: parent
        spacing: root.columnGap

        Item {
          id: stage
          width: root.glassStageWidth
          height: root.glassStageHeight

          Item {
            id: glass
            width: Style.space(52)
            height: Style.space(78)
            anchors.centerIn: parent
            transformOrigin: Item.Center

            Rectangle {
              id: bowl
              anchors.top: parent.top
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(44)
              height: Style.space(50)
              radius: Style.space(8)
              color: "transparent"
              border.width: Math.max(2, Style.space(2))
              border.color: Util.alpha(root.cardForeground, 0.75)
              clip: true

              Rectangle {
                id: water
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - parent.border.width * 2
                height: Math.max(Style.space(2),
                                 (parent.height - parent.border.width * 2) * root.fillRatio)
                color: root.waterBlue

                Behavior on height {
                  NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
                }

                Rectangle {
                  anchors.top: parent.top
                  width: parent.width
                  height: Math.max(2, Style.space(2))
                  color: Util.alpha(Qt.lighter(root.waterBlue, 1.25), 0.9)
                }
              }
            }

            Rectangle {
              id: stem
              anchors.top: bowl.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.max(4, Style.space(4))
              height: Style.space(14)
              color: Util.alpha(root.cardForeground, 0.55)
            }

            Rectangle {
              anchors.top: stem.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(48)
              height: Math.max(3, Style.space(3))
              radius: Math.max(1, Style.space(1))
              color: Util.alpha(root.cardForeground, 0.55)
            }
          }
        }

        Column {
          id: textColumn
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Text {
            id: titleText
            textFormat: Text.PlainText
            text: "Time to drink"
            color: root.cardForeground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            id: amountText
            textFormat: Text.PlainText
            text: "~" + root.ml + " ml"
            color: root.cardForeground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
          }

          Text {
            id: progressText
            textFormat: Text.PlainText
            text: root.drankNow + " / " + root.slots + " glasses today · "
                  + Math.round(root.targetNow / 1000 * 10) / 10 + " L goal"
            color: root.cardForeground
            opacity: 0.72
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            id: progressDots
            spacing: Style.space(4)
            topPadding: Style.space(2)

            Repeater {
              model: root.slots

              Rectangle {
                width: Style.space(6)
                height: Style.space(6)
                radius: width / 2
                color: index < root.drankNow ? root.waterBlue : "transparent"
                border.width: 1
                border.color: index < root.drankNow ? root.waterBlue
                                                    : Util.alpha(root.cardForeground, 0.35)

                Behavior on color {
                  ColorAnimation { duration: 250 }
                }
              }
            }
          }

          Row {
            id: buttonRow
            spacing: Style.space(6)
            topPadding: Style.space(4)

            Button {
              text: "Drank it"
              active: true
              foreground: root.cardForeground
              accent: root.waterBlue
              fontSize: Style.font.bodySmall
              onClicked: root.markDrunk()
            }

            Button {
              text: "Snooze " + root.snoozeMinutes + "m"
              bordered: true
              foreground: root.cardForeground
              fontSize: Style.font.bodySmall
              onClicked: root.snooze()
            }
          }

          Text {
            id: hintText
            textFormat: Text.PlainText
            text: "Enter drank · S snooze · Esc dismiss"
            color: root.cardForeground
            opacity: 0.38
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // Settings gear on the normal card.
      Button {
        visible: root.mode === "normal"
        anchors.top: card.top
        anchors.right: card.right
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        text: "⚙"
        tooltipText: "Settings"
        foreground: root.cardForeground
        onClicked: root.setMode("settings")
      }

      // --------------------------------------------------------- setup

      Column {
        id: setupColumn
        visible: root.mode === "setup"
        anchors.centerIn: parent
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: "Welcome to Water reminder"
          color: root.cardForeground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          text: "How much do you weigh? I'll pour your\n"
                + "eight daily glasses from that."
          color: root.cardForeground
          opacity: 0.8
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        WeightField {}

        Text {
          textFormat: Text.PlainText
          text: "Type your weight and press Enter"
          color: root.cardForeground
          opacity: 0.55
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Button {
            text: "Save"
            active: true
            foreground: root.cardForeground
            accent: root.waterBlue
            onClicked: root.submitWeight()
          }

          Button {
            text: "Use default (75 kg)"
            bordered: true
            foreground: root.cardForeground
            onClicked: root.useDefaultWeight()
          }
        }
      }

      // ------------------------------------------------------- settings

      Column {
        id: settingsColumn
        visible: root.mode === "settings"
        anchors.centerIn: parent
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          text: "Water settings"
          color: root.cardForeground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          text: "Weight: " + root.weightNow + " kg · "
                + Math.round(root.targetNow / 1000 * 10) / 10 + " L per day"
          color: root.cardForeground
          opacity: 0.8
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        Text {
          textFormat: Text.PlainText
          text: "Reminders: " + (root.enabledNow ? "On" : "Off")
          color: root.cardForeground
          opacity: 0.8
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Button {
            width: Style.space(150)
            text: "Change weight"
            bordered: true
            foreground: root.cardForeground
            onClicked: root.setMode("weight")
          }

          Button {
            width: Style.space(150)
            text: root.enabledNow ? "Disable reminders" : "Enable reminders"
            bordered: true
            foreground: root.cardForeground
            onClicked: root.toggleEnabled()
          }

          Button {
            width: Style.space(150)
            text: "Done"
            active: true
            foreground: root.cardForeground
            accent: root.waterBlue
            onClicked: root.setMode("normal")
          }
        }
      }

      // -------------------------------------------------------- weight

      Column {
        id: weightColumn
        visible: root.mode === "weight"
        anchors.centerIn: parent
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: "Change weight"
          color: root.cardForeground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        WeightField {}

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Button {
            text: "Save"
            active: true
            foreground: root.cardForeground
            accent: root.waterBlue
            onClicked: root.submitWeight()
          }

          Button {
            text: "Cancel"
            bordered: true
            foreground: root.cardForeground
            onClicked: root.setMode("settings")
          }
        }
      }
    }
  }

  SequentialAnimation {
    id: shake
    running: root.opened && root.mode === "normal"
    loops: Animation.Infinite

    NumberAnimation { target: glass; property: "rotation"; from: 0; to: -8; duration: 110; easing.type: Easing.InOutQuad }
    NumberAnimation { target: glass; property: "rotation"; from: -8; to: 8; duration: 220; easing.type: Easing.InOutQuad }
    NumberAnimation { target: glass; property: "rotation"; from: 8; to: 0; duration: 110; easing.type: Easing.InOutQuad }
    NumberAnimation { target: glass; property: "y"; from: 0; to: Style.space(5); duration: 130; easing.type: Easing.OutQuad }
    NumberAnimation { target: glass; property: "y"; from: Style.space(5); to: 0; duration: 130; easing.type: Easing.InQuad }
    PauseAnimation { duration: 1600 }
  }
}
