import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "Hack Nerd Font"
  property bool barVisible: true

  // MPRIS active player
  property var activePlayer: {
    const players = Mpris.players.values;
    if (!players || players.length === 0) return null;
    for (const p of players) {
      if (p.playbackState === MprisPlaybackState.Playing) return p;
    }
    return players[0];
  }

  IpcHandler {
    target: "bar"
    function toggle(): void { root.barVisible = !root.barVisible; }
  }

  PwObjectTracker {
    objects: [Pipewire.defaultAudioSink]
  }

  // Brightness state
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

      implicitWidth: 300
      color: root.theme.bgBase

      Item {
  anchors.fill: parent
  anchors.margins: 8

  ColumnLayout {
    anchors.fill: parent
    spacing: 6

    // workspace
    Rectangle {
      Layout.fillWidth: true
      height: 40
      color: root.theme.bgSurface

      Row {
        anchors.centerIn: parent
        spacing: 4

        Repeater {
          model: Hyprland.workspaces

          Rectangle {
            id: wsPill
            required property var modelData
            property bool urgentBlink: false

            width: 24
            height: 24
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

            Behavior on width { NumberAnimation { duration: 150 } }
          }
        }
      }
    }

    // now playing
    Rectangle {
      Layout.fillWidth: true
      height: 48
      color: root.theme.bgSurface
      visible: root.activePlayer !== null

      Column {
        anchors.centerIn: parent
        spacing: 2
        width: parent.width - 24

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.activePlayer ? (root.activePlayer.trackTitle || "") : ""
          color: root.theme.textPrimary
          font.pixelSize: 12
          font.family: root.font
          elide: Text.ElideRight
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.activePlayer ? (root.activePlayer.trackArtist || "") : ""
          color: root.theme.textSecondary
          font.pixelSize: 10
          font.family: root.font
          elide: Text.ElideRight
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.activePlayer.togglePlaying()
      }
    }

    // spacer
    Item { Layout.fillHeight: true }

// ── 時計（下部、1行） ──
Rectangle {
  Layout.fillWidth: true
  height: 32
  color: root.theme.bgSurface

  Row {
    anchors.centerIn: parent
    spacing: 8

    Text {
      text: Time.timeString
      color: root.theme.textPrimary
      font.pixelSize: 16
      font.bold: true
      font.family: root.font
    }
    Text {
      text: Time.dateString
      color: root.theme.textSecondary
      font.pixelSize: 12
      font.family: root.font
    }
  }
}

  
      RowLayout {
        Layout.fillWidth: true
        spacing: 6

    // ネットワーク
    Rectangle {
      Layout.fillWidth: true
      height: 32
      radius: 8
      color: root.theme.bgSurface

      Row {
        anchors.centerIn: parent
        spacing: 8
        Text {
          text: {
            if (SystemInfo.networkType === "ethernet") return "󰈀"
            if (SystemInfo.networkType === "wifi") return "󰖩"
            return "󰖪"
          }
          color: SystemInfo.networkType === "disconnected" ? root.theme.textMuted : root.theme.accentGreen
          font.pixelSize: 14
          font.family: root.font
        }
        Text {
          text: SystemInfo.networkInfo
          color: root.theme.textPrimary
          font.pixelSize: 12
          font.family: root.font
          elide: Text.ElideRight
        }
      }
    }

    // IME
    Rectangle {
      Layout.fillWidth: true
      height: 32
      radius: 8
      color: root.theme.bgSurface

      Row {
        anchors.centerIn: parent
        spacing: 8
        Text {
          text: "󰌌"
          color: root.theme.accentPrimary
          font.pixelSize: 14
          font.family: root.font
        }
        Text {
          id: imeText
          text: root.imeName
          color: root.theme.textPrimary
          font.pixelSize: 12
          font.family: root.font
        }
      }
    }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
        Layout.preferredWidth: 60
        Layout.fillWidth: false
        height: 32
        color: root.theme.bgSurface

        Row {
          anchors.centerIn: parent
          spacing: 8
          Text {
            text: {
              const sink = Pipewire.defaultAudioSink;
              if (!sink || !sink.audio || sink.audio.muted || sink.audio.volume <= 0) return "󰖁";
              if (sink.audio.volume < 0.33) return "󰕿";
              if (sink.audio.volume < 0.66) return "󰖀";
              return "󰕾";
            }
            color: root.theme.accentPrimary
            font.pixelSize: 14
            font.family: root.font
          }
          Text {
            text: {
              const sink = Pipewire.defaultAudioSink;
              if (!sink || !sink.audio) return "–";
              if (sink.audio.muted) return "Mute";
              return Math.round(sink.audio.volume * 100) + "%";
            }
            color: root.theme.textPrimary
            font.pixelSize: 12
            font.family: root.font
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: {
            const sink = Pipewire.defaultAudioSink;
            if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
          }
          onWheel: (wheel) => {
            const sink = Pipewire.defaultAudioSink;
            if (!sink || !sink.audio) return;
            const delta = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
            sink.audio.volume = Math.max(0, Math.min(1.5, sink.audio.volume + delta));
          }
        }
        }

        Rectangle {
        Layout.preferredWidth: 60
        Layout.fillWidth: false
        height: 32
        color: root.theme.bgSurface
        visible: brightnessFile.path !== ""

        Row {
          anchors.centerIn: parent
          spacing: 8
          Text {
            text: "󰃠"
            color: root.theme.accentOrange
            font.pixelSize: 14
            font.family: root.font
          }
          Text {
            text: Math.round(root.brightnessValue * 100) + "%"
            color: root.theme.textPrimary
            font.pixelSize: 12
            font.family: root.font
          }
        }

        MouseArea {
          anchors.fill: parent
          onWheel: (wheel) => {
            brightnessSetProc.command = wheel.angleDelta.y > 0
              ? ["brightnessctl", "set", "5%+"]
              : ["brightnessctl", "set", "5%-"];
            brightnessSetProc.running = true;
          }
        }
        }

        Rectangle {
        Layout.preferredWidth: 60
        Layout.fillWidth: false
        height: 32
        color: root.theme.bgSurface

        Row {
          anchors.centerIn: parent
          spacing: 8
          Text {
            text: SystemInfo.batteryIcon
            color: {
              if (SystemInfo.batteryCharging) return root.theme.accentGreen;
              if (SystemInfo.batteryLevelRaw > 20) return root.theme.batteryGood;
              if (SystemInfo.batteryLevelRaw > 10) return root.theme.batteryWarning;
              return root.theme.batteryCritical;
            }
            font.pixelSize: 14
            font.family: root.font
          }
          Text {
            text: SystemInfo.batteryLevel
            color: root.theme.textPrimary
            font.pixelSize: 12
            font.family: root.font
          }
        }
        }

// ログアウト
Rectangle {
  Layout.fillWidth: true
  height: 40
  radius: 8
  color: logoutHover.containsMouse ? root.theme.bgHover : root.theme.bgSurface

  Behavior on color { ColorAnimation { duration: 100 } }

  Text {
    anchors.centerIn: parent
    text: "󰍃"
    color: root.theme.textPrimary
    font.pixelSize: 16
    font.family: root.font
  }

  MouseArea {
    id: logoutHover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "exit"])
  }
}

// 電源
Rectangle {
  Layout.fillWidth: true
  height: 40
  radius: 8
  color: powerHover.containsMouse ? root.theme.bgHover : root.theme.bgSurface

  Behavior on color { ColorAnimation { duration: 100 } }

  Text {
    anchors.centerIn: parent
    text: "󰐥"
    color: root.theme.accentRed
    font.pixelSize: 16
    font.family: root.font
  }

  MouseArea {
    id: powerHover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
  }
}
            }
          }
        }
      }
    }
  }
}