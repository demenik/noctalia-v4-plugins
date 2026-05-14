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

    property real contentPreferredWidth:  Math.round(320 * Style.uiScaleRatio)
    property real contentPreferredHeight: Math.round(mainCol.implicitHeight + Style.marginL * 2)

    Component.onCompleted: { if (main) main.refresh(); }

    function fmtCost(c)   { return "$" + (c ?? 0).toFixed(2); }
    function fmtTokens(n) {
        if (!n || n <= 0) return "0";
        if (n >= 1000000) return (n / 1000000).toFixed(1) + "M";
        if (n >= 1000)    return Math.round(n / 1000) + "K";
        return n.toString();
    }
    function dotColor(pct) {
        return pct > 80 ? Color.mError : pct > 50 ? Color.mTertiary : "#f5a623";
    }
    function barColor(pct) {
        return pct > 80 ? Color.mError : pct > 50 ? Color.mTertiary : Color.mPrimary;
    }

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
                        icon: "robot"
                        pointSize: Style.fontSizeXL
                        color: Color.mPrimary
                    }

                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true

                        NLabel {
                            label: "Claude Code"
                        }

                        NLabel {
                            visible: (main?.sessionResetsIn ?? "") !== "" || (main?.weeklyResetsIn ?? "") !== ""
                            label: "Updated just now"
                            labelColor: Color.mOnSurfaceVariant
                        }
                    }

                    NIconButton {
                        icon: "refresh"
                        tooltipText: "Refresh"
                        baseSize: Style.baseWidgetSize * 0.8
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

            // ── Session + Weekly ─────────────────────────────────────────────
            NBox {
                Layout.fillWidth: true
                visible: (main?.sessionPercent ?? -1) >= 0
                Layout.preferredHeight: Math.round(limitsCol.implicitHeight + Style.marginM * 2)

                ColumnLayout {
                    id: limitsCol
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginM

                    // Session
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Math.round(4 * Style.uiScaleRatio)

                        NLabel {
                            label: "Session"
                            labelColor: Color.mOnSurface
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginS

                            Rectangle {
                                width:  Math.round(8 * Style.uiScaleRatio)
                                height: width
                                radius: width / 2
                                color: root.dotColor(main?.sessionPercent ?? 0)
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: Math.round(5 * Style.uiScaleRatio)
                                radius: height / 2
                                color: Color.mSurfaceVariant

                                Rectangle {
                                    width: parent.width * Math.min(1, Math.max(0, (main?.sessionPercent ?? 0) / 100))
                                    height: parent.height
                                    radius: parent.radius
                                    color: root.barColor(main?.sessionPercent ?? 0)
                                    Behavior on width { NumberAnimation { duration: 300 } }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            NLabel {
                                label: Math.round(main?.sessionPercent ?? 0) + "% used"
                                labelColor: Color.mOnSurfaceVariant
                                Layout.fillWidth: true
                            }

                            NLabel {
                                visible: (main?.sessionResetsIn ?? "") !== ""
                                label: "Resets " + (main?.sessionResetsIn ?? "")
                                labelColor: Color.mOnSurfaceVariant
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Color.mSurfaceVariant
                        opacity: 0.5
                    }

                    // Weekly
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Math.round(4 * Style.uiScaleRatio)

                        NLabel {
                            label: "Weekly"
                            labelColor: Color.mOnSurface
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginS

                            Rectangle {
                                width:  Math.round(8 * Style.uiScaleRatio)
                                height: width
                                radius: width / 2
                                color: root.dotColor(main?.weeklyPercent ?? 0)
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: Math.round(5 * Style.uiScaleRatio)
                                radius: height / 2
                                color: Color.mSurfaceVariant

                                Rectangle {
                                    width: parent.width * Math.min(1, Math.max(0, (main?.weeklyPercent ?? 0) / 100))
                                    height: parent.height
                                    radius: parent.radius
                                    color: root.barColor(main?.weeklyPercent ?? 0)
                                    Behavior on width { NumberAnimation { duration: 300 } }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            NLabel {
                                label: Math.round(main?.weeklyPercent ?? 0) + "% used"
                                labelColor: Color.mOnSurfaceVariant
                                Layout.fillWidth: true
                            }

                            NLabel {
                                visible: (main?.weeklyResetsIn ?? "") !== ""
                                label: "Resets " + (main?.weeklyResetsIn ?? "")
                                labelColor: Color.mOnSurfaceVariant
                            }
                        }
                    }
                }
            }

            // ── Cost ─────────────────────────────────────────────────────────
            NBox {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(costCol.implicitHeight + Style.marginM * 2)

                ColumnLayout {
                    id: costCol
                    anchors.fill: parent
                    anchors.margins: Style.marginM
                    spacing: Style.marginS

                    RowLayout {
                        Layout.fillWidth: true

                        NLabel {
                            label: "Cost"
                            labelColor: Color.mOnSurface
                            Layout.fillWidth: true
                        }
                    }

                    NLabel {
                        label: "Today: " + root.fmtCost(main?.todayCost ?? 0) +
                               "  ·  " + root.fmtTokens((main?.todayInputTokens ?? 0) + (main?.todayOutputTokens ?? 0)) + " tokens"
                        labelColor: Color.mOnSurfaceVariant
                        Layout.fillWidth: true
                    }

                    NLabel {
                        label: "This month: " + root.fmtCost(main?.monthCost ?? 0) +
                               "  ·  " + (main?.monthSessions ?? 0) + " sessions"
                        labelColor: Color.mOnSurfaceVariant
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
