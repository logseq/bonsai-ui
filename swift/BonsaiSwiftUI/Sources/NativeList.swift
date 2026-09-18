import Observation
import SwiftUI

struct RenderListSection: Equatable, Sendable {
  let hasHeader: Bool
  let hasFooter: Bool
  let separator: Int
  let key: Data
  static func decode(_ reader: inout WireReader) throws -> Self {
    Self(
      hasHeader: try reader.flag(), hasFooter: try reader.flag(), separator: try reader.choice(2),
      key: try reader.listKey())
  }
}

private func separatorVisibility(_ value: Int) -> Visibility {
  switch value {
  case 1: .hidden
  case 2: .visible
  default: .automatic
  }
}

struct RenderListRow: Equatable, Sendable {
  let separator: Int
  let key: Data
  let expanded: Bool?
  static func decode(_ reader: inout WireReader) throws -> Self {
    let separator = try reader.choice(2)
    let key = try reader.listKey()
    let expanded = try reader.choice(2)
    return Self(separator: separator, key: key, expanded: expanded == 0 ? nil : expanded == 2)
  }
}

extension NodeProperties {
  var booleanControlProperties: RenderBooleanControl? {
    switch self {
    case .booleanControl(let properties): properties
    case .listRow(let row):
      RenderBooleanControl(
        value: row.expanded ?? false, enabled: row.expanded != nil, style: .disclosure)
    default: nil
    }
  }
}

struct ListRowCatalog {
  let targets: [ListRowAddress: ListScrollTarget]
  let visible: [RenderIdentity]
  @MainActor init(sections: [RenderNodeState]) {
    var targets: [ListRowAddress: ListScrollTarget] = [:]
    var visible: [RenderIdentity] = []
    for section in sections {
      guard case .listSection(let properties) = section.properties else { continue }
      var pending = Array(section.children.dropFirst(2).reversed()).map { ($0, [Data](), true) }
      while let (row, ancestors, exposed) = pending.popLast() {
        guard case .listRow(let rowProperties) = row.properties else { continue }
        let path = ancestors + [rowProperties.key]
        targets[ListRowAddress(section: properties.key, path: path)] = ListScrollTarget(
          identity: row.id, visible: exposed)
        if exposed { visible.append(row.id) }
        pending.append(
          contentsOf: row.children.dropFirst(3).reversed().map {
            ($0, path, exposed && rowProperties.expanded == true)
          })
      }
    }
    self.targets = targets
    self.visible = visible
  }
}

// Native List disclosure headings may send both their label action and their
// expansion callback for one accessibility activation. Arbitrate within that
// native callback turn; no delayed replay or application-owned state is stored.
@MainActor @Observable final class ListRowInteraction {
  private(set) var revision: UInt64 = 0
  private var serial: UInt64 = 0
  private var labelActive = false
  private var disposed = false

  func labelActivated() {
    guard !disposed else { return }
    serial &+= 1
    let current = serial
    labelActive = true
    DispatchQueue.main.async { [weak self] in
      guard let self, self.serial == current else { return }
      self.labelActive = false
    }
  }

  func expand(_ commit: @escaping () -> Void) {
    guard !disposed else { return }
    let current = serial
    let fromLabel = labelActive
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.disposed else { return }
      if fromLabel || self.serial != current {
        self.revision &+= 1
        return
      }
      commit()
      self.revision &+= 1
    }
  }

  func dispose() {
    disposed = true
    serial &+= 1
  }
}

private struct ListRowInteractionKey: EnvironmentKey {
  static let defaultValue: ListRowInteraction? = nil
}
extension EnvironmentValues {
  var bonsaiListRowInteraction: ListRowInteraction? {
    get { self[ListRowInteractionKey.self] }
    set { self[ListRowInteractionKey.self] = newValue }
  }
}

struct NativeListRow: View {
  let node: RenderNodeState
  let list: RenderNodeState
  let activate: @MainActor (RenderNodeState) -> Void

  private var label: some View {
    NativeNodeView(node: node.children[0], activate: activate)
      .environment(\.bonsaiListRowInteraction, node.listRowInteraction)
      .modifier(NativeSwipeActionsModifier(controller: node.children[1].swipeController!))
      .modifier(NativeContextMenuModifier(controller: node.children[2].contextMenuController!))
      .background {
        if let controller = list.listScrollController {
          NativeListRowProbe(row: node.id, host: controller.nativeHost).allowsHitTesting(false)
        }
      }
      .id(node.id)
      .onScrollVisibilityChange(threshold: 0.01) {
        list.listVisibility?.update(node.id, visible: $0)
      }
      .onDisappear { list.listVisibility?.update(node.id, visible: false) }
  }

  @ViewBuilder var body: some View {
    if case .listRow(let properties) = node.properties {
      if properties.expanded != nil, let controller = node.booleanControlController {
        let handler = node.bindings[EventTagId.valueChanged]
        let expected = node.properties
        let children = node.children.map(\.id)
        let _ = node.listRowInteraction?.revision
        DisclosureGroup(
          isExpanded: Binding(
            get: { controller.value },
            set: { next in
              node.listRowInteraction?.expand {
                guard node.bindings[EventTagId.valueChanged] == handler,
                  node.properties == expected,
                  node.children.map(\.id) == children
                else { return }
                controller.request(next, emit: node.emit)
              }
            })
        ) {
          ForEach(Array(node.children.dropFirst(3))) { child in
            AnyView(NativeListRow(node: child, list: list, activate: activate))
              .disabled(!controller.value || properties.expanded != true)
              .allowsHitTesting(controller.value && properties.expanded == true)
              .accessibilityHidden(!controller.value || properties.expanded != true)
          }
        } label: {
          label
            .simultaneousGesture(
              TapGesture().onEnded { node.listRowInteraction?.labelActivated() })
        }
        .listRowSeparator(separatorVisibility(properties.separator))
      } else {
        label.listRowSeparator(separatorVisibility(properties.separator))
      }
    }
  }
}

struct NativeList: View {
  let node: RenderNodeState
  let activate: @MainActor (RenderNodeState) -> Void
  @Environment(\.bonsaiRefresh) private var refreshController

  private var nativeProperties: RenderListProperties {
    guard case .nativeList(let value) = node.properties else {
      preconditionFailure("Expected List")
    }
    return value
  }

  @ViewBuilder private var list: some View {
    let properties = nativeProperties
    switch properties.style {
    case 0: content.listStyle(.plain)
    case 1: content.listStyle(.inset)
    #if os(iOS)
      case 2: content.listStyle(.insetGrouped)
    #endif
    default: preconditionFailure("Invalid native List style")
    }
  }

  private var content: some View {
    List {
      ForEach(node.children) { section in
        if case .listSection(let properties) = section.properties {
          Section {
            ForEach(Array(section.children.dropFirst(2))) { row in
              NativeListRow(node: row, list: node, activate: activate)
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

  private var scrollingList: some View {
    ScrollViewReader { proxy in
      list.modifier(NativeListScrollModifier(controller: node.listScrollController!, proxy: proxy))
    }
  }

  @ViewBuilder var body: some View {
    if let controller = refreshController {
      let generation = controller.generation
      scrollingList.refreshable { await controller.perform(generation: generation) }
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
      scrollingList
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
