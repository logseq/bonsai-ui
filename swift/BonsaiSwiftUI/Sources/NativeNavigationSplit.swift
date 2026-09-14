import Observation
import SwiftUI

struct RenderSplitState: Equatable, Sendable {
  var visibility: Int
  var compactColumn: Int
  let selectionKey: String?

  var selectionIdentity: Data? { selectionKey.map { Data($0.utf8) } }
  var isValid: Bool {
    (0...3).contains(visibility) && (0...2).contains(compactColumn) && selectionKey != ""
  }
  static func == (left: Self, right: Self) -> Bool {
    left.visibility == right.visibility && left.compactColumn == right.compactColumn
      && left.selectionIdentity == right.selectionIdentity
  }
  static func decode(_ reader: inout WireReader) throws -> Self {
    let visibility = try reader.choice(3)
    let compactColumn = try reader.choice(2)
    let selectionKey = try reader.flag() ? reader.string() : nil
    guard selectionKey != "" else { throw TreeError.invalidProperties }
    return Self(visibility: visibility, compactColumn: compactColumn, selectionKey: selectionKey)
  }
  var nativeVisibility: NavigationSplitViewVisibility {
    switch visibility {
    case 1: .all
    case 2: .doubleColumn
    case 3: .detailOnly
    default: .automatic
    }
  }
  var nativeCompactColumn: NavigationSplitViewColumn {
    switch compactColumn {
    case 0: .sidebar
    case 2: .detail
    default: .content
    }
  }
}

struct RenderNavigationSplit: Equatable, Sendable {
  let state: RenderSplitState
  let sidebarTitle: String
  let contentTitle: String?
  let detailTitle: String
  static func decode(_ reader: inout WireReader) throws -> Self {
    let state = try RenderSplitState.decode(&reader)
    let sidebarTitle = try reader.string()
    let contentTitle = try reader.flag() ? reader.string() : nil
    let detailTitle = try reader.string()
    guard contentTitle != nil || state.compactColumn != 1 else {
      throw TreeError.invalidProperties
    }
    return Self(
      state: state, sidebarTitle: sidebarTitle, contentTitle: contentTitle,
      detailTitle: detailTitle)
  }
}

@MainActor @Observable final class NavigationSplitController {
  private(set) var state: RenderSplitState
  private var authoritative: RenderSplitState
  private var pending: RenderSplitState?
  private var generation: UInt64 = 0
  private var disposed = false
  private var hasContent: Bool

  init(_ state: RenderSplitState, hasContent: Bool = true) {
    self.state = state
    self.hasContent = hasContent
    authoritative = state
  }

  func synchronize(_ next: RenderSplitState, hasContent: Bool = true) {
    if self.hasContent != hasContent {
      pending = nil
      generation += 1
    }
    self.hasContent = hasContent
    authoritative = next
    let visible: RenderSplitState
    if let pending, pending.selectionIdentity == next.selectionIdentity {
      visible = pending
    } else {
      pending = nil
      visible = next
    }
    // Acknowledging native state must preserve retained binding reads: SwiftUI
    // has no changed value to read again before the next system action.
    if state != visible { generation += 1 }
    state = visible
  }

  func resolve(_ submitted: RenderSplitState) {
    guard pending == submitted else { return }
    if state != authoritative { generation += 1 }
    pending = nil
    state = authoritative
  }

  @discardableResult func request(_ next: RenderSplitState, emit: (NativeEventPayload) -> Bool)
    -> Bool
  {
    guard !disposed, next.isValid, hasContent || next.compactColumn != 1,
      next.selectionIdentity == authoritative.selectionIdentity,
      next != state, emit(.navigationSplit(next))
    else { return false }
    pending = next
    state = next
    return true
  }

  private final class BindingRead {
    var generation: UInt64
    init(_ generation: UInt64) { self.generation = generation }
  }

  func visibilityBinding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<
    NavigationSplitViewVisibility
  > {
    let read = BindingRead(generation)
    return Binding(
      get: {
        read.generation = self.generation
        return self.state.nativeVisibility
      },
      set: { value in
        guard read.generation == self.generation else { return }
        let id: Int
        // automatic is a computed alias of a concrete visibility on Apple platforms.
        if value == .all {
          id = 1
        } else if value == .doubleColumn {
          id = 2
        } else if value == .detailOnly {
          id = 3
        } else {
          return
        }
        var next = self.state
        next.visibility = id
        self.request(next, emit: emit)
      })
  }

  func compactColumnBinding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<
    NavigationSplitViewColumn
  > {
    let read = BindingRead(generation)
    return Binding(
      get: {
        read.generation = self.generation
        return self.state.nativeCompactColumn
      },
      set: { value in
        guard read.generation == self.generation else { return }
        let id: Int
        if value == .sidebar {
          id = 0
        } else if value == .content {
          id = 1
        } else if value == .detail {
          id = 2
        } else {
          return
        }
        var next = self.state
        next.compactColumn = id
        self.request(next, emit: emit)
      })
  }

  func dispose() {
    disposed = true
    pending = nil
    generation += 1
  }
}

struct NativeNavigationSplit: View {
  let node: RenderNodeState
  let properties: RenderNavigationSplit
  let controller: NavigationSplitController
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some View {
    if let contentTitle = properties.contentTitle {
      NavigationSplitView(
        columnVisibility: controller.visibilityBinding(emit: node.emit),
        preferredCompactColumn: controller.compactColumnBinding(emit: node.emit)
      ) {
        sidebar
      } content: {
        NativeNodeView(node: node.children[1], activate: activate).navigationTitle(contentTitle)
          .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 640)
      } detail: {
        detail
      }
    } else {
      NavigationSplitView(
        columnVisibility: controller.visibilityBinding(emit: node.emit),
        preferredCompactColumn: controller.compactColumnBinding(emit: node.emit)
      ) {
        sidebar
      } detail: {
        detail
      }
    }
  }

  private var sidebar: some View {
    NativeNodeView(node: node.children[0], activate: activate)
      .navigationTitle(properties.sidebarTitle)
      .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
  }

  private var detail: some View {
    NativeNodeView(node: node.children[properties.contentTitle == nil ? 1 : 2], activate: activate)
      .navigationTitle(properties.detailTitle)
      .navigationSplitViewColumnWidth(min: 320, ideal: 480)
  }
}
