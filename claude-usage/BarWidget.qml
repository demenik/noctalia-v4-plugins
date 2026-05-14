import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property var pluginSettings: pluginApi?.pluginSettings ?? ({})
    readonly property var main: pluginApi?.mainInstance ?? ({})

    readonly property string screenName: screen?.name ?? ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"

    readonly property string displayMode: pluginSettings.displayMode ?? "alwaysShow"
    readonly property bool isLoading: main.isLoading ?? true

    readonly property string pillIcon: isLoading ? "reload" : "robot"
    readonly property string pillText: {
        if (isLoading) return "";
        const pct = main.sessionPercent ?? -1;
        if (pct >= 0) return Math.round(pct) + "%";
        return "$" + (main.todayCost ?? 0).toFixed(2);
    }

    implicitWidth: pill.width
    implicitHeight: pill.height

    NPopupContextMenu {
        id: contextMenu
        model: [{
            label: pluginApi?.tr("settings.pluginSettings") ?? "Plugin settings",
            action: "plugin-settings",
            icon: "settings"
        }]
        onTriggered: (action) => {
            contextMenu.close();
            PanelService.closeContextMenu(screen);
            if (action === "plugin-settings" && pluginApi)
                BarService.openPluginSettings(screen, pluginApi.manifest);
        }
    }

    BarPill {
        id: pill
        screen: root.screen
        oppositeDirection: BarService.getPillDirection(root)
        autoHide: false

        icon: root.pillIcon
        text: root.pillText
        tooltipText: {
            const parts = [];
            const pct = root.main.sessionPercent ?? -1;
            if (pct >= 0) parts.push("Session " + Math.round(pct) + "%");
            parts.push("$" + (root.main.todayCost ?? 0).toFixed(2) + " today");
            parts.push("$" + (root.main.monthCost ?? 0).toFixed(2) + " this month");
            return parts.join(" · ");
        }

        forceOpen: !root.isBarVertical && root.displayMode === "alwaysShow"
        forceClose: root.isBarVertical || root.displayMode === "alwaysHide"

        onClicked: {
            if (pluginApi)
                pluginApi.openPanel(root.screen, pill);
        }

        onRightClicked: {
            PanelService.showContextMenu(contextMenu, pill, screen);
        }
    }
}
