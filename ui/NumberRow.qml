import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

// A whole number on a slider, written only when the drag ends.
SettingRow {
  id: numberRow
  property int value: 0
  property int from: 0
  property int to: 100
  property int step: 1
  property string suffix: ""
  signal committed(int next)

  // Keep the desired value until this mutation is explicitly reconciled.
  property int pending: value
  readonly property int effective: mutationPending ? pending : value
  readonly property int shown: numberSlider.dragging ? Math.round(numberSlider.liveValue) : effective

  navKeys: [{ key: "\u2190\u2192", label: "Adjust" }]

  function commit(next) {
    var wanted = Math.max(numberRow.from, Math.min(numberRow.to, Math.round(next)))
    if (wanted === numberRow.effective) return
    if (!beginMutation()) return
    numberRow.pending = wanted
    numberRow.committed(wanted)
  }

  onNavStep: function(delta) {
    numberRow.commit(numberRow.effective + delta * numberRow.step)
  }

  Row {
    width: parent.width
    spacing: Style.space(10)

    PanelSlider {
      id: numberSlider
      width: parent.width - readout.width - Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      integer: true
      step: numberRow.step
      minimum: numberRow.from
      maximum: numberRow.to
      value: numberRow.effective
      enabled: numberRow.enabled && !numberRow.mutationPending
      onReleased: function(v) { numberRow.commit(v) }
    }

    Text {
      id: readout
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(76)
      horizontalAlignment: Text.AlignRight
      text: numberRow.shown + (numberRow.suffix !== "" ? " " + numberRow.suffix : "")
      color: Local.Palette.muted
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
