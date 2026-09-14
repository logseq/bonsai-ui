import SwiftUI

struct RenderSheet: Equatable, Sendable {
  struct Configuration: Equatable, Sendable {
    let fullscreen: Bool
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
    let detents = try reader.choice(3)
    let initial = try reader.choice(1)
    let interactive = try reader.flag()
    let indicator = try reader.flag()
    let sizing = try reader.choice(3)
    guard detents > 0, detents & (1 << initial) != 0,
      !fullscreen || (detents == 2 && initial == 1 && !interactive && !indicator && sizing == 0)
    else { throw TreeError.invalidProperties }
    return Self(
      presented: presented,
      configuration: Configuration(
        fullscreen: fullscreen,
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
    let token = controller.generation
    return NativeNodeView(node: node.children[1], activate: activate)
      .interactiveDismissDisabled(!properties.configuration.interactive)
      .onAppear { controller.appeared(true, token: token) }
      .onDisappear { controller.appeared(false, token: token) }
      .id(token)
  }
  @ViewBuilder private var sizedContent: some View {
    switch properties.configuration.sizing {
    case 1: content.presentationSizing(.fitted)
    case 2: content.presentationSizing(.form)
    case 3: content.presentationSizing(.page)
    default: content.presentationSizing(.automatic)
    }
  }
  private var background: some View { NativeNodeView(node: node.children[0], activate: activate) }
  @ViewBuilder private var presentation: some View {
    #if os(iOS)
      if properties.configuration.fullscreen {
        background.fullScreenCover(isPresented: controller.binding(emit: node.emit)) { content }
      } else {
        background.sheet(isPresented: controller.binding(emit: node.emit)) {
          sizedContent
            .presentationDetents(
              Set(
                [0, 1].filter { properties.configuration.detents & (1 << $0) != 0 }
                  .map { $0 == 0 ? PresentationDetent.medium : .large }),
              selection: Binding(
                get: { detent == 0 ? .medium : .large }, set: { detent = $0 == .medium ? 0 : 1 })
            )
            .presentationDragIndicator(properties.configuration.indicator ? .visible : .hidden)
        }
      }
    #else
      background.sheet(isPresented: controller.binding(emit: node.emit)) { sizedContent }
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
