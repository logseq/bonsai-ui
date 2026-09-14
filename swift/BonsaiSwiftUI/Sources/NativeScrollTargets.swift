import Observation
import SwiftUI

struct RenderScrollTargets: Equatable, Sendable {
  let vertical: Bool
  let ids: [Int64]
  let position: Int64?
  let fraction: Double
  let spacing: Double
  let alignment: Int
  let snapping: Bool
  let enabled: Bool
  let indicators: Bool

  static func decode(_ reader: inout WireReader) throws -> Self {
    let vertical = try reader.flag()
    let count = Int(try reader.integer(UInt16.self))
    var ids: [Int64] = []
    for _ in 0..<count { ids.append(try Int64(bitPattern: reader.integer(UInt64.self))) }
    let position = try reader.flag() ? Int64(bitPattern: reader.integer(UInt64.self)) : nil
    let fraction = try reader.finiteDouble()
    let spacing = try reader.finiteDouble()
    let alignment = try reader.choice(2)
    let snapping = try reader.flag()
    let enabled = try reader.flag()
    let indicators = try reader.flag()
    guard Set(ids).count == ids.count, fraction > 0, fraction <= 1, spacing >= 0,
      ids.isEmpty ? position == nil : position.map(ids.contains) == true
    else { throw TreeError.invalidProperties }
    return Self(
      vertical: vertical, ids: ids, position: position, fraction: fraction,
      spacing: spacing, alignment: alignment, snapping: snapping,
      enabled: enabled, indicators: indicators)
  }
  func sameConfiguration(as other: Self) -> Bool {
    vertical == other.vertical && ids == other.ids && fraction == other.fraction
      && spacing == other.spacing && alignment == other.alignment && snapping == other.snapping
      && enabled == other.enabled && indicators == other.indicators
  }
  func admits(_ id: Int64) -> Bool { enabled && ids.contains(id) }
  var anchor: UnitPoint {
    let offset = Double(alignment) / 2
    return vertical ? UnitPoint(x: 0.5, y: offset) : UnitPoint(x: offset, y: 0.5)
  }
}

@MainActor @Observable final class ScrollTargetsController {
  struct Request: Equatable {
    let serial: UInt64
    let id: Int64
  }
  private(set) var position: Int64?
  private(set) var pending: Request?
  private var properties: RenderScrollTargets
  private var serial: UInt64 = 0
  private var generation: UInt64 = 0
  private var disposed = false
  init(_ properties: RenderScrollTargets) {
    self.properties = properties
    position = properties.position
  }
  func synchronize(_ next: RenderScrollTargets) {
    if !properties.sameConfiguration(as: next) { invalidateBinding() }
    properties = next
    let visible = pending?.id ?? next.position
    if position != visible { generation += 1 }
    position = visible
  }
  func invalidateBinding() {
    generation += 1
    pending = nil
    position = properties.position
  }
  func resolve(_ request: Request) {
    guard pending == request else { return }
    pending = nil
    if position != properties.position { generation += 1 }
    position = properties.position
  }
  @discardableResult func request(_ id: Int64, emit: (NativeEventPayload) -> Bool) -> Bool {
    guard !disposed, properties.admits(id), position != id else { return false }
    guard emit(.scrollPosition(id)) else {
      generation += 1
      return false
    }
    serial += 1
    pending = Request(serial: serial, id: id)
    position = id
    return true
  }
  private final class BindingRead {
    var generation: UInt64
    init(_ generation: UInt64) { self.generation = generation }
  }
  func binding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<Int64?> {
    let read = BindingRead(generation)
    return Binding(
      get: {
        read.generation = self.generation
        return self.position
      },
      set: { id in
        guard read.generation == self.generation, let id else { return }
        self.request(id, emit: emit)
      })
  }
  func dispose() {
    disposed = true
    invalidateBinding()
  }
}

private struct ScrollTargetFrames: PreferenceKey {
  static let defaultValue: [Int64: CGRect] = [:]
  static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

struct NativeScrollTargets: View {
  let node: RenderNodeState
  let properties: RenderScrollTargets
  let controller: ScrollTargetsController
  let activate: @MainActor (RenderNodeState) -> Void
  @Environment(\.layoutDirection) private var direction
  @State private var frames: [Int64: CGRect] = [:]
  @State private var restoring: Int64?
  @State private var hostPosition = ScrollPosition(idType: Never.self)

