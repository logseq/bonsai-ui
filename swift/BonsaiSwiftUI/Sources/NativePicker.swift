import Observation
import SwiftUI

struct RenderPicker: Equatable, Sendable {
  struct Option: Equatable, Identifiable, Sendable {
    let id: Int64
    let enabled: Bool
    let childIndex: Int?
  }
  let selection: Int64?
  let options: [Option]
  let label: String
  let style: Int
  let enabled: Bool

  static func decode(_ reader: inout WireReader) throws -> Self {
    let selection = try reader.flag() ? Int64(bitPattern: reader.integer(UInt64.self)) : nil
    let count = Int(try reader.integer(UInt16.self))
    guard count <= 256 else { throw WireError.limitExceeded }
    var options: [Option] = []
    var ids = Set<Int64>()
    var children = 0
    for _ in 0..<count {
      let id = try Int64(bitPattern: reader.integer(UInt64.self))
      let enabled = try reader.flag()
      let label = try reader.flag()
      guard ids.insert(id).inserted else { throw TreeError.invalidProperties }
      options.append(Option(id: id, enabled: enabled, childIndex: label ? children : nil))
      if label { children += 1 }
    }
    let label = try reader.string()
    guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      selection.map({ ids.contains($0) }) ?? true
    else { throw TreeError.invalidProperties }
    return Self(
      selection: selection, options: options, label: label,
      style: try reader.choice(3), enabled: try reader.flag())
  }
  func admits(_ id: Int64) -> Bool { enabled && options.contains { $0.id == id && $0.enabled } }
  func sameConfiguration(as other: Self) -> Bool {
    options == other.options && label == other.label && style == other.style
      && enabled == other.enabled
  }
}

@MainActor @Observable final class PickerController {
  struct Request: Equatable {
    let serial: UInt64
    let value: Int64
  }
  private(set) var selection: Int64?
  private(set) var pending: Request?
  private var properties: RenderPicker
  private var generation: UInt64 = 0
  private var serial: UInt64 = 0
  private var disposed = false
  init(_ properties: RenderPicker) {
    self.properties = properties
    selection = properties.selection
  }
  func synchronize(_ next: RenderPicker) {
    if !next.sameConfiguration(as: properties) {
      pending = nil
      generation += 1
    }
    properties = next
    let visible = pending?.value ?? next.selection
    if visible != selection { generation += 1 }
    selection = visible
  }
  func resolve(_ request: Request) {
    guard pending == request else { return }
    pending = nil
    if selection != properties.selection { generation += 1 }
    selection = properties.selection
  }
  @discardableResult func request(_ id: Int64, emit: (NativeEventPayload) -> Bool) -> Bool {
    guard !disposed, properties.admits(id), selection != id else { return false }
    guard emit(.pickerSelection(id)) else {
      generation += 1
      return false
    }
    serial += 1
    pending = Request(serial: serial, value: id)
    selection = id
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
        return self.selection
      },
      set: { id in
        guard read.generation == self.generation, let id else { return }
        self.request(id, emit: emit)
      })
  }
  func dispose() {
    disposed = true
    pending = nil
    generation += 1
  }
}

