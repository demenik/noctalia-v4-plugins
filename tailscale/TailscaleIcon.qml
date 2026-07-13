import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: root

  property real pointSize: Style.fontSizeL
  property bool applyUiScale: true
  property bool connected: false
  property bool connecting: false
  property bool hovered: false
  property color litColor: {
    if (hovered) return Color.mOnHover;
    if (connected) return Color.mPrimary;
    return Color.mOnSurface;
  }
  property color dimColor: hovered ? Color.mOnHover : Color.mOnSurface
  property real dimOpacity: 0.38

  readonly property real iconSize: Math.max(1, applyUiScale ? root.pointSize * Style.uiScaleRatio : root.pointSize)
  readonly property real dotSize: Math.max(3, iconSize * 0.22)
  readonly property real dotGap: Math.max(2, iconSize * 0.17)
  readonly property int activeConnectingDot: connecting ? connectingFrame % 9 : -1

  property int connectingFrame: 0

  implicitWidth: iconSize
  implicitHeight: iconSize

  Timer {
    interval: 420
    running: root.connecting && !root.connected
    repeat: true
    onTriggered: root.connectingFrame = (root.connectingFrame + 5) % 9
  }

  GridLayout {
    anchors.centerIn: parent
    columns: 3
    rowSpacing: root.dotGap
    columnSpacing: root.dotGap

    Repeater {
      model: 9

      Rectangle {
        required property int index

        readonly property bool isConnectingLit: root.connecting && !root.connected && (
          index === root.activeConnectingDot
          || index === (root.activeConnectingDot + 4) % 9
          || index === (root.activeConnectingDot + 7) % 9
        )
        readonly property bool isStaticLit: !root.connecting && (index === 3 || index === 4 || index === 5 || index === 7)
        readonly property bool lit: isConnectingLit || isStaticLit

        Layout.preferredWidth: root.dotSize
        Layout.preferredHeight: root.dotSize
        radius: width / 2
        color: lit ? root.litColor : root.dimColor
        opacity: lit ? 1.0 : root.dimOpacity
        scale: isConnectingLit ? 1.18 : 1.0

        Behavior on opacity {
          NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
          NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
      }
    }
  }
}
