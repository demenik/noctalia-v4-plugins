import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  property var _popupWindow: null
  property bool _xdphMode: false

  IpcHandler {
    id: ipcHandler
    target: "plugin:screencast-picker"

    function showScreensharePicker(): void {
      root.showScreensharePicker("");
    }

    function showScreensharePickerForXdph(xdphWindows: string): void {
      root.showScreensharePicker(xdphWindows);
    }

    signal popupClosed(result: string);
  }

  function showScreensharePicker(xdphWindows) {
    if (!pluginApi) return;
    root._xdphMode = false;
    if (!xdphWindows || xdphWindows === "") {
      xdphWindows = Quickshell.env("XDPH_WINDOW_SHARING_LIST") || "";
    }
    if (xdphWindows !== "")
      root._xdphMode = true;
    pluginApi.withCurrentScreen(function(screen) {
      if (!root._popupWindow) {
        root._popupWindow = popupComponent.createObject(null, {
          "pluginApi": root.pluginApi
        });
      }
      root._popupWindow.xdphMode = root._xdphMode;
      root._popupWindow.screen = screen;
      root._popupWindow.visible = true;
      root._popupWindow.refreshSources(xdphWindows);
    });
  }

  function closePopup(result) {
    if (root._popupWindow) {
      root._popupWindow.visible = false;
    }
    if (root._xdphMode && result !== "cancelled")
      ipcHandler.popupClosed("[SELECTION]/" + result);
    else
      ipcHandler.popupClosed(result);
  }

  Component {
    id: popupComponent

    PanelWindow {
      id: popupWin

      property var pluginApi: null
      property bool xdphMode: false

      property string _activeTab: "screens"
      property var _screensCache: []
      property var _windowsCache: []
      property var _previews: ({})

      visible: false
      color: "transparent"

      anchors { top: true; bottom: true; left: true; right: true }

      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      WlrLayershell.namespace: "noctalia-screencast-picker"

      Process {
        id: cleanupProc
        command: ["rm", "-rf", "/tmp/screencast-picker/"]
      }

      Component.onDestruction: {
        popupWin._previews = ({});
        cleanupProc.exec();
      }

      function parseXdphWindowList(raw) {
        if (!raw) return;
        var entries = raw.split("[HE>]");
        for (var i = 0; i < entries.length; i++) {
          var entry = entries[i].trim();
          if (!entry) continue;
          var parts = entry.split("[HC>]");
          if (parts.length < 2) continue;
          var id = parts[0];
          var haPos = id.indexOf("[HA>]");
          if (haPos >= 0)
            id = id.substring(haPos + 5);
          var titleParts = parts[1].split("[HT>]");
          var cls = titleParts[0];
          var title = titleParts.length > 1 ? titleParts.slice(1).join("[HT>]") : "";
          popupWin._windowsCache.push({
            type: "window",
            sourceId: id,
            label: title || cls,
            subtitle: cls
          });
        }
      }

      function refreshSources(xdphWindows) {
        var screens = [];
        for (var i = 0; i < Quickshell.screens.length; i++) {
          var s = Quickshell.screens[i];
          screens.push({
            type: "screen",
            sourceId: s.name,
            label: s.name,
            subtitle: s.width + "\u00D7" + s.height
          });
        }
        popupWin._screensCache = screens;
        popupWin._windowsCache = [];
        popupWin._previews = ({});
        popupWin._activeTab = "screens";
        popupWin.rebuildModel();
        if (popupWin.xdphMode) {
          popupWin.parseXdphWindowList(xdphWindows);
          popupWin.fetchWindows();
        } else {
          popupWin.fetchWindows();
          popupWin.capturePreviews();
        }
      }

      function rebuildModel() {
        sourcesModel.clear();
        var cache = popupWin._activeTab === "screens"
          ? popupWin._screensCache
          : popupWin._windowsCache;
        for (var i = 0; i < cache.length; i++) {
          sourcesModel.append(cache[i]);
        }
      }

      function fetchWindows() {
        if (CompositorService.isHyprland) {
          winFetchProc.exec({
            command: ["bash", "-c",
              "hyprctl clients -j 2>/dev/null | jq -c '.[] | select(.mapped == true) | {a:.address, t:.title, c:.class, s:.stableId}' 2>/dev/null"
            ]
          });
        } else if (CompositorService.isNiri) {
          winFetchProc.exec({
            command: ["bash", "-c",
              "niri msg --json windows 2>/dev/null | jq -c '.[] | {id, title}' 2>/dev/null"
            ]
          });
        }
      }

      Process {
        id: winFetchProc
        stdout: StdioCollector {}
        onExited: function(code) {
          var raw = String(winFetchProc.stdout.text || "").trim();
          if (!raw) return;
          var lines = raw.split("\n");

          if (popupWin.xdphMode) {
            // Build lookup from hyprctl output: (class, title) -> stableId
            var lookup = {};
            for (var i = 0; i < lines.length; i++) {
              var line = lines[i].trim();
              if (!line || line[0] !== "{") continue;
              try {
                var obj = JSON.parse(line);
                if (obj.c && obj.t && obj.s) {
                  var key = obj.c + "|" + obj.t;
                  if (!lookup[key]) lookup[key] = obj.s;
                }
              } catch (e) {}
            }
            // Match XDPH cache entries by (subtitle, label) = (class, title)
            for (var i = 0; i < popupWin._windowsCache.length; i++) {
              var entry = popupWin._windowsCache[i];
              var key = (entry.subtitle || "") + "|" + (entry.label || "");
              if (lookup[key])
                entry._hyprctlStableId = lookup[key];
            }
            popupWin.capturePreviews();
            return;
          }

          var windows = popupWin._windowsCache.slice();
          for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line || line[0] !== "{") continue;
            try {
              var obj = JSON.parse(line);
              if (CompositorService.isHyprland) {
                if (obj.a && obj.t) {
                  windows.push({
                    type: "window",
                    sourceId: obj.a,
                    label: obj.t,
                    subtitle: obj.c || ""
                  });
                }
              } else if (CompositorService.isNiri) {
                if (obj.title) {
                  windows.push({
                    type: "window",
                    sourceId: String(obj.id),
                    label: obj.title,
                    subtitle: ""
                  });
                }
              }
            } catch (e) {
              Logger.w("ScreencastPicker", "Failed to parse window line:", e);
            }
          }
          popupWin._windowsCache = windows;
          if (popupWin._activeTab === "windows") {
            popupWin.rebuildModel();
          }
        }
      }

      function capturePreviews() {
        if (!CompositorService.isHyprland) return;

        var c = "";
        c += "rm -rf /tmp/screencast-picker 2>/dev/null; mkdir -p /tmp/screencast-picker 2>/dev/null\n";

        for (var i = 0; i < Quickshell.screens.length; i++) {
          var n = Quickshell.screens[i].name;
          c += "grim -o " + n + " /tmp/screencast-picker/" + n + ".png 2>/dev/null; ";
          c += "printf 'screen:%s\\t%s\\n' " + n + " /tmp/screencast-picker/" + n + ".png\n";
        }

        if (popupWin.xdphMode) {
          // Match XDPH window IDs to compositor stableId via (class,title)
          for (var i = 0; i < popupWin._windowsCache.length; i++) {
            var w = popupWin._windowsCache[i];
            if (w._hyprctlStableId) {
              c += "grim -T \"" + w._hyprctlStableId + "\" " +
                "\"/tmp/screencast-picker/" + w.sourceId + ".png\" 2>/dev/null; ";
              c += "printf 'window:%s\\t%s\\n' " + w.sourceId +
                " /tmp/screencast-picker/" + w.sourceId + ".png\n";
            }
          }
        } else {
          c += "hyprctl clients -j 2>/dev/null | jq -r " +
            "'.[] | select(.mapped == true) | \"\\(.address)\\t\\(.stableId)\"' | " +
            "while IFS=$'\\t' read -r addr stableId; do ";
          c += "grim -T \"$stableId\" \"/tmp/screencast-picker/$addr.png\" 2>/dev/null; ";
          c += "printf 'window:%s\\t%s\\n' \"$addr\" \"/tmp/screencast-picker/$addr.png\"; ";
          c += "done\n";
        }

        previewProc.exec({ command: ["bash", "-c", c] });
      }

      Process {
        id: previewProc
        stdout: StdioCollector {}
        onExited: function(code) {
          var raw = String(previewProc.stdout.text || "").trim();
          if (!raw) return;
          var lines = raw.split("\n");
          // Rebuild as a fresh object so QML property change notifications fire.
          var next = Object.assign({}, popupWin._previews);
          for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line) continue;
            var parts = line.split("\t");
            if (parts.length >= 2) {
              next[parts[0]] = "file://" + parts[1];
            }
          }
          popupWin._previews = next;
        }
      }

      ListModel { id: sourcesModel }

      function cancel() {
        if (popupWin.pluginApi?.mainInstance) {
          popupWin.pluginApi.mainInstance.closePopup("cancelled");
        }
      }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        focus: popupWin.visible

        Keys.onEscapePressed: popupWin.cancel()

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          onClicked: popupWin.cancel()
        }

        NBox {
          id: dialogBox
          width: 640 * Style.uiScaleRatio
          height: 520 * Style.uiScaleRatio
          color: Color.mSurface
          radius: Style.radiusL
          border.color: Qt.alpha(Color.mOnSurface, 0.1)

          anchors.centerIn: parent

          // Swallow clicks inside the dialog so the backdrop MouseArea doesn't
          // close it when clicking on non-interactive areas of the card.
          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
          }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NIcon {
                icon: "video"
                pointSize: Style.fontSizeXL
                color: Color.mPrimary
              }

              NText {
                text: popupWin.pluginApi?.tr("popup.title")
                pointSize: Style.fontSizeXL
                font.weight: Style.fontWeightBold
                color: Color.mOnSurface
                Layout.fillWidth: true
                verticalAlignment: Text.AlignVCenter
              }

              NIconButton {
                icon: "close"
                tooltipText: popupWin.pluginApi?.tr("popup.close")
                baseSize: Style.baseWidgetSize * 0.8
                onClicked: popupWin.cancel()
              }
            }

            NText {
              text: popupWin.pluginApi?.tr("popup.selectSource")
              pointSize: Style.fontSizeM
              color: Color.mOnSurfaceVariant
              Layout.fillWidth: true
            }

            Rectangle {
              id: tabBar
              Layout.fillWidth: true
              Layout.preferredHeight: 40 * Style.uiScaleRatio
              radius: Style.radiusM
              color: Color.mSurfaceVariant

              Row {
                anchors.fill: parent
                Repeater {
                  model: ["screens", "windows"]

                  delegate: Item {
                    width: tabBar.width / 2
                    height: tabBar.height

                    Rectangle {
                      anchors {
                        fill: parent
                        margins: 3
                      }
                      radius: Style.radiusS
                      color: popupWin._activeTab === modelData
                        ? (tabMA.containsMouse ? Qt.lighter(Color.mPrimary, 1.08) : Color.mPrimary)
                        : (tabMA.containsMouse ? Color.mHover : "transparent")

                      NText {
                        anchors.centerIn: parent
                        text: popupWin.pluginApi?.tr("popup.tab." + modelData)
                        pointSize: Style.fontSizeM
                        font.weight: popupWin._activeTab === modelData
                          ? Style.fontWeightBold : Font.Normal
                        color: popupWin._activeTab === modelData
                          ? Color.mOnPrimary
                          : (tabMA.containsMouse ? Color.mOnPrimary : Color.mOnSurface)
                      }

                      MouseArea {
                        id: tabMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          popupWin._activeTab = modelData;
                          popupWin.rebuildModel();
                        }
                      }
                    }
                  }
                }
              }
            }

            GridView {
              id: sourcesGrid
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              model: sourcesModel
              cellWidth: 200 * Style.uiScaleRatio
              cellHeight: 160 * Style.uiScaleRatio

              delegate: Item {
                width: sourcesGrid.cellWidth
                height: sourcesGrid.cellHeight

                NBox {
                  anchors {
                    fill: parent
                    margins: 4
                  }
                  color: cellArea.containsMouse
                    ? Qt.alpha(Color.mPrimary, 0.15)
                    : Color.mSurface
                  border.color: cellArea.containsMouse
                    ? Qt.alpha(Color.mPrimary, 0.3)
                    : Qt.alpha(Color.mOnSurface, 0.15)

                  Column {
                    anchors {
                      fill: parent
                      margins: 6
                    }
                    spacing: 4

                    Rectangle {
                      id: previewRect
                      width: parent.width
                      height: parent.width * 9 / 16
                      radius: Style.radiusS
                      color: model.type === "screen"
                        ? Qt.alpha(Color.mPrimary, 0.08)
                        : Qt.alpha(Color.mTertiary, 0.08)
                      clip: true

                      readonly property string _sourceKey: model.type + ":" + model.sourceId
                      readonly property string _previewUrl: popupWin._previews[_sourceKey] || ""

                      Column {
                        anchors.centerIn: parent
                        spacing: 4
                        opacity: 0.35
                        visible: previewRect._previewUrl === ""

                        NIcon {
                          icon: model.type === "screen" ? "camera" : "app-window"
                          pointSize: Style.fontSizeXL
                          color: model.type === "screen" ? Color.mPrimary : Color.mTertiary
                          anchors.horizontalCenter: parent.horizontalCenter
                        }

                        NText {
                          text: model.type === "screen"
                            ? (popupWin.pluginApi?.tr("popup.type.screen"))
                            : (popupWin.pluginApi?.tr("popup.type.window"))
                          pointSize: Style.fontSizeXS
                          color: model.type === "screen" ? Color.mPrimary : Color.mTertiary
                          anchors.horizontalCenter: parent.horizontalCenter
                        }
                      }

                      Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        source: previewRect._previewUrl
                        visible: source !== ""
                        asynchronous: true
                        cache: false
                        smooth: true
                      }
                    }

                    NText {
                      text: model.label
                      width: parent.width
                      pointSize: Style.fontSizeXS
                      font.weight: Style.fontWeightBold
                      color: Color.mOnSurface
                      horizontalAlignment: Text.AlignHCenter
                      elide: Text.ElideRight
                    }

                    NText {
                      text: model.subtitle
                      width: parent.width
                      pointSize: Style.fontSizeXS
                      color: Color.mOnSurfaceVariant
                      horizontalAlignment: Text.AlignHCenter
                      elide: Text.ElideRight
                      visible: model.subtitle !== ""
                    }
                  }

                  MouseArea {
                    id: cellArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (popupWin.pluginApi?.mainInstance) {
                        popupWin.pluginApi.mainInstance.closePopup(model.type + ":" + model.sourceId);
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
