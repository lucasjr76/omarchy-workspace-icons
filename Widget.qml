import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// Workspace indicators where the number is the backdrop and the icons of the
// apps living on that workspace are layered over it. Click and scroll behave
// like the built-in omarchy.workspaces widget.
BarWidget {
  id: root
  moduleName: "lucasjr76.workspace-icons"

  // ------------------------------------------------------------- settings
  readonly property string layoutMode: String(root.setting("layout", "beside"))
  readonly property int minWorkspaces: Math.max(1, Math.min(10, Number(root.setting("minWorkspaces", 5))))
  readonly property int maxIcons: Math.max(1, Math.min(6, Number(root.setting("maxIcons", 3))))
  readonly property int iconSize: Math.max(8, Math.min(32, Number(root.setting("iconSize", 15))))
  readonly property real iconAlpha: clampPercent(root.setting("iconOpacity", 100))
  readonly property real inactiveIconAlpha: clampPercent(root.setting("inactiveIconOpacity", 80))
  // always | inactive | never — "inactive" leaves colour only on the focused
  // workspace, which is what keeps a full bar from turning into confetti.
  readonly property string grayscaleMode: String(root.setting("iconGrayscale", "inactive"))
  readonly property string numberVisibility: String(root.setting("showNumber", "always"))
  readonly property real numberScale: Math.max(1, Math.min(3.2, Number(root.setting("numberScale", 125)) / 100))
  readonly property real numberAlphaOccupied: clampPercent(root.setting("numberOpacityOccupied", 100))
  readonly property real numberAlphaEmpty: clampPercent(root.setting("numberOpacityEmpty", 45))
  readonly property bool numberBold: root.setting("numberBold", true) === true
  readonly property bool hideUnknownIcons: String(root.setting("unknownIcons", "generic")) === "hide"
  readonly property bool hideEmpty: root.setting("hideEmpty", false) === true
  readonly property bool scrollToSwitch: root.setting("scrollToSwitch", true) === true
  readonly property int refreshSeconds: Math.max(0, Math.min(300, Number(root.setting("refreshInterval", 0))))
  readonly property bool debugLogging: root.setting("debug", false) === true

  readonly property bool besideLayout: root.layoutMode === "beside"

  function clampPercent(value) {
    var n = Number(value)
    if (!isFinite(n)) return 1
    return Math.max(0, Math.min(100, n)) / 100
  }

  // ------------------------------------------------------------ workspaces
  // Omarchy gives every monitor its own workspaces 1-10, numbered by Hyprland
  // in a block of ten per monitor: 1-10, 11-20, ... (see
  // default/hypr/monitor-workspaces.lua). Each bar shows its own monitor's
  // block, labelled 1-10, like the built-in omarchy.workspaces widget.
  readonly property int slots: 10

  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""

  // Connector -> block, from the file Hyprland keeps them in.
  property var blocks: ({})

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }

  function blockOf(id) { return Math.floor((id - 1) / root.slots) }
  function slotOf(id) { return (id - 1) % root.slots + 1 }

  function activeWorkspaceId() {
    return root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  }

  // Until Hyprland has written the file, the workspace a monitor shows is in
  // its own block.
  readonly property int block: {
    var block = root.blocks[root.monitorName]
    if (block !== undefined) return block
    var active = root.activeWorkspaceId()
    return active > 0 ? root.blockOf(active) : 0
  }

  // The first minWorkspaces of this monitor's block, any others of the block
  // that exist, then guests: workspaces of an unplugged monitor parked here.
  function workspaceIds() {
    var base = root.block * root.slots
    var ids = []
    for (var n = 1; n <= root.minWorkspaces; n++) ids.push(base + n)
    var guests = []

    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0 || ids.indexOf(id) !== -1) continue
      if (root.hideEmpty && root.workspaceApps(id).length === 0) continue
      if (root.blockOf(id) === root.block) ids.push(id)
      else if (values[i].monitor && values[i].monitor.name === root.monitorName) guests.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    var expression = root.blockOf(id) === root.block
      ? "o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")"
      : "hl.dsp.focus({ workspace = \"" + id + "\" })"
    root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  function cycleWorkspace(delta) {
    var ids = root.workspaceIds()
    var current = root.activeWorkspaceId()
    var index = ids.indexOf(current)
    if (index === -1) index = 0
    var next = index + (delta < 0 ? 1 : -1)
    if (next < 0 || next >= ids.length) return
    root.focusWorkspace(ids[next])
  }

  // ------------------------------------------------------------- app icons
  // Hyprland exposes the app id twice; the wayland toplevel is the live one,
  // lastIpcObject only refreshes on an explicit refreshToplevels().
  function appIdOf(toplevel) {
    if (!toplevel) return ""
    try { if (toplevel.wayland && toplevel.wayland.appId) return String(toplevel.wayland.appId) } catch (e) {}
    try { if (toplevel.lastIpcObject && toplevel.lastIpcObject["class"]) return String(toplevel.lastIpcObject["class"]) } catch (e) {}
    return ""
  }

  // Distinct app ids per workspace, in stacking order, capped at maxIcons.
  //
  // Built from the flat Hyprland.toplevels list rather than from each
  // workspace's own toplevels collection: one source, one place for the model
  // to go stale, and it survives a workspace object being replaced underneath
  // us. Reading t.workspace inside the binding is what makes a window moved
  // between workspaces re-evaluate this.
  readonly property var appsByWorkspace: {
    var map = ({})
    var all = []
    try { all = Hyprland.toplevels.values || [] } catch (e) { return map }

    for (var i = 0; i < all.length; i++) {
      var workspace = null
      try { workspace = all[i].workspace } catch (e) {}
      if (!workspace) continue

      var appId = root.appIdOf(all[i])
      if (appId.length === 0) continue

      var id = workspace.id
      if (map[id] === undefined) map[id] = []
      if (map[id].length < root.maxIcons && map[id].indexOf(appId) === -1) map[id].push(appId)
    }
    return map
  }

  function workspaceApps(id) {
    return root.appsByWorkspace[id] || []
  }

  // Bumped whenever the desktop-entry set or the shell's icon index changes,
  // so icon bindings re-resolve instead of staying stuck on an early miss.
  property int iconRevision: 0

  readonly property var appLibrary: root.bar && root.bar.shell ? root.bar.shell.appLibrary : null

  function lookupEntry(appId) {
    var candidates = [appId, appId.toLowerCase()]
    var dot = appId.lastIndexOf(".")
    if (dot > 0 && dot < appId.length - 1) candidates.push(appId.slice(dot + 1).toLowerCase())

    for (var i = 0; i < candidates.length; i++) {
      var entry = null
      try { entry = DesktopEntries.heuristicLookup(candidates[i]) } catch (e) {}
      if (entry) return entry
      try { entry = DesktopEntries.byId(candidates[i]) } catch (e) {}
      if (entry) return entry
    }

    // Last resort: some entries only declare the window class they spawn.
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) { return null }
    var lower = appId.toLowerCase()
    for (var j = 0; j < values.length; j++) {
      var startupClass = String(values[j].startupClass || "")
      if (startupClass.length > 0 && startupClass.toLowerCase() === lower) return values[j]
    }
    return null
  }

  function iconNameFor(appId) {
    var name = String(appId || "")
    if (name.length === 0) return ""

    var entry = root.lookupEntry(name)
    if (entry && String(entry.icon || "").length > 0) return String(entry.icon)

    // No desktop entry: the app id is often an icon name in its own right.
    var lower = name.toLowerCase()
    var tries = lower === name ? [name] : [name, lower]
    for (var i = 0; i < tries.length; i++) {
      if (root.appLibrary && root.appLibrary.iconIndex[tries[i]]) return tries[i]
      if (Quickshell.iconPath(tries[i], true).length > 0) return tries[i]
    }
    return ""
  }

  function iconSourceFor(appId) {
    var iconName = root.iconNameFor(appId)
    if (iconName.length === 0) {
      if (root.hideUnknownIcons) return ""
      return Quickshell.iconPath("application-x-executable", true)
    }
    if (root.appLibrary) return root.appLibrary.iconSource(iconName)
    return Quickshell.iconPath(iconName, true)
  }

  function appLabel(appId) {
    var entry = root.lookupEntry(appId)
    if (entry && String(entry.name || "").length > 0) return String(entry.name)
    return appId
  }

  function tooltipFor(id, apps) {
    var label = "Workspace " + root.slotOf(id)
    if (apps.length === 0) return label
    var names = []
    for (var i = 0; i < apps.length; i++) names.push(root.appLabel(apps[i]))
    return label + " — " + names.join(", ")
  }

  // Quickshell builds its toplevel model from the Hyprland events it witnesses,
  // so windows that were already open when the shell started are missing from
  // it entirely — a workspace full of long-lived apps renders as empty. An
  // explicit refresh on startup seeds the model, and refreshing again on the
  // events that move windows around keeps it honest.
  function refreshHyprland() {
    try { Hyprland.refreshToplevels() } catch (e) {}
    try { Hyprland.refreshWorkspaces() } catch (e) {}
  }

  Timer {
    id: refreshDebounce
    interval: 150
    onTriggered: root.refreshHyprland()
  }

  // Off by default: across every measurement the toplevel model was correct,
  // so polling for staleness would be guarding a bug that was never observed.
  // Kept as a valve in case a missed event ever does strand a workspace.
  Timer {
    running: root.refreshSeconds > 0
    interval: root.refreshSeconds * 1000
    repeat: true
    onTriggered: root.refreshHyprland()
  }

  // Opt-in tracing for when the bar disagrees with `hyprctl clients`.
  Timer {
    running: root.debugLogging
    interval: 2500
    repeat: true
    onTriggered: {
      var ids = root.workspaceIds()
      var parts = []
      for (var i = 0; i < ids.length; i++) parts.push(ids[i] + ":[" + root.workspaceApps(ids[i]).join(",") + "]")
      var all = Hyprland.toplevels.values || []
      var raw = []
      for (var k = 0; k < all.length; k++) {
        var t = all[k], ws = "?", wl = "?", ipc = "?"
        try { ws = t.workspace ? String(t.workspace.id) : "NULLWS" } catch (e) { ws = "ERR" }
        try { wl = t.wayland ? String(t.wayland.appId) : "NULLWAYLAND" } catch (e) { wl = "ERR" }
        try { ipc = t.lastIpcObject ? String(t.lastIpcObject["class"]) : "NULLIPC" } catch (e) { ipc = "ERR" }
        raw.push("ws" + ws + "/" + wl + "/" + ipc)
      }
      console.log("WSDBG tl=" + all.length + " | " + parts.join(" ") + " | RAW " + raw.join(" ; "))
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      // Deliberately not windowtitle*: titles change constantly (progress
      // spinners, tab switches) and none of it moves a window.
      switch (String(event.name)) {
        case "openwindow":
        case "closewindow":
        case "movewindow":
        case "movewindowv2":
        case "workspace":
        case "workspacev2":
        case "focusedmon":
        case "focusedmonv2":
        case "createworkspace":
        case "createworkspacev2":
        case "destroyworkspace":
        case "destroyworkspacev2":
        case "monitoradded":
        case "monitorremoved":
        // Omarchy renumbers and moves workspaces between monitors; Quickshell
        // only learns either by asking again.
        case "moveworkspace":
        case "moveworkspacev2":
        case "changeworkspaceid":
          try { Hyprland.refreshMonitors() } catch (e) {}
          refreshDebounce.restart()
          break
      }
    }
  }

  Component.onCompleted: root.refreshHyprland()

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.iconRevision++ }
  }

  Connections {
    target: root.appLibrary
    ignoreUnknownSignals: true
    function onIconIndexChanged() { root.iconRevision++ }
  }

  // -------------------------------------------------------------- geometry
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  readonly property real cellPadding: Style.space(3)
  readonly property real iconSpacing: Style.space(2)
  // The gap between workspaces has to read as clearly wider than the gap
  // between the icons inside one, or the eye cannot tell which icons belong
  // to which number.
  readonly property real groupSpacing: Math.max(0, Number(root.setting("groupSpacing", 10)))
  readonly property real numberGap: Style.space(4)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : Math.max(1, root.workspaceIds().length)
    columnSpacing: root.vertical ? 0 : Style.space(root.groupSpacing)
    rowSpacing: root.vertical ? Style.space(root.groupSpacing / 2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: cell
        required property int modelData

        readonly property var apps: root.workspaceApps(modelData)
        readonly property bool occupied: apps.length > 0
        // The workspace this bar's monitor shows, whichever monitor has focus.
        readonly property bool focused: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData

        readonly property color baseColor: focused
          ? (root.bar ? root.bar.urgent : Color.urgent)
          : (root.bar ? root.bar.barForeground : Color.foreground)
        // Behind icons the number drops back a little; alone it stays at the
        // empty-workspace level. Focus always keeps it fully legible.
        readonly property real numberAlpha: occupied
          ? Math.max(root.numberAlphaOccupied, focused ? 1 : 0)
          : (focused ? 1 : root.numberAlphaEmpty)

        // Stacked along the bar's main axis, so a vertical bar puts the icons
        // under the number instead of next to it.
        readonly property bool stacked: root.besideLayout && root.vertical
        readonly property bool sideBySide: root.besideLayout && !root.vertical
        readonly property bool grayscale: root.grayscaleMode === "always"
          || (root.grayscaleMode === "inactive" && !focused)
        // Dropping the number on a busy workspace is an option, not a default:
        // it is the cleanest look but costs you the "jump to 4" muscle memory.
        readonly property bool numberShown: root.numberVisibility === "always" || !occupied

        readonly property real iconsWidth: icons.visible ? icons.implicitWidth : 0
        readonly property real iconsHeight: icons.visible ? icons.implicitHeight : 0
        readonly property real numberWidth: number.visible ? number.implicitWidth : 0
        readonly property real numberHeight: number.visible ? number.implicitHeight : 0
        readonly property real innerGap: number.visible && icons.visible ? root.numberGap : 0
        readonly property real contentWidth: sideBySide
          ? numberWidth + innerGap + iconsWidth
          : Math.max(numberWidth, iconsWidth)
        readonly property real contentHeight: stacked
          ? numberHeight + innerGap + iconsHeight
          : Math.max(numberHeight, iconsHeight)

        bar: root.bar
        text: root.slotOf(modelData) === root.slots ? "0" : String(root.slotOf(modelData))
        fontSize: Math.max(8, Math.round(Style.font.body * root.numberScale))
        // The number is drawn below, so the button's own label stays off.
        labelVisible: false
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Math.max(Style.space(20), contentWidth + root.cellPadding * 2)
        fixedHeight: root.vertical ? Math.max(root.barSize, contentHeight + root.cellPadding * 2) : root.barSize
        tooltipText: root.tooltipFor(modelData, apps)
        onPressed: function() { root.focusWorkspace(modelData) }
        onWheelMoved: function(delta) { if (root.scrollToSwitch) root.cycleWorkspace(delta) }

        Item {
          id: content
          anchors.centerIn: parent
          implicitWidth: cell.contentWidth
          implicitHeight: cell.contentHeight
          width: implicitWidth
          height: implicitHeight

          // Drawn last of the two so the digit sits above the icons; the
          // icons are the wash, the number is the thing you read.
          z: 1

          Grid {
            id: icons
            visible: cell.apps.length > 0
            columns: root.vertical ? 1 : Math.max(1, cell.apps.length)
            rows: root.vertical ? Math.max(1, cell.apps.length) : 1
            spacing: root.iconSpacing
            x: cell.sideBySide ? cell.numberWidth + cell.innerGap : (content.width - implicitWidth) / 2
            y: cell.stacked ? cell.numberHeight + cell.innerGap : (content.height - implicitHeight) / 2

            Repeater {
              model: cell.apps

              Item {
                id: slot
                required property string modelData

                implicitWidth: root.iconSize
                implicitHeight: root.iconSize
                visible: String(iconImage.source).length > 0
                opacity: cell.focused ? root.iconAlpha : root.inactiveIconAlpha

                Image {
                  id: iconImage
                  anchors.fill: parent
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  mipmap: true
                  // Decode at physical pixels; on a fractional-scaled screen
                  // the logical size leaves PNG icons upscaled and blurry.
                  sourceSize.width: Math.round(root.iconSize * Screen.devicePixelRatio)
                  sourceSize.height: Math.round(root.iconSize * Screen.devicePixelRatio)
                  // iconRevision is read so the binding re-runs once the
                  // desktop entry list and the shell icon index finish loading.
                  source: root.iconRevision >= 0 ? root.iconSourceFor(slot.modelData) : ""
                  // Always a hidden layer feeding the effect below. Toggling
                  // layer.enabled to switch grayscale on and off tears down the
                  // texture the effect samples, and it can come back invalid —
                  // the icon then renders as nothing until something forces the
                  // delegate to rebuild. Saturation carries the whole state
                  // instead, so nothing is created or destroyed on focus change.
                  visible: false
                  layer.enabled: true
                }

                MultiEffect {
                  anchors.fill: iconImage
                  source: iconImage
                  saturation: cell.grayscale ? -1.0 : 0.0

                  Behavior on saturation {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                  }
                }

                Behavior on opacity {
                  NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
              }
            }
          }

          Text {
            id: number
            visible: cell.numberShown
            text: cell.text
            color: Qt.rgba(cell.baseColor.r, cell.baseColor.g, cell.baseColor.b, cell.numberAlpha)
            font.family: cell.fontFamily
            font.pixelSize: cell.fontSize
            font.bold: root.numberBold
            renderType: Text.NativeRendering
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            x: cell.sideBySide ? 0 : (content.width - implicitWidth) / 2
            y: cell.stacked ? 0 : (content.height - implicitHeight) / 2

            Behavior on color {
              enabled: !root.bar || root.bar.foregroundAnimationEnabled
              ColorAnimation { duration: 160 }
            }
          }
        }
      }
    }
  }
}
