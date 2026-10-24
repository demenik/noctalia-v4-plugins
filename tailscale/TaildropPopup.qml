import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Widgets

// Floating Taildrop transfer card, positioned like Noctalia toasts.
PanelWindow {
  id: root

  property var mainInstance: null
  property var pluginApi: null

  readonly property string transferState: mainInstance?.taildropState ?? "idle"
  readonly property var files: mainInstance?.taildropFiles ?? []
  readonly property var savedFiles: mainInstance?.taildropSavedFiles ?? []
  readonly property real totalBytes: mainInstance?.taildropTotalBytes ?? 0
  readonly property real transferredBytes: mainInstance?.taildropTransferredBytes ?? 0
  readonly property bool inProgress: transferState === "receiving" || transferState === "sending"
  readonly property bool isBusy: transferState === "saving" || transferState === "discarding"
  readonly property real progress: totalBytes > 0 ? Math.min(1, transferredBytes / totalBytes) : 0

  // --- Placement (mirrors Modules/Toast/ToastScreen.qml) ---

  readonly property string location: Settings.data.notifications?.location || "top_right"
  readonly property bool isTop: location.startsWith("top")
  readonly property bool isBottom: location.startsWith("bottom")
  readonly property bool isLeft: location.endsWith("_left")
  readonly property bool isRight: location.endsWith("_right")

  readonly property bool isFramed: Settings.data.bar.barType === "framed"
  readonly property bool isFloating: Settings.data.bar.barType === "floating"
  readonly property real frameThickness: Settings.data.bar.frameThickness ?? 8
  readonly property string barPos: Settings.getBarPositionForScreen(screen?.name)
  readonly property real barHeight: Style.getBarHeightForScreen(screen?.name)

  function barOffset(edge) {
    if (barPos !== edge)
      return isFramed ? frameThickness : 0;
    var vertical = edge === "top" || edge === "bottom";
    var floatMargin = isFloating ? Math.ceil(vertical ? Settings.data.bar.marginVertical : Settings.data.bar.marginHorizontal) : 0;
    return barHeight + floatMargin;
  }

  readonly property int shadowPadding: Style.shadowBlurMax + Style.marginL
  readonly property int cardWidth: Math.round(380 * Style.uiScaleRatio)

  anchors.top: isTop
  anchors.bottom: isBottom
  anchors.left: isLeft
  anchors.right: isRight

  margins.top: isTop ? barOffset("top") - shadowPadding + Style.marginM : 0
  margins.bottom: isBottom ? barOffset("bottom") - shadowPadding + Style.marginM : 0
  margins.left: isLeft ? barOffset("left") - shadowPadding + Style.marginM : 0
  margins.right: isRight ? barOffset("right") - shadowPadding + Style.marginM : 0

  implicitWidth: cardWidth + shadowPadding * 2
  implicitHeight: Math.round(contentLayout.implicitHeight + Style.marginL * 2 + shadowPadding * 2)

  color: "transparent"

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "noctalia-taildrop-" + (screen?.name || "unknown")
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.exclusionMode: ExclusionMode.Ignore

  // Only the card itself takes input; the shadow area is click-through
  mask: Region {
    item: card
  }

  // --- Helpers ---

  function formatBytes(bytes) {
    if (bytes < 1024)
      return Math.round(bytes) + " B";
    var units = ["KB", "MB", "GB", "TB"];
    var value = bytes;
    var i = -1;
    do {
      value /= 1024;
      i++;
    } while (value >= 1024 && i < units.length - 1);
    return value.toFixed(value >= 100 ? 0 : 1) + " " + units[i];
  }

  function filesSummary(list) {
    if (list.length === 0)
      return pluginApi?.tr("taildrop.popup.unknown-files");
    if (list.length === 1)
      return typeof list[0] === "string" ? list[0] : list[0].name;
    return pluginApi?.trp("taildrop.popup.file-count", list.length);
  }

  readonly property string title: {
    var peer = mainInstance?.taildropPeerName || "";
    switch (transferState) {
    case "receiving":
      return pluginApi?.tr("taildrop.popup.receiving");
    case "incoming":
      return pluginApi?.tr("taildrop.popup.incoming");
    case "saving":
      return pluginApi?.tr("taildrop.popup.saving");
    case "discarding":
      return pluginApi?.tr("taildrop.popup.discarding");
    case "received":
      return pluginApi?.tr("taildrop.popup.received");
    case "sending":
      return pluginApi?.tr("taildrop.popup.sending", { "peer": peer });
    case "sent":
      return pluginApi?.tr("taildrop.popup.sent", { "peer": peer });
    case "error":
      return pluginApi?.tr("taildrop.popup.failed");
    }
    return "";
  }

  readonly property string subtitle: {
    if (transferState === "received")
      return pluginApi?.tr("taildrop.popup.saved-to", {
                             "files": filesSummary(savedFiles),
                             "dir": mainInstance?.taildropDownloadDirSetting || ""
                           });
    if (transferState === "error")
      return mainInstance?.taildropMessage || "";
    var summary = filesSummary(files);
    if (transferState === "incoming" && totalBytes > 0)
      summary += " - " + formatBytes(totalBytes);
    return summary;
  }

  readonly property string stateIcon: {
    switch (transferState) {
    case "sending":
      return "file-upload";
    case "received":
    case "sent":
      return "circle-check";
    case "error":
      return "alert-circle";
    }
    return "file-download";
  }

  readonly property color accentColor: transferState === "error" ? Color.mError : Color.mPrimary

  // --- Card ---

  NBox {
    id: card
    anchors.fill: parent
    anchors.margins: root.shadowPadding
    radius: Style.radiusL
    color: Color.mSurface
    border.width: Style.borderS
    border.color: root.transferState === "error" ? Color.mError : Color.mOutline
    forceOpaque: true

    opacity: 0
    scale: 0.9
    Component.onCompleted: {
      opacity = 1;
      scale = 1;
    }
    Behavior on opacity {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutCubic
      }
    }
    Behavior on scale {
      NumberAnimation {
        duration: Style.animationNormal
        easing.type: Easing.OutBack
      }
    }

    ColumnLayout {
      id: contentLayout
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NBox {
          Layout.preferredWidth: Math.round(44 * Style.uiScaleRatio)
          Layout.preferredHeight: Layout.preferredWidth
          Layout.alignment: Qt.AlignTop
          radius: width / 2
          color: Qt.alpha(root.accentColor, 0.15)

          NIcon {
            anchors.centerIn: parent
            icon: root.stateIcon
            pointSize: Style.fontSizeXL
            color: root.accentColor
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          spacing: 2

          NText {
            Layout.fillWidth: true
            text: root.title
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            elide: Text.ElideRight
          }

          NText {
            Layout.fillWidth: true
            text: root.subtitle
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            wrapMode: root.transferState === "error" ? Text.Wrap : Text.NoWrap
            maximumLineCount: 4
            elide: Text.ElideRight
          }
        }

        NIconButton {
          Layout.alignment: Qt.AlignTop
          icon: "close"
          tooltipText: root.inProgress ? pluginApi?.tr("taildrop.popup.hide") : pluginApi?.tr("panel.close")
          baseSize: Style.baseWidgetSize * 0.7
          onClicked: mainInstance?.dismissTaildropPopup()
        }
      }

      // Progress
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS
        visible: root.inProgress || root.transferState === "sent"

        NLinearGauge {
          Layout.fillWidth: true
          Layout.preferredHeight: Math.round(6 * Style.uiScaleRatio)
          orientation: Qt.Horizontal
          ratio: root.transferState === "sent" ? 1 : root.progress

          Behavior on ratio {
            NumberAnimation {
              duration: Style.animationNormal
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true

          NText {
            Layout.fillWidth: true
            text: root.totalBytes > 0 ? root.formatBytes(root.transferredBytes) + " / " + root.formatBytes(root.totalBytes) : pluginApi?.tr("taildrop.popup.waiting")
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }

          NText {
            text: Math.round((root.transferState === "sent" ? 1 : root.progress) * 100) + "%"
            pointSize: Style.fontSizeXS
            font.weight: Style.fontWeightMedium
            color: Color.mPrimary
            visible: root.totalBytes > 0
          }
        }
      }

      // Actions
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        visible: !root.isBusy && root.transferState !== "receiving"

        Item {
          Layout.fillWidth: true
        }

        NButton {
          visible: root.transferState === "incoming"
          text: pluginApi?.tr("taildrop.popup.decline")
          icon: "trash"
          outlined: true
          onClicked: mainInstance?.discardIncomingFiles()
        }

        NButton {
          visible: root.transferState === "incoming"
          text: pluginApi?.tr("taildrop.popup.save")
          icon: "download"
          onClicked: mainInstance?.saveIncomingFiles()
        }

        NButton {
          visible: root.transferState === "received"
          text: pluginApi?.tr("taildrop.popup.open-folder")
          icon: "folder-open"
          outlined: true
          onClicked: {
            mainInstance?.openTaildropDownloadDir();
            mainInstance?.dismissTaildropPopup();
          }
        }

        NButton {
          visible: root.transferState === "received" && root.savedFiles.length === 1
          text: pluginApi?.tr("taildrop.popup.open")
          icon: "external-link"
          onClicked: {
            mainInstance?.openTaildropSavedFile(root.savedFiles[0]);
            mainInstance?.dismissTaildropPopup();
          }
        }

        NButton {
          visible: root.transferState === "sending"
          text: pluginApi?.tr("taildrop.popup.cancel")
          icon: "x"
          outlined: true
          onClicked: mainInstance?.cancelTaildropSend()
        }

        NButton {
          visible: root.transferState === "sent" || root.transferState === "error" || (root.transferState === "received" && root.savedFiles.length !== 1)
          text: pluginApi?.tr("taildrop.popup.done")
          onClicked: mainInstance?.dismissTaildropPopup()
        }
      }

      NBusyIndicator {
        Layout.alignment: Qt.AlignHCenter
        visible: root.isBusy
        running: visible
        size: Math.round(Style.baseWidgetSize * 0.7)
      }
    }
  }

  NDropShadow {
    anchors.fill: card
    source: card
    autoPaddingEnabled: true
  }
}
