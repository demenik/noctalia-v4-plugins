import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen

    readonly property var geometryPlaceholder: container
    readonly property bool allowAttach: true

    readonly property var main: pluginApi?.mainInstance ?? null
    readonly property string vpnStatus: main?.vpnStatus ?? "unknown"
    readonly property bool connected: vpnStatus === "connected"
    readonly property bool acting: main?.isActing ?? false

    property real contentPreferredWidth:  Math.round(360 * Style.uiScaleRatio)
    property real contentPreferredHeight: Math.round(mainCol.implicitHeight + Style.marginL * 2)

    Component.onCompleted: { if (main) main.refresh(); }

    Rectangle {
        id: container
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            // ── Header ───────────────────────────────────────────────────────
            NBox {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(headerRow.implicitHeight + Style.marginM * 2)

                RowLayout {
                    id: headerRow
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginM

                    NIcon {
                        icon: root.connected ? "shield-lock" : "shield"
                        pointSize: Style.fontSizeXL
                        color: root.connected ? Color.mPrimary : Color.mOnSurfaceVariant
                    }

                    NLabel {
                        label: "ProtonVPN"
                        Layout.fillWidth: true
                    }

                    NIconButton {
                        icon: "refresh"
                        tooltipText: "Refresh"
                        baseSize: Style.baseWidgetSize * 0.8
                        enabled: !root.acting
                        onClicked: main?.refresh()
                    }

                    NIconButton {
                        icon: "close"
                        tooltipText: "Close"
                        baseSize: Style.baseWidgetSize * 0.8
                        onClicked: pluginApi.closePanel(pluginApi.panelOpenScreen)
                    }
                }
            }

            // ── Status card ──────────────────────────────────────────────────
            NBox {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(statusCol.implicitHeight + Style.marginM * 2)

                ColumnLayout {
                    id: statusCol
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginS

                    RowLayout {
                        spacing: Style.marginS

                        Rectangle {
                            width: Math.round(8 * Style.uiScaleRatio)
                            height: width
                            radius: width / 2
                            color: {
                                if (root.acting)    return Color.mTertiary;
                                if (root.connected) return Color.mPrimary;
                                if (root.vpnStatus === "disconnected") return Color.mError;
                                return Color.mOnSurfaceVariant;
                            }
                        }

                        NLabel {
                            label: {
                                if (root.acting)    return "Working…";
                                if (root.connected) return "Connected";
                                if (root.vpnStatus === "disconnected") return "Disconnected";
                                return "Unknown";
                            }
                            labelColor: {
                                if (root.acting)    return Color.mTertiary;
                                if (root.connected) return Color.mPrimary;
                                if (root.vpnStatus === "disconnected") return Color.mError;
                                return Color.mOnSurfaceVariant;
                            }
                        }

                        NLabel {
                            visible: root.connected && (main?.protocol ?? "") !== ""
                            label: (main?.protocol ?? "").toUpperCase()
                            labelColor: Color.mOnSurfaceVariant
                            Layout.fillWidth: true
                        }
                    }

                    // Server name + location
                    NLabel {
                        visible: root.connected && (main?.serverName ?? "") !== ""
                        label: (main?.serverName ?? "") +
                               ((main?.serverLocation ?? "") !== "" ? "  ·  " + main.serverLocation : "")
                        labelColor: Color.mOnSurface
                        Layout.fillWidth: true
                    }

                    // Load bar
                    RowLayout {
                        visible: root.connected && (main?.serverLoad ?? -1) >= 0
                        spacing: Style.marginS

                        NLabel {
                            label: "Load"
                            labelColor: Color.mOnSurfaceVariant
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: Math.round(4 * Style.uiScaleRatio)
                            radius: height / 2
                            color: Color.mSurfaceVariant

                            Rectangle {
                                width: parent.width * Math.min(1, Math.max(0, (main?.serverLoad ?? 0) / 100))
                                height: parent.height
                                radius: parent.radius
                                color: (main?.serverLoad ?? 0) > 80 ? Color.mError
                                     : (main?.serverLoad ?? 0) > 50 ? Color.mTertiary
                                     : Color.mPrimary
                                Behavior on width { NumberAnimation { duration: 300 } }
                            }
                        }

                        NLabel {
                            label: (main?.serverLoad ?? 0) + "%"
                            labelColor: Color.mOnSurfaceVariant
                        }
                    }

                    // Error message
                    NLabel {
                        visible: (main?.lastError ?? "") !== ""
                        label: main?.lastError ?? ""
                        labelColor: Color.mError
                        Layout.fillWidth: true
                    }
                }
            }

            // ── Primary action ───────────────────────────────────────────────
            NButton {
                Layout.fillWidth: true
                text: root.connected ? "Disconnect" : "Connect Fastest"
                enabled: !root.acting && root.vpnStatus !== "unknown"
                onClicked: root.connected ? main?.disconnect() : main?.connectFastest()
            }

            // ── Kill switch ──────────────────────────────────────────────────
            NBox {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(ksRow.implicitHeight + Style.marginM * 2)

                RowLayout {
                    id: ksRow
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginM

                    NIcon {
                        icon: "shield-bolt"
                        pointSize: Style.fontSizeL
                        color: (main?.killSwitch ?? "off") === "standard"
                               ? Color.mPrimary : Color.mOnSurfaceVariant
                    }

                    NLabel {
                        label: "Kill Switch"
                        description: {
                            const ks = main?.killSwitch ?? "unknown";
                            if (ks === "standard") return "Blocks internet if VPN drops";
                            if (ks === "off")      return "Disabled";
                            return "Loading…";
                        }
                        Layout.fillWidth: true
                    }

                    NToggle {
                        checked: (main?.killSwitch ?? "off") === "standard"
                        enabled: !root.acting && (main?.killSwitch ?? "unknown") !== "unknown"
                        onToggled: (isChecked) => main?.setKillSwitch(isChecked ? "standard" : "off")
                    }
                }
            }

            // ── Quick connect options (disconnected only) ────────────────────
            NBox {
                Layout.fillWidth: true
                visible: !root.connected
                Layout.preferredHeight: Math.round(quickCol.implicitHeight + Style.marginM * 2)

                ColumnLayout {
                    id: quickCol
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginS

                    NLabel {
                        label: "Quick connect"
                        labelColor: Color.mOnSurfaceVariant
                    }

                    GridLayout {
                        columns: 2
                        Layout.fillWidth: true
                        columnSpacing: Style.marginS
                        rowSpacing: Style.marginS

                        NButton {
                            Layout.fillWidth: true
                            text: "Secure Core"
                            enabled: !root.acting
                            onClicked: main?.connectSecureCore()
                        }

                        NButton {
                            Layout.fillWidth: true
                            text: "P2P"
                            enabled: !root.acting
                            onClicked: main?.connectP2P()
                        }
                    }
                }
            }
        }
    }
}
