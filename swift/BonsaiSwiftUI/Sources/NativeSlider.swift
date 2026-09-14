import Observation
import SwiftUI

struct SliderSelection: Equatable, Sendable {
  var lower: Double
  var upper: Double?
}
struct RenderSlider: Equatable, Sendable {
  let selection: SliderSelection
  let minimum: Double
  let maximum: Double
  let step: Double?
  let enabled: Bool
  let vertical: Bool
  let changes: Bool
  let label: String
  let upperLabel: String?
  var span: Double { maximum - minimum }
  var adjustment: Double { step ?? max(span / 20, span.ulp) }
  func contains(_ value: SliderSelection) -> Bool {
    guard value.lower.isFinite, (minimum...maximum).contains(value.lower),
      (selection.upper == nil) == (value.upper == nil)
    else { return false }
    guard let upper = value.upper else { return true }
    return upper.isFinite && (value.lower...maximum).contains(upper)
  }
  func snapped(_ input: Double) -> Double {
    let bounded = min(maximum, max(minimum, input))
    guard bounded > minimum, bounded < maximum, let step else { return bounded }
    return min(maximum, max(minimum, minimum + ((bounded - minimum) / step).rounded() * step))
  }
  static func decode(_ reader: inout WireReader, ranged: Bool) throws -> Self {
    let lower = try reader.finiteDouble()
    let upper = ranged ? try reader.finiteDouble() : nil
    let minimum = try reader.finiteDouble()
    let maximum = try reader.finiteDouble()
    let step = try reader.flag() ? reader.finiteDouble() : nil
    let enabled = try reader.flag()
    let vertical = try reader.flag()
    let changes = try reader.flag()
    let label = try reader.string()
    let upperLabel = ranged ? try reader.string() : nil
    guard minimum < maximum, (maximum - minimum).isFinite,
      step.map({
        $0 > 0 && $0 <= maximum - minimum && minimum + $0 > minimum && maximum - $0 < maximum
      }) ?? true,
      !label.isEmpty, upperLabel != ""
    else { throw TreeError.invalidProperties }
    let result = Self(
      selection: SliderSelection(lower: lower, upper: upper), minimum: minimum,
      maximum: maximum, step: step, enabled: enabled, vertical: vertical,
      changes: changes, label: label, upperLabel: upperLabel)
    guard result.contains(result.selection) else { throw TreeError.invalidProperties }
    return result
  }
  func sameConfiguration(as other: Self) -> Bool {
    minimum == other.minimum && maximum == other.maximum && step == other.step
      && enabled == other.enabled && vertical == other.vertical && changes == other.changes
      && label == other.label && upperLabel == other.upperLabel
      && (selection.upper == nil) == (other.selection.upper == nil)
  }
}

