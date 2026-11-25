import QtQuick
import Quickshell

// Too Busy To Click: open a bar icon's panel by resting the mouse on it, and close it once the mouse
// leaves the icon, the panel and the gap between them. Moving along the bar to another icon switches
// to that icon's panel (the shell morphs between panels in the same section).
//
// Works with any widget that has open() and close() (Omarchy's own panels and most plugin panels).
// Panels opened by click or keyboard are left alone: they close the usual way.
//
// The bar only sees the mouse while no panel is open. An open panel's window covers the whole
// screen, bar included, so while a hover-opened panel is up a tracker placed inside that window
// follows the mouse instead.
Item {
  id: hover
  visible: false

  required property var bar

  // Optional settings from shell.json: "bar": { "hover": { "enabled", "openDelay", "closeDelay" } }
  readonly property var settings: bar && bar.barConfig && bar.barConfig.hover ? bar.barConfig.hover : ({})
  function setting(key, fallback) {
    var v = settings[key]
    return typeof v === typeof fallback ? v : fallback
  }

  property bool active: setting("enabled", true)
  // How long the mouse rests on an icon before its panel opens; keeps panels from flashing open
  // when the mouse just passes along the bar.
  property int openDelay: Math.max(0, setting("openDelay", 150))
  // How long after leaving before the panel closes; leaves time to cross the gap into the panel.
  property int closeDelay: Math.max(0, setting("closeDelay", 300))
  // Icons in the tray drawer slide while the drawer opens, passing under a still mouse; wait for them
  // to settle before treating one as hovered.
  property int trayOpenDelay: Math.max(openDelay, 450)

  onActiveChanged: if (!active) reset()

  function openDelayFor(slot) {
    return slot && slot.region === "tray" ? trayOpenDelay : openDelay
  }

  // The widget whose panel this opened, its panel window object, and the tracker inside that window.
  property var item: null
  property var panel: null
  property var tracker: null
  property var pendingSlot: null
  // What the bar records as the open panel's owner; for some widgets (e.g. ones that load their panel
  // with a Loader) that is an inner object rather than the widget itself.
  property var popout: null

  function canOpen(widget) {
    return !!widget && typeof widget.open === "function" && typeof widget.close === "function"
  }

  function isOpen(widget) {
    if (!widget) return false
    if ("opened" in widget && widget.opened === true) return true
    if (bar.activePopout === widget) return true
    return widget === item && !!popout && bar.activePopout === popout
  }

  // Called by each bar slot when the mouse enters or leaves it.
  function slotHovered(slot) {
    if (!slot || !active) return
    if (slot.hovered && canOpen(slot.activeItem) && !isOpen(slot.activeItem)) {
      pendingSlot = slot
      openTimer.interval = openDelayFor(slot)
      openTimer.restart()
    } else if (pendingSlot === slot) {
      openTimer.stop()
      pendingSlot = null
    }
  }

  function openSlot(slot) {
    var widget = slot ? slot.activeItem : null
    if (!canOpen(widget)) return
    closeTimer.stop()
    if (widget === item && isOpen(widget)) return
    detachTracker()
    item = widget
    popout = null
    // Started before open() so the popout change open() causes isn't mistaken for a close.
    attachTimer.attempts = 0
    attachTimer.restart()
    widget.open()
    popout = bar.activePopout
  }

  function closeHovered() {
    var widget = item
    reset()
    if (widget && isOpen(widget)) widget.close()
  }

  function reset() {
    openTimer.stop()
    closeTimer.stop()
    attachTimer.stop()
    detachTracker()
    item = null
    popout = null
    pendingSlot = null
  }

  // ---- finding the open panel's window -------------------------------------------------------

  // The KeyboardPanel / PopupCard window object under a widget (it may sit inside a Loader).
  function findPanel(obj, depth) {
    if (!obj || depth > 4) return null
    if (obj !== item && "cardTarget" in obj && "loadedContent" in obj) return obj
    var lists = []
    if (obj.data) lists.push(obj.data)
    if (obj.item) lists.push([obj.item])
    for (var l = 0; l < lists.length; l++) {
      var list = lists[l]
      for (var i = 0; i < list.length; i++) {
        var found = findPanel(list[i], depth + 1)
        if (found) return found
      }
    }
    return null
  }

  // The root item of the panel's window, reached through any item drawn in it: content loaded from
  // `content:` (loadedContent), or items placed straight inside the panel (its default children).
  function panelWindowRoot(p) {
    if (!p) return null
    var candidates = [p.loadedContent, p.focusTarget]
    var direct = p.contentItem
    if (direct && direct.length !== undefined) for (var i = 0; i < direct.length; i++) candidates.push(direct[i])
    for (var c = 0; c < candidates.length; c++) {
      var item = candidates[c]
      var win = item && item.Window ? item.Window.window : null
      if (win && win.contentItem) return win.contentItem
    }
    return null
  }

  function attachTracker() {
    var p = findPanel(item, 0)
    var root = panelWindowRoot(p)
    if (!root) return false
    panel = p
    tracker = trackerComponent.createObject(root)
    return !!tracker
  }

  function detachTracker() {
    if (tracker) tracker.destroy()
    tracker = null
    panel = null
  }

  // ---- following the mouse while a hover-opened panel is up ----------------------------------

  // The bar slot under screen point (x, y) on the panel's screen, if (x, y) is on the bar. Slots can
  // nest (the tray's drawer is a slot holding the icons in it), so the smallest one under the point wins.
  function slotAt(x, y) {
    var slots = bar.moduleSlots || []
    var best = null
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || !slot.visible || !slot.activeItem || slot.width <= 0 || slot.height <= 0) continue
      var win = slot.QsWindow ? slot.QsWindow.window : null
      if (!win || !panel || win.screen !== panel.screen) continue
      var p = slot.mapToItem(win.contentItem, 0, 0)
      if (x >= p.x && x < p.x + slot.width && y >= p.y && y < p.y + slot.height
          && (!best || slot.width * slot.height < best.width * best.height)) best = slot
    }
    return best
  }

  function onBar(x, y) {
    var t = panel.barThickness
    if (panel.barPos === "bottom") return y >= panel.screenH - t
    if (panel.barPos === "left") return x <= t
    if (panel.barPos === "right") return x >= panel.screenW - t
    return y <= t
  }

  // Between the icon and its panel, across the gap the mouse crosses on its way in.
  function inGap(x, y, card) {
    var m = 6
    var ax = panel.anchorScreenPos.x
    var inColumn = x >= Math.min(ax, card.x) - m && x <= Math.max(ax + panel.anchorW, card.x + card.width) + m
    if (panel.barPos === "top") return inColumn && y <= card.y
    if (panel.barPos === "bottom") return inColumn && y >= card.y + card.height
    return false
  }

  function track(x, y, inside) {
    if (!active || !item || !panel || !isOpen(item)) return
    if (!inside) {
      closeTimer.restart()
      return
    }
    var m = 6
    var card = panel.cardTarget
    if (x >= card.x - m && x <= card.x + card.width + m && y >= card.y - m && y <= card.y + card.height + m) {
      closeTimer.stop()
      openTimer.stop()
      return
    }
    if (onBar(x, y)) {
      var slot = slotAt(x, y)
      if (slot && slot.activeItem === item) {
        closeTimer.stop()
        openTimer.stop()
        return
      }
      if (slot && canOpen(slot.activeItem)) {
        // Resting on another icon: switch to its panel.
        closeTimer.stop()
        if (pendingSlot !== slot) {
          pendingSlot = slot
          openTimer.interval = openDelayFor(slot)
          openTimer.restart()
        }
        return
      }
      openTimer.stop()
      pendingSlot = null
      if (!closeTimer.running) closeTimer.start()
      return
    }
    openTimer.stop()
    pendingSlot = null
    if (inGap(x, y, card)) closeTimer.stop()
    else if (!closeTimer.running) closeTimer.start()
  }

  Component {
    id: trackerComponent
    Item {
      anchors.fill: parent
      z: 100000
      HoverHandler {
        onPointChanged: hover.track(point.position.x, point.position.y, hovered)
        onHoveredChanged: hover.track(point.position.x, point.position.y, hovered)
      }
    }
  }

  Timer {
    id: openTimer
    onTriggered: {
      var slot = hover.pendingSlot
      hover.pendingSlot = null
      // Over the bar the slot's own hover says if the mouse is still there; over an open panel
      // the tracker has already checked.
      if (slot && (slot.hovered || hover.item)) hover.openSlot(slot)
    }
  }

  Timer {
    id: closeTimer
    interval: hover.closeDelay
    onTriggered: hover.closeHovered()
  }

  // The panel window and its content load a moment after open(); keep trying briefly.
  Timer {
    id: attachTimer
    property int attempts: 0
    interval: 40
    repeat: true
    onTriggered: {
      attempts++
      if (hover.attachTracker() || attempts > 125) stop()
    }
  }

  // Closed some other way (a click, Escape, another panel taking over by click): stop following.
  Connections {
    target: hover.bar
    function onActivePopoutChanged() {
      if (hover.item && !hover.popout && attachTimer.running) hover.popout = hover.bar.activePopout
      if (hover.item && !hover.isOpen(hover.item) && !attachTimer.running) hover.reset()
    }
  }
}
