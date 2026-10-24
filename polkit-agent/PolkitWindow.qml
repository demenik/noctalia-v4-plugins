import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.Commons
import qs.Widgets
import qs.Services.UI

PanelWindow {
    id: polkitWindow
   
    property AuthFlow flow
    property var pluginApi
    property string resolvedMessage: ""
    property var transientMatch: null

    // sudo askpass mode: no AuthFlow, the response is handed back via signals
    property bool askpassMode: false
    property string askpassPrompt: ""
    property string askpassCommand: ""

    signal askpassSubmitted(string response)
    signal askpassCancelled

    readonly property bool responseRequired: askpassMode || (flow !== null && flow.isResponseRequired)

    function submit() {
        var response = passwordInput.text;
        passwordInput.text = "";
        if (askpassMode) {
            if (response !== "") askpassSubmitted(response);
        } else if (flow) {
            flow.submit(response);
        }
    }

    function cancel() {
        passwordInput.text = "";
        if (askpassMode) {
            askpassCancelled();
        } else if (flow) {
            flow.cancelAuthenticationRequest();
        }
    }

    Connections {
        target: flow
        function onFailedChanged() {
            if (flow && flow.failed) {
                ToastService.showError(
                    pluginApi ? pluginApi.tr("error.failed.title") : "Authentication Failed",
                    pluginApi ? pluginApi.tr("error.failed.message") : "The password you entered was incorrect."
                )
            }
        }
    }

    // Resolve transient service names when flow changes
    onFlowChanged: {
        if (flow) resolveTransientServiceName(flow.message);
    }
    
    // Resolve transient service names (run-PID-random.service) to actual command
    Process {
        id: cmdLineProcess
        command: ["cat", "/proc/0/cmdline"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: function() {
                var args = this.text.split(String.fromCharCode(0)).filter(function(s) { return s.length > 0; });
                Logger.i("polkit-agent: Process output length=" + this.text.length + ", args=" + args.length);
                if (args.length > 0 && polkitWindow.transientMatch) {
                    var resolvedCmd = args.join(' ');
                    var isCommand = args.length > 1 || args[0].includes('/');
                    polkitWindow.resolvedMessage = polkitWindow.resolvedMessage.replace(polkitWindow.transientMatch[0], resolvedCmd);
                    if (isCommand) {
                        polkitWindow.resolvedMessage = polkitWindow.resolvedMessage.replace(/transient unit/i, 'run command');
                    }
                    Logger.i("polkit-agent: Resolved message: " + polkitWindow.resolvedMessage);
                }
            }
        }
    }

    function resolveTransientServiceName(message) {
        if (!message) return;
        var match = message.match(/run-p?(\d+)-[^.]+\.service/);
        if (!match) {
            Logger.i("polkit-agent: No transient service pattern in message: " + message);
            polkitWindow.resolvedMessage = message;
            polkitWindow.transientMatch = null;
            return;
        }
        var pid = match[1];
        Logger.i("polkit-agent: Found transient service pattern, PID=" + pid + ", message=" + message);
        polkitWindow.resolvedMessage = message;
        polkitWindow.transientMatch = match;
        cmdLineProcess.command = ["cat", "/proc/" + pid + "/cmdline"];
        cmdLineProcess.running = true;
    }
    
    // Layer above everything else (critical system prompt)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property real shadowPadding: Style.shadowBlurMax + Style.marginL

    // Explicit size - include shadowPadding so the shadow isn't clipped at window corners
    implicitWidth: 400 * Style.uiScaleRatio + shadowPadding * 2
    implicitHeight: contentLayout.implicitHeight + (Style.marginL * 2) + shadowPadding * 2

    color: "transparent"

    Item {
        id: contentContainer
        anchors.fill: parent
        anchors.margins: shadowPadding
        focus: true

        Keys.onPressed: function(event) {
            if (!flow && !askpassMode) return;

            if (Keybinds.checkKey(event, "escape", Settings)) {
                polkitWindow.cancel();
                event.accepted = true;
            } else if (Keybinds.checkKey(event, "enter", Settings)) {
                if (passwordInput.text !== "") {
                    polkitWindow.submit();
                }
                event.accepted = true;
            }
        }

        
        transform: Translate {
            id: shakeTranslate
            x: 0
        }

        // Error animation
        SequentialAnimation {
            id: errorShake
            running: flow && flow.failed
            loops: 1
            
            NumberAnimation { target: shakeTranslate; property: "x"; from: 0; to: -10; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: shakeTranslate; property: "x"; from: -10; to: 10; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: shakeTranslate; property: "x"; from: 10; to: -10; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: shakeTranslate; property: "x"; from: -10; to: 10; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: shakeTranslate; property: "x"; from: 10; to: 0; duration: 50; easing.type: Easing.InOutQuad }
        }

        // Shadow effect (behind background)
        NDropShadow {
            anchors.fill: customBackground
            source: customBackground
            autoPaddingEnabled: true
            z: -1
        }

        Rectangle {
            id: customBackground
            anchors.fill: parent
            radius: Style.radiusL
            color: Qt.alpha(Color.mSurface, 0.95)
            border.color: (flow && (flow.failed || flow.supplementaryIsError)) ? Color.mError : Color.mOutline
            border.width: Style.borderS
            
            Behavior on border.color {
                ColorAnimation { duration: Style.animationFast }
            }
        }

        ColumnLayout {
            id: contentLayout
            anchors.centerIn: parent
            width: parent.width - (Style.marginL * 2)
            spacing: Style.marginM

            // Header with Icon
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginM

                NImageRounded {
                    Layout.preferredWidth: Style.fontSizeXXL * 2
                    Layout.preferredHeight: Style.fontSizeXXL * 2
                    imagePath: Settings.preprocessPath(Settings.data.general.avatarImage) || ((flow && flow.iconName) ? Quickshell.iconPath(flow.iconName) : "")
                    fallbackIcon: "lock"
                    borderWidth: 0
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginXS

                    NText {
                        text: askpassMode ? (pluginApi ? pluginApi.tr("askpass.title") : "") : (polkitWindow.resolvedMessage || (flow ? flow.message : (pluginApi ? pluginApi.tr("window.title") : "Authentication Required")))
                        pointSize: Style.fontSizeL
                        font.weight: Style.fontWeightBold
                        color: Color.mOnSurface
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    NText {
                        text: askpassMode ? askpassCommand : (flow ? flow.actionId : "")
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurfaceVariant
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        visible: text !== ""
                    }
                }
            }
            
            // Supplementary Message (Error or prompt)
            NText {
                visible: text !== ""
                text: askpassMode ? askpassPrompt.trim() : (flow ? flow.supplementaryMessage : "")
                pointSize: Style.fontSizeS
                color: (flow && flow.supplementaryIsError) ? Color.mError : Color.mOnSurfaceVariant
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            
            // Input Field
            NTextInput {
                id: passwordInput
                Layout.fillWidth: true
                placeholderText: (flow && !askpassMode) ? flow.inputPrompt : (pluginApi ? pluginApi.tr("prompt.password") : "Password")
                label: polkitWindow.responseRequired ? (pluginApi ? pluginApi.tr("prompt.password") : "Password") : ""
                inputItem.echoMode: (askpassMode || (flow && !flow.responseVisible)) ? TextInput.Password : TextInput.Normal
                visible: polkitWindow.responseRequired

                onAccepted: polkitWindow.submit()
            }

            // Actions
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Style.marginS
                spacing: Style.marginM

                Item { Layout.fillWidth: true } // Spacer

                NButton {
                    text: pluginApi ? pluginApi.tr("action.cancel") : "Cancel"
                    backgroundColor: Color.mSurfaceVariant
                    textColor: Color.mOnSurfaceVariant
                    outlined: false
                    onClicked: polkitWindow.cancel()
                }

                NButton {
                    text: pluginApi ? pluginApi.tr("action.authenticate") : "Authenticate"
                    backgroundColor: Color.mPrimary
                    textColor: Color.mOnPrimary
                    enabled: polkitWindow.responseRequired
                    onClicked: polkitWindow.submit()
                }
            }
        }
    }
    
    // Focus handling
    Component.onCompleted: {
        passwordInput.inputItem.forceActiveFocus()
    }
}
