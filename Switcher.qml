import QtQuick
import Quickshell
import Quickshell.Io

// Ties the wallpaper to Omarchy's native background switcher.
//
// The switcher only lists images, from the theme and from
// ~/.config/omarchy/backgrounds/<theme>/, and whatever it picks lands in
// ~/.local/state/omarchy/current/background. So every video gets a poster
// (<video file>.video.jpg) in that folder, and this watches the link:
//
//   - a poster picked in the switcher plays that video;
//   - any other image picked there turns the video off and stays;
//   - the bar turning the video on, or the middle click, points the link at the
//     playing video's poster, so the switcher shows it as the current one;
//   - the bar turning it off goes back to the still that was there before;
//   - a theme change makes posters in the new theme's folder and keeps the video.
Item {
  id: sync
  visible: false

  property var widget: null
  // Only the leader's instance, with the integration on, does anything.
  property bool active: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string linkPath: home + "/.local/state/omarchy/current/background"
  readonly property string themeFile: home + "/.local/state/omarchy/current/theme.name"
  readonly property string suffix: ".video.jpg"
  readonly property string folder: widget ? widget.expandPath(widget.videoDir) : ""

  property string theme: ""
  property string link: ""
  property bool primed: false
  // theme-set writes theme.name and then the background link; a link change
  // that trails a theme change is Omarchy's doing, not a pick.
  property bool settlingTheme: false

  readonly property string posterDir: home + "/.config/omarchy/backgrounds/" + theme

  function isPoster(path) {
    var p = String(path || "")
    return theme !== "" && p.indexOf(posterDir + "/") === 0 && p.slice(-suffix.length) === suffix
  }

  function videoFor(poster) {
    var name = String(poster).split("/").pop()
    return folder + "/" + name.slice(0, name.length - suffix.length)
  }

  // ------------------------------------------------------------ engine calls

  // Its own queue, separate from the player's, so making posters never holds up
  // a start or a middle click.
  property var queue: []
  // show and restore jobs queued or running. While any is in flight, link
  // changes are our own doing and must not be read as a pick in the switcher.
  property int ownJobs: 0

  function run(args, tag) {
    if (tag === "show" || tag === "restore") ownJobs++
    // A newer request of the same kind supersedes a queued one.
    var kept = []
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].tag !== tag) kept.push(queue[i])
      else if (tag === "show" || tag === "restore") ownJobs--
    }
    kept.push({ args: args, tag: tag })
    queue = kept
    if (!proc.running) pump()
  }

  function pump() {
    if (queue.length === 0 || !widget) return
    var job = queue[0]
    queue = queue.slice(1)
    proc.tag = job.tag
    proc.command = [widget.engine].concat(job.args)
    proc.running = true
  }

  Process {
    id: proc
    property string tag: ""
    stdout: StdioCollector { id: procOut; waitForEnd: true }
    stderr: StdioCollector { id: procErr; waitForEnd: true }
    onExited: function(exitCode) {
      sync.finished(proc.tag, exitCode, procOut.text.trim(), procErr.text.trim())
      sync.pump()
    }
  }

  function finished(tag, exitCode, out, err) {
    if (tag === "show" || tag === "restore") ownJobs = Math.max(0, ownJobs - 1)
    if (exitCode !== 0) {
      console.warn("animated-wallpaper switcher:", tag, err)
      return
    }
    // What we set ourselves is not a pick; remember it so the watcher agrees.
    if ((tag === "show" || tag === "restore") && out !== "") link = out
  }

  function syncPosters() {
    if (active && folder !== "") run(["posters", folder], "posters")
  }

  // Make the playing video's poster the background, keeping the still that was
  // there so turning the video off can go back to it.
  function showVideo(video) {
    if (!active || !video) return
    if (link !== "" && !isPoster(link)) widget.rememberStill(link)
    run(["show", video], "show")
  }

  function restoreStill(still) {
    if (!active) return
    if (isPoster(link)) run(["restore", still || ""], "restore")
  }

  // ------------------------------------------------------------------ watch

  Process {
    id: watchProc
    command: ["bash", "-c", "readlink -f -- \"$1\"; cat -- \"$2\" 2>/dev/null", "_", sync.linkPath, sync.themeFile]
    stdout: StdioCollector { id: watchOut; waitForEnd: true }
    onExited: {
      var lines = watchOut.text.split("\n")
      sync.observe(String(lines[0] || "").trim(), String(lines[1] || "").trim())
    }
  }

  Timer {
    interval: 1500
    repeat: true
    running: sync.active
    triggeredOnStart: true
    onTriggered: if (!watchProc.running) watchProc.running = true
  }

  Timer {
    id: themeSettleTimer
    interval: 3000
    onTriggered: sync.themeSettled()
  }

  // Picks up videos added to the folder since the last pass.
  Timer {
    interval: 60000
    repeat: true
    running: sync.active
    onTriggered: sync.syncPosters()
  }

  function observe(currentLink, currentTheme) {
    if (!primed) {
      primed = true
      theme = currentTheme
      link = currentLink
      syncPosters()
      // First pass with a video already playing (the integration just turned
      // on, or an install over a running wallpaper): show it as the current one.
      if (widget.wantOn && widget.running && widget.playingVideo !== "" && !isPoster(currentLink))
        showVideo(widget.playingVideo)
      return
    }

    if (currentTheme !== theme) {
      theme = currentTheme
      link = currentLink
      settlingTheme = true
      syncPosters()
      themeSettleTimer.restart()
      return
    }

    // finished() records where our own change landed; until then, wait.
    if (ownJobs > 0) return
    if (currentLink === link) return
    link = currentLink
    if (settlingTheme) return

    if (isPoster(currentLink)) widget.playFromSwitcher(videoFor(currentLink))
    else widget.stillFromSwitcher(currentLink)
  }

  function themeSettled() {
    settlingTheme = false
    if (!active || !widget) return
    if (widget.wantOn) {
      // Keep the video across the theme change: point the new theme at its poster.
      var video = widget.playingVideo !== "" ? widget.playingVideo : widget.expandPath(widget.currentVideo)
      if (video !== "") showVideo(video)
    } else if (isPoster(link)) {
      // Omarchy picks a theme's first background, and our posters sort first.
      run(["restore", ""], "restore")
    }
  }

  onFolderChanged: if (primed) syncPosters()

  onActiveChanged: {
    if (active) {
      primed = false
      if (!watchProc.running) watchProc.running = true
    } else if (widget && primed) {
      // Turned off in the settings: take the posters away and leave a still.
      if (isPoster(link)) run(["restore", widget.staticBackground], "restore")
      run(["posters-clean"], "posters-clean")
      primed = false
    }
  }
}
