import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

SettingRow {
  id: switchRow
  property bool checked: false
  signal requested(bool next)

  // A write takes a state refresh to come back, and a press inside that window
  // would read a `checked` that has not moved yet — so it asks for the value
  // the last press asked for, and a switch the reader has just turned back
  // sits there saying on. So the row answers from what it last asked for and
  // shows that until the state says otherwise, which is the arrangement
  // NumberRow keeps for a number that has not come back.
  property bool basis: checked
  property bool desired: checked
  property bool stepping: false
  readonly property bool effective: stepping ? desired : checked

  function flip() {
    var next = !switchRow.effective
    switchRow.basis = switchRow.checked
    switchRow.desired = next
    switchRow.stepping = true
    switchRow.requested(next)
  }

  onCheckedChanged: {
    if (!switchRow.stepping) return
    // The state has caught up with what was asked, or it has answered
    // something else again — a live page moved under us, a rule took the
    // setting back. Either way the row stops guessing and shows it.
    if (switchRow.checked === switchRow.desired || switchRow.checked !== switchRow.basis)
      switchRow.stepping = false
  }

  // A write that complained was not applied, whatever it was for: the row
  // stops guessing there and then rather than sitting on a value the system
  // refused. Without this a refused write would leave the knob showing what
  // was asked for until something else moved it.
  Connections {
    target: switchRow.nav
    function onLastErrorChanged() { switchRow.stepping = false }
  }

  // Space or Enter flips it, the way clicking it would.
  onNavActivate: switchRow.flip()
  navKeys: [{ key: "Space", label: "Toggle" }]

  ToggleSwitch {
    anchors.right: parent.right
    checked: switchRow.effective
    foreground: Local.Palette.foreground
    accent: Local.Palette.accent
    interactive: switchRow.enabled
    onToggled: switchRow.flip()
  }
}
