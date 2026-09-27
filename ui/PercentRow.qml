import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

// A 0–1 value shown as a percentage.
SettingRow {
  id: percentRow
  property real value: 1
  signal committed(real next)

  // Keep the desired value until this mutation is explicitly reconciled.
  property real pending: value
  readonly property real effective: mutationPending ? pending : value
  readonly property real shown: percentSlider.dragging ? percentSlider.liveValue : effective

  navKeys: [{ key: "\u2190\u2192", label: "Adjust" }]

  function commit(next) {
    var wanted = Math.max(0, Math.min(1, Math.round(next * 100) / 100))
    if (Math.abs(wanted - percentRow.effective) < 0.001) return
    if (!beginMutation()) return
    percentRow.pending = wanted
    percentRow.committed(wanted)
  }

  onNavStep: function(delta) {
    percentRow.commit(percentRow.effective + delta * 0.05)
  }

  Row {
    width: parent.width
    spacing: Style.space(10)

    PanelSlider {
      id: percentSlider
      width: parent.width - percentReadout.width - Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      minimum: 0
      maximum: 1
      step: 0.05
      value: Math.max(0, Math.min(1, percentRow.effective))
      enabled: percentRow.enabled && !percentRow.mutationPending
      onReleased: function(v) { percentRow.commit(v) }
    }

    Text {
      id: percentReadout
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(76)
      horizontalAlignment: Text.AlignRight
      text: Math.round(percentRow.shown * 100) + "%"
      color: Local.Palette.muted
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
