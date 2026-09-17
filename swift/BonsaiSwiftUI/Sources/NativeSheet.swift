import SwiftUI

struct RenderSheet: Equatable, Sendable {
  struct Configuration: Equatable, Sendable {
    let fullscreen: Bool
    let fraction: Double
    let detents: Int
    let initial: Int
    let interactive: Bool
    let indicator: Bool
    let sizing: Int
  }
  let presented: Bool
  let configuration: Configuration
  static func decode(_ reader: inout WireReader) throws -> Self {
    let presented = try reader.flag()
    let fullscreen = try reader.flag()
    let detents = try reader.choice(7)
    let initial = try reader.choice(2)
    let interactive = try reader.flag()
    let indicator = try reader.flag()
    let sizing = try reader.choice(3)
    let fraction = Double(bitPattern: try reader.integer(UInt64.self))
    guard fraction.isFinite,
      detents & 4 != 0 ? fraction > 0 && fraction <= 1 : fraction == 0,
      detents > 0, detents & (1 << initial) != 0,
      !fullscreen || (detents == 2 && initial == 1 && !interactive && !indicator && sizing == 0)
    else { throw TreeError.invalidProperties }
    return Self(
      presented: presented,
      configuration: Configuration(
        fullscreen: fullscreen, fraction: fraction,
        detents: detents, initial: initial, interactive: interactive, indicator: indicator,
        sizing: sizing))
  }
}

struct NativeSheet: View {
  let node: RenderNodeState
  let controller: PresentationController
  let properties: RenderSheet
  let activate: @MainActor (RenderNodeState) -> Void
  @State private var detent: Int
  init(
    node: RenderNodeState, controller: PresentationController, properties: RenderSheet,
    activate: @escaping @MainActor (RenderNodeState) -> Void
  ) {
    self.node = node
    self.controller = controller
    self.properties = properties
    self.activate = activate
    _detent = State(initialValue: properties.configuration.initial)
  }
  private var content: some View {
    NativePresentationContent(node: node.children[1], controller: controller, activate: activate)
      .interactiveDismissDisabled(!properties.configuration.interactive)
  }
  @ViewBuilder private var sizedContent: some View {
    switch properties.configuration.sizing {
    case 1: content.presentationSizing(.fitted)
    case 2: content.presentationSizing(.form)
    case 3: content.presentationSizing(.page)
    default: content.presentationSizing(.automatic)
    }
  }
  #if os(iOS)
    private func nativeDetent(_ value: Int) -> PresentationDetent {
      switch value {
      case 0: .medium
      case 1: .large
      default: .fraction(properties.configuration.fraction)
      }
    }
  #endif
  private var background: some View { NativeNodeView(node: node.children[0], activate: activate) }
  @ViewBuilder private var presentation: some View {
    #if os(iOS)
      if properties.configuration.fullscreen {
        background.fullScreenCover(isPresented: controller.nativeBinding(emit: node.emit)) { content }
      } else {
        background.sheet(isPresented: controller.nativeBinding(emit: node.emit)) {
          sizedContent
            .presentationDetents(
              Set(
                [0, 1, 2].filter { properties.configuration.detents & (1 << $0) != 0 }
                  .map(nativeDetent)),
              selection: Binding(
                get: { nativeDetent(detent) },
                set: { value in detent = value == .medium ? 0 : value == .large ? 1 : 2 })
            )
            .presentationDragIndicator(properties.configuration.indicator ? .visible : .hidden)
        }
      }
    #else
      background.sheet(isPresented: controller.nativeBinding(emit: node.emit)) { sizedContent }
    #endif
  }
  var body: some View {
    presentation
      .onChange(of: properties.configuration) { _, value in detent = value.initial }
      .onChange(of: properties.presented) { _, value in
        if value { detent = properties.configuration.initial }
      }
  }
}
