import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Preset pill with an inline remove affordance. The chip itself is a single
// keyboard stop (Enter selects, Delete removes); the × is a pointer shortcut
// that only appears for the selected preset. Corners, fills, and borders come
// from the theme so the pill reads like the rest of the Omarchy kit.
//
// Hover is reported to the panel instead of painting a second highlight: the
// panel moves its one shared cursor here, so the pointer and the keyboard can
// never light two different chips at the same time.
BorderSurface {
  id: root

  property string text: ""
  property bool selected: false
  property bool removable: false
  property bool focusable: true
  property bool hasCursor: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real cornerRadius: Style.cornerRadius

  signal activated()
  signal removeRequested()
  signal hovered(bool isHovered)

  readonly property bool hot: hasCursor && enabled
  readonly property bool showFocusRing: (focusable && activeFocus) || (hasCursor && enabled)
  readonly property color line: Util.alpha(foreground, 0.14)
  readonly property color removeColor: removePointer.containsMouse ? urgent : Qt.darker(foreground, 1.6)
  readonly property int slotHeight: implicitHeight

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.activated()
  Keys.onEnterPressed: if (focusable) root.activated()
  Keys.onSpacePressed: if (focusable) root.activated()
  Keys.onDeletePressed: if (removable) root.removeRequested()

  implicitWidth: content.implicitWidth
  implicitHeight: Math.max(Style.spacing.controlHeight,
    fontSize + Style.spacing.controlPaddingY * 2 + Style.space(2))
  radius: Math.min(cornerRadius, height / 2)
  opacity: enabled ? 1 : 0.4

  color: selected
    ? Style.selectedFillFor(foreground, accent)
    : hot ? Style.hoverFillFor(foreground, accent) : "transparent"
  borderSpec: showFocusRing
    ? Border.flat(Util.alpha(accent, 0.9), Math.max(2, Style.focusBorderWidth))
    : selected
      ? Border.flat(Util.alpha(accent, 0.9), Math.max(1, Style.normalBorderWidth))
      : Border.controlSpec(hot ? "hover-cursor" : "normal", foreground, accent)

  Behavior on color { ColorAnimation { duration: 100 } }

  HoverHandler {
    enabled: root.enabled
    onHoveredChanged: root.hovered(hovered)
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      if (root.focusable) root.forceActiveFocus()
      root.activated()
    }
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 0

    Item {
      width: label.implicitWidth + Style.spacing.controlPaddingX * 2
      height: root.slotHeight

      Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.selected
          ? Style.selectedStateColor(root.foreground, root.accent)
          : root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.bold: root.selected
        textFormat: Text.PlainText
      }
    }

    Rectangle {
      visible: root.removable
      width: visible ? Math.max(1, Style.normalBorderWidth) : 0
      height: Math.max(0, root.slotHeight - Style.space(12))
      anchors.verticalCenter: parent.verticalCenter
      color: root.line
    }

    Item {
      visible: root.removable
      width: visible ? Math.max(Style.space(22), root.fontSize + Style.space(8)) : 0
      height: root.slotHeight

      Text {
        anchors.centerIn: parent
        text: "×"
        color: root.removeColor
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        textFormat: Text.PlainText
        Behavior on color { ColorAnimation { duration: 90 } }
      }

      MouseArea {
        id: removePointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.enabled && root.removable
        onClicked: root.removeRequested()
      }

      PanelToolTip {
        visible: removePointer.containsMouse
        text: "Remove preset · Del / Backspace"
        fontFamily: root.fontFamily
      }
    }
  }
}
