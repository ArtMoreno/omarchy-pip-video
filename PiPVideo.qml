import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget: PiP Video controls, settings and how-to-use.
Panel {
  id: root
  moduleName: "artmrn.pip-video"
  ipcTarget: "artmrn.pip-video"
  property string statusVideo: ""
  property string statusOpacity: ""
  property string opacityStep: "0.1"
  property string startMuted: "0"
  property string notice: ""
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/artmrn.pip-video"
  readonly property string cli: pluginDir + "/bin/omarchy-pip-video"
  readonly property var stepOptions: ["0.05", "0.10", "0.15", "0.20"]
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function run(args) {
    if (runProc.running) return
    runProc.command = args
    runProc.running = true
  }
  function helperRun(script, args) {
    root.run([root.pluginDir + "/bin/" + script].concat(args))
    refreshTimer.restart()
  }
  function cliRun(args) {
    root.run([root.cli].concat(args))
    refreshTimer.restart()
  }
  function hyprResize(x, y) {
    root.run(["hyprctl", "dispatch", "hl.dsp.window.resize({ x = " + x + ", y = " + y + ", relative = true, window = \"title:Picture[- ]in[- ]Picture\" })"])
  }
  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!settingsProc.running) settingsProc.running = true
  }
  function setStep(value) {
    root.cliRun(["set", "opacity_step", value])
  }
  function toggleMuted() {
    root.cliRun(["set", "start_muted", root.startMuted === "1" ? "0" : "1"])
  }

  TextMetrics {
    id: iconMetrics
    text: "PiP"
    font.family: "Liberation Sans"
    font.pixelSize: Style.bar.iconFont
    font.bold: true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "PiP Video"
    fixedWidth: vertical ? -1 : Math.ceil(iconMetrics.advanceWidth) + Style.space(12)
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: iconMetrics.text
          color: root.bar.foreground
          font: iconMetrics.font
        }
      }
    }
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(content.implicitHeight + padding * 2 + Style.space(8), Style.space(900))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)
        Text {
          text: "PiP Video"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          text: root.statusVideo + "\n" + root.statusOpacity
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          width: parent.width
        }
        Text {
          text: "Video wallpaper"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Button { text: "Play from clipboard URL"; width: parent.width; onClicked: function() { root.helperRun("video-wallpaper", ["clip"]) } }
        Button { text: "Pause / resume"; width: parent.width; onClicked: function() { root.helperRun("video-wallpaper", ["pause"]) } }
        Button { text: "Mute / unmute"; width: parent.width; onClicked: function() { root.helperRun("video-wallpaper", ["mute"]) } }
        Button { text: "Stop video"; width: parent.width; onClicked: function() { root.helperRun("video-wallpaper", ["stop"]) } }
        Text {
          text: "PiP size"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Button { text: "PiP smaller"; width: parent.width; onClicked: function() { root.hyprResize(-50, -28) } }
        Button { text: "PiP bigger"; width: parent.width; onClicked: function() { root.hyprResize(50, 28) } }
        Button { text: "PiP flatter"; width: parent.width; onClicked: function() { root.hyprResize(0, -30) } }
        Button { text: "PiP taller"; width: parent.width; onClicked: function() { root.hyprResize(0, 30) } }
        Text {
          text: "Workspace fade"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Button { text: "More see-through"; width: parent.width; onClicked: function() { root.helperRun("workspace-opacity", ["down"]) } }
        Button { text: "More opaque"; width: parent.width; onClicked: function() { root.helperRun("workspace-opacity", ["up"]) } }
        Button { text: "Reset transparency"; width: parent.width; onClicked: function() { root.helperRun("workspace-opacity", ["reset"]) } }
        Text {
          text: "Settings"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          text: "Fade step: " + root.opacityStep
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }
        Row {
          spacing: Style.space(8)
          Repeater {
            model: root.stepOptions
            Button {
              text: modelData
              onClicked: function() { root.cliRun(["set", "opacity_step", modelData]) }
            }
          }
        }
        Button { text: "Start muted: " + (root.startMuted === "1" ? "on" : "off"); width: parent.width; onClicked: function() { root.toggleMuted() } }
        Button { text: "Check setup"; width: parent.width; onClicked: function() { root.cliRun(["doctor"]) } }
        Text {
          text: root.notice
          visible: root.notice !== ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          width: parent.width
        }
        Text {
          text: "How to use"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          text: "Pop out a YouTube video, then SUPER+ALT+H/L to resize it (J/U for height) or hold SUPER and pinch the touchpad. Copy a video URL and press SUPER+ALT+V to play it behind all windows, then SUPER+CTRL+[ to fade the workspace and watch it through your apps."
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          width: parent.width
        }
      }
    }
  }

  Process {
    id: runProc
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) root.notice = "Command failed."
    }
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        root.statusVideo = String(lines[0] || "").trim()
        root.statusOpacity = String(lines[1] || "").trim()
      }
    }
  }

  Process {
    id: settingsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = String(lines[i]).split("=")
          if (parts[0] === "opacity_step" && parts[1]) root.opacityStep = String(parts[1]).trim()
          if (parts[0] === "start_muted" && parts[1]) root.startMuted = String(parts[1]).trim()
        }
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    statusProc.command = [root.cli, "status"]
    settingsProc.command = [root.cli, "settings"]
    root.refresh()
  }
}
