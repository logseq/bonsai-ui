import SwiftUI

struct RenderPopover: Equatable, Sendable {
  let presented: Bool
  let edge: Int
  static func decode(_ reader: inout WireReader) throws -> Self {
    Self(presented: try reader.flag(), edge: try reader.choice(4))
  }
  var arrowEdge: Edge? {
    switch edge {
    case 1: .top
    case 2: .bottom
    case 3: .leading
    case 4: .trailing
    default: nil
    }
  }
}

struct NativePopover: View {
  let node: RenderNodeState
  let controller: PresentationController
  let properties: RenderPopover
  let activate: @MainActor (RenderNodeState) -> Void
  var body: some View {
    let token = controller.generation
    NativeNodeView(node: node.children[0], activate: activate)
      .popover(isPresented: controller.binding(emit: node.emit), arrowEdge: properties.arrowEdge) {
        NativeNodeView(node: node.children[1], activate: activate)
          .onAppear { controller.appeared(true, token: token) }
          .onDisappear { controller.appeared(false, token: token) }
          .id(token)
      }
  }
}
