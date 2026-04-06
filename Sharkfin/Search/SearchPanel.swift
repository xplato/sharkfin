import AppKit

/// A borderless, floating NSPanel that hosts the search UI.
final class SearchPanel: NSPanel {

  // MARK: - Drag state

  /// The default Y origin set by AppState on first show, used for vertical snap detection.
  var defaultOriginY: CGFloat = 0

  /// Height of the search bar drag region (matches SearchBarView padding + content).
  private let dragRegionHeight: CGFloat = 50
  /// Minimum mouse movement (points) before committing to a drag.
  private let dragThreshold: CGFloat = 3
  /// Snap detection tolerance (points).
  private let snapTolerance: CGFloat = 4

  private var storedMouseDown: NSEvent?
  private var dragOrigin: NSPoint?
  private var frameAtDragStart: NSRect?
  private var isDragging = false

  private var wasAtHorizontalCenter = false
  private var wasAtVerticalOrigin = false

  // MARK: - Init

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )

    isFloatingPanel = true
    level = .floating
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isMovableByWindowBackground = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    becomesKeyOnlyIfNeeded = false
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func resignKey() {
    super.resignKey()
    NotificationCenter.default.post(
      name: .searchPanelDidResignKey,
      object: self
    )
  }

  // MARK: - Event interception for drag

  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown:
      let locationInWindow = event.locationInWindow
      let contentHeight = contentView?.frame.height ?? frame.height
      // Distance from top of window (window coords have origin at bottom-left)
      let distanceFromTop = contentHeight - locationInWindow.y

      if distanceFromTop <= dragRegionHeight {
        storedMouseDown = event
        dragOrigin = NSEvent.mouseLocation
        frameAtDragStart = frame
        isDragging = false
        wasAtHorizontalCenter = isAtHorizontalCenter
        wasAtVerticalOrigin = isAtVerticalOrigin
        // Don't forward yet — wait for drag or click resolution
        return
      }

    case .leftMouseDragged:
      guard let origin = dragOrigin, let startFrame = frameAtDragStart else { break }

      let current = NSEvent.mouseLocation
      let deltaX = current.x - origin.x
      let deltaY = current.y - origin.y

      if !isDragging {
        let distance = hypot(deltaX, deltaY)
        if distance < dragThreshold {
          return // Not yet a drag — swallow
        }
        isDragging = true
      }

      setFrameOrigin(NSPoint(
        x: startFrame.origin.x + deltaX,
        y: startFrame.origin.y + deltaY
      ))
      checkSnapPoints()
      return

    case .leftMouseUp:
      if let originalDown = storedMouseDown {
        let wasDragging = isDragging
        storedMouseDown = nil
        dragOrigin = nil
        frameAtDragStart = nil
        isDragging = false

        if wasDragging {
          // Drag completed
          return
        } else {
          // Was a click — replay the original mouseDown then this mouseUp
          super.sendEvent(originalDown)
          super.sendEvent(event)
          return
        }
      }

    default:
      break
    }

    super.sendEvent(event)
  }

  // MARK: - Snap detection & haptics

  private var isAtHorizontalCenter: Bool {
    guard let screen = screen ?? NSScreen.main else { return false }
    return abs(frame.midX - screen.visibleFrame.midX) <= snapTolerance
  }

  private var isAtVerticalOrigin: Bool {
    abs(frame.origin.y - defaultOriginY) <= snapTolerance
  }

  private func checkSnapPoints() {
    let atHCenter = isAtHorizontalCenter
    let atVOrigin = isAtVerticalOrigin

    if atHCenter && !wasAtHorizontalCenter {
      NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    if atVOrigin && !wasAtVerticalOrigin {
      NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    wasAtHorizontalCenter = atHCenter
    wasAtVerticalOrigin = atVOrigin
  }
}

extension Notification.Name {
  static let searchPanelDidResignKey = Notification.Name("searchPanelDidResignKey")
}
