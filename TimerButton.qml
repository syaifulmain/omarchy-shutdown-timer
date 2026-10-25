import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Timer panel button that can either sit quietly on a themed track or carry
// the theme accent as a filled primary action. Colors, corners, borders, and
// text all come from Style/Color so the panel follows the active Omarchy theme
// (including the user's Hyprland `decoration:rounding`).
//
// The panel owns one cursor for keyboard and mouse; this button only paints
// that cursor (`hasCursor`) and reports pointer hover so the panel can move
// the same cursor. It never lights itself from `containsMouse`, otherwise the
// pointer would highlight a second control next to the keyboard cursor.
BorderSurface {
  id: root

  property string text: ""
  property bool filled: false
  property bool bordered: false
  property bool destructive: false
  property bool cursorRing: true
  property bool focusable: true
  property bool hasCursor: false
  property string tooltipText: ""
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real cornerRadius: Style.cornerRadius

  signal clicked()
  signal hovered(bool isHovered)

  readonly property color tone: destructive ? urgent : accent
  readonly property bool hot: hasCursor && enabled
  readonly property bool showFocusRing: (focusable && activeFocus) || (hasCursor && enabled)
  readonly property color onAccent: {
    var luma = 0.299 * tone.r + 0.587 * tone.g + 0.114 * tone.b
    return luma > 0.55 ? Commons.Color.background : foreground
  }
  readonly property color quietText: destructive || hot || showFocusRing
    ? foreground
    : Qt.darker(foreground, 1.45)
  readonly property var ringSpec: Border.flat(
    filled ? onAccent : destructive ? urgent : accent,
    Math.max(2, Style.focusBorderWidth))

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  implicitHeight: Math.max(Style.spacing.controlHeight,
    fontSize + Style.spacing.controlPaddingY * 2 + Style.space(2))
  implicitWidth: label.implicitWidth + horizontalPadding * 2
  radius: Math.min(cornerRadius, height / 2)
  opacity: enabled ? 1 : 0.45

  color: filled
    ? (mouse.pressed ? Qt.darker(tone, 1.12)
      : hot || showFocusRing ? Qt.lighter(tone, 1.08)
      : tone)
    : destructive
      ? (mouse.pressed ? Util.alpha(urgent, 0.20)
        : hot || showFocusRing ? Util.alpha(urgent, 0.14)
        : Util.alpha(urgent, 0.07))
      : (mouse.pressed ? Style.pressedFillFor(foreground, tone, urgent)
        : hot || showFocusRing ? Style.hoverFillFor(foreground, tone, urgent)
        : "transparent")
  borderSpec: showFocusRing && cursorRing
    ? ringSpec
    : bordered
      ? Border.controlSpec(hot ? "hover-cursor" : "normal", foreground, tone, urgent)
      : Border.none()

  Behavior on color { ColorAnimation { duration: 110 } }

  Text {
    id: label
    anchors.centerIn: parent
    width: Math.max(0, parent.width - root.horizontalPadding * 2)
    text: root.text
    color: root.filled ? root.onAccent : root.quietText
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.filled || root.destructive
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.NoWrap
    textFormat: Text.PlainText
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
  }

  HoverHandler {
    enabled: root.enabled
    onHoveredChanged: root.hovered(hovered)
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      if (root.focusable) root.forceActiveFocus()
      root.clicked()
    }
  }
}
