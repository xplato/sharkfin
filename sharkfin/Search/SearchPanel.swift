import AppKit

/// A borderless, floating NSPanel that hosts the search UI.
final class SearchPanel: NSPanel {
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
    hasShadow = false
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
}

extension Notification.Name {
  static let searchPanelDidResignKey = Notification.Name("searchPanelDidResignKey")
}
