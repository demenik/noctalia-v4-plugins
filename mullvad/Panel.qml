import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
	id: root
	property var pluginApi: null
	property ShellScreen screen

	readonly property var main: pluginApi?.mainInstance
	readonly property string vpnState: main?.state ?? "disconnected"
	readonly property bool locked: main?.locked ?? false
	readonly property bool installed: main?.installed ?? false

	readonly property var geometryPlaceholder: panelContainer
	readonly property bool allowAttach: true

	property string currentView: "main" // "main" | "settings"

	property real contentPreferredWidth: 380 * Style.uiScaleRatio
	property real contentPreferredHeight: {
		var h = headerBox.Layout.preferredHeight
		        + scrollColumn.implicitHeight
		        + contentColumn.spacing
		        + Style.marginL * 2
		return Math.max(250 * Style.uiScaleRatio, Math.min(750 * Style.uiScaleRatio, h))
	}

	anchors.fill: parent

	function _flag(code) {
		var c = (code || "").toUpperCase()
		if (c.length !== 2) return ""
		return String.fromCodePoint(0x1F1E6 + c.charCodeAt(0) - 65, 0x1F1E6 + c.charCodeAt(1) - 65)
	}

	function _stateLabel() {
		if (!installed) return pluginApi?.tr("state.not-installed")
		if (vpnState === "error") return pluginApi?.tr("state.error")
		if (locked && vpnState !== "connected") return pluginApi?.tr("state.blocked")
		return pluginApi?.tr("state." + vpnState)
	}

	function _countryName(code) {
		var rl = main?.relayList || []
		for (var i = 0; i < rl.length; i++) if (rl[i].code === code) return rl[i].country
		return code ? code.toUpperCase() : ""
	}

	// Reactive bindings - QML tracks each property access here
	readonly property string _selectionLabel: {
		var loc = main ? main.currentLocation : null
		var sel = main ? main.relaySelection : null
		var rl = main ? main.relayList : []
		if (vpnState === "connected" && loc && loc.country) {
			var s = _flag(loc.country) + " " + (loc.city || _countryName(loc.country))
			if (loc.hostname) s += " / " + loc.hostname
			return s.trim()
		}
		if (sel && sel.country) {
			var t = _flag(sel.country) + " " + _countryName(sel.country)
			if (sel.city) t += " / " + sel.city
			if (sel.hostname) t += " / " + sel.hostname
			return t.trim()
		}
		return pluginApi?.tr("action.auto-select")
	}

	Rectangle {
		id: panelContainer
		anchors.fill: parent
		color: "transparent"
	}

	ColumnLayout {
		id: contentColumn
		anchors.fill: parent
		anchors.margins: Style.marginL
		spacing: Style.marginM

		// Header Box
		NBox {
			id: headerBox
			Layout.fillWidth: true
			Layout.preferredHeight: headerLayout.implicitHeight + Style.margin2M

			RowLayout {
				id: headerLayout
				anchors.fill: parent
				anchors.margins: Style.marginM
				spacing: Style.marginS

				MullvadIcon {
					pointSize: Style.fontSizeXL
					applyUiScale: true
					crossed: root.vpnState === "error" || !root.installed
					color: Color.mPrimary
					visible: root.currentView === "main"
				}

				NIconButton {
					icon: "arrow-left"
					tooltipText: pluginApi?.tr("panel.back")
					baseSize: Style.baseWidgetSize * 0.8
					visible: root.currentView === "settings"
					onClicked: root.currentView = "main"
				}

				NText {
					text: root.currentView === "main" ? pluginApi?.tr("panel.title") : pluginApi?.tr("panel.settings")
					pointSize: Style.fontSizeL
					font.weight: Style.fontWeightBold
					color: Color.mOnSurface
					Layout.fillWidth: true
				}

				// Settings button
				NIconButton {
					icon: "settings"
					tooltipText: pluginApi?.tr("panel.settings")
					baseSize: Style.baseWidgetSize * 0.8
					visible: root.currentView === "main"
					onClicked: root.currentView = "settings"
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

		// Scrollable content area
		ScrollView {
			id: scrollView
			Layout.fillWidth: true
			Layout.fillHeight: true
			clip: true
			ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
			ScrollBar.vertical.policy: ScrollBar.AsNeeded

			ColumnLayout {
				id: scrollColumn
				width: scrollView.width
				spacing: Style.marginM

				// Connection Status Box
				NBox {
					id: statusBox
					visible: root.currentView === "main"
					Layout.fillWidth: true
					Layout.preferredHeight: statusLayout.implicitHeight + Style.margin2M

					ColumnLayout {
						id: statusLayout
						anchors.fill: parent
						anchors.margins: Style.marginM
						spacing: Style.marginM

						NLabel {
							label: root._stateLabel()
							Layout.leftMargin: Style.marginXS
						}

						RowLayout {
							visible: !!(root.main?.currentLocation?.ipv4)
							spacing: Style.marginXS
							Layout.leftMargin: Style.marginS

							NText {
								text: root.main?.currentLocation?.ipv4 || ""
								font.family: Settings.data.ui.fontFixed
								pointSize: Style.fontSizeS
								color: Color.mOnSurfaceVariant
							}

							NIconButton {
								icon: "copy"
								baseSize: Style.baseWidgetSize * 0.6
								tooltipText: pluginApi?.tr("action.copy-ip")
								onClicked: {
									if (root.main?.currentLocation?.ipv4) {
										Quickshell.clipboardText = root.main.currentLocation.ipv4
										ToastService.showNotice(pluginApi?.tr("toast.title"), root.main.currentLocation.ipv4, "copy")
									}
								}
							}
						}

						NText {
							Layout.fillWidth: true
							Layout.leftMargin: Style.marginS
							pointSize: Style.fontSizeS
							color: Color.mOnSurfaceVariant
							wrapMode: Text.Wrap

							readonly property var _m: root.main
							readonly property var _loc: _m ? _m.currentLocation : null
							readonly property var _sel: _m ? _m.relaySelection : null
							readonly property bool _mh: _m ? _m.multihop : false
							readonly property string _mhe: _m ? (_m.multihopEntry || "") : ""
							readonly property string _iv: _m ? (_m.ipVersion || "any") : "any"
							readonly property bool _ld: _m ? _m.lockdownMode : false
							readonly property bool _ac: _m ? _m.autoConnect : false
							readonly property string _lan: _m ? (_m.lanSharing || "allow") : "allow"

							text: {
								var parts = []
								if (root.vpnState === "connected" && _loc && _loc.country) {
									var s = (_loc.city || root._countryName(_loc.country))
									if (_loc.hostname) s += " / " + _loc.hostname
									parts.push(s)
								} else if (_sel && _sel.country) {
									var t = root._countryName(_sel.country)
									if (_sel.city) t += " / " + _sel.city
									if (_sel.hostname) t += " / " + _sel.hostname
									parts.push(t)
								} else {
									parts.push(root.pluginApi?.tr("action.auto-select"))
								}
								if (_mh) parts.push(_mhe ? root.pluginApi?.tr("badges.multihop-via", { country: root._countryName(_mhe) }) : root.pluginApi?.tr("badges.multihop"))
								if (_iv !== "any") parts.push(root.pluginApi?.tr("badges.ip-version", { version: _iv }))
								if (_ld) parts.push(root.pluginApi?.tr("badges.lockdown"))
								if (_ac) parts.push(root.pluginApi?.tr("badges.auto-connect"))
								if (_lan === "block") parts.push(root.pluginApi?.tr("badges.lan-blocked"))
								return parts.join(" · ")
							}
						}

						NButton {
							Layout.fillWidth: true
							text: root.vpnState === "connected"
								? pluginApi?.tr("action.disconnect")
								: (root.vpnState === "connecting" ? pluginApi?.tr("action.cancel") : pluginApi?.tr("action.connect"))
							enabled: root.installed
							onClicked: root.main?.toggleVpn()
						}

						// Account expiry warning
						NBox {
							id: expiryWarningBox
							visible: root.installed && root.main?.accountDaysLeft !== undefined && root.main.accountDaysLeft <= (root.main?.expiryWarningDays ?? 7)
							Layout.fillWidth: true
							Layout.preferredHeight: expiryText.implicitHeight + Style.margin2M
							color: Color.mError

							NText {
								id: expiryText
								anchors.fill: parent
								anchors.margins: Style.marginM
								text: (root.main?.accountDaysLeft ?? 0) <= 0
									? pluginApi?.tr("account.expired")
									: pluginApi?.tr("account.expires-in", { days: root.main?.accountDaysLeft ?? 0 })
								color: Color.mOnError
								wrapMode: Text.Wrap
							}
						}
					}
				}

				// Settings / Toggles Box
				NBox {
					id: togglesBox
					visible: root.currentView === "settings"
					Layout.fillWidth: true
					Layout.preferredHeight: togglesLayout.implicitHeight + Style.margin2M

					ColumnLayout {
						id: togglesLayout
						anchors.fill: parent
						anchors.margins: Style.marginM
						spacing: Style.marginM

						NLabel {
							label: pluginApi?.tr("panel.settings")
							Layout.leftMargin: Style.marginXS
						}

						NToggle {
							Layout.fillWidth: true
							label: pluginApi?.tr("toggles.lockdown")
							description: pluginApi?.tr("toggles.lockdown-tooltip")
							checked: root.main?.lockdownMode ?? false
							onToggled: checked => root.main?.setLockdown(checked)
						}

						NToggle {
							Layout.fillWidth: true
							label: pluginApi?.tr("toggles.auto-connect")
							description: pluginApi?.tr("toggles.auto-connect-tooltip")
							checked: root.main?.autoConnect ?? false
							onToggled: checked => root.main?.setAutoConnect(checked)
						}

						NToggle {
							Layout.fillWidth: true
							label: pluginApi?.tr("toggles.lan")
							description: pluginApi?.tr("toggles.lan-tooltip")
							checked: (root.main?.lanSharing ?? "allow") === "allow"
							onToggled: checked => root.main?.setLanSharing(checked)
						}

						NToggle {
							Layout.fillWidth: true
							label: pluginApi?.tr("toggles.multihop")
							description: pluginApi?.tr("toggles.multihop-tooltip")
							checked: root.main?.multihop ?? false
							onToggled: checked => root.main?.setMultihop(checked)
						}

						NComboBox {
							Layout.fillWidth: true
							visible: root.main?.multihop ?? false
							label: pluginApi?.tr("toggles.multihop-entry")
							model: (root.main?.relayList || []).map(function (c) { return ({ key: c.code, name: c.country }) })
							currentKey: root.main?.multihopEntry ?? ""
							onSelected: key => root.main?.setMultihopEntry(key)
						}

						NComboBox {
							Layout.fillWidth: true
							label: pluginApi?.tr("toggles.ip-version")
							model: [
								{ key: "any", name: "any" },
								{ key: "v4", name: "v4" },
								{ key: "v6", name: "v6" }
							]
							currentKey: root.main?.ipVersion ?? "any"
							onSelected: key => root.main?.setIpVersion(key)
						}
					}
				}

				// Relay Picker Box
				NBox {
					id: relayBox
					visible: root.currentView === "main"
					Layout.fillWidth: true
					Layout.preferredHeight: relayLayout.implicitHeight + Style.margin2M

					ColumnLayout {
						id: relayLayout
						anchors.fill: parent
						anchors.margins: Style.marginM
						spacing: Style.marginM

						NLabel {
							label: pluginApi?.tr("panel.relays")
							Layout.leftMargin: Style.marginXS
						}

						RowLayout {
							Layout.fillWidth: true
							spacing: Style.marginS

							NTextInput {
								id: searchInput
								Layout.fillWidth: true
								placeholderText: pluginApi?.tr("relay.search-placeholder")
								onTextChanged: relayModel.refresh()
							}

							NIconButton {
								icon: "refresh"
								tooltipText: pluginApi?.tr("action.refresh-relays")
								onClicked: root.main?.refreshRelayList()
							}
						}

						NButton {
							Layout.fillWidth: true
							text: pluginApi?.tr("action.auto-select")
							onClicked: {
								root.main?.setLocation("", "", "")
								if (root.main?.relayClickConnects ?? true) root.main?.connectVpn()
							}
						}

						NListView {
							id: relayListView
							Layout.fillWidth: true
							Layout.preferredHeight: 160
							clip: true
							model: relayModel
							spacing: Style.marginXXS
							horizontalPolicy: ScrollBar.AlwaysOff
							verticalPolicy: ScrollBar.AsNeeded

							delegate: NBox {
								width: relayListView.width
								height: Math.round(40 * Style.uiScaleRatio)

								color: {
									if (model.isCurrent) {
										return rowMouse.containsMouse ? Qt.alpha(Color.mPrimary, 0.25) : Qt.alpha(Color.mPrimary, 0.15)
									} else {
										return rowMouse.containsMouse ? Qt.alpha(Color.mOnSurface, 0.08) : Color.mSurface
									}
								}

								RowLayout {
									anchors.fill: parent
									anchors.leftMargin: Style.marginM
									anchors.rightMargin: Style.marginM
									spacing: Style.marginS

									NText {
										id: rowText
										Layout.fillWidth: true
										text: model.label
										pointSize: Style.fontSizeS
										color: model.isCurrent ? Color.mPrimary : Color.mOnSurface
										elide: Text.ElideRight
									}

									NText {
										visible: model.kind === "country"
										text: String(model.count)
										pointSize: Style.fontSizeXS
										color: Color.mOnSurfaceVariant
									}
								}

								MouseArea {
									id: rowMouse
									anchors.fill: parent
									hoverEnabled: true
									cursorShape: Qt.PointingHandCursor
									onClicked: relayModel.activate(index)
								}
							}

							NText {
								visible: relayModel.count === 0
								anchors.centerIn: parent
								text: (root.main?.relayList?.length ?? 0) === 0
									? pluginApi?.tr("relay.loading")
									: pluginApi?.tr("relay.no-results")
								color: Color.mOnSurfaceVariant
							}
						}
					}
				}
			}
		}
	}

	ListModel {
		id: relayModel

		function refresh() {
			clear()
			var query = (searchInput.text || "").toLowerCase().trim()
			var rl = root.main?.relayList || []
			var fav = root.main?.favoriteCountries || []
			var sel = root.main?.relaySelection || { country: "", city: "", hostname: "" }

			function matches(c, ci, h) {
				if (!query) return true
				var hay = (c.country + " " + c.code + " " +
					(ci ? ci.city + " " + ci.code : "") + " " +
					(h ? h.name : "")).toLowerCase()
				return hay.indexOf(query) !== -1
			}

			var ordered = rl.slice()
			ordered.sort(function (a, b) {
				var af = fav.indexOf(a.code) !== -1, bf = fav.indexOf(b.code) !== -1
				if (af !== bf) return af ? -1 : 1
				return a.country.localeCompare(b.country)
			})

			for (var i = 0; i < ordered.length; i++) {
				var c = ordered[i]
				if (!matches(c, null, null) && !c.cities.some(function (ci) {
						return matches(c, ci, null) || ci.hostnames.some(function (h) { return matches(c, ci, h) })
					})) continue

				append({
					"kind": "country",
					"flag": root._flag(c.code),
					"label": c.country,
					"countryCode": c.code,
					"cityCode": "",
					"hostname": "",
					"count": c.cities.reduce(function (n, ci) { return n + ci.hostnames.length }, 0),
					"isCurrent": sel.country === c.code && !sel.city
				})

				if (!query) continue   // collapsed by default

				for (var j = 0; j < c.cities.length; j++) {
					var ci = c.cities[j]
					if (!matches(c, ci, null) && !ci.hostnames.some(function (h) { return matches(c, ci, h) })) continue
					append({
						"kind": "city",
						"flag": "  " + root._flag(c.code),
						"label": "  " + ci.city,
						"countryCode": c.code,
						"cityCode": ci.code,
						"hostname": "",
						"count": ci.hostnames.length,
						"isCurrent": sel.country === c.code && sel.city === ci.code && !sel.hostname
					})
					for (var k = 0; k < ci.hostnames.length; k++) {
						var h = ci.hostnames[k]
						if (!matches(c, ci, h)) continue
						append({
							"kind": "host",
							"flag": "    ",
							"label": "    " + h.name + "  " + h.ipv4,
							"countryCode": c.code,
							"cityCode": ci.code,
							"hostname": h.name,
							"count": 0,
							"isCurrent": sel.hostname === h.name
						})
					}
				}
			}
		}

		function activate(index) {
			if (index < 0 || index >= count) return
			var row = get(index)
			root.main?.setLocation(row.countryCode, row.cityCode, row.hostname)
			if (root.main?.relayClickConnects ?? true) root.main?.connectVpn()
		}
	}

	Connections {
		target: root.main
		function onRelayListChanged() { relayModel.refresh() }
		function onRelayListReadyChanged() { relayModel.refresh() }
		function onRelaySelectionChanged() { relayModel.refresh() }
		function onFavoriteCountriesChanged() { relayModel.refresh() }
	}

	onVisibleChanged: if (visible) {
		root.currentView = "main"
		relayModel.refresh()
		// Re-fetch in case the list isn't loaded yet
		if ((main?.relayList?.length ?? 0) === 0) main?.refreshRelayList()
	}

	Component.onCompleted: relayModel.refresh()
}
