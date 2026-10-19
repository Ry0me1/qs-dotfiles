import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick.Controls

Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "DaddyTimeMono Nerd Font"
  property bool barVisible: true

  IpcHandler {
    target: "bar"
    function toggle(): void { root.barVisible = !root.barVisible; }
  }

  PwObjectTracker {
    objects: [Pipewire.defaultAudioSink]
  }

  // ── Brightness ─────────────────────────────────────────────────────────
  property real brightnessValue: 0
  property real brightnessMax: 1

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
        if (!isNaN(val) && root.brightnessMax > 0)
          root.brightnessValue = val / root.brightnessMax;
      }
    }
  }

  Process {
    id: brightnessSetProc
    running: false
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
          if (!isNaN(max) && max > 0) root.brightnessMax = max;
          brightnessFile.path = lines[0];
          brightnessReadProc.running = true;
        }
      }
    }
  }

  // ── IME ────────────────────────────────────────────────────────────────
  property string imeName: "IME"

  Process {
    id: imeProc
    command: ["fcitx5-remote", "-n"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const name = text.trim();
        if (name !== "") root.imeName = name;
      }
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: imeProc.running = true
  }

  // ── Shared module chrome ───────────────────────────────────────────────
  // compact 32px-tall row with a hover highlight
  component ModRow: Rectangle {
    id: mod
    property alias content: inner.data
    property bool hovered: hover.hovered

    Layout.fillWidth: true
    implicitHeight: 30
    radius: 4
    color: hover.hovered ? root.theme.bgHover : "transparent"

    Behavior on color { ColorAnimation { duration: 120 } }

    HoverHandler { id: hover }

    RowLayout {
      id: inner
      anchors.centerIn: parent
      spacing: 2
      default property alias _data: inner.data
    }
  }

  // ── Bar ────────────────────────────────────────────────────────────────
  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.barVisible
      anchors {
        top: true
        right: true
        bottom: true
      }

      // 40px + 2×4px inner margin = 48px physical, content stays 40px wide
      implicitWidth: 40 + 8
      color: root.theme.bgBase

      Item {
        anchors.fill: parent
        anchors.margins: 4

        ColumnLayout {
          anchors.fill: parent
          spacing: 4

          // ── Workspaces (vertical pills) ────────────────────────────────
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
              model: Hyprland.workspaces

              Rectangle {
                id: wsPill
                required property var modelData
                property bool urgentBlink: false

                Layout.fillWidth: true
                Layout.preferredHeight: 24
                radius: 4
                color: modelData.focused ? root.theme.accentPrimary :
                       modelData.urgent && urgentBlink ? root.theme.accentRed : root.theme.bgBorder

                Behavior on color { ColorAnimation { duration: 150 } }

                SequentialAnimation {
                  loops: Animation.Infinite
                  running: wsPill.modelData.urgent && !wsPill.modelData.focused
                  PropertyAction { target: wsPill; property: "urgentBlink"; value: true }
                  PauseAnimation { duration: 500 }
                  PropertyAction { target: wsPill; property: "urgentBlink"; value: false }
                  PauseAnimation { duration: 500 }
                  onStopped: wsPill.urgentBlink = false
                }

                Text {
                  anchors.centerIn: parent
                  text: wsPill.modelData.id
                  color: wsPill.modelData.focused ? root.theme.bgBase : root.theme.textPrimary
                  font.pixelSize: 11
                  font.family: root.font
                  font.bold: wsPill.modelData.focused
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: wsPill.modelData.activate()
                }
              }
            }
          }

          // spacer
          Item { Layout.fillHeight: true }

          // ── Clock (2 lines: HH / MM) ───────────────────────────────────
          ModRow {
            implicitHeight: 50
            content: [
              ColumnLayout {
                spacing: 0
                Text {
                  Layout.fillWidth: true
                  horizontalAlignment: Text.AlignHCenter
                  text: Time.timeString ? Time.timeString.slice(0, 2) : ""
                  color: root.theme.textPrimary
                  font.pixelSize: 18
                  font.family: root.font
                  font.bold: true
                }
                Text {
                  Layout.fillWidth: true
                  horizontalAlignment: Text.AlignHCenter
                  text: Time.timeString ? Time.timeString.slice(3, 5) : ""
                  color: root.theme.textPrimary
                  font.pixelSize: 18
                  font.family: root.font
                  font.bold: true
                }
              }
            ]
          }

          // ── Network (icon only, hover = tooltip with SSID) ─────────────────────
