// The nixie shell: one Quickshell process for the whole desktop. A floating
// bar, an app launcher (apps, files, calculator, emoji, clipboard), a
// notification centre with popups, a control centre (sliders, toggles, media,
// finishes, wallpaper), OSDs, a power menu, a window switcher, a calendar, a
// wallpaper picker and a keybind cheat-sheet. Colours come from the active
// finish's /etc/nixie/desktop/<finish>/tokens.json; requests arrive over an
// IPC socket from `nixie-shell <verb>`. One visual language, one file.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower

ShellRoot {
  id: root

  // ---- theme -------------------------------------------------------------
  property var t: ({})
  property string finish: ""
  property var settings: ({})
  function col(k, fb) { return (root.t[k] !== undefined && root.t[k] !== null) ? root.t[k] : fb }
  property color cBg: col("bg", "#1f2226")
  property color cS1: col("s1", "#292d33")
  property color cS2: col("s2", "#181b1e")
  property color cS3: col("s3", "#31363d")
  property color cLine: col("line", "#383e46")
  property color cLine2: col("line2", "#4a515b")
  property color cInk: col("ink", "#eceae5")
  property color cMuted: col("muted", "#9a9ea6")
  property color cBrand: col("brand", "#5277c3")
  property color cBrand2: col("brand2", "#7ebae4")
  property color cOk: col("ok", "#8fd6a8")
  property color cErr: col("err", "#f08a86")
  property color cHot: col("hot", "#f0b870")
  property bool dark: col("dark", true) === true || col("dark", true) === "true"
  property string uiFont: col("fontUi", "Archivo")
  property string monoFont: col("fontMono", "JetBrains Mono")
  property int radius: root.settings.rounding !== undefined ? root.settings.rounding : 12
  property color accent: cBrand2

  FileView {
    id: tokensFile
    path: "/etc/nixie/desktop/tokens.json"
    watchChanges: true
    onLoaded: root.applyTokens(text())
    onFileChanged: reload()
  }
  FileView {
    id: settingsFile
    path: "/etc/nixie/desktop/settings.json"
    onLoaded: { try { root.settings = JSON.parse(text()) } catch (e) {} }
  }
  function applyTokens(s) {
    try {
      root.t = JSON.parse(s)
      root.finish = root.t.finish || ""
      var a = accentFile.text() ? accentFile.text().trim() : ""
      root.accent = a.match(/^#[0-9a-fA-F]{6}$/) ? a : root.cBrand2
    } catch (e) {}
  }
  FileView { id: accentFile; path: Quickshell.env("HOME") + "/.config/nixie/accent" }
  // When `nixie-shell finish` switches, it points this at the new finish dir.
  FileView {
    id: activeFinish
    path: Quickshell.env("HOME") + "/.config/nixie/finish"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var f = text().trim()
      if (f) tokensFile.path = "/etc/nixie/desktop/" + f + "/tokens.json"
    }
  }

  // Material Symbols Rounded glyphs, by name (codepoints, so the file stays ASCII).
  readonly property var ic: ({
    search: "\ue8b6", wifi: "\ue63e", wifiOff: "\ue648", bt: "\ue1a7",
    volume: "\ue050", volumeOff: "\ue04f", bright: "\ue1ac", moon: "\ue51c",
    battery: "\ue1a4", bell: "\ue7f4", bellOff: "\ue7f6", power: "\ue8ac",
    lock: "\ue897", logout: "\ue9ba", restart: "\uf053", sleep: "\uef44",
    play: "\ue037", pause: "\ue034", next: "\ue044", prev: "\ue045",
    wallpaper: "\ue1bc", dnd: "\ue644", coffee: "\uefF0", camera: "\ue3b0", tune: "\ue429", devices: "\ue1b1"
  })

  // ---- state -------------------------------------------------------------
  property string mode: ""   // "", launcher, notifications, power, switcher, cheatsheet, control, calendar, wallpapers, osd
  property string launcherMode: "apps"
  property string osdKind: ""
  property real osdValue: 0
  property string query: ""
  property var results: []
  property int selected: 0
  property var notifs: []
  property bool dnd: false
  property string notifFirst: ""
  property bool notifTruncated: false
  property bool caffeine: false
  property int cpu: 0
  property int mem: 0
  property int temp: 0
  property var nets: []
  property var bts: []
  property var mixers: []
  property string pendingSsid: ""

  // What the shell is showing, for `nixie-shell` callers and the tests: a
  // small JSON next to the socket, rewritten on every change.
  FileView { id: stateFile; path: Quickshell.env("XDG_RUNTIME_DIR") + "/nixie-shell.state"; blockWrites: true }
  function syncState() {
    if (!stateFile.path) return
    stateFile.setText(JSON.stringify({ mode: root.mode, launcher: root.launcherMode, results: root.results.length,
      first: root.results.length > 0 ? root.results[0].label : "", notifs: root.notifs.length, finish: root.finish, dnd: root.dnd,
      notifFirst: root.notifFirst, notifTruncated: root.notifTruncated, caffeine: root.caffeine,
      cpu: root.cpu, mem: root.mem, nets: root.nets.length, bts: root.bts.length, mixers: root.mixers.length }))
  }
  onModeChanged: syncState()
  onLauncherModeChanged: syncState()
  onResultsChanged: syncState()
  onNotifsChanged: syncState()
  onNotifFirstChanged: syncState()
  onNotifTruncatedChanged: syncState()
  onCaffeineChanged: syncState()
  onNetsChanged: syncState()
  onBtsChanged: syncState()
  onMixersChanged: syncState()
  onFinishChanged: syncState()
  function open(m, sub) { root.mode = m; if (sub) root.launcherMode = sub; root.query = ""; root.selected = 0; refresh() }
  function close() { root.mode = "" }
  function toggle(m) { root.mode = (root.mode === m) ? "" : m; if (root.mode === "launcher") refresh() }

  function refresh() {
    if (root.mode !== "launcher") return
    var q = root.query.toLowerCase()
    if (root.launcherMode === "apps") {
      var favs = (root.settings.favourites || [])
      var all = DesktopEntries.applications.values.filter(a => !a.noDisplay)
      var match = all.filter(a => a.name.toLowerCase().includes(q) || (a.comment || "").toLowerCase().includes(q))
      if (q === "") {
        var favEntries = favs.map(id => all.find(a => a.id === id || (a.id || "").startsWith(id))).filter(a => a)
        var rest = match.filter(a => favs.indexOf(a.id) < 0)
        match = favEntries.concat(rest)
      }
      root.results = match.slice(0, 10).map(a => ({ label: a.name, hint: a.comment || "", icon: a.icon, run: () => a.execute() }))
    } else if (root.launcherMode === "calculator") {
      // An empty expression would drop qalc into its prompt and never return.
      if (root.query.trim() === "") { root.results = []; return }
      run(calc, ["sh", "-c", "qalc -t " + shq(root.query) + " 2>/dev/null </dev/null || echo ''"])
    } else if (root.launcherMode === "clipboard") {
      run(clip, ["sh", "-c", "cliphist list </dev/null | head -80"])
    } else if (root.launcherMode === "files") {
      run(files, ["sh", "-c", "fd -H -d 4 . \"$HOME\" 2>/dev/null | grep -i -- " + shq(root.query) + " | head -14"])
    } else if (root.launcherMode === "emoji") {
      run(emoji, ["sh", "-c", "grep -i -- " + shq(root.query) + " /etc/nixie/desktop/emoji.txt | head -14"])
    }
  }
  // One process per source at a time; a newer request waits for the running
  // one to finish, then replaces it.
  function run(p, cmd) { if (p.running) { p.pending = cmd; return } p.command = cmd; p.running = true }
  component Src: Process {
    property var pending: null
    onRunningChanged: if (!running && pending) { var c = pending; pending = null; command = c; running = true }
  }
  // The desktop-entry scan fills in after the first access; keep the open
  // launcher in step with it.
  Component.onCompleted: DesktopEntries.applications.values.length
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { if (root.mode === "launcher") root.refresh() }
  }
  function shq(s) { return "'" + String(s).replace(/'/g, "") + "'" }
  function copy(s) { Quickshell.execDetached(["sh", "-c", "printf %s " + shq(s) + " | wl-copy"]) }
  function sh(cmd) { Quickshell.execDetached(["sh", "-c", cmd]) }

  Src { id: calc; stdout: StdioCollector { onStreamFinished: root.results = text.trim() ? [{ label: text.trim(), hint: "copy", run: () => root.copy(text.trim()) }] : [] } }
  Src { id: clip; stdout: StdioCollector { onStreamFinished: root.results = text.trim().split("\n").filter(l => l && l.toLowerCase().includes(root.query.toLowerCase())).slice(0, 14).map(l => ({ label: l.replace(/^\d+\t/, ""), hint: "paste", run: () => Quickshell.execDetached(["sh", "-c", "printf %s " + root.shq(l.split("\t")[0]) + " | cliphist decode | wl-copy"]) })) } }
  Src { id: files; stdout: StdioCollector { onStreamFinished: root.results = text.trim().split("\n").filter(l => l).map(l => ({ label: l.replace(Quickshell.env("HOME"), "~"), hint: "open", run: () => Quickshell.execDetached(["xdg-open", l]) })) } }
  Src { id: emoji; stdout: StdioCollector { onStreamFinished: root.results = text.trim().split("\n").filter(l => l).map(l => ({ label: l, hint: "copy", run: () => root.copy(l.split(" ")[0]) })) } }

  // Wallpapers for the picker.
  property var wallpaperList: []
  Process { id: wallProc; stdout: StdioCollector { onStreamFinished: root.wallpaperList = text.trim().split("\n").filter(l => l) } }
  function loadWallpapers() { wallProc.command = ["nixie-shell", "wallpaper", "list"]; wallProc.running = true }
  FileView {
    id: wallpaperFile
    path: Quickshell.env("HOME") + "/.config/nixie/wallpaper"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: if (root.settings.accentFromWallpaper && text().trim()) quantizer.source = "file://" + text().trim()
  }

  // Processor, memory and temperature for the bar.
  Src { id: sysinfo; stdout: StdioCollector { onStreamFinished: {
    var f = text.trim().split(" ")
    if (f.length >= 3) { root.cpu = parseInt(f[0]) || 0; root.mem = parseInt(f[1]) || 0; root.temp = parseInt(f[2]) || 0; root.syncState() }
  } } }
  Timer {
    interval: 5000; running: root.settings.systemReadouts !== false; repeat: true; triggeredOnStart: true
    onTriggered: root.run(sysinfo, ["sh", "-c", "cpu=$(vmstat 1 2 | tail -1 | awk '{print 100-$15}'); mem=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"%d\", (t-a)*100/t}' /proc/meminfo); t=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1); printf '%s %s %s' \"${cpu:-0}\" \"$mem\" \"$(( ${t:-0} / 1000 ))\""])
  }
  // Wi-Fi networks, paired devices and the streams playing right now.
  Src { id: netList; stdout: StdioCollector { onStreamFinished: root.nets = text.trim().split("\n").filter(l => l).map(l => {
    var f = l.split(":"); return { active: f[0] === "*", ssid: f[1], signal: parseInt(f[2]) || 0, secure: (f[3] || "").trim() !== "" }
  }) } }
  Src { id: btList; stdout: StdioCollector { onStreamFinished: root.bts = text.trim().split("\n").filter(l => l).map(l => {
    var i = l.indexOf(" "); return { mac: l.slice(0, i), name: l.slice(i + 1) }
  }) } }
  Src { id: mixerList; stdout: StdioCollector { onStreamFinished: root.mixers = text.trim().split("\n").filter(l => l).map(l => {
    var f = l.split("\t"); return { index: f[0], name: f[1], pct: parseInt(f[2]) || 0 }
  }) } }
  function loadNets() { root.run(netList, ["nixie-shell", "net", "list"]) }
  function loadBts() { root.run(btList, ["nixie-shell", "bt", "list"]) }
  function loadMixers() { root.run(mixerList, ["nixie-shell", "streams", "list"]) }

  // Wallbash: the accent follows the wallpaper when the site asks for it.
  ColorQuantizer {
    id: quantizer
    depth: 3
    rescaleSize: 64
    onColorsChanged: {
      if (!root.settings.accentFromWallpaper || colors.length === 0) return
      var best = colors[0], score = -1
      for (var i = 0; i < colors.length; i++) {
        var c = colors[i]
        var mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b)
        var sat = mx <= 0 ? 0 : (mx - mn) / mx
        var s2 = sat * (0.35 + mx)
        if (s2 > score) { score = s2; best = c }
      }
      root.accent = best
      root.sh("printf %s " + root.shq(String(best)) + " > ~/.config/nixie/accent; hyprctl reload >/dev/null 2>&1 || true")
    }
  }

  // Network and Bluetooth status, polled with the everyday tools.
  property string netLabel: ""
  property bool netUp: false
  property string btLabel: ""
  Process { id: netProc; stdout: StdioCollector { onStreamFinished: { var l = text.trim(); root.netUp = l !== ""; root.netLabel = l || "offline" } } }
  Process { id: btProc; stdout: StdioCollector { onStreamFinished: root.btLabel = text.trim() } }
  Timer {
    interval: 5000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: {
      netProc.command = ["sh", "-c", "nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep -v loopback | head -1 | cut -d: -f1"]; netProc.running = true
      btProc.command = ["sh", "-c", "bluetoothctl devices Connected 2>/dev/null | head -1 | cut -d' ' -f3-"]; btProc.running = true
    }
  }

  // ---- IPC ---------------------------------------------------------------
  SocketServer {
    active: true
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/nixie-shell.sock"
    handler: Socket {
      parser: SplitParser {
        onRead: msg => {
          var a = msg.trim().split(" ")
          if (a[0] === "launcher") root.open("launcher", a[1] || "apps")
          else if (["clipboard", "emoji", "calculator", "files"].indexOf(a[0]) >= 0) root.open("launcher", a[0])
          else if (a[0] === "osd") { root.osdKind = a[1]; root.osdValue = parseFloat(a[2] || "0"); root.mode = "osd"; osdTimer.restart() }
          else if (a[0] === "toggle") root.toggle(a[1])
          else if (a[0] === "close") root.close()
          else if (a[0] === "control") { root.loadWallpapers(); root.toggle("control") }
          else if (a[0] === "wallpapers") { root.loadWallpapers(); root.toggle("wallpapers") }
          else if (a[0] === "network") { root.loadNets(); root.sh("nixie-shell net scan"); root.toggle("network") }
          else if (a[0] === "bluetooth") { root.loadBts(); root.sh("nixie-shell bt scan"); root.toggle("bluetooth") }
          else if (a[0] === "mixer") { root.loadMixers(); root.toggle("mixer") }
          else if (a[0] === "screenshots") root.toggle("screenshot")
          else if (a[0] === "caffeine") root.caffeine = a[1] === "1"
          else if (a[0] === "finish" || a[0] === "wallpaper") { activeFinish.reload() }
          else root.open(a[0])
        }
      }
    }
  }
  Timer { id: osdTimer; interval: 1600; onTriggered: if (root.mode === "osd") root.mode = "" }

  NotificationServer {
    id: ns
    keepOnReload: false
    bodySupported: true
    imageSupported: true
    actionsSupported: true
    onNotification: n => {
      n.tracked = true
      root.notifs = [n].concat(root.notifs).slice(0, 40)
      if (!root.dnd) popup.show(n)
    }
  }

  component IconText: Text {
    property string glyph: ""
    property color color2: root.cInk
    text: glyph; color: color2
    height: 28; verticalAlignment: Text.AlignVCenter
    font.family: "Material Symbols Rounded"; font.pixelSize: 17
  }

  // ---- bar ---------------------------------------------------------------
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: root.settings.barPosition !== "bottom"; bottom: root.settings.barPosition === "bottom"; left: true; right: true }
      implicitHeight: 44
      color: "transparent"
      WlrLayershell.namespace: "nixie-shell"

      Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: root.radius
        color: Qt.rgba(root.cS1.r, root.cS1.g, root.cS1.b, 0.92)
        border.color: root.cLine
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 10
          spacing: 12

          // mark + wordmark
          MouseArea {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: markRow.width; implicitHeight: 24
            onClicked: root.open("launcher", "apps")
            Row {
              id: markRow; spacing: 8; anchors.verticalCenter: parent.verticalCenter
              Canvas {
                id: mark
                width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter
                onPaint: {
                  // Mark 3, "Segment n": two stems under a bar, the right one lit.
                  var c = getContext("2d"); c.reset()
                  c.fillStyle = root.cBrand
                  c.fillRect(2.5, 4.5, 2.5, 11); c.fillRect(2.5, 4.5, 13, 2.5)
                  c.fillStyle = root.accent
                  c.fillRect(13, 4.5, 2.5, 11)
                }
                Connections { target: root; function onAccentChanged() { mark.requestPaint() } function onCBrandChanged() { mark.requestPaint() } }
              }
              Text { text: "nixie"; color: root.cInk; font.family: root.uiFont; font.weight: Font.DemiBold; font.pixelSize: 14; font.letterSpacing: -0.4; anchors.verticalCenter: parent.verticalCenter }
            }
          }

          // workspaces
          Row {
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
            Repeater {
              model: Hyprland.workspaces
              Rectangle {
                required property var modelData
                width: wsLabel.width + 16; height: 22; radius: 6
                property bool active: modelData.active
                color: active ? root.cBrand : root.cS3
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                  id: wsLabel; anchors.centerIn: parent
                  text: {
                    var labels = root.settings.workspaces || []
                    return (labels.length >= modelData.id && modelData.id >= 1) ? labels[modelData.id - 1] : modelData.id
                  }
                  color: parent.active ? "#ffffff" : root.cMuted
                  font.family: root.uiFont; font.pixelSize: 12; font.weight: parent.active ? Font.Medium : Font.Normal
                }
                MouseArea { anchors.fill: parent; onClicked: Hyprland.dispatch("workspace " + modelData.id) }
              }
            }
          }

          // focused window, or what is playing
          Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: {
              var ps = Mpris.players ? Mpris.players.values : []
              var p = ps.find(x => x.isPlaying)
              if (p && p.trackTitle) return "♪ " + p.trackTitle + (p.trackArtist ? " — " + p.trackArtist : "")
              return Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
            }
            color: root.cMuted; font.family: root.uiFont; font.pixelSize: 12
          }

          // processor, memory, temperature
          Row {
            visible: root.settings.systemReadouts !== false
            spacing: 10; Layout.alignment: Qt.AlignVCenter; height: 28
            Text { height: 28; verticalAlignment: Text.AlignVCenter; text: "cpu " + root.cpu + "%"; color: root.cpu > 80 ? root.cHot : root.cMuted; font.family: root.monoFont; font.pixelSize: 11 }
            Text { height: 28; verticalAlignment: Text.AlignVCenter; text: "mem " + root.mem + "%"; color: root.mem > 85 ? root.cHot : root.cMuted; font.family: root.monoFont; font.pixelSize: 11 }
            Text { visible: root.temp > 0; height: 28; verticalAlignment: Text.AlignVCenter; text: root.temp + "°"; color: root.temp > 80 ? root.cErr : root.cMuted; font.family: root.monoFont; font.pixelSize: 11 }
          }

          // tray
          Row {
            spacing: 8; Layout.alignment: Qt.AlignVCenter
            Repeater {
              model: SystemTray.items
              Image {
                required property var modelData
                width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter
                source: modelData.icon
                MouseArea { anchors.fill: parent; onClicked: modelData.activate() }
              }
            }
          }

          // indicators (open the control centre)
          MouseArea {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: pills.width + 8; implicitHeight: 28
            onClicked: { root.loadWallpapers(); root.toggle("control") }
            Row {
              id: pills; anchors.centerIn: parent; spacing: 12; height: 28
              IconText { glyph: root.netUp ? root.ic.wifi : root.ic.wifiOff; color2: root.netUp ? root.cInk : root.cMuted }
              IconText { visible: root.btLabel !== ""; glyph: root.ic.bt }
              IconText { visible: root.caffeine; glyph: root.ic.coffee; color2: root.accent }
              IconText { glyph: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted) ? root.ic.volumeOff : root.ic.volume }
              Row {
                spacing: 3; visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
                IconText { glyph: root.ic.battery; color2: (UPower.displayDevice && UPower.displayDevice.percentage < 0.15) ? root.cErr : root.cInk }
                Text { height: 28; verticalAlignment: Text.AlignVCenter; text: UPower.displayDevice ? Math.round(UPower.displayDevice.percentage * 100) + "%" : ""; color: root.cMuted; font.family: root.monoFont; font.pixelSize: 11 }
              }
            }
          }

          // notifications bell
          MouseArea {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 24; implicitHeight: 24
            onClicked: root.toggle("notifications")
            Text { anchors.centerIn: parent; text: root.dnd ? root.ic.bellOff : root.ic.bell; font.family: "Material Symbols Rounded"; font.pixelSize: 18; color: root.notifs.length > 0 ? root.accent : root.cMuted }
            Rectangle { visible: root.notifs.length > 0; width: 7; height: 7; radius: 4; color: root.cOk; anchors.top: parent.top; anchors.right: parent.right }
          }

          // clock
          MouseArea {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: clockText.implicitWidth + 4; implicitHeight: 24
            onClicked: root.toggle("calendar")
            Text {
              id: clockText; anchors.centerIn: parent
              color: root.cInk; font.family: root.monoFont; font.pixelSize: 12
              Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: clockText.text = Qt.formatDateTime(new Date(), (root.settings.clock && root.settings.clock.format) ? root.settings.clock.format : "ddd d MMM  HH:mm") }
            }
          }
        }
      }
    }
  }

  // ---- overlay scrim + dialogs ------------------------------------------
  PanelWindow {
    id: overlay
    readonly property var ownModes: ["launcher", "notifications", "power", "switcher", "cheatsheet", "control", "calendar", "wallpapers"]
    visible: ownModes.indexOf(root.mode) >= 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: Qt.rgba(0, 0, 0, root.dark ? 0.45 : 0.25)
    WlrLayershell.namespace: "nixie-shell"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    MouseArea { anchors.fill: parent; onClicked: root.close() }
    // Escape closes whatever is open; the launcher's input keeps the focus
    // for everything else. Exactly one of these is enabled at a time.
    Shortcut { sequences: [ "Escape" ]; enabled: overlay.visible; context: Qt.ApplicationShortcut; onActivated: root.close() }
    Item {
      anchors.fill: parent
      focus: overlay.visible && root.mode !== "launcher"
      Keys.onEscapePressed: root.close()
    }

    // launcher / notifications / power / switcher / cheatsheet (centred card)
    Rectangle {
      visible: ["launcher", "notifications", "power", "switcher", "cheatsheet"].indexOf(root.mode) >= 0
      width: root.mode === "cheatsheet" ? 780 : 620
      height: root.mode === "cheatsheet" ? 540 : (root.mode === "launcher" ? Math.min(560, 64 + root.results.length * 44 + 44) : Math.min(560, 64 + Math.max(1, root.mode === "notifications" ? root.notifs.length : 5) * 66 + 24))
      anchors.horizontalCenter: parent.horizontalCenter; y: 110
      color: root.cS1; border.color: root.accent; border.width: 1; radius: root.radius
      MouseArea { anchors.fill: parent }

      // launcher
      Column {
        visible: root.mode === "launcher"; anchors.fill: parent
        Rectangle {
          height: 56; width: parent.width; color: "transparent"
          Row {
            anchors.fill: parent; anchors.margins: 16; spacing: 12
            Text { text: root.ic.search; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: root.accent; anchors.verticalCenter: parent.verticalCenter }
            TextInput {
              id: input; width: parent.width - 160; color: root.cInk; font.family: root.uiFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter
              focus: root.mode === "launcher"; text: root.query
              onTextChanged: { root.query = text; root.selected = 0; root.refresh() }
              Keys.onEscapePressed: root.close()
              Keys.onDownPressed: root.selected = Math.min(root.results.length - 1, root.selected + 1)
              Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
              Keys.onReturnPressed: if (root.results[root.selected]) { root.results[root.selected].run(); root.close() }
              Keys.onTabPressed: { var m = ["apps", "files", "calculator", "emoji", "clipboard"]; root.launcherMode = m[(m.indexOf(root.launcherMode) + 1) % m.length]; root.query = ""; text = ""; root.refresh() }
            }
            Rectangle { width: modeLabel.width + 16; height: 24; radius: 6; color: root.cS2; anchors.verticalCenter: parent.verticalCenter
              Text { id: modeLabel; anchors.centerIn: parent; text: root.launcherMode + "  ⇥"; color: root.cMuted; font.family: root.monoFont; font.pixelSize: 11 } }
          }
        }
        Rectangle { width: parent.width; height: 1; color: root.cLine }
        Repeater {
          model: root.results
          Rectangle {
            required property var modelData; required property int index
            width: parent.width; height: 44; color: index === root.selected ? root.cS3 : "transparent"
            Row { anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
              IconImage { visible: root.launcherMode === "apps"; implicitSize: 24; anchors.verticalCenter: parent.verticalCenter; source: modelData.icon ? Quickshell.iconPath(modelData.icon, "application-x-executable") : "" }
              Text { text: modelData.label; color: root.cInk; font.family: root.uiFont; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; width: parent.width - 200 }
              Text { text: modelData.hint; color: root.cMuted; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; width: 130; horizontalAlignment: Text.AlignRight }
            }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: root.selected = index; onClicked: { modelData.run(); root.close() } }
          }
        }
        Text { text: "↑↓ move · ↵ run · ⇥ mode · " + root.results.length + " matches"; color: root.cMuted; font.pixelSize: 12; padding: 12 }
      }

      // notifications
      Column {
        visible: root.mode === "notifications"; anchors.fill: parent; anchors.margins: 16; spacing: 8
        Row { width: parent.width; spacing: 10
          Text { text: "Notifications"; color: root.cInk; font.family: root.uiFont; font.pixelSize: 16; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
          Item { width: parent.width - 320; height: 1 }
          Text { text: root.dnd ? "DND on" : "DND off"; color: root.dnd ? root.accent : root.cMuted; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter
            MouseArea { anchors.fill: parent; onClicked: root.dnd = !root.dnd } }
          Text { text: "clear all"; color: root.cBrand2; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter
            MouseArea { anchors.fill: parent; onClicked: { root.notifs.forEach(n => n.dismiss()); root.notifs = [] } } }
        }
        Rectangle { width: parent.width; height: 1; color: root.cLine }
        Column {
          width: parent.width; spacing: 6
          Repeater {
            model: root.notifs
            Rectangle {
              id: nCard
              required property var modelData
              required property int index
              width: parent.width; height: 58; color: root.cS2; radius: 8
              Rectangle { id: nBar; width: 3; height: parent.height - 18; radius: 2; color: root.accent; anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter }
              Column {
                spacing: 2
                anchors { left: nBar.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                Text {
                  width: parent.width; text: nCard.modelData.summary
                  color: root.cInk; font.family: root.uiFont; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight
                  onTruncatedChanged: if (nCard.index === 0) root.notifTruncated = truncated
                  Component.onCompleted: if (nCard.index === 0) { root.notifFirst = nCard.modelData.summary + " / " + nCard.modelData.body; root.notifTruncated = truncated }
                }
                Text { width: parent.width; text: nCard.modelData.body; color: root.cMuted; font.family: root.uiFont; font.pixelSize: 12; elide: Text.ElideRight }
              }
              MouseArea { anchors.fill: parent; onClicked: { nCard.modelData.dismiss(); root.notifs = root.notifs.filter(n => n !== nCard.modelData) } }
            }
          }
          Text { visible: root.notifs.length === 0; text: "nothing new"; color: root.cMuted; padding: 8 }
        }
      }

      // power
      Grid {
        visible: root.mode === "power"; anchors.centerIn: parent
        columns: 3; spacing: 8
        Repeater {
          model: [["Lock", root.ic.lock, "loginctl lock-session"], ["Suspend", root.ic.sleep, "systemctl suspend"], ["Log out", root.ic.logout, "uwsm stop"], ["Reboot", root.ic.restart, "systemctl reboot"], ["Power off", root.ic.power, "systemctl poweroff"]]
          Rectangle { required property var modelData; required property int index
            width: 150; height: 90; radius: root.radius; color: index === root.selected ? root.cS3 : root.cS2; border.color: index === root.selected ? root.accent : "transparent"; border.width: 1
            Column { anchors.centerIn: parent; spacing: 8
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[1]; font.family: "Material Symbols Rounded"; font.pixelSize: 28; color: root.cInk }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[0]; color: root.cInk; font.family: root.uiFont; font.pixelSize: 13 }
            }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: root.selected = index; onClicked: { root.sh(modelData[2]); root.close() } }
          }
        }
      }

      // window switcher
      Column {
        visible: root.mode === "switcher"; anchors.fill: parent; anchors.margins: 10
        Repeater {
          model: Hyprland.toplevels
          Rectangle { required property var modelData; width: parent.width; height: 42; radius: 8; color: modelData.activated ? root.cS3 : "transparent"
            Row { anchors.fill: parent; anchors.leftMargin: 12; spacing: 12
              Text { text: modelData.workspace ? modelData.workspace.id : ""; color: root.accent; font.family: root.monoFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter; width: 20 }
              Text { text: modelData.title || "window"; color: root.cInk; font.family: root.uiFont; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width - 60; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; onClicked: { modelData.activate(); root.close() } }
          }
        }
      }

      // cheat-sheet
      Column {
        visible: root.mode === "cheatsheet"; anchors.fill: parent; anchors.margins: 20; spacing: 8
        Text { text: "Keys"; color: root.cInk; font.family: root.uiFont; font.pixelSize: 16; font.weight: Font.Medium }
        FileView { id: cheat; path: "/etc/nixie/desktop/keys.txt" }
        Text { text: cheat.text(); color: root.cMuted; font.family: root.monoFont; font.pixelSize: 12; width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.35 }
      }
    }

    // control centre (top-right panel)
    Rectangle {
      visible: root.mode === "control"
      width: 380; height: cc.height + 32
      anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: 12; anchors.topMargin: 56
      color: root.cS1; border.color: root.cLine; border.width: 1; radius: root.radius
      MouseArea { anchors.fill: parent }
      Column {
        id: cc; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 16; spacing: 14
        Text { text: "Control centre"; color: root.cInk; font.family: root.uiFont; font.pixelSize: 15; font.weight: Font.Medium }
        SliderRow { label: root.ic.volume; value: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) ? Pipewire.defaultAudioSink.audio.volume : 0.5
          onMoved: v => { if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) Pipewire.defaultAudioSink.audio.volume = v } }
        SliderRow { label: root.ic.bright; value: 0.7; onMoved: v => root.sh("brightnessctl -q set " + Math.round(v * 100) + "%") }
        Grid {
          columns: 2; spacing: 8; width: parent.width
          Toggle { glyph: root.netUp ? root.ic.wifi : root.ic.wifiOff; label: root.netUp ? root.netLabel : "Wi-Fi"; on: root.netUp; width: (parent.width - 8) / 2
            onToggled: root.sh("nmcli radio wifi " + (root.netUp ? "off" : "on")) }
          Toggle { glyph: root.ic.bt; label: root.btLabel !== "" ? root.btLabel : "Bluetooth"; on: root.btLabel !== ""; width: (parent.width - 8) / 2
            onToggled: root.sh("rfkill toggle bluetooth") }
          Toggle { glyph: root.ic.dnd; label: "Do not disturb"; on: root.dnd; width: (parent.width - 8) / 2; onToggled: root.dnd = !root.dnd }
          Toggle { glyph: root.ic.moon; label: "Night light"; on: false; width: (parent.width - 8) / 2; onToggled: root.sh("pgrep -x hyprsunset >/dev/null && pkill -x hyprsunset || (hyprsunset -t 4500 &)") }
          Toggle { glyph: root.ic.coffee; label: "Keep awake"; on: root.caffeine; width: (parent.width - 8) / 2; onToggled: root.sh("nixie-shell caffeine") }
          Toggle { glyph: root.ic.camera; label: "Screenshot"; on: false; width: (parent.width - 8) / 2; onToggled: root.open("screenshot") }
        }
        Row {
          spacing: 8; width: parent.width
          PanelBtn { glyph: root.ic.wifi; label: root.netUp ? root.netLabel : "Networks"; width: (parent.width - 16) / 3; onClicked: { root.loadNets(); root.sh("nixie-shell net scan"); root.open("network") } }
          PanelBtn { glyph: root.ic.devices; label: "Devices"; width: (parent.width - 16) / 3; onClicked: { root.loadBts(); root.sh("nixie-shell bt scan"); root.open("bluetooth") } }
          PanelBtn { glyph: root.ic.tune; label: "Mixer"; width: (parent.width - 16) / 3; onClicked: { root.loadMixers(); root.open("mixer") } }
        }
        Rectangle {
          id: mediaCard
          property var player: { var ps = Mpris.players ? Mpris.players.values : []; return ps.find(x => x.isPlaying) || ps[0] || null }
          visible: player !== null
          width: parent.width; height: 56; radius: 8; color: root.cS2
          Row { anchors.fill: parent; anchors.margins: 10; spacing: 10
            Column { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 130
              Text { text: mediaCard.player ? (mediaCard.player.trackTitle || "") : ""; color: root.cInk; font.family: root.uiFont; font.pixelSize: 13; elide: Text.ElideRight; width: parent.width }
              Text { text: mediaCard.player ? (mediaCard.player.trackArtist || "") : ""; color: root.cMuted; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width }
            }
            Row { anchors.verticalCenter: parent.verticalCenter; spacing: 6
              CircleBtn { glyph: root.ic.prev; onClicked: if (mediaCard.player) mediaCard.player.previous() }
              CircleBtn { glyph: (mediaCard.player && mediaCard.player.isPlaying) ? root.ic.pause : root.ic.play; onClicked: if (mediaCard.player) mediaCard.player.togglePlaying() }
              CircleBtn { glyph: root.ic.next; onClicked: if (mediaCard.player) mediaCard.player.next() }
            }
          }
        }
        Row {
          spacing: 8
          Text { text: "Finish"; color: root.cMuted; font.family: root.uiFont; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter; width: 60 }
          Repeater {
            model: root.settings.finishes || ["graphite", "umber", "paper"]
            Rectangle { required property var modelData
              width: 40; height: 28; radius: 6
              color: (root.settings.swatches && root.settings.swatches[modelData]) ? root.settings.swatches[modelData] : root.cS2
              border.color: root.finish === modelData ? root.accent : root.cLine2; border.width: root.finish === modelData ? 2 : 1
              MouseArea { anchors.fill: parent; onClicked: root.sh("nixie-shell finish " + modelData) }
            }
          }
          Item { width: 8; height: 1 }
          CircleBtn { glyph: root.ic.wallpaper; onClicked: { root.loadWallpapers(); root.open("wallpapers") } }
        }
      }
    }

    // calendar (top-right, under the clock)
    Rectangle {
      visible: root.mode === "calendar"
      width: 300; height: 330
      anchors.right: parent.right; anchors.top: parent.top; anchors.rightMargin: 12; anchors.topMargin: 56
      color: root.cS1; border.color: root.cLine; border.width: 1; radius: root.radius
      MouseArea { anchors.fill: parent }
      Column {
        anchors.fill: parent; anchors.margins: 16; spacing: 10
        Text { text: Qt.formatDateTime(new Date(), "HH:mm"); color: root.cInk; font.family: root.monoFont; font.pixelSize: 40 }
        Text { text: Qt.formatDateTime(new Date(), "dddd, d MMMM yyyy"); color: root.cMuted; font.family: root.uiFont; font.pixelSize: 13 }
        Rectangle { width: parent.width; height: 1; color: root.cLine }
        Grid {
          id: calGrid
          columns: 7; spacing: 2; width: parent.width
          property int first: { var d = new Date(); var f = new Date(d.getFullYear(), d.getMonth(), 1).getDay(); return f === 0 ? 6 : f - 1 }
          property int dim: new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).getDate()
          Repeater { model: ["M", "T", "W", "T", "F", "S", "S"]
            Text { required property var modelData; width: (calGrid.width - 12) / 7; horizontalAlignment: Text.AlignHCenter; text: modelData; color: root.cMuted; font.family: root.monoFont; font.pixelSize: 11 } }
          Repeater {
            model: 42
            Rectangle {
              required property int index
              width: (calGrid.width - 12) / 7; height: 30; radius: 6
              property int day: index - calGrid.first + 1
              property bool valid: day >= 1 && day <= calGrid.dim
              property bool today: valid && day === new Date().getDate()
              color: today ? root.cBrand : "transparent"
              Text { anchors.centerIn: parent; visible: parent.valid; text: parent.day; color: parent.today ? "#ffffff" : root.cInk; font.family: root.monoFont; font.pixelSize: 11 }
            }
          }
        }
      }
    }

    // wallpaper picker
    Rectangle {
      visible: root.mode === "wallpapers"
      width: 720; height: 480
      anchors.horizontalCenter: parent.horizontalCenter; y: 90
      color: root.cS1; border.color: root.cLine; border.width: 1; radius: root.radius
      MouseArea { anchors.fill: parent }
      Column {
        anchors.fill: parent; anchors.margins: 16; spacing: 12
        Text { text: "Wallpaper"; color: root.cInk; font.family: root.uiFont; font.pixelSize: 16; font.weight: Font.Medium }
        Grid {
          id: wallGrid
          columns: 3; spacing: 12; width: parent.width
          Repeater {
            model: root.wallpaperList
            Rectangle {
              required property var modelData
              width: (wallGrid.width - 24) / 3; height: width * 0.56; radius: 8; color: root.cS2; clip: true; border.color: root.cLine; border.width: 1
              Image { anchors.fill: parent; source: "file://" + modelData; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 480 }
              MouseArea { anchors.fill: parent; onClicked: { root.sh("nixie-shell wallpaper " + root.shq(modelData)); root.close() } }
            }
          }
        }
      }
    }
  }

  // network, devices, mixer and the screenshot menu
  PanelWindow {
    id: menus
    visible: ["network", "bluetooth", "mixer", "screenshot"].indexOf(root.mode) >= 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: Qt.rgba(0, 0, 0, root.dark ? 0.45 : 0.25)
    WlrLayershell.namespace: "nixie-shell"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    MouseArea { anchors.fill: parent; onClicked: root.close() }
    Shortcut { sequences: [ "Escape" ]; enabled: menus.visible; context: Qt.ApplicationShortcut; onActivated: root.close() }

    Rectangle {
      width: 520
      // The screenshot menu is two rows of tiles, not a list of rows.
      height: root.mode === "screenshot" ? 236 : Math.min(560, 64 + Math.max(1, rowsFor()) * 46 + 20)
      anchors.horizontalCenter: parent.horizontalCenter; y: 110
      color: root.cS1; border.color: root.cLine; border.width: 1; radius: root.radius
      MouseArea { anchors.fill: parent }
      function rowsFor() {
        if (root.mode === "network") return root.nets.length
        if (root.mode === "bluetooth") return root.bts.length
        if (root.mode === "mixer") return root.mixers.length
        return 2
      }

      Column {
        anchors.fill: parent; anchors.margins: 16; spacing: 10
        Text {
          color: root.cInk; font.family: root.uiFont; font.pixelSize: 16; font.weight: Font.Medium
          text: root.mode === "network" ? "Networks" : root.mode === "bluetooth" ? "Devices" : root.mode === "mixer" ? "Volume by app" : "Screenshot"
        }
        Rectangle { width: parent.width; height: 1; color: root.cLine }

        // Wi-Fi
        Column {
          visible: root.mode === "network"; width: parent.width; spacing: 4
          Repeater {
            model: root.nets
            Rectangle {
              required property var modelData
              width: parent.width; height: 42; radius: 8; color: modelData.active ? root.cS3 : "transparent"
              Row {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                Text { height: parent.height; verticalAlignment: Text.AlignVCenter; text: root.ic.wifi; font.family: "Material Symbols Rounded"; font.pixelSize: 17; color: modelData.signal > 55 ? root.cInk : root.cMuted }
                Text { height: parent.height; verticalAlignment: Text.AlignVCenter; width: parent.width - 190; elide: Text.ElideRight; text: modelData.ssid; color: root.cInk; font.family: root.uiFont; font.pixelSize: 13 }
                Text { height: parent.height; verticalAlignment: Text.AlignVCenter; text: modelData.secure ? root.ic.lock : ""; font.family: "Material Symbols Rounded"; font.pixelSize: 14; color: root.cMuted }
                Text { height: parent.height; verticalAlignment: Text.AlignVCenter; text: modelData.signal + "%"; color: root.cMuted; font.family: root.monoFont; font.pixelSize: 11 }
              }
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  if (modelData.secure && !modelData.active) { root.pendingSsid = modelData.ssid; psk.text = ""; psk.forceActiveFocus() }
                  else { root.sh("nixie-shell net connect " + root.shq(modelData.ssid)); root.close() }
                }
              }
            }
          }
          Text { visible: root.nets.length === 0; text: "looking for networks…"; color: root.cMuted; padding: 8 }
          Rectangle {
            visible: root.pendingSsid !== ""
            width: parent.width; height: 42; radius: 8; color: root.cS2
            Row {
              anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
              Text { height: parent.height; verticalAlignment: Text.AlignVCenter; text: "password"; color: root.cMuted; font.family: root.uiFont; font.pixelSize: 12 }
              TextInput {
                id: psk
                height: parent.height; width: parent.width - 130; verticalAlignment: Text.AlignVCenter
                echoMode: TextInput.Password; color: root.cInk; font.family: root.uiFont; font.pixelSize: 13
                Keys.onReturnPressed: { root.sh("nixie-shell net connect " + root.shq(root.pendingSsid) + " " + root.shq(text)); root.pendingSsid = ""; root.close() }
              }
            }
          }
        }

        // Bluetooth
        Column {
          visible: root.mode === "bluetooth"; width: parent.width; spacing: 4
          Repeater {
            model: root.bts
            Rectangle {
              required property var modelData
              width: parent.width; height: 42; radius: 8; color: "transparent"
              Row {
                anchors.fill: parent; anchors.leftMargin: 10; spacing: 10
                Text { height: parent.height; verticalAlignment: Text.AlignVCenter; text: root.ic.bt; font.family: "Material Symbols Rounded"; font.pixelSize: 17; color: root.cInk }
                Text { height: parent.height; verticalAlignment: Text.AlignVCenter; width: parent.width - 80; elide: Text.ElideRight; text: modelData.name; color: root.cInk; font.family: root.uiFont; font.pixelSize: 13 }
              }
              MouseArea { anchors.fill: parent; onClicked: { root.sh("nixie-shell bt connect " + root.shq(modelData.mac)); root.close() } }
            }
          }
          Text { visible: root.bts.length === 0; text: "no paired devices yet; scanning…"; color: root.cMuted; padding: 8 }
        }

        // Per-app volume
        Column {
          visible: root.mode === "mixer"; width: parent.width; spacing: 6
          Repeater {
            model: root.mixers
            Item {
              required property var modelData
              width: parent.width; height: 42
              Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 140; elide: Text.ElideRight; text: modelData.name; color: root.cInk; font.family: root.uiFont; font.pixelSize: 13 }
              Rectangle {
                id: mTrack
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 160; height: 6; radius: 3; color: root.cS2
                Rectangle { width: mTrack.width * Math.max(0, Math.min(1, modelData.pct / 100)); height: 6; radius: 3; color: root.accent }
                MouseArea {
                  anchors.fill: parent; anchors.margins: -8
                  onClicked: mouse => { var v = Math.round(Math.max(0, Math.min(1, (mouse.x - 8) / mTrack.width)) * 100); root.sh("nixie-shell streams set " + modelData.index + " " + v); root.loadMixers() }
                }
              }
            }
          }
          Text { visible: root.mixers.length === 0; text: "nothing is playing"; color: root.cMuted; padding: 8 }
        }

        // Screenshot
        Grid {
          visible: root.mode === "screenshot"; columns: 2; spacing: 8
          Repeater {
            model: [["Region", "region"], ["Window", "window"], ["Whole screen", "screen"], ["After 5 seconds", "delay"]]
            Rectangle {
              required property var modelData
              width: 236; height: 72; radius: root.radius; color: root.cS2
              Row {
                anchors.centerIn: parent; spacing: 10
                Text { text: root.ic.camera; font.family: "Material Symbols Rounded"; font.pixelSize: 22; color: root.cInk }
                Text { text: modelData[0]; color: root.cInk; font.family: root.uiFont; font.pixelSize: 13 }
              }
              MouseArea { anchors.fill: parent; onClicked: { root.close(); root.sh("nixie-shell screenshot " + modelData[1]) } }
            }
          }
        }
      }
    }
  }

  component PanelBtn: Rectangle {
    id: panelBtn
    property string glyph: ""
    property string label: ""
    signal clicked()
    height: 44; radius: 8; color: root.cS2
    Column {
      anchors.centerIn: parent; spacing: 2
      Text { anchors.horizontalCenter: parent.horizontalCenter; text: panelBtn.glyph; font.family: "Material Symbols Rounded"; font.pixelSize: 17; color: root.cInk }
      Text { anchors.horizontalCenter: parent.horizontalCenter; text: panelBtn.label; color: root.cMuted; font.family: root.uiFont; font.pixelSize: 10; elide: Text.ElideRight; width: panelBtn.width - 12; horizontalAlignment: Text.AlignHCenter }
    }
    MouseArea { anchors.fill: parent; onClicked: panelBtn.clicked() }
  }

  component SliderRow: Item {
    id: sliderRow
    property string label: ""
    property real value: 0.5
    signal moved(real v)
    width: parent ? parent.width : 340; height: 28
    Row {
      anchors.fill: parent; spacing: 12
      Text { text: sliderRow.label; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: root.cInk; anchors.verticalCenter: parent.verticalCenter; width: 24 }
      Rectangle {
        id: track
        width: parent.width - 40; height: 6; radius: 3; color: root.cS2; anchors.verticalCenter: parent.verticalCenter
        Rectangle { width: track.width * Math.max(0, Math.min(1, sliderRow.value)); height: 6; radius: 3; color: root.accent }
        MouseArea { anchors.fill: parent; anchors.margins: -8
          onPositionChanged: mouse => { if (pressed) sliderRow.moved(Math.max(0, Math.min(1, (mouse.x - 8) / track.width))) }
          onClicked: mouse => sliderRow.moved(Math.max(0, Math.min(1, (mouse.x - 8) / track.width))) }
      }
    }
  }

  component Toggle: Rectangle {
    id: toggleBox
    property string glyph: ""
    property string label: ""
    property bool on: false
    signal toggled()
    height: 52; radius: 8; color: on ? root.cBrand : root.cS2
    Row { anchors.fill: parent; anchors.margins: 10; spacing: 8
      Text { text: toggleBox.glyph; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: toggleBox.on ? "#ffffff" : root.cInk; anchors.verticalCenter: parent.verticalCenter }
      Text { text: toggleBox.label; color: toggleBox.on ? "#ffffff" : root.cInk; font.family: root.uiFont; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width - 34; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea { anchors.fill: parent; onClicked: toggleBox.toggled() }
  }

  component CircleBtn: Rectangle {
    id: circleBtn
    property string glyph: ""
    signal clicked()
    width: 32; height: 32; radius: 16; color: root.cS3
    Text { anchors.centerIn: parent; text: circleBtn.glyph; font.family: "Material Symbols Rounded"; font.pixelSize: 18; color: root.cInk }
    MouseArea { anchors.fill: parent; onClicked: circleBtn.clicked() }
  }

  // ---- OSD ---------------------------------------------------------------
  PanelWindow {
    visible: root.mode === "osd"
    anchors { bottom: true }
    margins { bottom: 96 }
    implicitWidth: 280; implicitHeight: 48; color: "transparent"
    WlrLayershell.namespace: "nixie-shell"
    Rectangle { anchors.fill: parent; color: root.cS1; border.color: root.cLine; radius: root.radius
      Row { anchors.fill: parent; anchors.margins: 14; spacing: 12
        Text { text: root.osdKind === "brightness" ? root.ic.bright : root.ic.volume; font.family: "Material Symbols Rounded"; font.pixelSize: 22; color: root.cInk; anchors.verticalCenter: parent.verticalCenter }
        Rectangle { width: 150; height: 6; radius: 3; color: root.cS2; anchors.verticalCenter: parent.verticalCenter
          Rectangle { width: parent.width * Math.max(0, Math.min(1, root.osdValue / 100)); height: 6; radius: 3; color: root.osdKind === "brightness" ? root.cHot : root.accent } }
        Text { text: Math.round(root.osdValue); color: root.cInk; font.family: root.monoFont; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }

  // ---- notification popup -----------------------------------------------
  PanelWindow {
    id: popup
    property var current: null
    function show(n) { current = n; visible = true; popTimer.restart() }
    visible: false
    anchors { top: true; right: true }
    margins { top: 52; right: 14 }
    implicitWidth: 380; implicitHeight: 76; color: "transparent"
    WlrLayershell.namespace: "nixie-shell"
    Timer { id: popTimer; interval: 5000; onTriggered: popup.visible = false }
    Rectangle { anchors.fill: parent; color: root.cS1; border.color: root.cLine; radius: root.radius
      Rectangle { id: pBar; width: 3; height: parent.height - 24; radius: 2; color: root.accent; anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter }
      Column {
        spacing: 2
        anchors { left: pBar.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        Text { width: parent.width; text: popup.current ? popup.current.summary : ""; color: root.cInk; font.family: root.uiFont; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight }
        Text { width: parent.width; text: popup.current ? popup.current.body : ""; color: root.cMuted; font.family: root.uiFont; font.pixelSize: 12; elide: Text.ElideRight }
      }
      MouseArea { anchors.fill: parent; onClicked: popup.visible = false }
    }
  }
}
