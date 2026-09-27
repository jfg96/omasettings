import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

SettingRow {
  id: switchRow
  property bool checked: false
  signal requested(bool next)

  property bool desired: checked
  readonly property bool effective: mutationPending ? desired : checked

  function flip() {
    if (!beginMutation()) return
    desired = !checked
    requested(desired)
  }

  // Space or Enter flips it, the way clicking it would.
  onNavActivate: switchRow.flip()
  navKeys: [{ key: "Space", label: "Toggle" }]

  ToggleSwitch {
    anchors.right: parent.right
    busy: switchRow.mutationPending
    checked: switchRow.effective
    foreground: Local.Palette.foreground
    accent: Local.Palette.accent
    interactive: switchRow.enabled
    onToggled: switchRow.flip()
  }
}