@MainActor @Observable final class SliderController {
  struct Request: Equatable {
    let serial: UInt64
    let selection: SliderSelection
  }
  private(set) var selection: SliderSelection
  private(set) var pending: Request?
  private(set) var editing = false
  private var properties: RenderSlider
  private var generation: UInt64 = 0
  private var serial: UInt64 = 0
  private var disposed = false
  init(_ properties: RenderSlider) {
    self.properties = properties
    selection = properties.selection
  }
  func synchronize(_ next: RenderSlider) {
    if !properties.sameConfiguration(as: next) {
      cancel()
      generation += 1
    }
    properties = next
    if pending == nil && !editing { replace(next.selection) }
  }
  private func replace(_ next: SliderSelection) {
    if selection != next { generation += 1 }
    selection = next
  }
  func resolve(_ request: Request) {
    guard pending == request else { return }
    pending = nil
    replace(properties.selection)
  }
  func cancel() {
    editing = false
    pending = nil
    replace(properties.selection)
  }
  func begin() { if !disposed && properties.enabled { editing = true } }
  private func payload(_ value: SliderSelection, ended: Bool) -> NativeEventPayload {
    if let upper = value.upper {
      return ended ? .rangeSliderEnded(value.lower, upper) : .rangeSliderChanged(value.lower, upper)
    }
    return ended ? .sliderEnded(value.lower) : .sliderChanged(value.lower)
  }
  private func send(_ value: SliderSelection, ended: Bool, emit: (NativeEventPayload) -> Bool)
    -> Bool
  {
    guard emit(payload(value, ended: ended)) else { return false }
    serial += 1
    pending = Request(serial: serial, selection: value)
    return true
  }
  func change(_ input: Double, thumb: Int, emit: (NativeEventPayload) -> Bool) {
    guard !disposed, properties.enabled, input.isFinite else { return }
    var next = selection
    let value = properties.snapped(input)
    if thumb == 0 {
      next.lower = min(next.upper ?? properties.maximum, value)
    } else {
      guard next.upper != nil else { return }
      next.upper = max(next.lower, value)
    }
    guard next != selection else { return }
    if properties.changes && !send(next, ended: false, emit: emit) {
      generation += 1
      return
    }
    selection = next
    if !editing { finish(emit: emit) }
  }
  func finish(emit: (NativeEventPayload) -> Bool) {
    editing = false
    guard !disposed, properties.enabled, send(selection, ended: true, emit: emit) else {
      cancel()
      return
    }
  }
  func editingChanged(_ editing: Bool, emit: (NativeEventPayload) -> Bool) {
    if editing { begin() } else if self.editing { finish(emit: emit) }
  }
  func adjust(_ thumb: Int, increase: Bool, emit: (NativeEventPayload) -> Bool) {
    let value = thumb == 0 ? selection.lower : selection.upper ?? selection.lower
    let next: Double
    if increase {
      next =
        value >= properties.maximum - properties.adjustment
        ? properties.maximum : value + properties.adjustment
    } else {
      next =
        value <= properties.minimum + properties.adjustment
        ? properties.minimum : value - properties.adjustment
    }
    change(next, thumb: thumb, emit: emit)
  }
  private final class Read {
    var generation: UInt64
    init(_ generation: UInt64) { self.generation = generation }
  }
  func binding(_ thumb: Int, emit: @escaping (NativeEventPayload) -> Bool) -> Binding<Double> {
    let read = Read(generation)
    return Binding(
      get: {
        read.generation = self.generation
        return thumb == 0 ? self.selection.lower : self.selection.upper ?? self.selection.lower
      },
      set: { value in
        guard read.generation == self.generation else { return }
        self.change(value, thumb: thumb, emit: emit)
      })
  }
  func dispose() {
    disposed = true
    cancel()
    generation += 1
  }
}