  init(
    node: RenderNodeState, properties: RenderScrollTargets, controller: ScrollTargetsController,
    activate: @escaping @MainActor (RenderNodeState) -> Void
  ) {
    self.node = node
    self.properties = properties
    self.controller = controller
    self.activate = activate
    _restoring = State(initialValue: properties.position)
  }
  private struct LayoutKey: Hashable {
    let size: CGSize
    let ids: [Int64]
    let vertical: Bool
    let fraction: Double
    let spacing: Double
    let alignment: Int
    let rtl: Bool
    let snapping: Bool
  }
  private func focal(_ frames: [Int64: CGRect], size: CGSize) -> (id: Int64, distance: CGFloat)? {
    guard frames.count == properties.ids.count else { return nil }
    let logical = Double(properties.alignment) / 2
    let anchor = properties.vertical || direction == .leftToRight ? logical : 1 - logical
    let target = (properties.vertical ? size.height : size.width) * anchor
    return properties.ids.compactMap { id -> (id: Int64, distance: CGFloat)? in
      guard let frame = frames[id], frame.width > 0, frame.height > 0 else { return nil }
      let point =
        properties.vertical ? frame.minY + frame.height * anchor : frame.minX + frame.width * anchor
      return (id, abs(point - target))
    }.min { left, right in
      if abs(left.distance - right.distance) < 0.01 { return left.id == controller.position }
      return left.distance < right.distance
    }
  }
  private func cards(_ length: CGFloat) -> some View {
    ForEach(Array(zip(properties.ids, node.children)), id: \.0) { pair in
      NativeNodeView(node: pair.1, activate: activate)
        .frame(
          width: properties.vertical ? nil : length,
          height: properties.vertical ? length : nil
        )
        .frame(
          maxWidth: properties.vertical ? .infinity : nil,
          maxHeight: properties.vertical ? nil : .infinity
        )
        .background(
          GeometryReader { geometry in
            Color.clear.preference(
              key: ScrollTargetFrames.self,
              value: [pair.0: geometry.frame(in: .named(node.id))])
          }
        )
        .id(pair.0)
    }
  }
  private func scroll(_ size: CGSize) -> some View {
    let binding = controller.binding(emit: node.emit)
    let length = properties.vertical ? size.height : size.width
    let extent = length * properties.fraction
    let before = (length - extent) * Double(properties.alignment) / 2
    let after = length - extent - before
    let rtl = !properties.vertical && direction == .rightToLeft
    let key = LayoutKey(
      size: size, ids: properties.ids, vertical: properties.vertical,
      fraction: properties.fraction, spacing: properties.spacing, alignment: properties.alignment,
      rtl: rtl, snapping: properties.snapping)
    return ScrollViewReader { proxy in
      ScrollView(
        properties.vertical ? .vertical : .horizontal, showsIndicators: properties.indicators
      ) {
        if properties.vertical {
          VStack(spacing: properties.spacing) { cards(extent).environment(\.bonsaiRefresh, nil) }
            .scrollTargetLayout()
        } else {
          HStack(spacing: properties.spacing) { cards(extent).environment(\.bonsaiRefresh, nil) }
            .scrollTargetLayout()
        }
      }
      .contentMargins(
        properties.vertical ? .top : .leading, rtl ? after : before, for: .scrollContent
      )
      .contentMargins(
        properties.vertical ? .bottom : .trailing, rtl ? before : after, for: .scrollContent
      )
      .modifier(ScrollObservationModifier(observer: node.scrollObserver))
      .scrollPosition($hostPosition)
      .modifier(
        NativeScrollCommandModifier(controller: node.scrollCommand, position: $hostPosition)
      )
      .coordinateSpace(name: node.id)
      .onPreferenceChange(ScrollTargetFrames.self) { next in
        frames = next
        guard let measured = focal(next, size: size) else { return }
        if let restoring {
          if measured.id == restoring && measured.distance < 1 { self.restoring = nil }
          return
        }
        binding.wrappedValue = measured.id
      }
      .onChange(of: controller.position) { _, id in
        guard let id else {
          restoring = nil
          return
        }
        // Native observations already moved the viewport. Only canonical commands
        // and rejected observations should reposition it.
        guard controller.pending?.id != id else { return }
        let measured = focal(frames, size: size)
        if measured?.id != id || (measured?.distance ?? .infinity) >= 1 {
          restoring = id
          proxy.scrollTo(id, anchor: properties.anchor)
        }
      }
      .task(id: key) {
        restoring = controller.position
        if size.width > 0, size.height > 0, let id = restoring {
          proxy.scrollTo(id, anchor: properties.anchor)
          await Task.yield()
          guard !Task.isCancelled else { return }
          if let measured = focal(frames, size: size), measured.id == id, measured.distance < 1 {
            restoring = nil
          }
        }
      }
      .scrollDisabled(!properties.enabled)
      .modifier(RefreshScrollModifier())
      .modifier(SwipeScrollActivity())
    }
  }
  var body: some View {
    GeometryReader { geometry in
      if properties.snapping {
        scroll(geometry.size).scrollTargetBehavior(.viewAligned)
      } else {
        scroll(geometry.size)
      }
    }
  }
}
