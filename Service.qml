import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Runs the plugin doctor once when the shell loads. A half-installed plugin
// (missing symlinks, config blocks, or mpvpaper) tells the user exactly what
// is missing instead of failing silently. A healthy install stays quiet.
Item {
  id: root

  // omarchy-shell injects this into first-party services. Unused here; declared
  // so the loader has somewhere to put it.
  property var shell: null

  // Wherever this plugin was installed. The script is called by absolute path
  // so nothing depends on ~/.local/bin being on the shell's PATH.
  readonly property string pluginDir: String(Qt.resolvedUrl("."))
    .replace(/^file:\/\//, "")
    .replace(/\/$/, "")

  Component.onCompleted: doctorProcess.running = true

  Process {
    id: doctorProcess
    command: [root.pluginDir + "/bin/omarchy-pip-video", "doctor", "--on-load"]
  }
}
