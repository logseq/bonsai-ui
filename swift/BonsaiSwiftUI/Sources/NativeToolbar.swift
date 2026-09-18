import SwiftUI

struct RenderToolbarEntry: Equatable, Sendable {
  let key: String
  let placement: Int
  let kind: Int

  static func decode(_ reader: inout WireReader) throws -> Self {
    try Self(key: reader.string(), placement: reader.choice(9), kind: reader.choice(3))
  }

  var nativePlacement: ToolbarItemPlacement {
    switch placement {
    case 0: return .automatic
    case 1: return .principal
    case 2: return .navigation
    case 3: return .primaryAction
    case 4: return .secondaryAction
    case 5: return .status
    case 6: return .confirmationAction
    case 7: return .cancellationAction
    case 8: return .destructiveAction
    #if os(iOS)
      case 9: return .bottomBar
    #endif
    default: preconditionFailure("Unsupported toolbar placement passed validation")
    }
  }
}

extension NodeProperties {
  func sameToolbarOwner(as other: NodeProperties) -> Bool {
    switch (self, other) {
    case (.toolbar, .toolbar): return true
    case (.toolbarEntry(let lhs), .toolbarEntry(let rhs)):
      return Data(lhs.key.utf8) == Data(rhs.key.utf8) && lhs.kind == rhs.kind
    case (.toolbarChild(let lhs), .toolbarChild(let rhs)):
      return Data(lhs.utf8) == Data(rhs.utf8)
    default: return false
    }
  }

  var isToolbarStructure: Bool {
    switch self {
    case .toolbarEntry, .toolbarChild, .toolbarBody: return true
    default: return false
    }
  }
}

private struct NativeToolbarEntries: ToolbarContent {
  let entries: ArraySlice<RenderNodeState>
  let focus: ToolbarFocusController
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some ToolbarContent {
    if let entry = entries.first, case .toolbarEntry(let properties) = entry.properties {
      if properties.kind < 2 {
        ToolbarItem(
          id: "bonsai-\(entry.id.epoch)-\(entry.id.node)", placement: properties.nativePlacement
        ) {
          if properties.kind == 1 {
            ControlGroup {
              ForEach(entry.children) { item in
                NativeNodeView(node: item.children[0], activate: activate)
                  .environment(\.bonsaiToolbarFocus, focus).id(item.id)
              }
            }.id(entry.id)
          } else {
            NativeNodeView(node: entry.children[0], activate: activate)
              .environment(\.bonsaiToolbarFocus, focus).id(entry.id)
          }
        }
      } else {
        ToolbarSpacer(
          properties.kind == 2 ? .fixed : .flexible, placement: properties.nativePlacement)
      }
      // Every recursion level has the same concrete body type. Changing an
      // erased payload's type at an existing level crashes SwiftUI's storage.
      ToolbarContentBuilder.buildLimitedAvailability(
        NativeToolbarEntries(entries: entries.dropFirst(), focus: focus, activate: activate))
    }
  }
}

struct NativeToolbar: View {
  let node: RenderNodeState
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some View {
    NativeNodeView(node: node.children[0].children[0], activate: activate)
      .toolbar {
        NativeToolbarEntries(
          entries: node.children.dropFirst(), focus: node.toolbarFocus!, activate: activate)
      }
  }
}
