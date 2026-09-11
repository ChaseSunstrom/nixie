// The nixie shell: one Quickshell process. Bar, launcher (apps, files,
// calculator, emoji, clipboard), notification centre, OSDs, power menu,
// window switcher and the keybind cheat-sheet. Colours come from
// /etc/nixie/desktop/tokens.json; requests arrive over an IPC socket from
// `nixie-shell <verb>`.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower

ShellRoot {
  id: root
  property var t: ({})
  property string mode: ""        // "", launcher, notifications, power, switcher, cheatsheet, osd
  property string launcherMode: "apps"
  property string osdKind: ""
  property real osdValue: 0
  property string query: ""
  property var results: []
  property int selected: 0
  property var notifs: []

  FileView { id: tokens; path: "/etc/nixie/desktop/tokens.json"; onLoaded: root.t = JSON.parse(text()) }

  function col(k, fb) { return root.t[k] || fb }
  function open(m, sub) { root.mode = m; if (sub) root.launcherMode = sub; root.query = ""; root.selected = 0; refresh() }
  function close() { root.mode = "" }
  function refresh() {
    if (root.mode !== "launcher") return
    if (root.launcherMode === "apps") {
      var q = root.query.toLowerCase()
      root.results = DesktopEntries.applications.values.filter(a => !a.noDisplay && (a.name.toLowerCase().includes(q) || (a.comment||"").toLowerCase().includes(q))).slice(0, 9).map(a => ({ label: a.name, hint: a.comment || "", run: () => a.execute() }))
    } else if (root.launcherMode === "calculator") {
      calc.command = ["sh", "-c", "qalc -t '" + root.query.replace(/'/g, "") + "' 2>/dev/null || echo ''"]; calc.running = true
    } else if (root.launcherMode === "clipboard") {
      clip.command = ["sh", "-c", "cliphist list | head -50"]; clip.running = true
    } else if (root.launcherMode === "files") {
      files.command = ["sh", "-c", "fd -H -d 4 . \"$HOME\" 2>/dev/null | grep -i -- '" + root.query.replace(/'/g, "") + "' | head -12"]; files.running = true
    } else if (root.launcherMode === "emoji") {
      emoji.command = ["sh", "-c", "grep -i -- '" + root.query.replace(/'/g, "") + "' /etc/nixie/desktop/emoji.txt | head -12"]; emoji.running = true
    }
  }
  Process { id: calc; stdout: StdioCollector { onStreamFinished: root.results = text.trim() ? [{ label: text.trim(), hint: "copy", run: () => Quickshell.execDetached(["sh", "-c", "printf %s '" + text.trim() + "' | wl-copy"]) }] : [] } }
  Process { id: clip; stdout: StdioCollector { onStreamFinished: root.results = text.trim().split("\n").filter(l => l && l.toLowerCase().includes(root.query.toLowerCase())).slice(0, 12).map(l => ({ label: l.replace(/^\d+\t/, ""), hint: "paste", run: () => Quickshell.execDetached(["sh", "-c", "printf %s '" + l.split("\t")[0] + "\t' | cliphist decode | wl-copy"]) })) } }
  Process { id: files; stdout: StdioCollector { onStreamFinished: root.results = text.trim().split("\n").filter(l => l).map(l => ({ label: l, hint: "open", run: () => Quickshell.execDetached(["xdg-open", l]) })) } }
  Process { id: emoji; stdout: StdioCollector { onStreamFinished: root.results = text.trim().split("\n").filter(l => l).map(l => ({ label: l, hint: "copy", run: () => Quickshell.execDetached(["sh", "-c", "printf %s '" + l.split(" ")[0] + "' | wl-copy"]) })) } }

  // `nixie-shell <verb>` connects here; the server must be active to bind.
  SocketServer {
    active: true
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/nixie-shell.sock"
    handler: Socket {
      parser: SplitParser {
        onRead: msg => {
          var a = msg.trim().split(" ")
          if (a[0] === "launcher") root.open("launcher", a[1] || "apps")
          else if (a[0] === "clipboard" || a[0] === "emoji" || a[0] === "calculator" || a[0] === "files") root.open("launcher", a[0])
          else if (a[0] === "osd") { root.osdKind = a[1]; root.osdValue = parseFloat(a[2] || "0"); root.mode = "osd"; osdTimer.restart() }
          else if (a[0] === "toggle") root.mode = root.mode === a[1] ? "" : a[1]
          else root.open(a[0])
        }
      }
    }
  }
  Timer { id: osdTimer; interval: 1600; onTriggered: if (root.mode === "osd") root.mode = "" }

  NotificationServer {
    id: ns
    onNotification: n => { n.tracked = true; root.notifs = [n].concat(root.notifs).slice(0, 30); popup.show(n) }
  }

  // ---------------------------------------------------------------- bar
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; left: true; right: true }
      implicitHeight: 34
      color: "transparent"
      WlrLayershell.namespace: "nixie-shell"
      Rectangle {
        anchors.fill: parent; color: root.col("s1", "#292d33"); border.color: root.col("line", "#383e46"); border.width: 1; radius: 0
        RowLayout {
          anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 14
          Text { text: "nixie"; color: root.col("ink", "#eceae5"); font.family: "Archivo"; font.weight: Font.DemiBold; font.pixelSize: 14; font.letterSpacing: -0.4 }
          Row {
            spacing: 4
            Repeater {
              model: Hyprland.workspaces
              Rectangle {
                required property var modelData
                width: 22; height: 20; radius: 3
                color: modelData.active ? root.col("brand", "#5277c3") : "transparent"
                Text { anchors.centerIn: parent; text: modelData.id; color: modelData.active ? "#fff" : root.col("muted", "#9a9ea6"); font.family: "JetBrains Mono"; font.pixelSize: 11 }
                MouseArea { anchors.fill: parent; onClicked: Hyprland.dispatch("workspace " + modelData.id) }
              }
            }
          }
          Text { Layout.fillWidth: true; elide: Text.ElideRight; text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""; color: root.col("muted", "#9a9ea6"); font.family: "Archivo"; font.pixelSize: 12 }
          Row {
            spacing: 6
            Repeater {
              model: SystemTray.items
              Image { required property var modelData; width: 16; height: 16; source: modelData.icon; MouseArea { anchors.fill: parent; onClicked: modelData.activate() } }
            }
          }
          Text { text: (Pipewire.defaultAudioSink ? Math.round(Pipewire.defaultAudioSink.audio.volume * 100) + "%" : "") ; color: root.col("muted", "#9a9ea6"); font.family: "JetBrains Mono"; font.pixelSize: 11 }
          Text { visible: UPower.displayDevice.isLaptopBattery; text: Math.round(UPower.displayDevice.percentage * 100) + "%" + (UPower.onBattery ? "" : " ⚡"); color: UPower.displayDevice.percentage < 0.15 ? root.col("err", "#f08a86") : root.col("muted", "#9a9ea6"); font.family: "JetBrains Mono"; font.pixelSize: 11 }
          Rectangle { width: 8; height: 8; radius: 4; color: root.col("ok", "#8fd6a8"); visible: root.notifs.length > 0; MouseArea { anchors.fill: parent; onClicked: root.open("notifications") } }
          Text { id: clock; color: root.col("ink", "#eceae5"); font.family: "JetBrains Mono"; font.pixelSize: 12; Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: clock.text = Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm") } MouseArea { anchors.fill: parent; onClicked: root.open("notifications") } }
        }
      }
    }
  }

  // --------------------------------------------------------- overlays
  PanelWindow {
    id: overlay
    visible: root.mode !== "" && root.mode !== "osd"
    anchors { top: true; bottom: true; left: true; right: true }
    color: root.col("scrim", "#000000b3")
    WlrLayershell.namespace: "nixie-shell"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    MouseArea { anchors.fill: parent; onClicked: root.close() }
    Rectangle {
      width: root.mode === "cheatsheet" ? 760 : 560; height: root.mode === "cheatsheet" ? 520 : Math.min(480, 60 + root.results.length * 38 + 40)
      anchors.horizontalCenter: parent.horizontalCenter; y: 120
      color: root.col("s1", "#292d33"); border.color: root.col("brand", "#5277c3"); border.width: 1; radius: 8
      MouseArea { anchors.fill: parent }
      // launcher
      Column {
        visible: root.mode === "launcher"; anchors.fill: parent
        Rectangle {
          height: 48; width: parent.width; color: "transparent"
          Row {
            anchors.fill: parent; anchors.margins: 12; spacing: 10
            Text { text: "›"; color: root.col("brand2", "#7ebae4"); font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
            TextInput {
              id: input; width: parent.width - 120; color: root.col("ink", "#eceae5"); font.family: "Archivo"; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter
              focus: root.mode === "launcher"; text: root.query
              onTextChanged: { root.query = text; root.selected = 0; root.refresh() }
              Keys.onEscapePressed: root.close()
              Keys.onDownPressed: root.selected = Math.min(root.results.length - 1, root.selected + 1)
              Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
              Keys.onReturnPressed: if (root.results[root.selected]) { root.results[root.selected].run(); root.close() }
              Keys.onTabPressed: { var m = ["apps", "files", "calculator", "emoji", "clipboard"]; root.launcherMode = m[(m.indexOf(root.launcherMode) + 1) % m.length]; root.refresh() }
            }
            Text { text: root.launcherMode + "  ⇥"; color: root.col("muted", "#9a9ea6"); font.family: "JetBrains Mono"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
          }
        }
        Rectangle { width: parent.width; height: 1; color: root.col("line", "#383e46") }
        Repeater {
          model: root.results
          Rectangle {
            required property var modelData; required property int index
            width: parent.width; height: 38; color: index === root.selected ? root.col("s3", "#31363d") : "transparent"
            Row { anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
              Text { text: modelData.label; color: root.col("ink", "#eceae5"); font.family: "Archivo"; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; width: parent.width - 120 }
              Text { text: modelData.hint; color: root.col("muted", "#9a9ea6"); font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; onClicked: { modelData.run(); root.close() } }
          }
        }
        Text { text: "↑↓ move · ↵ run · ⇥ mode · " + root.results.length + " matches"; color: root.col("muted", "#9a9ea6"); font.pixelSize: 12; padding: 10 }
      }
      // notifications
      Column {
        visible: root.mode === "notifications"; anchors.fill: parent; anchors.margins: 14; spacing: 8
        Row { width: parent.width; Text { text: "Notifications"; color: root.col("ink", "#eceae5"); font.family: "Archivo"; font.pixelSize: 15; font.weight: Font.Medium } Item { width: parent.width - 200; height: 1 } Text { text: "clear all"; color: root.col("brand2", "#7ebae4"); font.pixelSize: 12; MouseArea { anchors.fill: parent; onClicked: { root.notifs.forEach(n => n.dismiss()); root.notifs = [] } } } }
        Repeater {
          model: root.notifs
          Rectangle { required property var modelData; width: parent.width; height: 52; color: root.col("s2", "#181b1e"); radius: 4
            Column { anchors.fill: parent; anchors.margins: 8; Text { text: modelData.summary; color: root.col("ink", "#eceae5"); font.pixelSize: 13; font.weight: Font.Medium } Text { text: modelData.body; color: root.col("muted", "#9a9ea6"); font.pixelSize: 12; elide: Text.ElideRight; width: parent.width } }
            MouseArea { anchors.fill: parent; onClicked: { modelData.dismiss(); root.notifs = root.notifs.filter(n => n !== modelData) } }
          }
        }
        Text { visible: root.notifs.length === 0; text: "nothing new"; color: root.col("muted", "#9a9ea6") }
      }
      // power menu
      Column {
        visible: root.mode === "power"; anchors.centerIn: parent; spacing: 6
        Repeater {
          model: [["Lock", "loginctl lock-session"], ["Suspend", "systemctl suspend"], ["Log out", "uwsm stop"], ["Reboot", "systemctl reboot"], ["Power off", "systemctl poweroff"]]
          Rectangle { required property var modelData; width: 300; height: 38; radius: 3; color: root.col("s2", "#181b1e")
            Text { anchors.centerIn: parent; text: modelData[0]; color: root.col("ink", "#eceae5"); font.pixelSize: 14 }
            MouseArea { anchors.fill: parent; onClicked: { Quickshell.execDetached(["sh", "-c", modelData[1]]); root.close() } }
          }
        }
      }
      // window switcher
      Column {
        visible: root.mode === "switcher"; anchors.fill: parent; anchors.margins: 8
        Repeater {
          model: Hyprland.toplevels
          Rectangle { required property var modelData; width: parent.width; height: 38; radius: 3; color: modelData.activated ? root.col("s3", "#31363d") : "transparent"
            Row { anchors.fill: parent; anchors.margins: 8; spacing: 12
              Text { text: modelData.workspace ? modelData.workspace.id : ""; color: root.col("brand2", "#7ebae4"); font.family: "JetBrains Mono"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
              Text { text: modelData.title; color: root.col("ink", "#eceae5"); font.pixelSize: 13; elide: Text.ElideRight; width: parent.width - 60; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; onClicked: { modelData.activate(); root.close() } }
          }
        }
      }
      // cheat-sheet
      Column {
        visible: root.mode === "cheatsheet"; anchors.fill: parent; anchors.margins: 16; spacing: 4
        Text { text: "Keys"; color: root.col("ink", "#eceae5"); font.family: "Archivo"; font.pixelSize: 15; font.weight: Font.Medium }
        FileView { id: cheat; path: "/etc/nixie/desktop/keys.txt" }
        Text { text: cheat.text(); color: root.col("muted", "#9a9ea6"); font.family: "JetBrains Mono"; font.pixelSize: 12; width: parent.width; wrapMode: Text.Wrap }
      }
    }
  }

  // OSD: volume, brightness, caps lock
  PanelWindow {
    visible: root.mode === "osd"
    anchors { bottom: true }
    margins { bottom: 80 }
    implicitWidth: 260; implicitHeight: 44; color: "transparent"
    WlrLayershell.namespace: "nixie-shell"
    Rectangle { anchors.fill: parent; color: root.col("s1", "#292d33"); border.color: root.col("line", "#383e46"); radius: 6
      Row { anchors.fill: parent; anchors.margins: 12; spacing: 10
        Text { text: root.osdKind; color: root.col("muted", "#9a9ea6"); font.pixelSize: 12; width: 70; anchors.verticalCenter: parent.verticalCenter }
        Rectangle { width: 140; height: 5; radius: 2; color: root.col("s2", "#181b1e"); anchors.verticalCenter: parent.verticalCenter
          Rectangle { width: parent.width * Math.max(0, Math.min(1, root.osdValue / 100)); height: 5; radius: 2; color: root.osdKind === "brightness" ? root.col("hot", "#f0b870") : root.col("cpu", "#7ebae4") } }
        Text { text: Math.round(root.osdValue); color: root.col("ink", "#eceae5"); font.family: "JetBrains Mono"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }

  // notification popup
  PanelWindow {
    id: popup
    property var current: null
    function show(n) { current = n; visible = true; popTimer.restart() }
    visible: false
    anchors { top: true; right: true }
    margins { top: 44; right: 12 }
    implicitWidth: 360; implicitHeight: 64; color: "transparent"
    WlrLayershell.namespace: "nixie-shell"
    Timer { id: popTimer; interval: 5000; onTriggered: popup.visible = false }
    Rectangle { anchors.fill: parent; color: root.col("s1", "#292d33"); border.color: root.col("line", "#383e46"); radius: 6
      Rectangle { width: 3; height: parent.height - 12; y: 6; x: 6; radius: 2; color: root.col("brand2", "#7ebae4") }
      Column { anchors.fill: parent; anchors.margins: 12; anchors.leftMargin: 18
        Text { text: popup.current ? popup.current.summary : ""; color: root.col("ink", "#eceae5"); font.pixelSize: 13; font.weight: Font.Medium }
        Text { text: popup.current ? popup.current.body : ""; color: root.col("muted", "#9a9ea6"); font.pixelSize: 12; elide: Text.ElideRight; width: parent.width }
      }
      MouseArea { anchors.fill: parent; onClicked: popup.visible = false }
    }
  }
}
