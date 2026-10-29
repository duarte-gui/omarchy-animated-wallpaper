import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The bar button for the animated wallpaper. It owns the settings (inline in
// shell.json) and drives bin/wallpaper-video, which owns the mpvpaper process.
//
// Left click turns the wallpaper on or off, right click picks the video folder,
// middle click skips to the next video.
BarWidget {
  id: root
  moduleName: "io.github.duarte-gui.animated-wallpaper"

  // The bar builds one widget per monitor. Only the one on the first screen
  // drives the engine, so two displays do not start two players.
  readonly property var hostWindow: root.QsWindow ? root.QsWindow.window : null
  readonly property bool isLeader: !hostWindow || !hostWindow.screen
    || Quickshell.screens.length === 0
    || String(hostWindow.screen.name) === String(Quickshell.screens[0].name)

  readonly property string engine: decodeURIComponent(Qt.resolvedUrl("bin/wallpaper-video").toString().replace(/^file:\/\//, ""))
  readonly property string home: Quickshell.env("HOME") || ""

  readonly property string videoDir: String(setting("videoDir", "~/Videos/Wallpapers"))
  readonly property bool wantOn: setting("enabled", false) === true
  readonly property bool shuffle: setting("order", "sequential") === "shuffle"
  readonly property bool pauseWhenHidden: setting("pauseWhenHidden", true) === true
  readonly property string mpvOptions: String(setting("mpvOptions", ""))

  // Everything that changes what mpvpaper should be doing. When it differs from
  // what was last applied, the engine is told again.
  readonly property string desiredKey: [wantOn, expandPath(videoDir), shuffle, pauseWhenHidden, mpvOptions].join("\u0001")
  property string appliedKey: ""
  property bool ready: false

  property bool running: false
  property string playingFolder: ""
  property int videoCount: 0
  property string lastError: ""

  readonly property color barForeground: bar ? bar.barForeground : Color.foreground

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function expandPath(path) {
    var p = String(path || "").trim()
    if (p === "~" || p.indexOf("~/") === 0) p = home + p.slice(1)
    return p.length > 1 ? p.replace(/\/+$/, "") : p
  }

  function prettyPath(path) {
    var p = String(path || "")
    return home !== "" && p.indexOf(home) === 0 ? "~" + p.slice(home.length) : p
  }

  // ---------------------------------------------------------------- engine

  // One engine call at a time; a call that arrives while another runs replaces
  // whatever was queued, because only the newest intent matters.
  property var pendingArgs: null

  function runEngine(args) {
    if (engineProc.running) {
      pendingArgs = args
      return
    }
    engineProc.command = [engine].concat(args)
    engineProc.running = true
  }

  function startArgs() {
    var args = ["start", expandPath(videoDir)]
    if (shuffle) args.push("--shuffle")
    if (pauseWhenHidden) args.push("--pause-hidden")
    if (mpvOptions.trim() !== "") args.push("--mpv-options", mpvOptions.trim())
    return args
  }

  function apply() {
    if (!isLeader) return
    appliedKey = desiredKey
    if (!wantOn) lastError = ""
    runEngine(wantOn ? startArgs() : ["stop"])
  }

  function requestApply() {
    if (ready && isLeader) applyTimer.restart()
  }

  function refresh() {
    if (isLeader) runEngine(["status"])
  }

  Process {
    id: engineProc
    stdout: StdioCollector { id: engineOut; waitForEnd: true }
    stderr: StdioCollector { id: engineErr; waitForEnd: true }

    onExited: function(exitCode) {
      var action = engineProc.command.length > 1 ? engineProc.command[1] : ""
      if (action === "status") {
        root.readStatus(engineOut.text)
      } else {
        if (action === "start") {
          root.lastError = exitCode === 0 ? "" : engineErr.text.trim().replace(/^wallpaper-video: /, "")
          if (exitCode !== 0) root.notify("Could not start the animated wallpaper", root.lastError)
        }
        if (root.pendingArgs === null) root.pendingArgs = ["status"]
      }

      if (root.pendingArgs !== null) {
        var next = root.pendingArgs
        root.pendingArgs = null
        root.runEngine(next)
      }
    }
  }

  function readStatus(text) {
    var state = null
    try { state = JSON.parse(String(text).trim()) } catch (e) { state = null }
    if (!state) return

    running = state.running === true
    playingFolder = String(state.folder || "")
    videoCount = Number(state.videos || 0)

    if (!ready) {
      ready = true
      // A shell restart or plugin reload must not restart a wallpaper that is
      // already playing the right folder: mpvpaper survives both on its own.
      var sameFolder = playingFolder === expandPath(videoDir)
      if ((wantOn && (!running || !sameFolder)) || (!wantOn && running)) apply()
      else appliedKey = desiredKey
    }
  }

  function notify(summary, body) {
    Quickshell.execDetached(["notify-send", "-a", "Animated Wallpaper", summary, body || ""])
  }

  // Coalesce a burst of setting writes (a folder pick also turns the wallpaper
  // on) into one restart instead of two.
  Timer {
    id: applyTimer
    interval: 300
    onTriggered: if (root.desiredKey !== root.appliedKey || (root.wantOn && !root.running)) root.apply()
  }

  // Notices an mpvpaper that died on its own, so the icon does not lie.
  Timer {
    interval: 15000
    running: root.isLeader
    repeat: true
    onTriggered: root.refresh()
  }

  // Settings arrive from the host after construction; wait a beat before the
  // first status check so the decision uses them.
  Timer {
    interval: 400
    running: root.isLeader
    onTriggered: root.refresh()
  }

  onDesiredKeyChanged: if (desiredKey !== appliedKey) requestApply()

  // --------------------------------------------------------------- actions

  // Persist inline settings back to shell.json, the same way omarchy.clock
  // stores a cycled format: apply locally first so the UI reacts on the click,
  // then let the bar write the entry.
  function setSettings(changes) {
    var entry = { id: root.moduleName }
    for (var name in root.settings) {
      if (name !== "id") entry[name] = root.settings[name]
    }
    for (var key in changes) entry[key] = changes[key]

    root.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function leader() {
    if (isLeader) return root
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i].isLeader) return items[i]
    }
    return root
  }

  function turn(on) {
    var target = leader()
    if (target !== root) return target.turn(on)
    if (wantOn !== on) setSettings({ enabled: on })
    requestApply()
  }

  function toggle() {
    var target = leader()
    turn(!target.running)
  }

  function pickFolder() {
    if (pickerProc.running) return
    var start = expandPath(videoDir)
    pickerProc.command = ["zenity", "--file-selection", "--directory",
      "--title=Animated wallpaper: choose a folder of videos",
      "--filename=" + (start !== "" ? start + "/" : home + "/")]
    pickerProc.running = true
  }

  function next() {
    var target = leader()
    if (target !== root) return target.next()
    if (running) runEngine(["next"])
  }

  Process {
    id: pickerProc
    stdout: StdioCollector { id: pickerOut; waitForEnd: true }
    onExited: function(exitCode) {
      var folder = pickerOut.text.trim()
      if (exitCode !== 0 || folder === "") return
      // Picking a folder means "play this", so it also turns the wallpaper on.
      var target = root.leader()
      target.setSettings({ videoDir: root.prettyPath(folder), enabled: true })
      target.requestApply()
    }
  }

  // `omarchy-shell animated-wallpaper toggle`, for keybindings and scripts.
  IpcHandler {
    target: "animated-wallpaper"
    enabled: root.isLeader

    function toggle(): void { root.toggle() }
    function on(): void { root.turn(true) }
    function off(): void { root.turn(false) }
    function pick(): void { root.pickFolder() }
    function next(): void { root.next() }
    function status(): string { return root.statusText }
  }

  readonly property string statusText: {
    if (lastError !== "") return "error: " + lastError
    if (running) return "playing " + prettyPath(playingFolder) + " (" + videoCount + (videoCount === 1 ? " video)" : " videos)")
    if (wantOn) return "starting " + prettyPath(expandPath(videoDir))
    return "off · " + prettyPath(expandPath(videoDir))
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(root.running ? 0xf0567 : 0xf0568)
    foreground: root.lastError !== "" ? (root.bar ? root.bar.urgent : Color.urgent) : root.barForeground
    dimmed: !root.running && root.lastError === ""
    useActiveColor: false
    active: root.running
    tooltipText: "Animated wallpaper · " + root.statusText
      + "\nLeft: on/off · Right: choose folder · Middle: next video"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.pickFolder()
      else if (buttonCode === Qt.MiddleButton) root.next()
      else root.toggle()
    }
  }
}
