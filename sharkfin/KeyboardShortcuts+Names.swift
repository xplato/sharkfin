import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let activateSearch = Self("activateSearch", default: .init(.space, modifiers: [.command, .shift]))
}
