import Observation
import SwiftUI

struct RenderBooleanControl: Equatable, Sendable {
  enum Style: Equatable, Sendable {
    case toggle(Int)
    case disclosure
  }
  let value: Bool
  let enabled: Bool
  let style: Style
  static func decode(_ reader: inout WireReader, disclosure: Bool = false) throws -> Self {
    Self(
      value: try reader.flag(), enabled: try reader.flag(),
      style: disclosure ? .disclosure : .toggle(try reader.choice(3)))
  }
}

@MainActor @Observable final class BooleanControlController {
  struct Request: Equatable {
    let serial: UInt64
    let value: Bool
  }
  @ObservationIgnored var onPresentationChange: (() -> Void)?
  private(set) var value: Bool {
    didSet { if oldValue != value { onPresentationChange?() } }
  }
  private(set) var pending: Request?
  private var properties: RenderBooleanControl
  private var generation: UInt64 = 0
  private var serial: UInt64 = 0
  private var disposed = false
  init(_ properties: RenderBooleanControl) {
    self.properties = properties
    value = properties.value
  }
  func synchronize(_ next: RenderBooleanControl) {
    if next.enabled != properties.enabled || next.style != properties.style {
      pending = nil
      generation += 1
    }
    properties = next
    let visible = pending?.value ?? next.value
    if visible != value { generation += 1 }
    value = visible
  }
  func resolve(_ request: Request) {
    guard pending == request else { return }
    pending = nil
    if value != properties.value { generation += 1 }
    value = properties.value
  }
  @discardableResult func request(_ next: Bool, emit: (NativeEventPayload) -> Bool) -> Bool {
    guard !disposed, properties.enabled, next != value else { return false }
    guard emit(.valueChanged(next)) else {
      generation += 1
      return false
    }
    serial += 1
    pending = Request(serial: serial, value: next)
    value = next
    return true
  }
  private final class BindingRead {
    var generation: UInt64
    init(_ generation: UInt64) { self.generation = generation }
  }
  func binding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<Bool> {
    let read = BindingRead(generation)
    return Binding(
      get: {
        read.generation = self.generation
        return self.value
      },
      set: { next in
        guard read.generation == self.generation else { return }
        self.request(next, emit: emit)
      })
  }
  func dispose() {
    disposed = true
    pending = nil
    generation += 1
  }
}

struct NativeBooleanControl: View {
  let node: RenderNodeState
  let controller: BooleanControlController
  let properties: RenderBooleanControl
  let activate: @MainActor (RenderNodeState) -> Void
  private var toggle: some View {
    Toggle(isOn: controller.binding(emit: node.emit)) {
      NativeNodeView(node: node.children[0], activate: activate).allowsHitTesting(false)
    }.accessibilityElement(children: .combine).disabled(!properties.enabled)
  }
  @ViewBuilder var body: some View {
    switch properties.style {
    case .disclosure:
      DisclosureGroup(isExpanded: controller.binding(emit: node.emit)) {
        NativeNodeView(node: node.children[1], activate: activate)
          .disabled(!controller.value).allowsHitTesting(controller.value)
          .accessibilityHidden(!controller.value)
      } label: {
        NativeNodeView(node: node.children[0], activate: activate)
          .allowsHitTesting(false).accessibilityElement(children: .combine)
      }.disabled(!properties.enabled)
    case .toggle(let style):
      switch style {
      case 1: toggle.toggleStyle(.switch)
      case 2:
        #if os(macOS)
          toggle.toggleStyle(.checkbox)
        #else
          toggle.toggleStyle(ChecklistToggleStyle())
        #endif
      case 3: toggle.toggleStyle(.button)
      default: toggle.toggleStyle(.automatic)
      }
    }
  }
}

#if os(iOS)
  private struct ChecklistToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
      Button {
        configuration.isOn.toggle()
      } label: {
        HStack {
          Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
          configuration.label
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityRepresentation {
        Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
      }
    }
  }
#endif
