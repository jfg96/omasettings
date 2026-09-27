import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

// A duration stored in seconds but edited in whole minutes.
SettingRow {
  id: minutesRow
  property int seconds: 0
  signal committed(int mins)

  readonly property int currentMinutes: Math.max(1, Math.round(seconds / 60))
  readonly property int shownMinutes: minutesSlider.dragging ? Math.round(minutesSlider.liveValue) : effective

  // Keep the desired value until this mutation is explicitly reconciled.
  property int pending: currentMinutes
  readonly property int effective: mutationPending ? pending : currentMinutes

  navKeys: [{ key: "\u2190\u2192", label: "Adjust" }]

  function commit(next) {
    var wanted = Math.max(1, Math.min(60, Math.round(next)))
    if (wanted === minutesRow.effective) return
    if (!beginMutation()) return
    minutesRow.pending = wanted
    minutesRow.committed(wanted)
  }

  onNavStep: function(delta) {
    minutesRow.commit(minutesRow.effective + delta)
  }

  Row {
    width: parent.width
    spacing: Style.space(10)

    PanelSlider {
      id: minutesSlider
      width: parent.width - minutesReadout.width - Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      integer: true
      step: 1
      minimum: 1
      maximum: 60
      enabled: minutesRow.enabled && !minutesRow.mutationPending
      value: minutesRow.effective
      onReleased: function(v) { minutesRow.commit(v) }
    }

    Text {
      id: minutesReadout
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(76)
      horizontalAlignment: Text.AlignRight
      text: minutesRow.shownMinutes + (minutesRow.shownMinutes === 1 ? " min" : " mins")
      color: Local.Palette.muted
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
