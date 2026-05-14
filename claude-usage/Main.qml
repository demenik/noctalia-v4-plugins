import QtQuick
import Quickshell.Io

Item {
    id: root

    property var pluginApi: null

    property real todayCost: 0
    property int  todayInputTokens: 0
    property int  todayOutputTokens: 0
    property int  todayCacheReadTokens: 0
    property int  todayCacheWriteTokens: 0
    property int  todaySessions: 0
    property real monthCost: 0
    property int  monthSessions: 0
    property real allCost: 0
    property bool isLoading: true

    property real   sessionPercent: -1
    property string sessionResetsIn: ""
    property real   weeklyPercent: -1
    property string weeklyResetsIn: ""

    readonly property int pollInterval: pluginApi?.pluginSettings?.pollInterval ?? 60000

    function refresh() {
        if (!statsProc.running) statsProc.running = true;
    }

    StdioCollector {
        id: statsOut
        onStreamFinished: {
            root.isLoading = false;
            try {
                const d = JSON.parse(this.text.trim());
                root.todayCost             = d.today?.cost ?? 0;
                root.todayInputTokens      = d.today?.input_tokens ?? 0;
                root.todayOutputTokens     = d.today?.output_tokens ?? 0;
                root.todayCacheReadTokens  = d.today?.cache_read_tokens ?? 0;
                root.todayCacheWriteTokens = d.today?.cache_write_tokens ?? 0;
                root.todaySessions         = d.today?.sessions ?? 0;
                root.monthCost             = d.month?.cost ?? 0;
                root.monthSessions         = d.month?.sessions ?? 0;
                root.allCost               = d.all?.cost ?? 0;
                root.sessionPercent        = d.limits?.session?.percent ?? -1;
                root.sessionResetsIn       = d.limits?.session?.resets ?? "";
                root.weeklyPercent         = d.limits?.weekly?.percent ?? -1;
                root.weeklyResetsIn        = d.limits?.weekly?.resets ?? "";
            } catch(e) {}
        }
    }

    StdioCollector { id: statsErr }

    Process {
        id: statsProc
        command: ["python3", "/home/reinhart/.local/bin/claude-usage-stats"]
        running: false
        stdout: statsOut
        stderr: statsErr
    }

    Timer {
        interval: root.pollInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
