import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Scope {
  id: root
  property var theme: DefaultTheme {}
  property string font: "Hack Nerd Font"

  IpcHandler {
    target: "launcher"

    function toggle(): void {
      launcherPanel.visible = !launcherPanel.visible
      if (launcherPanel.visible) {
        searchInput.text = ""
        // start with first item selected so Enter works immediately
        root.selectedIndex = 0
        searchInput.forceActiveFocus()
      }
    }
  }

  property int selectedIndex: 0

  // Sort once at startup, not on every keystroke.
  readonly property var allAppsSorted: {
    const all = [...DesktopEntries.applications.values];
    all.sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""));
    return all;
  }

  ScriptModel {
    id: filteredApps
    objectProp: "id"
    values: {
      const q = searchInput.text.trim().toLowerCase();
      if (q === "") return root.allAppsSorted;
      const out = [];
      for (const d of root.allAppsSorted) {
        const name = (d.name ?? "").toLowerCase();
        const generic = (d.genericName ?? "").toLowerCase();
        const keywords = d.keywords ?? [];
        const cats = d.categories ?? [];
        if (
          name.includes(q) ||
          generic.includes(q) ||
          keywords.some(k => k.toLowerCase().includes(q)) ||
          cats.some(c => c.toLowerCase().includes(q))
        ) {
          out.push(d);
        }
      }
      // Stable sort: prefix matches first, then alphabetical.
      out.sort((a, b) => {
        const an = (a.name ?? "").toLowerCase();
        const bn = (b.name ?? "").toLowerCase();
        const ap = an.startsWith(q) ? 0 : 1;
        const bp = bn.startsWith(q) ? 0 : 1;
        if (ap !== bp) return ap - bp;
        return an.localeCompare(bn);
      });
      return out;
    }
  }

  function launchApp(entry) {
    if (!entry) return;
    entry.execute();
    launcherPanel.visible = false;
  }

  PanelWindow {
    id: launcherPanel
    visible: false
    focusable: true
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-launcher"

    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Backdrop click closes
    MouseArea {
      anchors.fill: parent
      onClicked: launcherPanel.visible = false

      Rectangle {
        anchors.fill: parent
        color: root.theme.bgOverlay
      }
    }

    Rectangle {
      id: launcherBox
      anchors.centerIn: parent
      width: 700
      height: 550
      radius: 16
      color: root.theme.bgBase
      border.color: root.theme.bgBorder
      border.width: 1

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Text {
          text: "  Applications"
          color: root.theme.accentPrimary
          font.pixelSize: 14
          font.family: root.font
          font.bold: true
        }

        Rectangle {
          Layout.fillWidth: true
          height: 44
          radius: 10
          color: root.theme.bgSurface
          border.color: searchInput.activeFocus ? root.theme.accentPrimary : root.theme.bgBorder
          border.width: 1

          Behavior on border.color {
            ColorAnimation { duration: 150 }
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10

            Text {
              text: ""
              color: root.theme.textMuted
              font.pixelSize: 16
              font.family: root.font
              Layout.alignment: Qt.AlignVCenter
            }

            TextInput {
              id: searchInput
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              color: root.theme.textPrimary
              font.pixelSize: 15
              font.family: root.font
              clip: true
              // focus is set explicitly by IpcHandler.toggle() -> forceActiveFocus()
              Accessible.role: Accessible.EditableText
              Accessible.name: "Search applications"

              Text {
                anchors.fill: parent
                text: "Type to search..."
                color: root.theme.textMuted
                font: parent.font
                visible: !parent.text && !parent.activeFocus
                verticalAlignment: Text.AlignVCenter
              }

              onTextChanged: {
                // Empty query -> first item selected; non-empty -> first result.
                root.selectedIndex = 0
                resultsList.positionViewAtBeginning()
              }

              Keys.onPressed: event => {
                const count = resultsList.count;

                if (event.key === Qt.Key_Down) {
                  event.accepted = true;
                  if (count > 0)
                    root.selectedIndex = Math.min(root.selectedIndex + 1, count - 1);
                  resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                } else if (event.key === Qt.Key_Up) {
                  event.accepted = true;
                  if (count > 0)
                    root.selectedIndex = Math.max(root.selectedIndex - 1, 0);
                  resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                } else if (event.key === Qt.Key_Tab) {
                  event.accepted = true;
                  if (count > 0)
                    root.selectedIndex = Math.min(root.selectedIndex + 1, count - 1);
                  resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  event.accepted = true;
                  const entry = filteredApps.values[root.selectedIndex];
                  if (entry) root.launchApp(entry);
                } else if (event.key === Qt.Key_Escape) {
                  event.accepted = true;
                  launcherPanel.visible = false;
                }
              }
            }
          }
        }

        Text {
          text: resultsList.count + " application" + (resultsList.count !== 1 ? "s" : "")
          color: root.theme.textMuted
          font.pixelSize: 11
          font.family: root.font
        }

        ListView {
          id: resultsList
          Layout.fillWidth: true
          Layout.fillHeight: true
          model: filteredApps
          clip: true
          spacing: 2
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: root.selectedIndex
          highlightMoveDuration: 150
          highlightMoveVelocity: -1
          cacheBuffer: 400

          highlight: Rectangle {
            radius: 8
            color: root.theme.bgSelected
            visible: root.selectedIndex >= 0

            Rectangle {
              width: 3
              height: 24
              radius: 2
              color: root.theme.accentPrimary
              anchors.left: parent.left
              anchors.leftMargin: 2
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          delegate: Rectangle {
            id: delegateRoot
            required property var modelData
            required property int index

            Accessible.role: Accessible.Button
            Accessible.name: (modelData.name ?? "Application") + (modelData.genericName ? " - " + modelData.genericName : "")

            width: resultsList.width
            height: 44
            radius: 8
            color: "transparent"

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              spacing: 12

              Item {
                width: 28
                height: 28
                Layout.alignment: Qt.AlignVCenter

                IconImage {
                  id: appIcon
                  anchors.fill: parent
                  source: {
                    const i = delegateRoot.modelData.icon ?? "";
                    return i !== "" ? Quickshell.iconPath(i, true) : "";
                  }
                  visible: source !== "" && status !== Image.Error
                }

                Text {
                  anchors.centerIn: parent
                  text: ""
                  color: root.theme.accentPrimary
                  font.pixelSize: 20
                  font.family: root.font
                  visible: !appIcon.visible
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                  text: delegateRoot.modelData.name ?? ""
                  color: root.selectedIndex === delegateRoot.index ? root.theme.textPrimary : root.theme.textSecondary
                  font.pixelSize: 13
                  font.family: root.font
                  font.bold: root.selectedIndex === delegateRoot.index
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Text {
                  text: delegateRoot.modelData.genericName ?? delegateRoot.modelData.comment ?? ""
                  color: root.theme.textMuted
                  font.pixelSize: 11
                  font.family: root.font
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.launchApp(delegateRoot.modelData)
              // Only update selection when actually entering the item,
              // not on every mouse movement (which caused "selection jumping").
              onEntered: root.selectedIndex = delegateRoot.index
            }
          }

          Text {
            anchors.centerIn: parent
            text: "  No applications found"
            color: root.theme.textMuted
            font.pixelSize: 14
            font.family: root.font
            visible: resultsList.count === 0 && searchInput.text !== ""
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 16

          Row {
            spacing: 4
            Rectangle {
              width: hintUp.width + 8; height: 18; radius: 4; color: root.theme.bgSurface
              Text { id: hintUp; anchors.centerIn: parent; text: "↑↓"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
            }
            Text { text: "navigate"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font; anchors.verticalCenter: parent.verticalCenter }
          }

          Row {
            spacing: 4
            Rectangle {
              width: hintEnter.width + 8; height: 18; radius: 4; color: root.theme.bgSurface
              Text { id: hintEnter; anchors.centerIn: parent; text: "⏎"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
            }
            Text { text: "launch"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font; anchors.verticalCenter: parent.verticalCenter }
          }

          Row {
            spacing: 4
            Rectangle {
              width: hintEsc.width + 8; height: 18; radius: 4; color: root.theme.bgSurface
              Text { id: hintEsc; anchors.centerIn: parent; text: "esc"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font }
            }
            Text { text: "close"; color: root.theme.textMuted; font.pixelSize: 10; font.family: root.font; anchors.verticalCenter: parent.verticalCenter }
          }

          Item { Layout.fillWidth: true }
        }
      }
    }
  }
}