struct NativePicker: View {
  let node: RenderNodeState
  let properties: RenderPicker
  let controller: PickerController
  let activate: @MainActor (RenderNodeState) -> Void
  private var picker: some View {
    Picker(properties.label, selection: controller.binding(emit: node.emit)) {
      if controller.selection == nil {
        Text("Choose").tag(nil as Int64?).disabled(true)
      }
      ForEach(properties.options) { option in
        Group {
          if let index = option.childIndex {
            NativeNodeView(node: node.children[index], activate: activate).allowsHitTesting(false)
          } else {
            Text(String(option.id))
          }
        }.tag(Optional(option.id)).disabled(!option.enabled)
      }
    }.disabled(!properties.enabled || !properties.options.contains { $0.enabled })
  }
  #if os(macOS)
    private var popup: some View {
      VStack(alignment: .leading) {
        Text(properties.label)
        NativePopupPicker(
          node: node, properties: properties,
          selection: controller.binding(emit: node.emit)
        )
        .accessibilityLabel(properties.label)
        .disabled(!properties.enabled || !properties.options.contains { $0.enabled })
      }
    }
  #endif
  @ViewBuilder var body: some View {
    switch properties.style {
    case 1:
      #if os(macOS)
        popup
      #else
        picker.pickerStyle(.menu).modifier(NativeInteractiveBounds())
      #endif
    case 2:
      #if os(macOS)
        VStack(alignment: .leading) {
          Text(properties.label)
          NativeSegmentedPicker(
            node: node, properties: properties,
            selection: controller.binding(emit: node.emit)
          )
          .frame(height: 28).disabled(!properties.enabled)
        }
      #else
        picker.pickerStyle(.segmented).modifier(NativeInteractiveBounds())
      #endif
    case 3:
      #if os(macOS)
        NativeInlinePicker(
          node: node, properties: properties, controller: controller, activate: activate)
      #else
        picker.pickerStyle(.inline).modifier(NativeInteractiveBounds())
      #endif
    default:
      #if os(macOS)
        popup
      #else
        picker.pickerStyle(.automatic).modifier(NativeInteractiveBounds())
      #endif
    }
  }
}

