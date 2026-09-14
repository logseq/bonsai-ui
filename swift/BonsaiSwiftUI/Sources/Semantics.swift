import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct RenderSemantics: Equatable, Sendable {
  struct Action: Equatable, Sendable, Identifiable {
    let id: UInt64
    let label: String
  }
  let label: String?
  let hint: String?
  let value: String?
  let role: Int
  let selected: Bool?
  let children: Int
  let hidden: Bool
  let liveRegion: Bool
  let heading: Int?
  let priority: Double?
  let identifier: String?
  let actions: [Action]

  static func decode(_ reader: inout WireReader) throws -> Self {
    let label = try reader.flag() ? reader.string() : nil
    let hint = try reader.flag() ? reader.string() : nil
    let value = try reader.flag() ? reader.string() : nil
    let role = try reader.choice(6)
    let selection = try reader.choice(2)
    let children = try reader.choice(2)
    let hidden = try reader.flag()
    let liveRegion = try reader.flag()
    let heading = try reader.flag() ? reader.choice(6) : nil
    guard heading != 0 else { throw TreeError.invalidProperties }
    let priority = try reader.flag() ? reader.finiteDouble() : nil
    let identifier = try reader.flag() ? reader.string() : nil
    let count = Int(try reader.integer(UInt16.self))
    guard count <= 1024 else { throw WireError.limitExceeded }
    var ids: Set<UInt64> = []
    var actions: [Action] = []
    for _ in 0..<count {
      let id = try reader.identity()
      let label = try reader.string()
      guard !label.isEmpty, ids.insert(id).inserted else { throw TreeError.invalidProperties }
      actions.append(Action(id: id, label: label))
    }
    return Self(
      label: label, hint: hint, value: value, role: role,
      selected: selection == 0 ? nil : selection == 2, children: children,
      hidden: hidden, liveRegion: liveRegion, heading: heading, priority: priority,
      identifier: identifier, actions: actions)
  }

  var announcement: String? {
    guard liveRegion, !hidden else { return nil }
    let text = [label, value].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    return text.isEmpty ? nil : text
  }
}

extension NodeProperties {
  var accessibilityHidden: Bool {
    if case .semantics(let properties) = self { return properties.hidden }
    return false
  }
}

extension NodeStore {
  func liveAnnouncements(since previous: NodeStore) -> [String] {
    guard previous.revision > 0, epoch == previous.epoch else { return [] }
    return nodes.keys.sorted().compactMap { id in
      guard !accessibilityHiddenNodes.contains(id),
        case .semantics(let properties) = nodes[id]?.properties,
        let text = properties.announcement
      else { return nil }
      if !previous.accessibilityHiddenNodes.contains(id),
        case .semantics(let old) = previous.nodes[id]?.properties,
        old.announcement == text
      {
        return nil
      }
      return text
    }
  }
}

struct NativeSemanticsModifier: ViewModifier {
  let properties: RenderSemantics
  let emit: (NativeEventPayload) -> Bool

  private var traits: AccessibilityTraits {
    var result: AccessibilityTraits = []
    switch properties.role {
    case 1: result.insert(.isButton)
    case 2: result.insert(.isLink)
    case 3: result.insert(.isImage)
    case 4: result.insert(.isHeader)
    case 5: result.insert(.isToggle)
    case 6: result.insert(.isStaticText)
    default: break
    }
    if properties.selected == true { result.insert(.isSelected) }
    return result
  }

  func body(content: Content) -> some View {
    content
      .accessibilityElement(
        children: properties.children == 1
          ? .contain : properties.children == 2 ? .ignore : .combine
      )
      .accessibilityLabel(Text(properties.label ?? ""), isEnabled: properties.label != nil)
      .accessibilityHint(Text(properties.hint ?? ""), isEnabled: properties.hint != nil)
      .accessibilityValue(Text(properties.value ?? ""), isEnabled: properties.value != nil)
      .accessibilityIdentifier(properties.identifier ?? "", isEnabled: properties.identifier != nil)
      .accessibilityAddTraits(traits)
      .accessibilityRemoveTraits(properties.selected == false ? .isSelected : [])
      .accessibilityHeading(
        [AccessibilityHeadingLevel.unspecified, .h1, .h2, .h3, .h4, .h5, .h6][
          properties.heading ?? 0]
      )
      .accessibilitySortPriority(properties.priority ?? 0)
      .accessibilityHidden(properties.hidden)
      .accessibilityActions {
        ForEach(properties.actions) { action in
          Button(action.label) { _ = emit(.semanticsAction(action.id)) }
        }
      }
  }
}

@MainActor func postAccessibilityAnnouncement(_ text: String) {
  #if os(macOS)
    NSAccessibility.post(
      element: NSApplication.shared, notification: .announcementRequested,
      userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
  #else
    UIAccessibility.post(notification: .announcement, argument: text)
  #endif
}
