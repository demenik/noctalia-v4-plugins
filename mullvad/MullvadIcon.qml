import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets

Item {
	id: root
	property real pointSize: Style.fontSizeL
	property bool applyUiScale: true
	property bool crossed: false
	property color color: Color.mOnSurface

	readonly property real iconSize: Math.max(1, applyUiScale ? root.pointSize * Style.uiScaleRatio : root.pointSize)

	width: iconSize
	height: iconSize
	implicitWidth: iconSize
	implicitHeight: iconSize

	Image {
		id: icon
		anchors.fill: parent
		source: "icons/mullvad.svg"
		fillMode: Image.PreserveAspectFit
		mipmap: true
		smooth: true

		layer.enabled: true
		layer.effect: ShaderEffect {
			property color targetColor: root.color
			property real colorizeMode: 2.0
			fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
		}
	}

	NIcon {
		visible: root.crossed
		anchors.centerIn: parent
		icon: "close"
		pointSize: root.pointSize * 0.7
		applyUiScale: root.applyUiScale
		color: root.color
	}
}
