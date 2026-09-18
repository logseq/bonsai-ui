import Foundation
import Observation
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct RenderComposer: Equatable {
  struct Action: Equatable, Identifiable {
    let id: UInt32
    let leading: Bool
    let visibility: Int
    let prominent: Bool
    let enabled: Bool
    let tooltip: String
    var role: Int = 0
  }
  let enabled: Bool
  let autofocus: Bool
  let maximumLines: Int
  let hint: String
  let actions: [Action]

  static func decode(_ data: Data) throws -> Self {
    var reader = WireReader(data)
    let flags = try reader.integer(UInt8.self)
    guard flags & ~3 == 0, try reader.integer(UInt8.self) == 0 else {
      throw TreeError.invalidProperties
    }
    let maximumLines = Int(try reader.integer(UInt16.self))
    let count = Int(try reader.integer(UInt16.self))
    guard maximumLines > 0, try reader.integer(UInt16.self) == 0 else {
      throw TreeError.invalidProperties
    }
    let hint = try reader.string()
    let actions = try decodeActions(&reader, count: count, trimTooltip: true)
    guard reader.remaining == 0 else { throw TreeError.invalidProperties }
    return Self(
      enabled: flags & 1 != 0, autofocus: flags & 2 != 0, maximumLines: maximumLines, hint: hint,
      actions: actions)
  }

  static func decodeActions(
    _ reader: inout WireReader, count: Int, trimTooltip: Bool, sheet: Bool = false
  ) throws
    -> [Action]
  {
    var actions: [Action] = []
    var identities = Set<UInt32>()
    for _ in 0..<count {
      let id = try reader.integer(UInt32.self)
      guard id > 0, identities.insert(id).inserted else { throw TreeError.invalidProperties }
      let position = try reader.choice(sheet ? 2 : 1)
      let visibility = try reader.choice(2)
      let style = try sheet ? 0 : reader.choice(1)
      let enabled = try reader.flag()
      let tooltip = try reader.string()
      guard
        !(trimTooltip
          ? tooltip.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{000C}")) : tooltip)
          .isEmpty
      else { throw TreeError.invalidProperties }
      actions.append(
        Action(
          id: id, leading: position == 0, visibility: visibility, prominent: style == 1,
          enabled: enabled, tooltip: tooltip, role: sheet ? position : 0))
    }
    return actions
  }
}

enum ComposerEvent {
  case changed(String)
  case action(UInt32, String)
  var encoded: BonsaiNativeEvent {
    switch self {
    case .changed(let text): BonsaiNativeEvent(id: 1, payload: Data(text.utf8))
    case .action(let id, let text):
      {
        var writer = WireWriter()
        writer.integer(id)
        writer.bytes.append(contentsOf: text.utf8)
        return BonsaiNativeEvent(id: 2, payload: writer.bytes)
      }()
    }
  }
}

@MainActor @Observable final class ComposerController {
  private(set) var text = ""
  private(set) var focused = false
  private(set) var collapsed = false
  private(set) var limitReached = false
  private(set) var active = false
  @ObservationIgnored private var editorStorage: NativeTextController?
  @ObservationIgnored private var properties: RenderComposer?
  @ObservationIgnored private var emit: (ComposerEvent) -> Bool = { _ in false }
  @ObservationIgnored private var disposed = false
  @ObservationIgnored private var requestedAutofocus = false
  @ObservationIgnored private var autofocusPending = false

  var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  var expanded: Bool { !collapsed && (hasText || focused) }
  var editor: NativeTextController {
    if let editorStorage { return editorStorage }
    let snapshot = try! TextSnapshot(
      sessionID: 1, documentRevision: 0, acceptedLocalRevision: 0, mode: .forceReplace,
      value: TextValue(text: "", selection: NSRange(location: 0, length: 0)))
    let created = NativeTextController(
      snapshot: snapshot, configuration: try! TextEditorConfiguration(),
      emit: { [weak self] in self?.input($0) ?? false }, failed: { _ in })
    editorStorage = created
    return created
  }

  func synchronize(
    _ context: BonsaiNativeContext<RenderComposer, ComposerEvent, ComposerController>
  ) {
    guard !disposed else { return }
    properties = context.properties
    active = context.isPresented
    emit = context.emit
    editor.configure(try! TextEditorConfiguration(enabled: context.properties.enabled))
    #if os(macOS)
      editor.view.setAccessibilityLabel(context.properties.hint)
    #else
      editor.view.accessibilityLabel = context.properties.hint
    #endif
    if context.properties.autofocus && !requestedAutofocus {
      requestedAutofocus = true
      autofocusPending = true
    }
  }

  private func input(_ payload: NativeEventPayload) -> Bool {
    guard !disposed, active, properties?.enabled == true else { return false }
    switch payload {
    case .textEdit(let edit):
      if !edit.value.text.utf8.elementsEqual(text.utf8) {
        guard emit(.changed(edit.value.text)) else { return false }
        text = edit.value.text
        limitReached = false
      }
      return true
    case .focusChanged(let value):
      focused = value
      if value { collapsed = false }
      return true
    case .textLimitReached:
      limitReached = true
      return true
    default: return false
    }
  }

  func shows(_ action: RenderComposer.Action) -> Bool {
    action.visibility == 0 || (action.visibility == 1 ? !hasText : hasText)
  }
  func press(_ action: RenderComposer.Action) {
    guard !disposed, active, properties?.enabled == true,
      properties?.actions.contains(action) == true, action.enabled, shows(action)
    else { return }
    _ = emit(.action(action.id, editor.session.value.text))
  }
  func focusIfRequested() {
    guard !disposed, active, properties?.enabled == true, autofocusPending else { return }
    #if os(macOS)
      if editor.view.window?.makeFirstResponder(editor.view) == true { autofocusPending = false }
    #else
      if editor.view.window != nil, editor.view.becomeFirstResponder() { autofocusPending = false }
    #endif
  }
  private func unfocus() {
    guard let editor = editorStorage else { return }
    #if os(macOS)
      if editor.view.window?.firstResponder === editor.view {
        editor.view.window?.makeFirstResponder(nil)
      }
    #else
      editor.view.resignFirstResponder()
    #endif
    focused = false
  }
  func beginPresentation() {
    guard !disposed else { return }
    collapsed = false
    autofocusPending = true
  }
  func collapse() {
    guard active, properties?.enabled == true else { return }
    collapsed = true
    unfocus()
  }
  func suspend() {
    unfocus()
    active = false
    emit = { _ in false }
  }
  func dispose() {
    guard !disposed else { return }
    suspend()
    disposed = true
    editorStorage?.dispose()
  }
}

@MainActor enum NativeMessageComposer {
  static var definition: NativeViewDefinition {
    BonsaiNativeViews.definition(
      version: 1, capabilities: [.stateful, .semantics], decode: RenderComposer.decode,
      validateChildren: { properties, count in
        guard properties.actions.count == count else { throw TreeError.invalidChildren }
      },
      encodeEvent: { $0.encoded }, makeResource: { ComposerController() },
      dispose: { $0.dispose() }, content: { NativeMessageComposerView(context: $0) })
  }
}

struct NativeMessageComposerView: View {
  let context: BonsaiNativeContext<RenderComposer, ComposerEvent, ComposerController>
  var closeSheet: (() -> Void)? = nil
  private var isExpanded: Bool { closeSheet != nil || controller.expanded }
  private var controller: ComposerController { context.resource }
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private func actions(leading: Bool = false, role: Int? = nil) -> some View {
    ForEach(Array(context.properties.actions.enumerated()), id: \.element.id) { index, action in
      if (role.map { action.role == $0 } ?? (action.leading == leading)) && controller.shows(action)
      {
        let label = NativeNodeView(node: context.children[index].node, activate: { _ in })
          .disabled(true).allowsHitTesting(false).accessibilityHidden(true)
        let button = Button(role: closeSheet != nil && action.role == 2 ? .cancel : nil) {
          guard context.isPresented, context.canInteract() else { return }
          controller.press(action)
        } label: {
          label
        }
        .accessibilityLabel(action.tooltip).help(action.tooltip)
        .disabled(!context.properties.enabled || !action.enabled || !context.isPresented)
        if closeSheet != nil {
          button
        } else if action.prominent {
          button.buttonStyle(.borderedProminent)
        } else {
          button.buttonStyle(.plain)
        }
      }
    }
  }
  var sheetContent: some View {
    body
      .toolbar {
        if let closeSheet {
          ToolbarItemGroup(placement: .cancellationAction) {
            Button("Close", role: .cancel, action: closeSheet).keyboardShortcut(.cancelAction)
            actions(role: 2)
          }
          ToolbarItemGroup(placement: .confirmationAction) { actions(role: 1) }
          ToolbarItemGroup(placement: .automatic) { actions(role: 0) }
        }
      }
  }

  var body: some View {
    VStack(spacing: 8) {
      if isExpanded && closeSheet == nil {
        HStack {
          Color.clear.frame(height: 16).contentShape(Rectangle())
            .gesture(
              DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height > 50
                  && value.translation.height > abs(value.translation.width)
                {
                  controller.collapse()
                }
              })
          Button(
            "Collapse composer", systemImage: "chevron.down"
          ) {
            controller.collapse()
          }
          .labelStyle(.iconOnly).buttonStyle(.plain)
          .disabled(closeSheet == nil && !context.properties.enabled)
        }
      }
      NativeTextEditorView(
        controller: controller.editor,
        maximumLines: isExpanded ? context.properties.maximumLines : 1
      )
      .fixedSize(horizontal: false, vertical: true)
      .overlay(alignment: .topLeading) {
        if controller.text.isEmpty {
          Text(context.properties.hint).foregroundStyle(.secondary).padding(.horizontal, 6)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
      }
      if closeSheet == nil {
        HStack {
          actions(leading: true)
          Spacer(minLength: 12)
          actions(leading: false)
        }
      }
      if controller.limitReached {
        Text("Draft limit reached").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .background {
      if closeSheet == nil { RoundedRectangle(cornerRadius: 16).fill(.background) }
    }
    .overlay {
      if closeSheet == nil { RoundedRectangle(cornerRadius: 16).strokeBorder(.separator) }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: controller.expanded)
    .onChange(of: context.properties, initial: true) { _, _ in controller.synchronize(context) }
    .onChange(of: context.isPresented) { _, _ in controller.synchronize(context) }
    .onChange(of: context.children.map(\.id)) { _, _ in controller.synchronize(context) }
    .onAppear { controller.synchronize(context) }
    .onDisappear { controller.suspend() }
    .task(id: context.isPresented) {
      await Task.yield()
      controller.focusIfRequested()
    }
  }
}
