import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var manifest: null
  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""

  function run(process, arguments) {
    if (!root.pluginDir || process.running) return
    process.command = [root.pluginDir + "/bin/reomarchy-session"].concat(arguments)
    process.running = true
  }

  // Give Hyprland and the shell time to settle. The restore command detects
  // already-running applications, so enabling the plugin mid-session is safe.
  Timer {
    interval: 4000
    running: true
    repeat: false
    onTriggered: root.run(restoreProcess, ["restore", "--execute", "--startup"])
  }

  // Keep a recent, atomic snapshot. Empty desktops are deliberately ignored
  // by the engine so a logout cannot erase the last useful session.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.run(snapshotProcess, ["snapshot", "--quiet"])
  }

  Process { id: restoreProcess }
  Process { id: snapshotProcess }
}
