import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true

  readonly property var mainInstance: pluginApi?.mainInstance

  function copyToClipboard(text) {
    var escaped = text.replace(/'/g, "'\\''")
    Quickshell.execDetached(["sh", "-c", "printf '%s' '" + escaped + "' | wl-copy"])
  }

  // Shared state for context menu
  property var selectedPeer: null
  property var selectedPeerDelegate: null
  property var sendTargetPeer: null
  property string searchQuery: ""

  NFilePicker {
    id: sendFilePicker
    title: pluginApi?.tr("file-picker.title")
    selectionMode: "files"
    initialPath: Quickshell.env("HOME") ?? ""
    onAccepted: function(paths) {
      if (!mainInstance || !root.sendTargetPeer || paths.length === 0) return
      // Use Tailscale DNS name (not system HostName) to avoid LAN DNS resolution
      var tsName = mainInstance.tailscaleName(root.sendTargetPeer.DNSName)
      var target = (tsName || root.sendTargetPeer.TailscaleIPs[0]) + ":"
      mainInstance.sendFilesViaTaildrop(paths, target)
    }
  }

  function openPeerContextMenu(peer, delegate, mouseX, mouseY) {
    selectedPeer = peer
    selectedPeerDelegate = delegate
    peerContextMenu.openAtItem(delegate, mouseX, mouseY)
  }

  function filterIPv4(ips) {
    return mainInstance?.filterIPv4(ips) || []
  }

  function normalizeFqdn(fqdn) {
    if (!fqdn) return ""
    return fqdn.endsWith(".") ? fqdn.slice(0, -1) : fqdn
  }

  function peerMatchesSearch(peer, query) {
    var trimmedQuery = (query || "").trim().toLowerCase()
    if (trimmedQuery === "") return true

    var ipv4s = filterIPv4(peer?.TailscaleIPs || []).join(" ")
    var fqdn = normalizeFqdn(peer?.DNSName)
    var tsName = mainInstance ? mainInstance.tailscaleName(peer?.DNSName) : ""
    var searchableText = [
      peer?.HostName || "",
      fqdn,
      tsName,
      ipv4s,
      peer?.OS || ""
    ].join(" ").toLowerCase()

    var tokens = trimmedQuery.split(/\s+/)
    for (var i = 0; i < tokens.length; i++) {
      if (searchableText.indexOf(tokens[i]) === -1) {
        return false
      }
    }
    return true
  }

  function getOSIcon(os) {
    if (!os) return "circle-check"
    switch (os.toLowerCase()) {
      case "linux":
        return "brand-debian"
      case "macos":
        return "brand-apple"
      case "ios":
        return "device-mobile"
      case "android":
        return "device-mobile"
      case "windows":
        return "brand-windows"
      default:
        return "circle-check"
    }
  }



  function requireTerminal() {
    if (!isTerminalConfigured) {
      ToastService.showError(
        pluginApi?.tr("toast.terminal-not-configured.title"),
        pluginApi?.tr("toast.terminal-not-configured.message"),
        "alert-circle"
      )
      return false
    }
    return true
  }

  function copySelectedPeerIp() {
    if (selectedPeer) {
      var ips = filterIPv4(selectedPeer.TailscaleIPs)
      if (ips.length > 0) {
        copyToClipboard(ips[0])
        ToastService.showNotice(
          pluginApi?.tr("toast.ip-copied.title"),
          ips[0],
          "clipboard"
        )
      }
    }
  }

  function copySelectedPeerFqdn() {
    if (selectedPeer) {
      var fqdn = normalizeFqdn(selectedPeer.DNSName)
      if (fqdn) {
        copyToClipboard(fqdn)
        ToastService.showNotice(
          pluginApi?.tr("toast.fqdn-copied.title"),
          fqdn,
          "clipboard"
        )
      }
    }
  }

  function sshToSelectedPeer() {
    if (!requireTerminal()) return
    if (selectedPeer) {
      var ips = filterIPv4(selectedPeer.TailscaleIPs)
      if (ips.length > 0) {
        var target = root.sshUsername.trim() !== "" ? root.sshUsername.trim() + "@" + ips[0] : ips[0]
        Quickshell.execDetached([root.terminalCommand, "-e", "ssh", target])
      }
    }
  }

  function pingSelectedPeer() {
    if (!requireTerminal()) return
    if (selectedPeer) {
      var ips = filterIPv4(selectedPeer.TailscaleIPs)
      if (ips.length > 0) {
        Quickshell.execDetached([root.terminalCommand, "-e", "ping", "-c", root.pingCount.toString(), ips[0]])
      }
    }
  }

  function useExitNode(peer) {
    var ips = filterIPv4(peer.TailscaleIPs)
    if (ips.length > 0 && mainInstance) {
      mainInstance.setExitNode(ips[0])
    }
  }

  function clearExitNode() {
    if (mainInstance) {
      mainInstance.clearExitNode()
    }
  }

  function executePeerAction(action, peer) {
    selectedPeer = peer
    switch (action) {
      case "copy-ip":
        copySelectedPeerIp()
        break
      case "copy-fqdn":
        copySelectedPeerFqdn()
        break
      case "ssh":
        sshToSelectedPeer()
        break
      case "ping":
        pingSelectedPeer()
        break
      case "use-exit-node":
        useExitNode(peer)
        break
    }
  }

  NContextMenu {
    id: peerContextMenu
    model: [
      { 
        label: pluginApi?.tr("context.copy-ip"), 
        action: "copy-ip", 
        icon: "clipboard" 
      },
      {
        label: pluginApi?.tr("context.copy-fqdn"),
        action: "copy-fqdn",
        icon: "world",
        enabled: root.normalizeFqdn(root.selectedPeer?.DNSName) !== ""
      },
      { 
        label: pluginApi?.tr("context.ssh"), 
        action: "ssh", 
        icon: "terminal",
        enabled: (root.selectedPeer?.Online || false) && root.isTerminalConfigured
      },
      { 
        label: pluginApi?.tr("context.ping"), 
        action: "ping", 
        icon: "activity",
        enabled: root.isTerminalConfigured
      },
      {
        label: pluginApi?.tr("context.use-exit-node"),
        action: "use-exit-node",
        icon: "globe",
        visible: (root.selectedPeer?.ExitNodeOption || false) && !(root.selectedPeer?.ExitNode || false) && (root.selectedPeer?.Online || false)
      },
      {
        label: pluginApi?.tr("context.send-file"),
        action: "send-file",
        icon: "file-upload",
        visible: mainInstance?.taildropEnabled ?? true,
        enabled: root.selectedPeer?.Online || false
      }
    ]
    onTriggered: function(action) {
      switch (action) {
        case "copy-ip":
          root.copySelectedPeerIp()
          break
        case "copy-fqdn":
          root.copySelectedPeerFqdn()
          break
        case "ssh":
          root.sshToSelectedPeer()
          break
        case "ping":
          root.pingSelectedPeer()
          break
        case "use-exit-node":
          root.useExitNode(root.selectedPeer)
          break
        case "send-file":
          root.sendTargetPeer = root.selectedPeer
          sendFilePicker.openFilePicker()
          break
      }
    }
  }

  onPluginApiChanged: {
    if (pluginApi && pluginApi.mainInstance) {
      mainInstanceChanged()
    }
  }

  readonly property bool panelReady: pluginApi !== null && mainInstance !== null && mainInstance !== undefined

  readonly property bool hideDisconnected:
    pluginApi?.pluginSettings?.hideDisconnected ??
    pluginApi?.manifest?.metadata?.defaultSettings?.hideDisconnected ??
    false

  readonly property bool hideMullvadExitNodes:
    pluginApi?.pluginSettings?.hideMullvadExitNodes ??
    pluginApi?.manifest?.metadata?.defaultSettings?.hideMullvadExitNodes ??
    true

  readonly property bool showSearchBar:
    pluginApi?.pluginSettings?.showSearchBar ??
    pluginApi?.manifest?.metadata?.defaultSettings?.showSearchBar ??
    false

  readonly property string terminalCommand:
    pluginApi?.pluginSettings?.terminalCommand ||
    pluginApi?.manifest?.metadata?.defaultSettings?.terminalCommand ||
    ""

  readonly property string sshUsername:
    pluginApi?.pluginSettings?.sshUsername ||
    pluginApi?.manifest?.metadata?.defaultSettings?.sshUsername ||
    ""

  readonly property int pingCount:
    pluginApi?.pluginSettings?.pingCount ||
    pluginApi?.manifest?.metadata?.defaultSettings?.pingCount ||
    5

  readonly property string defaultPeerAction:
    pluginApi?.pluginSettings?.defaultPeerAction ||
    pluginApi?.manifest?.metadata?.defaultSettings?.defaultPeerAction ||
    "copy-ip"

  readonly property bool isTerminalConfigured: terminalCommand.trim() !== ""

  readonly property var sortedPeerList: {
    if (!mainInstance?.peerList) return []
    var peers = mainInstance.peerList.slice()
    
    // Filter out disconnected peers if setting is enabled
    if (hideDisconnected) {
      peers = peers.filter(function(peer) {
        return peer.Online === true
      })
    }

    // Filter out Mullvad exit nodes if setting is enabled
    if (hideMullvadExitNodes) {
      peers = peers.filter(function(peer) {
        return !(peer.DNSName || "").endsWith(".mullvad.ts.net.")
      })
    }
    
    peers.sort(function(a, b) {
      // Online peers first
      if (a.Online && !b.Online) return -1
      if (!a.Online && b.Online) return 1
      // Then alphabetically by hostname
      var nameA = (a.HostName || normalizeFqdn(a.DNSName) || "").toLowerCase()
      var nameB = (b.HostName || normalizeFqdn(b.DNSName) || "").toLowerCase()
      return nameA.localeCompare(nameB)
    })
    return peers
  }

  readonly property var filteredPeerList: {
    var query = searchQuery.trim()
    if (!showSearchBar || query === "") return sortedPeerList
    return sortedPeerList.filter(function(peer) {
      return peerMatchesSearch(peer, query)
    })
  }

  readonly property bool searchActive: showSearchBar && searchQuery.trim() !== ""
  readonly property bool searchHasNoResults:
    searchActive &&
    (mainInstance?.tailscaleRunning ?? false) &&
    sortedPeerList.length > 0 &&
    filteredPeerList.length === 0

  property real contentPreferredWidth: panelReady ? 400 * Style.uiScaleRatio : 0
  property real contentPreferredHeight: {
    if (!panelReady) return 0

    // Base height: header, outer margins, outer layout spacing
    var h = (headerLayout.implicitHeight + Style.margin2M)
            + Style.marginL * 2
            + Style.marginM

    // Add This Device box height
    if (thisDeviceBox) {
      h += thisDeviceBox.height + Style.marginM
    }

    // Content box base height: inner padding, peers label
    h += Style.marginM * 2
         + (peersLabel ? peersLabel.implicitHeight : 0) + Style.marginM

    // Add conditional elements inside the content box
    if (comboBox && comboBox.visible) {
      h += comboBox.implicitHeight + Style.marginM
    }
    if (exitNodeWarningBox && exitNodeWarningBox.visible) {
      h += exitNodeWarningBox.height + Style.marginM
    }
    if (terminalWarningBox && terminalWarningBox.visible) {
      h += terminalWarningBox.height + Style.marginM
    }
    if (searchInput && searchInput.visible) {
      h += searchInput.implicitHeight + Style.marginM
    }

    // Add the list area height (which automatically scales with number of peers)
    if (peerListColumn && mainInstance?.tailscaleRunning && sortedPeerList.length > 0) {
      h += peerListColumn.implicitHeight
    } else {
      h += Math.round(100 * Style.uiScaleRatio)
    }

    // Limit to minimum 250px and maximum 750px (scaled with uiScaleRatio)
    return Math.max(250 * Style.uiScaleRatio, Math.min(750 * Style.uiScaleRatio, h))
  }

  anchors.fill: parent

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"
    visible: panelReady

    ColumnLayout {
      id: mainContainer
      anchors {
        fill: parent
        margins: Style.marginL
      }
      spacing: Style.marginM

      NBox {
        id: headerBox
        Layout.fillWidth: true
        Layout.preferredHeight: headerLayout.implicitHeight + Style.margin2M

        RowLayout {
          id: headerLayout
          anchors {
            fill: parent
            margins: Style.marginM
          }
          spacing: Style.marginS

          TailscaleIcon {
            pointSize: Style.fontSizeL
            applyUiScale: true
            connected: mainInstance?.tailscaleRunning ?? false
            connecting: (mainInstance?.isRefreshing ?? false) && !(mainInstance?.tailscaleRunning ?? false)
          }

          NText {
            text: pluginApi?.tr("panel.title")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          // Taildrop receive
          NIconButton {
            icon: "file-download"
            tooltipText: pluginApi?.tr("panel.taildrop.receive")
            baseSize: Style.baseWidgetSize * 0.8
            visible: (mainInstance?.tailscaleRunning ?? false) && (mainInstance?.taildropEnabled ?? true)
            onClicked: {
              if (mainInstance) {
                mainInstance.startTaildropReceive()
                if (pluginApi) pluginApi.closePanel(pluginApi.panelOpenScreen)
              }
            }
          }

          // Admin console
          NIconButton {
            icon: "external-link"
            tooltipText: pluginApi?.tr("panel.admin-console")
            baseSize: Style.baseWidgetSize * 0.8
            visible: mainInstance?.tailscaleRunning ?? false
            onClicked: {
              Qt.openUrlExternally("https://login.tailscale.com/admin")
            }
          }

          // Exit node disable
          NIconButton {
            icon: "globe-off"
            tooltipText: pluginApi?.tr("panel.exit-node.disable")
            baseSize: Style.baseWidgetSize * 0.8
            visible: mainInstance?.exitNodeStatus !== null && mainInstance?.exitNodeStatus !== undefined
            onClicked: root.clearExitNode()
          }

          // Login Button
          NIconButton {
            icon: "login"
            tooltipText: pluginApi?.tr("context.login")
            baseSize: Style.baseWidgetSize * 0.8
            visible: mainInstance?.needsLogin ?? false
            colorFg: Color.mPrimary
            enabled: mainInstance?.tailscaleInstalled ?? false
            onClicked: {
              if (mainInstance) {
                mainInstance.loginTailscale()
              }
            }
          }

          // Connect / Disconnect Button
          NIconButton {
            icon: mainInstance?.tailscaleRunning ? "plug-x" : "plug"
            tooltipText: mainInstance?.tailscaleRunning
              ? pluginApi?.tr("context.disconnect")
              : pluginApi?.tr("context.connect")
            baseSize: Style.baseWidgetSize * 0.8
            visible: !(mainInstance?.needsLogin ?? false)
            colorFg: mainInstance?.tailscaleRunning ? Color.mError : Color.mPrimary
            enabled: mainInstance?.tailscaleInstalled ?? false
            onClicked: {
              if (mainInstance) {
                mainInstance.toggleTailscale()
              }
            }
          }

          // Close button
          NIconButton {
            icon: "close"
            tooltipText: pluginApi?.tr("panel.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              if (pluginApi) {
                pluginApi.closePanel(pluginApi.panelOpenScreen)
              }
            }
          }
        }
      }

      NBox {
        id: thisDeviceBox
        Layout.fillWidth: true
        Layout.preferredHeight: thisDeviceLayout.implicitHeight + Style.margin2M
        forceOpaque: true

        ColumnLayout {
          id: thisDeviceLayout
          anchors {
            fill: parent
            margins: Style.marginM
          }
          spacing: Style.marginS

          NLabel {
            id: thisDeviceLabel
            label: pluginApi?.tr("panel.this-device")
            Layout.fillWidth: true
            Layout.leftMargin: Style.marginXS
          }

          RowLayout {
            id: thisDeviceRow
            Layout.fillWidth: true
            spacing: Style.marginM
            opacity: mainInstance?.tailscaleRunning ? 1.0 : 0.65

            NIcon {
              icon: mainInstance?.selfNode ? root.getOSIcon(mainInstance.selfNode.OS) : "device-laptop"
              pointSize: Style.fontSizeXXL
              color: mainInstance?.tailscaleRunning ? Color.mPrimary : Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
              spacing: 2
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter

              NText {
                text: mainInstance?.selfNode ? mainInstance.selfNode.HostName : "Local Host"
                color: mainInstance?.tailscaleRunning ? Color.mOnSurface : Color.mOnSurfaceVariant
                font.weight: Style.fontWeightBold
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              NText {
                text: mainInstance?.selfNode 
                  ? root.normalizeFqdn(mainInstance.selfNode.DNSName) 
                  : (mainInstance?.needsLogin ? pluginApi?.tr("panel.not-authenticated") : pluginApi?.tr("panel.not-connected"))
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }

            ColumnLayout {
              spacing: 4
              Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

              // IP Address (clickable to copy)
              RowLayout {
                id: thisDeviceIpContainer
                spacing: Style.marginXS
                visible: mainInstance?.tailscaleRunning && mainInstance?.tailscaleIp !== ""
                Layout.alignment: Qt.AlignRight

                NText {
                  text: mainInstance?.tailscaleIp || ""
                  pointSize: Style.fontSizeS
                  font.family: Settings.data.ui.fontFixed
                  color: thisDeviceIpMouseArea.containsMouse ? Color.mPrimary : Color.mOnSurfaceVariant
                }

                NIcon {
                  icon: "copy"
                  pointSize: Style.fontSizeXS
                  color: thisDeviceIpMouseArea.containsMouse ? Color.mPrimary : Qt.alpha(Color.mOnSurfaceVariant, 0.5)
                }

                MouseArea {
                  id: thisDeviceIpMouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (mainInstance?.tailscaleIp) {
                      root.copyToClipboard(mainInstance.tailscaleIp)
                      ToastService.showNotice(
                        pluginApi?.tr("toast.ip-copied.title"),
                        mainInstance.tailscaleIp,
                        "clipboard"
                      )
                    }
                  }
                }
              }

              // Connection Status Pill
              NBox {
                Layout.alignment: Qt.AlignRight
                Layout.preferredWidth: statusLabel.implicitWidth + Style.marginS * 2
                Layout.preferredHeight: statusLabel.implicitHeight + Style.marginXS * 2
                color: mainInstance?.tailscaleRunning 
                  ? Qt.alpha(Color.mPrimary, 0.15) 
                  : Qt.alpha(Color.mOnSurface, 0.08)
                border.width: 1
                border.color: mainInstance?.tailscaleRunning 
                  ? Qt.alpha(Color.mPrimary, 0.3) 
                  : Qt.alpha(Color.mOnSurface, 0.15)

                NText {
                  id: statusLabel
                  anchors.centerIn: parent
                  text: mainInstance?.tailscaleRunning ? pluginApi?.tr("panel.status-connected") : pluginApi?.tr("panel.status-offline")
                  pointSize: Style.fontSizeXXS
                  font.weight: Style.fontWeightMedium
                  color: mainInstance?.tailscaleRunning ? Color.mPrimary : Color.mOnSurfaceVariant
                }
              }
            }
          }
        }
      }

      NBox {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM
          clip: true

          NLabel {
            id: peersLabel
            label: pluginApi?.tr("panel.peers-title")
            Layout.fillWidth: true
            Layout.leftMargin: Style.marginS
          }

          NComboBox {
            id: comboBox
            Layout.fillWidth: true
            visible: (mainInstance?.accounts?.length ?? 0) >= 2
            model: (mainInstance?.accounts || []).map(function (a) {
              return { key: a.id, name: a.tailnet || a.account || a.nickname || a.id }
            })
            currentKey: mainInstance?.currentAccountId || ""
            onSelected: function (key) {
              if (mainInstance) {
                mainInstance.switchAccount(key)
              }
            }
            Component.onCompleted: comboBox.Layout.fillWidth = true
          }

          // Exit node status
          Rectangle {
            id: exitNodeWarningBox
            Layout.fillWidth: true
            Layout.preferredHeight: exitNodeLayout.implicitHeight + Style.marginS * 2
            visible: mainInstance?.exitNodeStatus !== null && mainInstance?.exitNodeStatus !== undefined
            color: Qt.alpha(Color.mPrimary, 0.1)
            radius: Style.radiusS
            border.width: 1
            border.color: Qt.alpha(Color.mPrimary, 0.3)

            RowLayout {
              id: exitNodeLayout
              anchors.fill: parent
              anchors.margins: Style.marginS
              spacing: Style.marginS

              NIcon {
                icon: "globe"
                pointSize: Style.fontSizeS
                color: mainInstance?.exitNodeStatus?.Online ? Color.mPrimary : Color.mOnSurfaceVariant
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                NText {
                  text: pluginApi?.tr("panel.exit-node.active")
                  pointSize: Style.fontSizeXS
                  font.weight: Style.fontWeightMedium
                  color: Color.mPrimary
                }

                NText {
                  Layout.fillWidth: true
                  text: {
                    if (!mainInstance?.exitNodeStatus) return ""
                    var ipv4 = filterIPv4(mainInstance.exitNodeStatus.TailscaleIPs)[0]
                    var status = mainInstance.exitNodeStatus.Online ? pluginApi?.tr("panel.exit-node.online") : pluginApi?.tr("panel.exit-node.offline")
                    return ipv4 ? ipv4 + " • " + status : status
                  }
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                  font.family: Settings.data.ui.fontFixed
                  wrapMode: Text.Wrap
                }
              }
            }
          }

          // Warning banner for missing terminal configuration
          Rectangle {
            id: terminalWarningBox
            Layout.fillWidth: true
            Layout.preferredHeight: terminalWarningLayout.implicitHeight + Style.marginM * 2
            visible: !root.isTerminalConfigured
            color: Qt.alpha(Color.mError, 0.1)
            radius: Style.radiusM
            border.width: 1
            border.color: Qt.alpha(Color.mError, 0.3)

            RowLayout {
              id: terminalWarningLayout
              anchors.fill: parent
              anchors.margins: Style.marginM
              spacing: Style.marginS

              NIcon {
                icon: "alert-circle"
                pointSize: Style.fontSizeM
                color: Color.mError
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS

                NText {
                  text: pluginApi?.tr("panel.terminal-warning.title")
                  pointSize: Style.fontSizeS
                  font.weight: Style.fontWeightMedium
                  color: Color.mError
                }

                NText {
                  Layout.fillWidth: true
                  text: pluginApi?.tr("panel.terminal-warning.message")
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                  wrapMode: Text.Wrap
                }
              }
            }
          }

          NTextInput {
            id: searchInput
            Layout.fillWidth: true
            visible: root.showSearchBar && (root.mainInstance?.tailscaleRunning ?? false) && root.sortedPeerList.length > 0
            placeholderText: root.pluginApi?.tr("panel.search-placeholder")
            inputIconName: "search"
            text: root.searchQuery
            onTextChanged: root.searchQuery = searchInput.text

            Keys.onEscapePressed: {
              if (searchInput.text !== "") {
                searchInput.text = ""
              }
            }
          }

          Flickable {
            id: peerFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: (mainInstance?.tailscaleRunning ?? false) && root.sortedPeerList.length > 0 && !root.searchHasNoResults
            clip: true
            contentWidth: width
            contentHeight: peerListColumn.implicitHeight
            interactive: contentHeight > height + 4
            boundsBehavior: Flickable.StopAtBounds
            pressDelay: 0
            enabled: !(mainInstance?.accountSwitchInProgress ?? false)
            opacity: enabled ? 1.0 : 0.4

            Behavior on opacity {
              NumberAnimation { duration: Style.animationFast }
            }

            ColumnLayout {
              id: peerListColumn
              width: peerFlickable.width
              spacing: Style.marginM

              Repeater {
                model: root.filteredPeerList

                delegate: ItemDelegate {
                  id: peerDelegate
                  Layout.fillWidth: true
                  Layout.preferredWidth: peerFlickable.width
                  Layout.leftMargin: Style.marginXS
                  Layout.rightMargin: Style.marginXS
                  implicitWidth: peerFlickable.width
                  implicitHeight: Math.round(50 * Style.uiScaleRatio)
                  topPadding: Style.marginM
                  bottomPadding: Style.marginM
                  leftPadding: Style.marginM
                  rightPadding: Style.marginM

                  MouseArea {
                    anchors {
                      left: parent.left
                      top: parent.top
                      bottom: parent.bottom
                      right: peerIpContainer.visible ? peerIpContainer.left : parent.right
                    }
                    acceptedButtons: Qt.NoButton
                    cursorShape: (peerDelegate.peerIp && root.defaultPeerAction !== "copy-ip") ? Qt.PointingHandCursor : Qt.ArrowCursor
                  }

                  readonly property var peerData: modelData
                  readonly property string peerIp: filterIPv4(peerData.TailscaleIPs)[0] || ""
                  readonly property string peerHostname: peerData.HostName || normalizeFqdn(peerData.DNSName) || "Unknown"
                  readonly property string peerTsName: mainInstance ? mainInstance.tailscaleName(peerData.DNSName) : ""
                  readonly property bool peerOnline: peerData.Online || false

                  background: NBox {
                    anchors.fill: parent
                    color: peerDelegate.peerData.IsSelf
                      ? (peerDelegate.hovered ? Qt.alpha(Color.mPrimary, 0.35) : Qt.alpha(Color.mPrimary, 0.25))
                      : (peerDelegate.peerOnline 
                        ? (peerDelegate.hovered ? Qt.alpha(Color.mPrimary, 0.25) : Qt.alpha(Color.mPrimary, 0.15)) 
                        : (peerDelegate.hovered ? Qt.alpha(Color.mOnSurface, 0.08) : Color.mSurface))
                    forceOpaque: true
                  }

                  contentItem: RowLayout {
                    spacing: Style.marginM

                    NIcon {
                      icon: root.getOSIcon(peerDelegate.peerData.OS)
                      pointSize: Style.fontSizeXXL
                      color: peerDelegate.peerOnline ? Color.mPrimary : Color.mOnSurfaceVariant
                      Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                      spacing: 0
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignVCenter

                      NText {
                        text: peerDelegate.peerHostname + (peerDelegate.peerData.IsSelf ? " (" + (pluginApi?.tr("panel.self") || "you") + ")" : "")
                        color: peerDelegate.peerData.IsSelf ? Color.mPrimary : Color.mOnSurface
                        font.weight: Style.fontWeightMedium
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                      }

                      NText {
                        text: peerDelegate.peerTsName
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurfaceVariant
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: peerDelegate.peerTsName !== "" && peerDelegate.peerTsName !== peerDelegate.peerHostname
                      }
                    }

                    NIcon {
                      icon: "globe"
                      pointSize: Style.fontSizeL
                      color: peerDelegate.peerData.ExitNode ? Color.mPrimary : Qt.alpha(Color.mOnSurfaceVariant, 0.4)
                      visible: peerDelegate.peerData.ExitNode || peerDelegate.peerData.ExitNodeOption
                      Layout.alignment: Qt.AlignRight
                    }

                    RowLayout {
                      id: peerIpContainer
                      spacing: Style.marginXS
                      visible: peerDelegate.peerIp !== ""
                      Layout.alignment: Qt.AlignRight

                      NText {
                        text: peerDelegate.peerIp
                        pointSize: Style.fontSizeS
                        font.family: Settings.data.ui.fontFixed
                        color: peerIpMouseArea.containsMouse ? Color.mPrimary : Color.mOnSurfaceVariant
                      }

                      NIcon {
                        icon: "copy"
                        pointSize: Style.fontSizeXS
                        color: peerIpMouseArea.containsMouse ? Color.mPrimary : Qt.alpha(Color.mOnSurfaceVariant, 0.5)
                      }

                      MouseArea {
                        id: peerIpMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.copyToClipboard(peerDelegate.peerIp)
                          ToastService.showNotice(
                            pluginApi?.tr("toast.ip-copied.title"),
                            peerDelegate.peerIp,
                            "clipboard"
                          )
                        }
                      }
                    }
                  }

                  onClicked: {
                    if (peerDelegate.peerIp && root.defaultPeerAction !== "copy-ip") {
                      root.executePeerAction(root.defaultPeerAction, peerDelegate.peerData)
                    }
                  }

                  TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: root.openPeerContextMenu(peerDelegate.peerData, peerDelegate, point.position.x, point.position.y)
                  }
                }
              }
            }
          }

          // Centered empty state container
          Item {
            id: emptyStateContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !(mainInstance?.tailscaleRunning ?? false) || root.sortedPeerList.length === 0 || root.searchHasNoResults

            NText {
              id: noPeersLabel
              anchors.centerIn: parent
              width: parent.width - Style.margin2XL
              text: root.searchHasNoResults ? root.pluginApi?.tr("panel.no-search-results") : root.pluginApi?.tr("panel.no-peers")
              pointSize: Style.fontSizeM
              color: Color.mOnSurfaceVariant
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
            }
          }
        }
      }
    }
  }
}
