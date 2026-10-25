import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Compact "− 00 +" number field. One themed surface holds three cells split by
// hairlines; the value stays type-editable and Up/Down step it from the
// keyboard. The value is only a display: edits emit `modified(value)` and the
// caller writes the new value back, which keeps preset and normalized-total
// updates flowing in one direction.
Column {
  id: root

  property string label: ""
  property int value: 0
  property int from: 0
  property int to: 999
  property int stepSize: 1
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real fieldHeight: Math.max(
    Style.spacing.controlHeight + Style.space(4),
    fontSize + Style.spacing.controlPaddingY * 2 + Style.space(2))
  property string cursorCell: ""
  property real cornerRadius: Style.cornerRadius

  signal modified(int value)
  signal cellHovered(string cell)
  signal cursorRequested(string cell)
  signal editFinished(int direction)
  signal editCancelled()

  readonly property alias decrementItem: minusButton
  readonly property alias incrementItem: plusButton
  readonly property bool hasCursor: cursorCell !== ""
  readonly property int sideWidth: Math.max(Style.space(26), Math.round(width * 0.24))
  readonly property int separatorWidth: Math.max(1, Style.space(1))
  readonly property int innerRadius: Math.max(0, Math.min(cornerRadius, fieldHeight / 2) - 1)
  readonly property bool focused: input.activeFocus
  readonly property bool editing: input.activeFocus
  readonly property bool focusVisible: focused || hasCursor
  readonly property bool hot: hasCursor && enabled
  readonly property color line: Util.alpha(foreground, 0.12)
  readonly property var borderSpec: focusVisible
    ? Border.flat(Util.alpha(accent, 0.9), Math.max(2, Style.focusBorderWidth))
    : Border.controlSpec("normal", foreground, accent)

  spacing: Style.spacing.labelGap

  function pad(value) {
    var n = Math.max(0, Math.round(Number(value) || 0))
    return (n < 10 ? "0" : "") + n
  }

  function clamp(value) {
    var n = Math.round(Number(value))
    if (!isFinite(n)) return root.value
    return Math.max(root.from, Math.min(root.to, n))
  }

  function commit() {
    var parsed = parseInt(input.text, 10)
    if (!isFinite(parsed)) parsed = root.value
    parsed = root.clamp(parsed)
    input.text = root.pad(parsed)
    if (parsed !== root.value) root.modified(parsed)
  }

  function step(delta) {
    if (!root.enabled) return
    var next = root.clamp(root.value + delta * root.stepSize)
    if (next !== root.value) {
      input.text = root.pad(next)
      root.modified(next)
    }
  }

  function beginEdit() {
    if (!root.enabled) return
    input.forceActiveFocus()
    input.selectAll()
  }

  onValueChanged: {
    // A focused field is normally mid-typing, so only rewrite it when the
    // caller normalized the value to something the text does not show
    // (e.g. 120 minutes rolling into 2 hours).
    var parsed = parseInt(input.text, 10)
    if (!input.activeFocus || parsed !== root.value)
      input.text = root.pad(root.value)
  }

  Text {
    text: root.label
    visible: text !== ""
    color: Qt.darker(root.foreground, 1.55)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.0
    textFormat: Text.PlainText
  }

  BorderSurface {
    id: field
    width: root.width
    height: root.fieldHeight
    radius: Math.min(root.cornerRadius, height / 2)
    color: Style.controlFill(root.focusVisible, root.hot, root.foreground, root.accent)
    borderSpec: root.borderSpec

    WheelHandler {
      onWheel: function(event) {
        if (!root.enabled || event.angleDelta.y === 0) return
        root.step(event.angleDelta.y > 0 ? 1 : -1)
      }
    }

    Row {
      anchors.fill: parent
      spacing: 0

      TimerButton {
        id: minusButton
        width: root.sideWidth
        height: parent.height
        text: "−"
        filled: root.cursorCell === "dec" && enabled
        bordered: false
        focusable: false
        cursorRing: false
        hasCursor: root.cursorCell === "dec"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: root.fontSize
        horizontalPadding: Style.space(2)
        cornerRadius: root.innerRadius
        enabled: root.enabled && root.value > root.from
        onHovered: function(on) { if (on && root.enabled) root.cellHovered("dec") }
        onClicked: {
          root.commit()
          root.cursorRequested("dec")
          root.step(-1)
        }
      }

      Rectangle {
        width: root.separatorWidth
        height: Math.max(0, root.fieldHeight - Style.space(10))
        y: Math.round((parent.height - height) / 2)
        color: root.line
      }

      Item {
        width: Math.max(0, parent.width - root.sideWidth * 2 - root.separatorWidth * 2)
        height: parent.height

        Rectangle {
          anchors.fill: parent
          radius: root.innerRadius
          color: root.cursorCell === "value" && !root.focused
            ? Style.hoverFillFor(root.foreground, root.accent)
            : "transparent"
          Behavior on color { ColorAnimation { duration: 90 } }
        }

        TextInput {
          id: input
          anchors.fill: parent
          text: root.pad(root.value)
          color: root.foreground
          selectionColor: Style.selectionFillFor(root.foreground, root.accent)
          selectedTextColor: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          font.bold: true
          horizontalAlignment: TextInput.AlignHCenter
          verticalAlignment: TextInput.AlignVCenter
          activeFocusOnTab: false
          readOnly: !root.enabled
          inputMethodHints: Qt.ImhDigitsOnly
          validator: IntValidator {
            bottom: root.from
            top: root.to
          }
          onActiveFocusChanged: {
            if (!activeFocus) return
            selectAll()
            root.cursorRequested("value")
          }
          onEditingFinished: root.commit()
          Keys.priority: Keys.BeforeItem
          Keys.onUpPressed: function(event) {
            root.step(1)
            event.accepted = true
          }
          Keys.onDownPressed: function(event) {
            root.step(-1)
            event.accepted = true
          }
          Keys.onReturnPressed: function(event) {
            root.commit()
            root.editFinished(0)
            event.accepted = true
          }
          Keys.onEnterPressed: function(event) {
            root.commit()
            root.editFinished(0)
            event.accepted = true
          }
          Keys.onSpacePressed: function(event) {
            root.commit()
            root.editFinished(0)
            event.accepted = true
          }
          Keys.onEscapePressed: function(event) {
            input.text = root.pad(root.value)
            root.editCancelled()
            event.accepted = true
          }
          Keys.onTabPressed: function(event) {
            root.commit()
            root.editFinished(1)
            event.accepted = true
          }
          Keys.onBacktabPressed: function(event) {
            root.commit()
            root.editFinished(-1)
            event.accepted = true
          }

          HoverHandler {
            enabled: root.enabled
            onHoveredChanged: if (hovered) root.cellHovered("value")
          }
        }
      }

      Rectangle {
        width: root.separatorWidth
        height: Math.max(0, root.fieldHeight - Style.space(10))
        y: Math.round((parent.height - height) / 2)
        color: root.line
      }

      TimerButton {
        id: plusButton
        width: root.sideWidth
        height: parent.height
        text: "+"
        filled: root.cursorCell === "inc" && enabled
        bordered: false
        focusable: false
        cursorRing: false
        hasCursor: root.cursorCell === "inc"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: root.fontSize
        horizontalPadding: Style.space(2)
        cornerRadius: root.innerRadius
        enabled: root.enabled && root.value < root.to
        onHovered: function(on) { if (on && root.enabled) root.cellHovered("inc") }
        onClicked: {
          root.commit()
          root.cursorRequested("inc")
          root.step(1)
        }
      }
    }
  }
}
