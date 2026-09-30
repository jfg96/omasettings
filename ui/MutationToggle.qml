import QtQuick
import qs.Ui
import "." as Local

// Compact switches use the same lifecycle as SettingRow switches and sliders.
ToggleSwitch {
  id: root
  property var app: null
  property string label: "Setting"
  property bool confirmed: false
  property bool desired: confirmed
  readonly property bool mutationPending: operation.pending
  signal requested(bool next)

  Local.MutationState {
    id: operation
    app: root.app
    label: root.label
  }

  function flip() {
    var next = !confirmed
    if (!enabled || !interactive || !operation.begin(next, function() { return root.confirmed })) return
    desired = next
    requested(next)
  }

  checked: operation.pending ? desired : confirmed
  busy: operation.pending
  onToggled: flip()
}