struct NativeSlider: View {
  let node: RenderNodeState
  let controller: SliderController
  let properties: RenderSlider
  @Environment(\.layoutDirection) private var direction
  @FocusState private var focusedThumb: Int?
  @State private var draggedThumb: Int?
  private func accessibleSlider(_ index: Int) -> some View {
    let label = index == 0 ? properties.label : properties.upperLabel!
    return Slider(
      value: controller.binding(index, emit: node.emit),
      in: properties.minimum...properties.maximum,
      onEditingChanged: { controller.editingChanged($0, emit: node.emit) }
    ) { Text(verbatim: label) }
    .accessibilityLabel(Text(verbatim: label))
    .accessibilityAdjustableAction { value in
      if value == .increment || value == .decrement {
        controller.adjust(index, increase: value == .increment, emit: node.emit)
      }
    }
  }
  private var horizontal: some View {
    Slider(
      value: controller.binding(0, emit: node.emit), in: properties.minimum...properties.maximum,
      onEditingChanged: { controller.editingChanged($0, emit: node.emit) }
    ) { Text(verbatim: properties.label) }
    .accessibilityRepresentation { accessibleSlider(0) }
  }
  @ViewBuilder var body: some View {
    Group {
      if properties.selection.upper != nil {
        range
      } else if properties.vertical {
        GeometryReader { geometry in
          horizontal.environment(\.layoutDirection, .leftToRight)
            .frame(width: geometry.size.height, height: geometry.size.width)
            .rotationEffect(.degrees(-90))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.frame(minWidth: 44, idealWidth: 44, minHeight: 80, idealHeight: 180)
      } else {
        horizontal
      }
    }
    .disabled(!properties.enabled)
    .onDisappear {
      controller.cancel()
      draggedThumb = nil
    }
    .onChange(of: node.progressAnimationsActive) { _, active in
      if !active {
        controller.cancel()
        draggedThumb = nil
      }
    }
  }
  private var range: some View {
    GeometryReader { geometry in
      let size = geometry.size
      let extent = max(1, (properties.vertical ? size.height : size.width) - 44)
      let lower = point(controller.selection.lower, size: size, extent: extent)
      let upper = point(controller.selection.upper!, size: size, extent: extent)
      ZStack {
        Path { path in
          path.move(to: point(properties.minimum, size: size, extent: extent))
          path.addLine(to: point(properties.maximum, size: size, extent: extent))
        }.stroke(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        Path { path in
          path.move(to: lower)
          path.addLine(to: upper)
        }
        .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        thumb(0, size: size, extent: extent).position(lower)
        thumb(1, size: size, extent: extent).position(upper)
      }
      .coordinateSpace(name: node.id)
      // Points are already mirrored explicitly; SwiftUI positioning must not mirror them again.
      .environment(\.layoutDirection, .leftToRight)
    }
    .frame(
      minWidth: properties.vertical ? 44 : 120, idealWidth: properties.vertical ? 44 : 240,
      minHeight: 44, idealHeight: properties.vertical ? 180 : 44
    )
    .accessibilityElement(children: .contain)
  }
  private func point(_ value: Double, size: CGSize, extent: Double) -> CGPoint {
    let fraction = (value - properties.minimum) / properties.span
    if properties.vertical { return CGPoint(x: size.width / 2, y: 22 + (1 - fraction) * extent) }
    return CGPoint(
      x: 22 + (direction == .rightToLeft ? 1 - fraction : fraction) * extent, y: size.height / 2)
  }
  private func thumb(_ index: Int, size: CGSize, extent: Double) -> some View {
    return Circle().fill(.background).overlay(Circle().stroke(.tint, lineWidth: 2))
      .frame(width: 22, height: 22).shadow(radius: 1)
      .frame(width: 44, height: 44).contentShape(Rectangle())
      .focusable()
      .focused($focusedThumb, equals: index)
      .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
        let increase: Bool
        switch press.key {
        case .upArrow: increase = true
        case .downArrow: increase = false
        case .rightArrow: increase = properties.vertical || direction == .leftToRight
        case .leftArrow: increase = !properties.vertical && direction == .rightToLeft
        default: return .ignored
        }
        controller.adjust(index, increase: increase, emit: node.emit)
        return .handled
      }
      .highPriorityGesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .named(node.id))
          .onChanged { updateDrag($0, index: index, extent: extent) }
          .onEnded { value in
            updateDrag(value, index: index, extent: extent)
            controller.finish(emit: node.emit)
            draggedThumb = nil
          }
      )
      .accessibilityRepresentation {
        accessibleSlider(index).environment(\.layoutDirection, direction)
      }
  }
  private func updateDrag(_ value: DragGesture.Value, index: Int, extent: Double) {
    if draggedThumb == nil {
      if controller.selection.lower == controller.selection.upper {
        var travel = properties.vertical ? value.translation.height : value.translation.width
        if properties.vertical || direction == .rightToLeft { travel = -travel }
        guard travel != 0 else { return }
        draggedThumb = travel < 0 ? 0 : 1
      } else {
        draggedThumb = index
      }
    }
    guard let draggedThumb else { return }
    focusedThumb = draggedThumb
    controller.begin()
    let coordinate = properties.vertical ? value.location.y : value.location.x
    var fraction = min(1, max(0, (coordinate - 22) / extent))
    if properties.vertical || direction == .rightToLeft { fraction = 1 - fraction }
    controller.change(
      properties.minimum + fraction * properties.span, thumb: draggedThumb, emit: node.emit)
  }

}
