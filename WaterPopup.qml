import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string slotLabel: "preview"
  property int ml: 310

  readonly property int autoHideMs: 12000

  readonly property color cardBackground: Util.alpha(Color.popups.background, 0.97)
  readonly property color cardForeground: Color.popups.text
  // Themes define no blue role, so the water is a fixed blue that reads well
  // against any popup background.
  readonly property color waterBlue: "#6cb2f2"
  readonly property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  readonly property int glassStageWidth: Style.space(64)
  readonly property int glassStageHeight: Style.space(88)
  readonly property int columnGap: Style.space(14)

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    slotLabel = payload.slot !== undefined ? String(payload.slot) : "preview"
    ml = isFinite(Number(payload.ml)) ? Math.round(Number(payload.ml)) : 310
    opened = true
    hideTimer.restart()
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

  Timer {
    id: hideTimer
    interval: root.autoHideMs
    onTriggered: root.dismiss()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    color: "transparent"
    width: card.width
    height: card.height
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
      width: card.contentLeftInset + root.glassStageWidth + root.columnGap
             + Math.max(titleText.implicitWidth, amountText.implicitWidth)
             + card.contentRightInset
      height: card.contentTopInset + root.glassStageHeight + card.contentBottomInset
      color: root.cardBackground
      borderSpec: root.borderSpec
      radius: Style.cornerRadius
      padding: Style.spacing.panelPadding

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          }
        }
      }

      Row {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
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
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - parent.border.width * 2
                height: parent.height * 0.68 - parent.border.width
                color: root.waterBlue

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
        }
      }
    }
  }

  SequentialAnimation {
    id: shake
    running: root.opened
    loops: Animation.Infinite

    NumberAnimation { target: glass; property: "rotation"; from: 0; to: -8; duration: 110; easing.type: Easing.InOutQuad }
    NumberAnimation { target: glass; property: "rotation"; from: -8; to: 8; duration: 220; easing.type: Easing.InOutQuad }
    NumberAnimation { target: glass; property: "rotation"; from: 8; to: 0; duration: 110; easing.type: Easing.InOutQuad }
    NumberAnimation { target: glass; property: "y"; from: 0; to: Style.space(5); duration: 130; easing.type: Easing.OutQuad }
    NumberAnimation { target: glass; property: "y"; from: Style.space(5); to: 0; duration: 130; easing.type: Easing.InQuad }
    PauseAnimation { duration: 1600 }
  }
}
