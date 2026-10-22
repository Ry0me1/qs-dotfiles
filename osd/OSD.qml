import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "DaddyTimeMono Nerd Font"

  // Which OSD to show: "", "volume", "brightness"
  property string activeOsd: ""
  property real volumeValue: 0
  property bool volumeMuted: false
  property real brightnessValue: 0
  property real maxBrightness: 1
  property bool _brightnessReady: false

  PwObjectTracker {
    objects: [Pipewire.defaultAudioSink]
  }

  Connections {
    target: Pipewire.defaultAudioSink?.audio ?? null

    function onVolumeChanged() {
      root.volumeValue = Pipewire.defaultAudioSink.audio.volume;
      root.activeOsd = "volume";
      osdHideTimer.restart();
    }

    function onMutedChanged() {
      root.volumeMuted = Pipewire.defaultAudioSink.audio.muted;
      root.activeOsd = "volume";
      osdHideTimer.restart();
    }
  }

  // Brightness monitoring
  FileView {
    id: brightnessFile
    path: ""
    watchChanges: true
    onFileChanged: brightnessReadProc.running = true
  }

  Process {
    id: brightnessReadProc
    command: ["brightnessctl", "get"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const val = parseInt(text.trim());
        if (!isNaN(val) && root.maxBrightness > 0) {
          root.brightnessValue = val / root.maxBrightness;
          if (root._brightnessReady) {
            root.activeOsd = "brightness";
            osdHideTimer.restart();
          }
          root._brightnessReady = true;
        }
      }
    }
  }

  Process {
    id: backlightDiscovery
    command: ["sh", "-c", "p=$(ls -d /sys/class/backlight/*/brightness 2>/dev/null | head -1); [ -n \"$p\" ] && echo \"$p\" && cat \"${p%brightness}max_brightness\""]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n");
        if (lines.length >= 2) {
          const max = parseInt(lines[1]);
          if (!isNaN(max) && max > 0) root.maxBrightness = max;
          brightnessFile.path = lines[0];
          brightnessReadProc.running = true;
        }
      }
    }
  }

  Timer {
    id: osdHideTimer
    interval: 1500
    onTriggered: root.activeOsd = ""
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData

      visible: root.activeOsd !== ""
      focusable: false
      color: "transparent"

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.namespace: "quickshell-osd"

      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      // Centered horizontal OSD box
      Rectangle {
        id: osdBox
        anchors.centerIn: parent
        width: 260
        height: 80
        radius: 16
        color: root.theme.bgBase
        border.color: root.theme.bgBorder
        border.width: 1
        opacity: root.activeOsd !== "" ? 1 : 0
        scale: root.activeOsd !== "" ? 1.0 : 0.92

        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 14
          spacing: 8

          RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
              text: {
                if (root.activeOsd === "volume") {
                  if (root.volumeMuted || root.volumeValue <= 0) return "󰖁";
                  if (root.volumeValue < 0.33) return "󰕿";
                  if (root.volumeValue < 0.66) return "󰖀";
                  return "󰕾";
                }
                return "󰃠";
              }
              color: root.activeOsd === "volume"
                ? (root.volumeMuted ? root.theme.textMuted : root.theme.accentPrimary)
                : root.theme.accentOrange
              font.pixelSize: 20
              font.family: root.font
            }

            Text {
              Layout.fillWidth: true
              text: {
                if (root.activeOsd === "volume")
                  return root.volumeMuted ? "Muted" : "Volume";
                return "Brightness";
              }
              color: root.theme.textSecondary
              font.pixelSize: 12
              font.family: root.font
            }

            Text {
              text: {
                if (root.activeOsd === "volume")
                  return root.volumeMuted ? "--" : Math.round(root.volumeValue * 100) + "%";
                return Math.round(root.brightnessValue * 100) + "%";
              }
              color: root.theme.textPrimary
              font.pixelSize: 13
              font.family: root.font
              font.bold: true
            }
          }

          // Horizontal progress bar
          Rectangle {
            Layout.fillWidth: true
            height: 8
            radius: 4
            color: root.theme.bgSurface
            border.color: root.theme.bgBorder
            border.width: 1
            clip: true

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.margins: 1
              width: Math.max(0, (parent.width - 2) * Math.max(0, Math.min(1,
                root.activeOsd === "volume"
                  ? (root.volumeMuted ? 0 : root.volumeValue)
                  : root.brightnessValue)))
              radius: 3
              color: root.activeOsd === "volume"
                ? (root.volumeMuted ? root.theme.textMuted : root.theme.accentPrimary)
                : root.theme.accentOrange

              Behavior on width { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
            }
          }
        }
      }
    }
  }
}
