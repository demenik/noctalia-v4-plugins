import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import qs.Commons

Item {
    id: root
    property var pluginApi: null

    PolkitAgent {
        id: agent

        onIsActiveChanged: {
            if (isActive) {
                openWindow()
            } else if (!root.askpassActive) {
                closeWindow()
            }
        }
    }

    property var window: null

    // Path of the FIFO the pending askpass request answers through; empty when idle
    property string askpassFifo: ""
    readonly property bool askpassActive: askpassFifo !== ""

    IpcHandler {
        target: "plugin:polkit-agent"

        // Returns immediately; the password (or EOF on cancel) is written to fifoPath
        function askpass(prompt: string, fifoPath: string, command: string): string {
            return root.startAskpass(prompt, fifoPath, command);
        }

        // Called by the helper on timeout so the popup does not linger
        function cancelAskpass(fifoPath: string): void {
            if (root.askpassActive && root.askpassFifo === fifoPath) {
                root.endAskpass();
            }
        }
    }

    function createWindow(properties) {
        var component = Qt.createComponent("PolkitWindow.qml");
        if (component.status === Component.Ready) {
            properties.pluginApi = root.pluginApi;
            window = component.createObject(root, properties);
            if (window !== null) {
                window.visible = true;
            }
        } else {
            Logger.e("polkit-agent: Failed to load PolkitWindow.qml: " + component.errorString());
        }
        component.destroy();
    }

    function openWindow() {
        // Polkit requests wait until a pending askpass request is answered
        if (askpassActive) {
            Logger.i("polkit-agent: Deferring polkit request until askpass request finishes");
            return;
        }
        if (agent.flow === null) {
            Logger.w("polkit-agent: Cannot open window, agent.flow is null");
            return;
        }
        if (window === null) {
            createWindow({ flow: agent.flow });
        } else {
            window.flow = agent.flow;
            window.pluginApi = root.pluginApi;
            window.visible = true;
        }
    }

    function closeWindow() {
        if (window !== null) {
            window.destroy();
            window = null;
        }
    }

    // ----------------------------------------
    // sudo askpass

    function startAskpass(prompt, fifoPath, command) {
        if (askpassActive || window !== null || agent.isActive || fifoWriter.running) {
            Logger.w("polkit-agent: Rejecting askpass request, another authentication is in progress");
            return "busy";
        }
        if (!fifoPath.startsWith("/")) {
            Logger.w("polkit-agent: Rejecting askpass request, FIFO path must be absolute");
            return "invalid";
        }

        askpassFifo = fifoPath;
        createWindow({
            askpassMode: true,
            askpassPrompt: prompt,
            askpassCommand: command
        });
        if (window === null) {
            endAskpass();
            return "error";
        }
        window.askpassSubmitted.connect(function (response) {
            finishAskpass(response);
        });
        window.askpassCancelled.connect(function () {
            finishAskpass("");
        });
        return "ok";
    }

    // An empty response closes the FIFO without data, which makes the helper abort
    function finishAskpass(response) {
        if (!askpassActive) return;

        fifoWriter.payload = response !== "" ? response + "\n" : "";
        fifoWriter.command = ["timeout", "5", "sh", "-c", '[ -p "$1" ] && cat > "$1"', "sh", askpassFifo];
        fifoWriter.stdinEnabled = true;
        fifoWriter.running = true;

        endAskpass();
    }

    function endAskpass() {
        askpassFifo = "";
        closeWindow();

        if (agent.isActive) {
            openWindow();
        }
    }

    // The password goes through stdin so it never appears in a process cmdline
    Process {
        id: fifoWriter
        property string payload: ""

        onStarted: {
            if (payload !== "") {
                write(payload);
            }
            payload = "";
            stdinEnabled = false;
        }

        onExited: function (exitCode) {
            payload = "";
            if (exitCode !== 0) {
                Logger.w("polkit-agent: Failed to answer askpass request (exit code " + exitCode + ")");
            }
        }
    }
}
