import QtQuick

// Shared lifecycle for any control: one request, its own reconciliation,
// optional authoritative readback, and cleanup when its owner disappears.
QtObject {
  id: root
  property var app: null
  property string label: "Setting"
  property bool pending: false
  property int mutationId: -1

  function begin(expected, readback) {
    if (pending || !app) return false
    mutationId = app.nextMutationId
    if (readback !== undefined)
      app.expectMutation(mutationId, expected, readback, label)
    pending = true
    return true
  }

  property Connections observer: Connections {
    target: root.app
    function onMutationReconciled(result) {
      if (root.pending && result.id === root.mutationId) root.pending = false
    }
  }

  Component.onDestruction: {
    if (app) app.forgetMutationExpectation(mutationId)
  }
}
