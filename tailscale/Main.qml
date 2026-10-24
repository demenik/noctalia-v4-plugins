import QtQuick
import Quickshell
import qs.Commons
import Quickshell.Io
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null

  onPluginApiChanged: {
    if (pluginApi) {
      settingsVersion++;
    }
  }

  // Watch for settings changes (when pluginSettings object is replaced)
  property var settingsWatcher: pluginApi?.pluginSettings
  onSettingsWatcherChanged: {
    if (settingsWatcher) {
      settingsVersion++;
    }
  }

  property int settingsVersion: 0

  property int refreshInterval: _computeRefreshInterval()
  property bool compactMode: _computeCompactMode()
  property bool showIpAddress: _computeShowIpAddress()
  property bool showPeerCount: _computeShowPeerCount()

  function _computeRefreshInterval() {
    return pluginApi?.pluginSettings?.refreshInterval ?? 5000;
  }
  function _computeCompactMode() {
    return pluginApi?.pluginSettings?.compactMode ?? false;
  }
  function _computeShowIpAddress() {
    return pluginApi?.pluginSettings?.showIpAddress ?? true;
  }
  function _computeShowPeerCount() {
    return pluginApi?.pluginSettings?.showPeerCount ?? true;
  }

  onSettingsVersionChanged: {
    refreshInterval = _computeRefreshInterval();
    compactMode = _computeCompactMode();
    showIpAddress = _computeShowIpAddress();
    showPeerCount = _computeShowPeerCount();
    updateTimer.interval = refreshInterval;
  }

  property bool tailscaleInstalled: false
  property bool tailscaleRunning: false
  property string tailscaleIp: ""
  property string tailscaleStatus: ""
  property bool needsLogin: false
  property string authUrl: ""
  property int peerCount: 0
  property bool isRefreshing: false
  property string lastToggleAction: ""
  property var _realPeerList: []
  property var exitNodeStatus: null
  property var selfNode: null

  property var accounts: []
  property string currentAccountId: ""
  property bool accountSwitchInProgress: false

  // Dev/testing: override the peer list with a short mock to reproduce few-device layouts.
  // Toggle via: qs -c noctalia-shell ipc call plugin:tailscale setMockPeers
  property bool useMockData: false
  readonly property var mockPeerList: [
    {
      "HostName": "mock-linux-box",
      "DNSName": "mock-linux-box.tail1234.ts.net.",
      "TailscaleIPs": ["100.64.0.1"],
      "Online": true,
      "OS": "linux",
      "Tags": [],
      "ExitNodeOption": true,
      "ExitNode": false
    },
    {
      "HostName": "mock-mac",
      "DNSName": "mock-mac.tail1234.ts.net.",
      "TailscaleIPs": ["100.64.0.2"],
      "Online": true,
      "OS": "macos",
      "Tags": [],
      "ExitNodeOption": false,
      "ExitNode": false
    },
    {
      "HostName": "mock-win-pc",
      "DNSName": "mock-win-pc.tail1234.ts.net.",
      "TailscaleIPs": ["100.64.0.3"],
      "Online": false,
      "OS": "windows",
      "Tags": [],
      "ExitNodeOption": false,
      "ExitNode": false
    },
    {
      "HostName": "google-pixel-9-pro-xl",
      "DNSName": "google-pixel-9-pro-xl.tail1234.ts.net.",
      "TailscaleIPs": ["100.64.0.4"],
      "Online": true,
      "OS": "android",
      "Tags": [],
      "ExitNodeOption": false,
      "ExitNode": false
    }
  ]

  readonly property var peerList: useMockData ? mockPeerList : _realPeerList

  // Helper to filter IPv4 addresses from Tailscale (100.x.x.x range)
  function filterIPv4(ips) {
    if (!ips || !ips.length)
      return [];
    return ips.filter(ip => ip.startsWith("100."));
  }

  // Some devices (e.g. Android) report "localhost" as their HostName.
  // In that case, derive a meaningful name from the first label of DNSName.
  function resolveHostName(hostName, dnsName) {
    if (hostName && hostName.toLowerCase() !== "localhost")
      return hostName;
    if (!dnsName)
      return hostName;
    var label = dnsName.split(".")[0];
    return label || hostName;
  }

  // Extract the Tailscale short name from DNSName (e.g. "tp-g6.tail68e513.ts.net." → "tp-g6").
  // This is what `tailscale file cp` and other commands expect as a target.
  function tailscaleName(dnsName) {
    if (!dnsName) return ""
    return dnsName.split(".")[0] || ""
  }

  Process {
    id: whichProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function (exitCode, exitStatus) {
      root.tailscaleInstalled = (exitCode === 0);
      root.isRefreshing = false;
      updateTailscaleStatus();
      loadAccounts();
    }
  }

  Process {
    id: statusProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function (exitCode, exitStatus) {
      root.isRefreshing = false;
      var stdout = String(statusProcess.stdout.text || "").trim();
      var stderr = String(statusProcess.stderr.text || "").trim();

      if (exitCode === 0 && stdout && stdout.length > 0) {
        try {
          var data = JSON.parse(stdout);
          root.tailscaleRunning = data.BackendState === "Running";
          root.needsLogin = data.BackendState === "NeedsLogin";

          if (root.needsLogin) {
            root.tailscaleIp = "";
            root.tailscaleStatus = "NeedsLogin";
            root.peerCount = 0;
            root._realPeerList = [];
            root.exitNodeStatus = null;
            root.selfNode = null;
            // Capture the pending authentication URL exposed by the daemon.
            var newAuthUrl = data.AuthURL || "";
            root.authUrl = newAuthUrl;
            // If a login attempt is in progress and the daemon has surfaced a
            // URL that differs from the one cached at click-time, it means the
            // URL was regenerated (fresh) — open it immediately.
            if (root._loginInProgress
                && !root._loginUrlOpened
                && newAuthUrl.length > 0
                && newAuthUrl !== root._preLoginAuthUrl) {
              root._openAuthUrl(newAuthUrl);
            }
          } else if (root.tailscaleRunning && data.Self && data.Self.TailscaleIPs && data.Self.TailscaleIPs.length > 0) {
            root.tailscaleIp = filterIPv4(data.Self.TailscaleIPs)[0] || data.Self.TailscaleIPs[0];
            root.tailscaleStatus = "Connected";
            root.authUrl = "";
            // Login flow settled — reset flags so the next attempt starts clean
            if (root._loginInProgress) {
              loadAccounts();
            }
            root._loginInProgress = false;
            root._loginUrlOpened = false;
            root._preLoginAuthUrl = "";
            loginTimeoutTimer.stop();

            var peers = [];
            if (data.Self) {
              var selfIpv4s = filterIPv4(data.Self.TailscaleIPs);
              root.selfNode = {
                "HostName": resolveHostName(data.Self.HostName, data.Self.DNSName),
                "DNSName": data.Self.DNSName,
                "TailscaleIPs": selfIpv4s,
                "Online": true,
                "OS": data.Self.OS || "linux",
                "Tags": data.Self.Tags || [],
                "ExitNodeOption": false,
                "ExitNode": false,
                "IsSelf": true
              };
            } else {
              root.selfNode = null;
            }
            if (data.Peer) {
              for (var peerId in data.Peer) {
                var peer = data.Peer[peerId];
                var ipv4s = filterIPv4(peer.TailscaleIPs);
                peers.push({
                             "ID": peer.ID || "",
                             "HostName": resolveHostName(peer.HostName, peer.DNSName),
                             "DNSName": peer.DNSName,
                             "TailscaleIPs": ipv4s,
                             "Online": peer.Online,
                             "OS": peer.OS,
                             "Tags": peer.Tags || [],
                             "ExitNodeOption": peer.ExitNodeOption || false,
                             "ExitNode": peer.ExitNode || false
                           });
              }
            }
            root._realPeerList = peers;
            root.peerCount = peers.length;

            // Extract exit node status if present
            if (data.ExitNodeStatus) {
              root.exitNodeStatus = {
                "ID": data.ExitNodeStatus.ID || "",
                "Online": data.ExitNodeStatus.Online || false,
                "TailscaleIPs": data.ExitNodeStatus.TailscaleIPs || []
              };
            } else {
              root.exitNodeStatus = null;
            }
          } else {
            root.tailscaleIp = "";
            root.tailscaleStatus = root.tailscaleRunning ? "Connected" : "Disconnected";
            root.peerCount = 0;
            root._realPeerList = [];
            root.exitNodeStatus = null;
            root.selfNode = null;
            root.authUrl = "";
          }
        } catch (e) {
          Logger.e("Tailscale", "Failed to parse status: " + e);
          root.tailscaleRunning = false;
          root.needsLogin = false;
          root.tailscaleStatus = "Error";
          root._realPeerList = [];
          root.selfNode = null;
          root.authUrl = "";
        }
      } else {
        root.tailscaleRunning = false;
        root.needsLogin = false;
        root.tailscaleStatus = "Disconnected";
        root.tailscaleIp = "";
        root.peerCount = 0;
        root._realPeerList = [];
        root.selfNode = null;
        root.authUrl = "";
      }
      root.accountSwitchInProgress = false;
    }
  }

  Process {
    id: toggleProcess
    onExited: function (exitCode, exitStatus) {
      if (exitCode === 0) {
        var message = root.lastToggleAction === "connect" ? pluginApi?.tr("toast.connected") : pluginApi?.tr("toast.disconnected");
        ToastService.showNotice(pluginApi?.tr("toast.title"), message, "network");
      }

      statusDelayTimer.start();
    }
  }

  Process {
    id: exitNodeProcess
    onExited: function (exitCode, exitStatus) {
      if (exitCode === 0) {
        var message = root.lastExitNodeAction === "set" ? pluginApi?.tr("toast.exit-node-enabled") : pluginApi?.tr("toast.exit-node-disabled");
        ToastService.showNotice(pluginApi?.tr("toast.title"), message, "globe");
      }
      statusDelayTimer.start();
    }
  }

  property string lastExitNodeAction: ""

  // ─── Account switching ──────────────────────────────────────────────────

  Process {
    id: accountsListProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function (exitCode, exitStatus) {
      // Older tailscale binaries may not support this; treat as no accounts.
      root.accounts = [];
      root.currentAccountId = "";
      if (exitCode !== 0) return;
      var raw = String(accountsListProcess.stdout.text || "").trim();
      if (raw.length === 0) return;
      try {
        var arr = JSON.parse(raw);
        if (!Array.isArray(arr)) return;
        root.accounts = arr;
        for (var i = 0; i < arr.length; i++) {
          if (arr[i].selected) {
            root.currentAccountId = arr[i].id || "";
            break;
          }
        }
      } catch (e) {
        Logger.e("Tailscale", "Failed to parse accounts: " + e);
      }
    }
  }

  Process {
    id: switchAccountProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function (exitCode, exitStatus) {
      if (exitCode === 0) {
        ToastService.showNotice(pluginApi?.tr("toast.title"), pluginApi?.tr("toast.account-switched"), "user");
      } else {
        var stderr = String(switchAccountProcess.stderr.text || "").trim();
        Logger.e("Tailscale", "Account switch failed (exit " + exitCode + "): " + stderr);
        ToastService.showError(pluginApi?.tr("toast.title"), pluginApi?.tr("toast.account-switch-failed"), "alert-circle");
      }
      loadAccounts();
      statusDelayTimer.start();
    }
  }

  // ─── Login flow state ────────────────────────────────────────────────────
  // A login attempt is tracked across two asynchronous sources that may deliver
  // a fresh AuthURL: (1) stdout/stderr of `tailscale up` and (2) the periodic
  // `tailscale status --json` poll. Whichever arrives first wins; the other is
  // deduped via `_loginUrlOpened`.
  property bool _loginUrlOpened: false
  property bool _loginInProgress: false
  // Snapshot of authUrl taken at click-time. Used to detect when the daemon
  // has regenerated the URL so we never open a stale/expired one.
  property string _preLoginAuthUrl: ""

  /**
   * Open an authentication URL in the default browser, with anti-double-open
   * protection. Resets login-flow state.
   *
   * @param {string} url Authentication URL to open
   */
  function _openAuthUrl(url) {
    if (root._loginUrlOpened) return;
    if (!url || url.length === 0) return;
    root._loginUrlOpened = true;
    root._loginInProgress = false;
    loginTimeoutTimer.stop();
    Logger.d("Tailscale", "Opening auth URL: " + url);
    Qt.openUrlExternally(url);
    ToastService.showNotice(
      pluginApi?.tr("toast.title"),
      pluginApi?.tr("toast.login-browser-opened"),
      "external-link"
    );
  }

  // Safety net: if no fresh AuthURL surfaces within 10s after a login click,
  // either open whatever is cached (best effort) or show an error toast.
  Timer {
    id: loginTimeoutTimer
    interval: 10000
    repeat: false
    onTriggered: {
      if (!root._loginInProgress || root._loginUrlOpened) return;
      root._loginInProgress = false;
      Logger.w("Tailscale", "Login timeout: no fresh AuthURL received within 10s");
      if (root.authUrl && root.authUrl.length > 0) {
        // Last resort: open the cached URL (may be the stale one)
        Logger.w("Tailscale", "Falling back to cached (possibly stale) AuthURL");
        root._openAuthUrl(root.authUrl);
      } else {
        ToastService.showError(
          pluginApi?.tr("toast.title"),
          pluginApi?.tr("toast.login-failed"),
          "alert-circle"
        );
      }
    }
  }

  Process {
    id: loginProcess

    function _handleLine(data) {
      if (root._loginUrlOpened) return;
      var line = data.trim();
      Logger.d("Tailscale", "Login output: " + line);
      var urlMatch = line.match(/https?:\/\/\S+/);
      if (urlMatch) {
        root._openAuthUrl(urlMatch[0]);
      }
    }

    stdout: SplitParser {
      onRead: data => loginProcess._handleLine(data)
    }

    stderr: SplitParser {
      onRead: data => loginProcess._handleLine(data)
    }

    onExited: function (exitCode, exitStatus) {
      Logger.d("Tailscale", "Login exited (code " + exitCode + "), urlOpened=" + root._loginUrlOpened);
      if (exitCode !== 0 && !root._loginUrlOpened) {
        Logger.e("Tailscale", "tailscale up failed (exit " + exitCode + "), waiting on status poll for fresh AuthURL");
      }
      // Do NOT reset _loginUrlOpened here — the status poll may still deliver
      // the fresh URL after process exit. The flag is reset by _openAuthUrl
      // and by the login-state transitions in statusProcess.
      statusDelayTimer.start();
    }
  }

  // ─── Taildrop state ──────────────────────────────────────────────────────
  // Transfers are tracked through the IPN bus (`tailscale debug watch-ipn`),
  // which reports progress for incoming (IncomingFiles), finished-but-unclaimed
  // (FilesWaiting) and outgoing (OutgoingFiles) transfers.

  // Possible values: "idle", "receiving", "incoming", "saving", "discarding",
  // "received", "sending", "sent", "error"
  property string taildropState: "idle"
  property string taildropMessage: ""
  // "in" or "out"
  property string taildropDirection: ""
  property string taildropPeerName: ""
  // [{ name, size, transferred, done }] - size is -1 when unknown
  property var taildropFiles: []
  property real taildropTotalBytes: 0
  property real taildropTransferredBytes: 0
  property var taildropSavedFiles: []
  property bool taildropPopupVisible: false
  property var taildropPopupScreen: null

  readonly property string _homeDir: Quickshell.env("HOME") ?? ""

  function _expandPath(path) {
    if (!path)
      return path;
    if (path.startsWith("~/"))
      return _homeDir + path.substring(1);
    return path;
  }

  readonly property bool taildropEnabled: pluginApi?.pluginSettings?.taildropEnabled ?? pluginApi?.manifest?.metadata?.defaultSettings?.taildropEnabled ?? true

  readonly property string taildropDownloadDirSetting: pluginApi?.pluginSettings?.taildropDownloadDir || pluginApi?.manifest?.metadata?.defaultSettings?.taildropDownloadDir || "~/Downloads"
  readonly property string taildropDownloadDir: _expandPath(taildropDownloadDirSetting)

  readonly property bool taildropAutoSave: pluginApi?.pluginSettings?.taildropAutoSave ?? pluginApi?.manifest?.metadata?.defaultSettings?.taildropAutoSave ?? false

  // "operator" = no priv-esc (requires `sudo tailscale set --operator $USER`)
  // "pkexec"   = use pkexec to run as root
  readonly property string taildropReceiveMode: pluginApi?.pluginSettings?.taildropReceiveMode || pluginApi?.manifest?.metadata?.defaultSettings?.taildropReceiveMode || "operator"

  // Snapshot of filenames in download dir taken just before receive starts
  property var _preScanFiles: []
  // Last FilesWaiting value seen on the IPN bus
  property bool _filesWaiting: false
  // Set when the user dismissed or failed to save the current inbox content,
  // so repeated FilesWaiting notifications do not reopen the popup.
  property bool _inboxAcknowledged: false
  property string _sendPeerId: ""
  property bool _sendCancelled: false
  // OutgoingFile IDs that belong to earlier sends
  property var _seenOutgoingIds: ({})
  property var _staleOutgoingIds: ({})

  function _taildropGetCommand(dir) {
    var cmd = ["tailscale", "file", "get", "--conflict=rename", dir];
    return root.taildropReceiveMode === "pkexec" ? ["pkexec"].concat(cmd) : cmd;
  }

  function _setTaildropFiles(files) {
    var total = 0;
    var done = 0;
    for (var i = 0; i < files.length; i++) {
      if (files[i].size > 0)
        total += files[i].size;
      done += files[i].transferred;
    }
    root.taildropFiles = files;
    root.taildropTotalBytes = total;
    root.taildropTransferredBytes = done;
  }

  function _allIncomingDone() {
    for (var i = 0; i < root.taildropFiles.length; i++) {
      var f = root.taildropFiles[i];
      if (!f.done)
        return false;
    }
    return true;
  }

  function showTaildropPopup() {
    root.taildropPopupScreen = root.taildropPopupScreen || Quickshell.screens[0] || null;
    root.taildropPopupVisible = true;
    if (pluginApi) {
      pluginApi.withCurrentScreen(screen => {
                                    root.taildropPopupScreen = screen;
                                  });
    }
  }

  // Hides the popup. Finished transfers are cleared; running ones continue
  // in the background and the popup reappears when they complete.
  function dismissTaildropPopup() {
    root.taildropPopupVisible = false;
    taildropAutoHideTimer.stop();
    if (root.taildropState === "incoming") {
      root._inboxAcknowledged = true;
    } else if (["received", "sent", "error"].indexOf(root.taildropState) !== -1) {
      _resetTaildrop();
    }
  }

  function _resetTaildrop() {
    root.taildropState = "idle";
    root.taildropMessage = "";
    root.taildropDirection = "";
    root.taildropPeerName = "";
    root.taildropSavedFiles = [];
    _setTaildropFiles([]);
  }

  function _finishTaildrop(state, message) {
    root.taildropState = state;
    root.taildropMessage = message || "";
    showTaildropPopup();
    if (state === "received" || state === "sent")
      taildropAutoHideTimer.restart();
    else
      taildropAutoHideTimer.stop();
  }

  // --- IPN bus watcher ---

  readonly property bool _ipnWatchWanted: root.tailscaleInstalled && root.taildropEnabled
  on_IpnWatchWantedChanged: _syncIpnWatcher()

  property var _ipnBuffer: []

  function _syncIpnWatcher() {
    if (root._ipnWatchWanted && !ipnWatchProcess.running) {
      root._ipnBuffer = [];
      ipnWatchProcess.running = true;
    } else if (!root._ipnWatchWanted && ipnWatchProcess.running) {
      ipnWatchProcess.running = false;
    }
  }

  // watch-ipn prints each Notify as tab-indented JSON, so a top-level object
  // always starts with a lone "{" line and ends with a lone "}" line.
  function _onIpnLine(line) {
    if (line === "{") {
      root._ipnBuffer = [line];
      return;
    }
    if (root._ipnBuffer.length === 0)
      return;
    root._ipnBuffer.push(line);
    if (line !== "}")
      return;
    var raw = root._ipnBuffer.join("\n");
    root._ipnBuffer = [];
    try {
      _handleIpnNotify(JSON.parse(raw));
    } catch (e) {
      Logger.e("Tailscale", "Failed to parse IPN notification: " + e);
    }
  }

  function _handleIpnNotify(n) {
    if (n.OutgoingFiles)
      _handleOutgoingFiles(n.OutgoingFiles);
    if (n.IncomingFiles)
      _handleIncomingFiles(n.IncomingFiles);
    _handleFilesWaiting(n.FilesWaiting !== undefined && n.FilesWaiting !== null);
  }

  function _handleIncomingFiles(list) {
    if (list.length === 0)
      return;
    if (["sending", "saving", "discarding"].indexOf(root.taildropState) !== -1)
      return;

    var files = [];
    if (root.taildropState === "receiving") {
      files = root.taildropFiles.slice();
    } else {
      _resetTaildrop();
      root.taildropState = "receiving";
      root.taildropDirection = "in";
      root._inboxAcknowledged = false;
      taildropAutoHideTimer.stop();
      showTaildropPopup();
      Logger.i("Tailscale", "Taildrop incoming transfer detected");
    }

    for (var i = 0; i < list.length; i++) {
      var pf = list[i];
      var entry = {
        "name": pf.Name,
        "size": pf.DeclaredSize >= 0 ? pf.DeclaredSize : -1,
        "transferred": pf.Received || 0,
        "done": pf.Done === true || (pf.DeclaredSize >= 0 && pf.Received >= pf.DeclaredSize)
      };
      var idx = files.findIndex(f => f.name === pf.Name);
      if (idx === -1)
        files.push(entry);
      else
        files[idx] = entry;
    }
    _setTaildropFiles(files);

    taildropSettleTimer.stop();
    taildropStallTimer.restart();
  }

  function _handleFilesWaiting(waiting) {
    root._filesWaiting = waiting;
    if (waiting) {
      if (root.taildropState === "receiving") {
        if (_allIncomingDone())
          taildropSettleTimer.restart();
      } else if (["idle", "received", "sent", "error"].indexOf(root.taildropState) !== -1 && !root._inboxAcknowledged) {
        _resetTaildrop();
        root.taildropDirection = "in";
        _enterIncoming();
      }
    } else {
      root._inboxAcknowledged = false;
      // Inbox was emptied elsewhere (e.g. `tailscale file get` from a terminal)
      if (root.taildropState === "incoming") {
        root.taildropPopupVisible = false;
        _resetTaildrop();
      }
    }
  }

  function _enterIncoming() {
    taildropStallTimer.stop();
    taildropSettleTimer.stop();
    root.taildropState = "incoming";
    if (root.taildropAutoSave) {
      saveIncomingFiles();
    } else {
      showTaildropPopup();
    }
  }

  function _handleOutgoingFiles(list) {
    var seen = Object.assign({}, root._seenOutgoingIds);
    for (var i = 0; i < list.length; i++)
      seen[list[i].ID] = true;
    root._seenOutgoingIds = seen;

    if (root.taildropState !== "sending")
      return;

    var files = root.taildropFiles.slice();
    var changed = false;
    for (var j = 0; j < list.length; j++) {
      var of = list[j];
      if (root._staleOutgoingIds[of.ID])
        continue;
      if (root._sendPeerId && of.PeerID && of.PeerID !== root._sendPeerId)
        continue;
      var idx = files.findIndex(f => f.name === of.Name);
      if (idx === -1)
        continue;
      files[idx] = {
        "name": of.Name,
        "size": of.DeclaredSize >= 0 ? of.DeclaredSize : -1,
        "transferred": of.Sent || 0
      };
      changed = true;
    }
    if (changed)
      _setTaildropFiles(files);
  }

  Process {
    id: ipnWatchProcess
    command: ["tailscale", "debug", "watch-ipn", "--initial-outgoing-files", "--peer-changes=false", "--peer-patches=false"]

    stdout: SplitParser {
      onRead: data => root._onIpnLine(data)
    }
    stderr: StdioCollector {}

    onStarted: Logger.d("Tailscale", "IPN bus watcher started")

    onExited: function (exitCode, exitStatus) {
      var stderr = String(ipnWatchProcess.stderr.text || "").trim();
      Logger.d("Tailscale", "IPN bus watcher exited (code " + exitCode + "): " + stderr);
      if (root._ipnWatchWanted)
        ipnWatchRestartTimer.restart();
    }
  }

  Timer {
    id: ipnWatchRestartTimer
    interval: 5000
    repeat: false
    onTriggered: root._syncIpnWatcher()
  }

  // Multi-file sends arrive one after another, so wait briefly after the
  // last file completes before treating the batch as finished.
  Timer {
    id: taildropSettleTimer
    interval: 1500
    repeat: false
    onTriggered: {
      if (root.taildropState === "receiving")
        root._enterIncoming();
    }
  }

  // The bus does not report aborted incoming transfers; give up on a
  // receive that has not progressed for a while.
  Timer {
    id: taildropStallTimer
    interval: 30000
    repeat: false
    onTriggered: {
      if (root.taildropState !== "receiving")
        return;
      Logger.w("Tailscale", "Taildrop incoming transfer stalled");
      if (root._filesWaiting) {
        root._enterIncoming();
      } else {
        root.taildropPopupVisible = false;
        root._resetTaildrop();
      }
    }
  }

  Timer {
    id: taildropAutoHideTimer
    interval: 8000
    repeat: false
    onTriggered: root.dismissTaildropPopup()
  }

  // --- Taildrop actions ---

  Process {
    id: preScanProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function (exitCode) {
      if (exitCode === 0) {
        var raw = String(preScanProcess.stdout.text || "").trim();
        root._preScanFiles = raw.length > 0 ? raw.split("\n") : [];
      } else {
        root._preScanFiles = [];
      }
      Logger.d("Tailscale", "Pre-scan: " + root._preScanFiles.length + " files");
      taildropReceiveProcess.command = root._taildropGetCommand(root.taildropDownloadDir);
      taildropReceiveProcess.running = true;
    }
  }

  Process {
    id: postScanProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function (exitCode) {
      var newFiles = [];
      if (exitCode === 0) {
        var raw = String(postScanProcess.stdout.text || "").trim();
        var postFiles = raw.length > 0 ? raw.split("\n") : [];
        var preSet = {};
        for (var i = 0; i < root._preScanFiles.length; i++) {
          preSet[root._preScanFiles[i]] = true;
        }
        for (var j = 0; j < postFiles.length; j++) {
          if (!preSet[postFiles[j]]) {
            newFiles.push(postFiles[j]);
          }
        }
      }
      Logger.i("Tailscale", "Taildrop received " + newFiles.length + " new file(s)");
      if (newFiles.length > 0) {
        root.taildropSavedFiles = newFiles;
        root._finishTaildrop("received");
      } else {
        root._inboxAcknowledged = true;
        root._finishTaildrop("error", pluginApi?.tr("taildrop.toast.no-files"));
      }
    }
  }

  Process {
    id: taildropReceiveProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onStarted: {
      root.taildropState = "saving";
      root.taildropMessage = "";
      Logger.i("Tailscale", "Taildrop receive started in: " + root.taildropDownloadDir);
    }

    onExited: function (exitCode, exitStatus) {
      var stderr = String(taildropReceiveProcess.stderr.text || "").trim();
      var stdout = String(taildropReceiveProcess.stdout.text || "").trim();
      var allOutput = (stderr + "\n" + stdout).trim();
      if (exitCode === 0) {
        postScanProcess.command = ["ls", "-1", root.taildropDownloadDir];
        postScanProcess.running = true;
        Logger.i("Tailscale", "Taildrop receive completed, running post-scan");
      } else {
        root._inboxAcknowledged = true;
        var isDuplicateFile = allOutput.indexOf("file exists") !== -1 || allOutput.indexOf("refusing to overwrite") !== -1 || /moved 0\/\d+ files/.test(allOutput);
        root._finishTaildrop("error", isDuplicateFile ? pluginApi?.tr("taildrop.error.file-exists") : allOutput || pluginApi?.tr("taildrop.error.unknown"));
        Logger.e("Tailscale", "Taildrop receive failed (exit " + exitCode + "): " + allOutput);
      }
    }
  }

  Process {
    id: taildropDiscardProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function (exitCode, exitStatus) {
      var stderr = String(taildropDiscardProcess.stderr.text || "").trim();
      if (exitCode === 0) {
        root.taildropPopupVisible = false;
        root._resetTaildrop();
        ToastService.showNotice(pluginApi?.tr("toast.title"), pluginApi?.tr("taildrop.toast.discarded"), "trash");
        Logger.i("Tailscale", "Taildrop inbox discarded");
      } else {
        root._inboxAcknowledged = true;
        root._finishTaildrop("error", stderr || pluginApi?.tr("taildrop.error.unknown"));
        Logger.e("Tailscale", "Taildrop discard failed (exit " + exitCode + "): " + stderr);
      }
    }
  }

  Process {
    id: taildropSendProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onStarted: {
      Logger.i("Tailscale", "Taildrop send started");
    }

    onExited: function (exitCode, exitStatus) {
      var stderr = String(taildropSendProcess.stderr.text || "").trim();
      if (root._sendCancelled) {
        root._sendCancelled = false;
        root.taildropPopupVisible = false;
        root._resetTaildrop();
        Logger.i("Tailscale", "Taildrop send cancelled");
      } else if (exitCode === 0) {
        root._setTaildropFiles(root.taildropFiles.map(f => ({
                                                              "name": f.name,
                                                              "size": f.size,
                                                              "transferred": Math.max(f.size, f.transferred)
                                                            })));
        root._finishTaildrop("sent");
        Logger.i("Tailscale", "Taildrop send completed successfully");
      } else {
        root._finishTaildrop("error", stderr || pluginApi?.tr("taildrop.error.unknown"));
        Logger.e("Tailscale", "Taildrop send failed (exit " + exitCode + "): " + stderr);
      }
    }
  }

  // Moves all files from the Taildrop inbox into the download directory.
  function saveIncomingFiles() {
    if (!root.tailscaleInstalled) {
      Logger.w("Tailscale", "Cannot receive: tailscale not installed");
      return;
    }
    if (!root.taildropEnabled) {
      Logger.w("Tailscale", "Taildrop is disabled in settings");
      return;
    }
    if (preScanProcess.running || taildropReceiveProcess.running || taildropDiscardProcess.running) {
      Logger.w("Tailscale", "Already handling the Taildrop inbox");
      return;
    }
    root.taildropDirection = "in";
    root.taildropState = "saving";
    // Pre-scan the download dir; the scan's onExited launches the actual receive
    preScanProcess.command = ["ls", "-1", root.taildropDownloadDir];
    preScanProcess.running = true;
  }

  // Deletes all files from the Taildrop inbox. There is no CLI command for
  // this, so the files are fetched into a throwaway directory instead.
  function discardIncomingFiles() {
    if (!root.tailscaleInstalled || taildropReceiveProcess.running || taildropDiscardProcess.running)
      return;
    root.taildropState = "discarding";
    var script = 'd=$(mktemp -d) || exit 1; "$@" "$d"; r=$?; rm -rf "$d"; exit $r';
    taildropDiscardProcess.command = ["sh", "-c", script, "sh"].concat(root._taildropGetCommand("").slice(0, -1));
    taildropDiscardProcess.running = true;
  }

  // files: array of local file paths, peerTarget: "hostname:" or "ip:",
  // peer: peer object from peerList (used for progress tracking and display)
  function sendFilesViaTaildrop(files, peerTarget, peer) {
    if (!root.tailscaleInstalled || !root.tailscaleRunning) {
      Logger.w("Tailscale", "Cannot send: tailscale not running");
      return;
    }
    if (!root.taildropEnabled) {
      Logger.w("Tailscale", "Taildrop is disabled in settings");
      return;
    }
    if (!files || files.length === 0) {
      Logger.w("Tailscale", "No files to send");
      return;
    }
    if (taildropSendProcess.running) {
      Logger.w("Tailscale", "Already sending files");
      return;
    }

    _resetTaildrop();
    taildropAutoHideTimer.stop();
    root.taildropState = "sending";
    root.taildropDirection = "out";
    root.taildropPeerName = peer?.HostName || peerTarget.replace(/:$/, "");
    root._sendPeerId = peer?.ID || "";
    root._sendCancelled = false;
    root._staleOutgoingIds = Object.assign({}, root._seenOutgoingIds);
    _setTaildropFiles(files.map(p => ({
                                        "name": p.split("/").pop(),
                                        "size": -1,
                                        "transferred": 0
                                      })));
    showTaildropPopup();

    taildropSendProcess.command = ["tailscale", "file", "cp"].concat(files).concat([peerTarget]);
    taildropSendProcess.running = true;
  }

  function cancelTaildropSend() {
    if (!taildropSendProcess.running)
      return;
    root._sendCancelled = true;
    taildropSendProcess.running = false;
  }

  function openTaildropDownloadDir() {
    Qt.openUrlExternally("file://" + root.taildropDownloadDir);
  }

  function openTaildropSavedFile(name) {
    Qt.openUrlExternally("file://" + root.taildropDownloadDir + "/" + name);
  }

  Loader {
    active: root.taildropPopupVisible && root.taildropPopupScreen !== null
    sourceComponent: TaildropPopup {
      screen: root.taildropPopupScreen
      mainInstance: root
      pluginApi: root.pluginApi
    }
  }

  function setExitNode(ip) {
    if (!root.tailscaleInstalled || !root.tailscaleRunning)
      return;
    root.lastExitNodeAction = "set";
    exitNodeProcess.command = ["tailscale", "set", "--exit-node=" + ip];
    exitNodeProcess.running = true;
  }

  function clearExitNode() {
    if (!root.tailscaleInstalled || !root.tailscaleRunning)
      return;
    root.lastExitNodeAction = "clear";
    exitNodeProcess.command = ["tailscale", "set", "--exit-node="];
    exitNodeProcess.running = true;
  }

  function loadAccounts() {
    if (!root.tailscaleInstalled) {
      root.accounts = [];
      root.currentAccountId = "";
      return;
    }
    accountsListProcess.command = ["tailscale", "switch", "--list", "--json"];
    accountsListProcess.running = true;
  }

  function switchAccount(id) {
    if (!root.tailscaleInstalled || !id)
      return;
    if (id === root.currentAccountId)
      return;
    root.accountSwitchInProgress = true;
    switchAccountProcess.command = ["tailscale", "switch", id];
    switchAccountProcess.running = true;
  }

  Timer {
    id: statusDelayTimer
    interval: 500
    repeat: false
    onTriggered: {
      root.isRefreshing = false;
      updateTailscaleStatus();
    }
  }

  function checkTailscaleInstalled() {
    root.isRefreshing = true;
    whichProcess.command = ["which", "tailscale"];
    whichProcess.running = true;
  }

  function updateTailscaleStatus() {
    if (!root.tailscaleInstalled) {
      root.tailscaleRunning = false;
      root.needsLogin = false;
      root.tailscaleIp = "";
      root.tailscaleStatus = "Not installed";
      root.peerCount = 0;
      return;
    }

    root.isRefreshing = true;
    statusProcess.command = ["tailscale", "status", "--json"];
    statusProcess.running = true;
  }

  function toggleTailscale() {
    if (!root.tailscaleInstalled)
      return;
    root.isRefreshing = true;
    if (root.tailscaleRunning) {
      root.lastToggleAction = "disconnect";
      toggleProcess.command = ["tailscale", "down"];
    } else {
      root.lastToggleAction = "connect";
      toggleProcess.command = ["tailscale", "up"];
    }
    toggleProcess.running = true;
  }

  /**
   * Trigger the Tailscale authentication flow.
   *
   * @description
   * Always runs `tailscale up --force-reauth` to force the daemon to generate
   * a fresh AuthURL (any cached one may be expired). The fresh URL is then
   * opened from whichever channel delivers it first:
   *  - stdout/stderr of `tailscale up` (parsed by loginProcess)
   *  - the next `tailscale status --json` poll (via statusProcess)
   * Deduped through `_openAuthUrl` / `_loginUrlOpened`.
   *
   * Guard: no-op when not in NeedsLogin state to avoid disconnecting an
   * already-authenticated session.
   */
  function loginTailscale() {
    if (!root.tailscaleInstalled)
      return;
    if (!root.needsLogin) {
      Logger.w("Tailscale", "Login requested but backend is not in NeedsLogin state — ignoring");
      return;
    }

    // Start a fresh login attempt
    root._loginInProgress = true;
    root._loginUrlOpened = false;
    root._preLoginAuthUrl = root.authUrl;

    // --force-reauth forces the daemon to regenerate the AuthURL even if a
    // (possibly expired) one is still cached in its session state.
    var loginServer = pluginApi?.pluginSettings?.loginServer || "";
    var cmd = ["tailscale", "up", "--accept-routes", "--force-reauth"];
    if (loginServer.trim() !== "") {
      cmd.push("--login-server=" + loginServer.trim());
    }
    loginProcess.command = cmd;
    loginProcess.running = true;

    // Arm the safety-net timeout and kick an early status refresh
    loginTimeoutTimer.restart();
    statusDelayTimer.start();
  }

  Timer {
    id: updateTimer
    interval: refreshInterval
    repeat: true
    running: true
    triggeredOnStart: true

    onTriggered: {
      if (root.tailscaleInstalled === false) {
        checkTailscaleInstalled();
      } else {
        updateTailscaleStatus();
      }
    }
  }

  Component.onCompleted: {
    checkTailscaleInstalled();
  }

  IpcHandler {
    target: "plugin:tailscale"

    function toggle() {
      toggleTailscale();
    }

    function togglePanel() {
      pluginApi.withCurrentScreen(screen => {
                                    pluginApi.togglePanel(screen);
                                  });
    }

    function status() {
      return {
        "installed": root.tailscaleInstalled,
        "running": root.tailscaleRunning,
        "ip": root.tailscaleIp,
        "status": root.tailscaleStatus,
        "peers": root.peerCount,
        "needsLogin": root.needsLogin
      };
    }

    function refresh() {
      updateTailscaleStatus();
    }

    function login() {
      loginTailscale();
    }

    function switchAccount(id: string) {
      root.switchAccount(id);
    }

    // Taildrop IPC: qs ipc call plugin:tailscale receive
    function receive() {
      saveIncomingFiles();
    }

    // Dev/testing: toggle mock peer list to reproduce few-device layouts.
    // Usage: qs -c noctalia-shell ipc call plugin:tailscale setMockPeers
    function setMockPeers() {
      root.useMockData = !root.useMockData;
      Logger.d("Tailscale", "Mock peer data " + (root.useMockData ? "enabled" : "disabled"));
    }
  }
}
