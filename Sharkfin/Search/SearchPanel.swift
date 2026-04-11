import AppKit

/// A borderless, floating NSPanel that hosts the search UI.
final class SearchPanel: NSPanel {
  
  // MARK: - Layout constants
  
  static let panelWidth: CGFloat = 760
  static let panelHeight: CGFloat = 720
  static let cornerRadius: CGFloat = 12
  
  // MARK: - Drag state
  
  /// The default Y origin set by AppState on first show, used for vertical snap detection.
  var defaultOriginY: CGFloat = 0
  
  /// Height of the search bar drag region (matches SearchBarView padding + content).
  private let dragRegionHeight: CGFloat = 56
  /// Minimum mouse movement (points) before committing to a drag.
  private let dragThreshold: CGFloat = 3
  /// How close (points) the natural position must be to a snap point to engage.
  private let snapTolerance: CGFloat = 6
  /// How far (points) past the snap point the user must drag to break free.
  private let snapBreakout: CGFloat = 9
  
  private var storedMouseDown: NSEvent?
  private var dragOrigin: NSPoint?
  private var frameAtDragStart: NSRect?
  private var isDragging = false
  
  private var snappedToHCenter = false
  private var snappedToVOrigin = false
  
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
    collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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
        snappedToHCenter = false
        snappedToVOrigin = false
        // Don't forward yet — wait for drag or click resolution
        return
      }
      
    case .leftMouseDragged:
      guard let origin = dragOrigin, let startFrame = frameAtDragStart else {
        break
      }
      
      let current = NSEvent.mouseLocation
      let deltaX = current.x - origin.x
      let deltaY = current.y - origin.y
      
      if !isDragging {
        let distance = hypot(deltaX, deltaY)
        if distance < dragThreshold {
          return  // Not yet a drag — swallow
        }
        isDragging = true
      }
      
      var newX = startFrame.origin.x + deltaX
      var newY = startFrame.origin.y + deltaY
      
      // Horizontal center snap
      if let screen = screen ?? NSScreen.main {
        let screenCenterX = screen.visibleFrame.midX
        let naturalCenterX = newX + frame.width / 2
        let dist = abs(naturalCenterX - screenCenterX)
        
        if snappedToHCenter {
          if dist > snapBreakout {
            snappedToHCenter = false
          } else {
            newX = screenCenterX - frame.width / 2
          }
        } else if dist <= snapTolerance {
          snappedToHCenter = true
          newX = screenCenterX - frame.width / 2
          NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
          )
        }
      }
      
      // Vertical origin snap
      let vDist = abs(newY - defaultOriginY)
      if snappedToVOrigin {
        if vDist > snapBreakout {
          snappedToVOrigin = false
        } else {
          newY = defaultOriginY
        }
      } else if vDist <= snapTolerance {
        snappedToVOrigin = true
        newY = defaultOriginY
        NSHapticFeedbackManager.defaultPerformer.perform(
          .alignment,
          performanceTime: .now
        )
      }
      
      setFrameOrigin(NSPoint(x: newX, y: newY))
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
  
}

extension Notification.Name {
  static let searchPanelDidResignKey = Notification.Name(
    "searchPanelDidResignKey"
  )
}