ModRow {
  content: [
    Text {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      text: {
        if (SystemInfo.networkType === "ethernet") return "󰈀"
        if (SystemInfo.networkType === "wifi") return "󰖩"
        return "󰖪"
      }
      color: SystemInfo.networkType === "disconnected"
        ? root.theme.textMuted : root.theme.accentGreen
      font.pixelSize: 16
      font.family: root.font
    }
  ]

  ToolTip.visible: hovered
  ToolTip.text: SystemInfo.networkInfo
}

          // ── IME logo (system tray, SystemServices category) ────────────
          ModRow {
            content: [
              Repeater {
                model: SystemTray.items
                delegate: Item {
                  required property var modelData
                  visible: modelData.category === SystemTrayCategory.SystemServices
                  implicitWidth: 20
                  implicitHeight: 20

                  Image {
                    anchors.fill: parent
                    source: modelData.icon
                    sourceSize.width: 20
                    sourceSize.height: 20
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: modelData.activate()
                  }
                }
              }
            ]
          }
            // ── Volume (icon + value, click = mute) ────────────────────────────────
ModRow {
  implicitHeight: 40
  content: [
    ColumnLayout {
      spacing: 0
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: {
          const sink = Pipewire.defaultAudioSink;
          if (!sink || !sink.audio || sink.audio.muted || sink.audio.volume <= 0) return "󰖁";
          if (sink.audio.volume < 0.33) return "󰕿";
          if (sink.audio.volume < 0.66) return "󰖀";
          return "󰕾";
        }
        color: root.theme.accentPrimary
        font.pixelSize: 16
        font.family: root.font
      }
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: {
          const sink = Pipewire.defaultAudioSink;
          if (!sink || !sink.audio) return "–";
          if (sink.audio.muted) return "MUT";
          return Math.round(sink.audio.volume * 100);
        }
        color: root.theme.textPrimary
        font.pixelSize: 16
        font.family: root.font
      }
    }
  ]

            MouseArea {
              anchors.fill: parent
              onClicked: {
                const sink = Pipewire.defaultAudioSink;
                if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
              }
            }
          }

          // ── Backlight (icon + value) ──
ModRow {
  implicitHeight: 40
  visible: brightnessFile.path !== ""
  content: [
    ColumnLayout {
      spacing: 0
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: "󰃠"
        color: root.theme.accentOrange
        font.pixelSize: 16
        font.family: root.font
      }
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: Math.round(root.brightnessValue * 100)
        color: root.theme.textPrimary
        font.pixelSize: 16
        font.family: root.font
      }
    }
  ]
}

          // ── Battery (icon + value) ─────────────────────────────────────────────
ModRow {
  implicitHeight: 40
  content: [
    ColumnLayout {
      spacing: 0
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: SystemInfo.batteryIcon
        color: {
          if (SystemInfo.batteryCharging) return root.theme.accentGreen;
          if (SystemInfo.batteryLevelRaw > 20) return root.theme.batteryGood;
          if (SystemInfo.batteryLevelRaw > 10) return root.theme.batteryWarning;
          return root.theme.batteryCritical;
        }
        font.pixelSize: 16
        font.family: root.font
      }
      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: SystemInfo.batteryLevel
        color: root.theme.textPrimary
        font.pixelSize: 16
        font.family: root.font
      }
    }
  ]
}
        }
      }
    }
  }
}
