import SwiftUI

struct RenderListSection: Equatable, Sendable {
  let hasHeader: Bool
  let hasFooter: Bool
  let separator: Int
  static func decode(_ reader: inout WireReader) throws -> Self {
    Self(
      hasHeader: try reader.flag(), hasFooter: try reader.flag(), separator: try reader.choice(2))
  }
}

private func separatorVisibility(_ value: Int) -> Visibility {
  switch value {
  case 1: .hidden
  case 2: .visible
  default: .automatic
  }
}

struct NativeList: View {
  let node: RenderNodeState
  let activate: @MainActor (RenderNodeState) -> Void
  @Environment(\.bonsaiRefresh) private var refreshController

  private var list: some View {
    List {
      ForEach(node.children) { section in
        if case .listSection(let properties) = section.properties {
          Section {
            ForEach(Array(section.children.dropFirst(2))) { row in
              if case .listRow(let separator) = row.properties {
                NativeNodeView(node: row, activate: activate)
                  .listRowSeparator(separatorVisibility(separator))
                  .onScrollVisibilityChange(threshold: 0.01) { visible in
                    node.listVisibility?.update(row.id, visible: visible)
                  }
                  .onDisappear { node.listVisibility?.update(row.id, visible: false) }
              }
            }
          } header: {
            if properties.hasHeader {
              NativeNodeView(node: section.children[0], activate: activate)
            }
          } footer: {
            if properties.hasFooter {
              NativeNodeView(node: section.children[1], activate: activate)
            }
          }
          .listSectionSeparator(separatorVisibility(properties.separator))
        }
      }
    }
    .environment(\.bonsaiRefresh, nil)
  }

  @ViewBuilder var body: some View {
    if let controller = refreshController {
      let generation = controller.generation
      list.refreshable { await controller.perform(generation: generation) }
        #if os(macOS)
          .toolbar {
            ToolbarItem {
              Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await controller.perform(generation: generation) }
              }.disabled(!controller.canRequest)
            }
          }
        #endif
    } else {
      list
    }
  }
}

@MainActor final class ListVisibility {
  private var rows: [RenderIdentity] = []
  private var indices: [RenderIdentity: Int] = [:]
  private var visible: Set<RenderIdentity> = []
  private var handler: UInt64?
  private var current: Range<Int>?
  private var delivered: Range<Int>?

  func synchronize(_ rows: [RenderIdentity], handler: UInt64?) {
    if self.handler != handler {
      self.handler = handler
      delivered = nil
    }
    guard self.rows != rows else { return }
    self.rows = rows
    indices = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element, $0.offset) })
    visible.formIntersection(rows)
    delivered = nil
    recalculate()
  }

  func update(_ row: RenderIdentity, visible: Bool) {
    guard indices[row] != nil else { return }
    let changed = visible ? self.visible.insert(row).inserted : self.visible.remove(row) != nil
    if changed { recalculate() }
  }

  private func recalculate() {
    let positions = visible.compactMap { indices[$0] }
    current = positions.min().flatMap { first in positions.max().map { first..<($0 + 1) } }
  }

  var request: Range<Int>? { current == delivered ? nil : current }
  func accepted(_ range: Range<Int>) { delivered = range }
}
