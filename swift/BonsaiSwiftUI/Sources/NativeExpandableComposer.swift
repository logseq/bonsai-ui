import Foundation
import Observation
import SwiftUI

struct RenderExpandableComposer: Equatable {
  let composer: RenderComposer
  let label: String
  let tooltip: String
  let compact: Bool
  let duration: Double
  let curve: Int

  static func decode(_ data: Data) throws -> Self {
    var reader = WireReader(data)
    let enabled = try reader.flag()
    let curve = try reader.choice(3)
    let duration = Double(try reader.integer(UInt16.self)) / 1000
    let lines = Int(try reader.integer(UInt16.self))
    let count = Int(try reader.integer(UInt16.self))
    guard lines > 0, count < 65535 else { throw TreeError.invalidProperties }
    let lengths = try (0..<3).map { _ in Int(try reader.integer(UInt32.self)) }
    let compact = try reader.flag()
    for _ in 0..<3 {
      guard try reader.integer(UInt8.self) == 0 else { throw TreeError.invalidProperties }
    }
    let strings = try lengths.map { length in
      guard length <= ProtocolLimits.maxStringBytes else { throw WireError.limitExceeded }
      guard let string = String(data: try reader.data(length), encoding: .utf8)
      else { throw TreeError.invalidProperties }
      return string
    }
    guard !strings[0].isEmpty, !strings[1].isEmpty else { throw TreeError.invalidProperties }
    let actions = try RenderComposer.decodeActions(&reader, count: count, trimTooltip: false)
    guard reader.remaining == 0 else { throw TreeError.invalidProperties }
    return Self(
      composer: RenderComposer(
        enabled: enabled, autofocus: true, maximumLines: lines,
        hint: strings[2], actions: actions),
      label: strings[0], tooltip: strings[1], compact: compact, duration: duration, curve: curve)
  }

  func animation(reduceMotion: Bool) -> Animation? {
    guard duration > 0, !reduceMotion else { return nil }
    switch curve {
    case 0: return .linear(duration: duration)
    case 1: return .easeIn(duration: duration)
    case 2: return .easeOut(duration: duration)
    default: return .easeInOut(duration: duration)
    }
  }
}

@MainActor @Observable final class ExpandableComposerController: NativeModalResource {
  let composer = ComposerController()
  private(set) var generation: UInt64 = 0
  private(set) var requested = false
  private(set) var visible = false
  private(set) var closing = false
  @ObservationIgnored private var disposed = false
  var blocksBackgroundInput: Bool { !disposed && (requested || visible || closing) }

  func open(
    _ context: BonsaiNativeContext<
      RenderExpandableComposer, ComposerEvent, ExpandableComposerController
    >
  ) {
    guard !disposed, !requested, !closing, context.properties.composer.enabled,
      context.canInteract()
    else { return }
    generation += 1
    requested = true
    composer.beginPresentation()
  }
  func appeared(_ token: UInt64) {
    guard !disposed, requested, generation == token else { return }
    visible = true
  }
  func close(_ token: UInt64) {
    guard !disposed, requested, generation == token else { return }
    requested = false
    closing = true
    composer.suspend()
  }
  func disappeared(_ token: UInt64) {
    guard generation == token else { return }
    visible = false
  }
  func dismissed(_ token: UInt64) {
    guard generation == token, !requested else { return }
    closing = false
    visible = false
  }
  func accepts(_ token: UInt64) -> Bool {
    !disposed && requested && visible && generation == token
  }
  func binding(_ token: UInt64) -> Binding<Bool> {
    Binding(
      get: { self.generation == token && self.requested },
      set: {
        if !$0 { self.close(token) }
      })
  }
  func dispose() {
    guard !disposed else { return }
    disposed = true
    requested = false
    closing = false
    visible = false
    generation += 1
    composer.dispose()
  }
}

@MainActor enum NativeExpandableComposer {
  static var definition: NativeViewDefinition {
    BonsaiNativeViews.definition(
      version: 2, capabilities: [.stateful, .semantics], decode: RenderExpandableComposer.decode,
      validateChildren: { properties, count in
        guard properties.composer.actions.count + 1 == count else {
          throw TreeError.invalidChildren
        }
      }, encodeEvent: { $0.encoded }, makeResource: { ExpandableComposerController() },
      dispose: { $0.dispose() }, content: { NativeExpandableComposerView(context: $0) })
  }
}

private struct NativeExpandableComposerView: View {
  let context:
    BonsaiNativeContext<RenderExpandableComposer, ComposerEvent, ExpandableComposerController>
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var controller: ExpandableComposerController { context.resource }

  private func surface(_ token: UInt64) -> some View {
    let nested = BonsaiNativeContext(
      properties: context.properties.composer, resource: controller.composer,
      children: Array(context.children.dropFirst()),
      isPresented: context.isPresented && controller.accepts(token),
      canInteract: { controller.accepts(token) && context.canInteract() },
      emit: { (event: ComposerEvent) in
        controller.accepts(token) && context.canInteract() && context.emit(event)
      })
    return NativeMessageComposerView(context: nested, closeSheet: { controller.close(token) })
      .onAppear { controller.appeared(token) }
      .onDisappear { controller.disappeared(token) }
      .id(token)
  }

  var body: some View {
    let token = controller.generation
    Button {
      controller.open(context)
    } label: {
      HStack {
        NativeNodeView(node: context.children[0].node, activate: { _ in })
          .disabled(true).allowsHitTesting(false).accessibilityHidden(true)
        if !context.properties.compact { Text(context.properties.label) }
      }
      .padding(6)
    }
    .buttonStyle(.borderedProminent)
    .accessibilityLabel(context.properties.tooltip).help(context.properties.tooltip)
    .disabled(
      !context.isPresented || !context.properties.composer.enabled
        || controller.blocksBackgroundInput
    )
    .accessibilityHidden(controller.blocksBackgroundInput)
    .animation(
      context.properties.animation(reduceMotion: reduceMotion), value: context.properties.compact
    )
    .sheet(
      isPresented: controller.binding(token), onDismiss: { controller.dismissed(token) },
      content: {
        #if os(macOS)
          surface(token).frame(minWidth: 480, idealWidth: 600, maxWidth: 800)
            .presentationSizing(.fitted)
        #else
          surface(token).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        #endif
      })
  }
}