#if os(macOS)
  private struct NativePopupPicker: NSViewRepresentable {
    let node: RenderNodeState
    let properties: RenderPicker
    let selection: Binding<Int64?>
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSPopUpButton {
      let control = NSPopUpButton(frame: .zero, pullsDown: false)
      control.target = context.coordinator
      control.action = #selector(Coordinator.changed(_:))
      return control
    }
    func updateNSView(_ control: NSPopUpButton, context: Context) {
      let ids = properties.options.map(\.id)
      if ids != context.coordinator.ids {
        control.removeAllItems()
        control.addItem(withTitle: "Choose")
        for id in ids { control.addItem(withTitle: String(id)) }
        context.coordinator.ids = ids
      }
      control.menu?.autoenablesItems = false
      control.item(at: 0)?.isEnabled = false
      control.item(at: 0)?.isHidden = selection.wrappedValue != nil
      control.isEnabled = properties.enabled && properties.options.contains { $0.enabled }
      control.setAccessibilityLabel(properties.label)
      for (index, option) in properties.options.enumerated() {
        let label = pickerLabel(node, option: option)
        let item = control.item(at: index + 1)
        item?.title = label.text
        item?.image = label.symbol.flatMap {
          NSImage(systemSymbolName: $0, accessibilityDescription: nil)
        }
        item?.isEnabled = properties.enabled && option.enabled
      }
      control.selectItem(
        at: properties.options.firstIndex { $0.id == selection.wrappedValue }.map { $0 + 1 } ?? 0)
      context.coordinator.changed = { control in
        let index = control.indexOfSelectedItem - 1
        if properties.options.indices.contains(index),
          properties.admits(properties.options[index].id)
        {
          selection.wrappedValue = properties.options[index].id
        }
        control.selectItem(
          at: properties.options.firstIndex { $0.id == selection.wrappedValue }.map { $0 + 1 } ?? 0)
      }
    }
    static func dismantleNSView(_ control: NSPopUpButton, coordinator: Coordinator) {
      control.target = nil
      coordinator.changed = nil
    }
    @MainActor final class Coordinator: NSObject {
      var ids: [Int64]?
      var changed: ((NSPopUpButton) -> Void)?
      @objc func changed(_ sender: NSPopUpButton) { changed?(sender) }
    }
  }

  @MainActor private func pickerLabel(_ node: RenderNodeState, option: RenderPicker.Option)
    -> (text: String, symbol: String?)
  {
    guard let index = option.childIndex else { return (String(option.id), nil) }
    var pending = [node.children[index]]
    var text: [String] = []
    var symbol: String?
    while let node = pending.popLast() {
      switch node.properties {
      case .text(let value): text.append(value.value)
      case .richText(let spans): text.append(spans.map(\.value).joined())
      case .symbol(let value): if symbol == nil { symbol = value.name }
      case .semantics(let value):
        if let label = value.label {
          text.append(label)
          continue
        }
      default: break
      }
      pending.append(contentsOf: node.children.reversed())
    }
    return (text.isEmpty ? String(option.id) : text.joined(separator: " "), symbol)
  }

  private struct NativeSegmentedPicker: NSViewRepresentable {
    let node: RenderNodeState
    let properties: RenderPicker
    let selection: Binding<Int64?>
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSSegmentedControl {
      let control = NSSegmentedControl()
      control.trackingMode = .selectOne
      control.segmentDistribution = .fillEqually
      control.target = context.coordinator
      control.action = #selector(Coordinator.changed(_:))
      return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
      control.segmentCount = properties.options.count
      control.isEnabled = properties.enabled
      control.setAccessibilityLabel(properties.label)
      for (index, option) in properties.options.enumerated() {
        let label = pickerLabel(node, option: option)
        control.setLabel(label.text, forSegment: index)
        control.setImage(
          label.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) },
          forSegment: index)
        control.setEnabled(properties.enabled && option.enabled, forSegment: index)
      }
      control.selectedSegment =
        properties.options.firstIndex { $0.id == selection.wrappedValue } ?? -1
      context.coordinator.changed = { control in
        let index = control.selectedSegment
        if properties.options.indices.contains(index),
          properties.admits(properties.options[index].id)
        {
          selection.wrappedValue = properties.options[index].id
        }
        control.selectedSegment =
          properties.options.firstIndex { $0.id == selection.wrappedValue } ?? -1
      }
    }
    static func dismantleNSView(_ control: NSSegmentedControl, coordinator: Coordinator) {
      control.target = nil
      coordinator.changed = nil
    }
    @MainActor final class Coordinator: NSObject {
      var changed: ((NSSegmentedControl) -> Void)?
      @objc func changed(_ sender: NSSegmentedControl) { changed?(sender) }
    }
  }

  private struct NativeInlinePicker: View {
    let node: RenderNodeState
    let properties: RenderPicker
    let controller: PickerController
    let activate: @MainActor (RenderNodeState) -> Void

    private func label(_ option: RenderPicker.Option) -> String {
      pickerLabel(node, option: option).text
    }
    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(properties.label)
        ForEach(properties.options) { option in
          HStack(spacing: 6) {
            NativeRadioChoice(
              id: option.id, label: label(option),
              enabled: properties.enabled && option.enabled,
              selection: controller.binding(emit: node.emit)
            )
            .frame(width: 18, height: 22)
            .accessibilityLabel(label(option))
            if let index = option.childIndex {
              NativeNodeView(node: node.children[index], activate: activate)
                .allowsHitTesting(false).accessibilityHidden(true)
            } else {
              Text(String(option.id)).accessibilityHidden(true)
            }
          }
          .contentShape(Rectangle())
          .onTapGesture { controller.request(option.id, emit: node.emit) }
          .disabled(!properties.enabled || !option.enabled)
        }
      }
    }
  }

  private struct NativeRadioChoice: NSViewRepresentable {
    let id: Int64
    let label: String
    let enabled: Bool
    let selection: Binding<Int64?>
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
      let button = NSButton(
        radioButtonWithTitle: "", target: context.coordinator,
        action: #selector(Coordinator.select(_:)))
      return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
      button.isEnabled = enabled
      button.state = selection.wrappedValue == id ? .on : .off
      button.setAccessibilityLabel(label)
      context.coordinator.select = {
        guard enabled else { return }
        selection.wrappedValue = id
        button.state = selection.wrappedValue == id ? .on : .off
      }
    }
    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
      button.target = nil
      coordinator.select = nil
    }
    @MainActor final class Coordinator: NSObject {
      var select: (() -> Void)?
      @objc func select(_ sender: NSButton) { select?() }
    }

  }
#endif
