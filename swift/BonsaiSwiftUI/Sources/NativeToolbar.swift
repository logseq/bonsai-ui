import SwiftUI

struct RenderToolbar: Equatable, Sendable {
  let placements: [Int]
  static func decode(_ reader: inout WireReader) throws -> Self {
    let count = Int(try reader.integer(UInt16.self))
    guard count <= 256 else { throw TreeError.invalidProperties }
    var placements: [Int] = []
    for _ in 0..<count { placements.append(try reader.choice(8)) }
    guard placements.filter({ $0 == 1 }).count <= 1 else { throw TreeError.invalidProperties }
    return Self(placements: placements)
  }
}

struct NativeToolbar: View {
  let node: RenderNodeState
  let properties: RenderToolbar
  let activate: @MainActor (RenderNodeState) -> Void

  private func group(_ value: Int, _ placement: ToolbarItemPlacement) -> some ToolbarContent {
    ToolbarItemGroup(placement: placement) {
      ForEach(
        Array(node.children.dropFirst().enumerated()).filter {
          properties.placements[$0.offset] == value
        }.map(\.element)
      ) { item in
        NativeNodeView(node: item, activate: activate)
      }
    }
  }

  var body: some View {
    NativeNodeView(node: node.children[0], activate: activate)
      .toolbar {
        group(0, .automatic)
        group(1, .principal)
        group(2, .navigation)
        group(3, .primaryAction)
        group(4, .secondaryAction)
        group(5, .status)
        group(6, .confirmationAction)
        group(7, .cancellationAction)
        group(8, .destructiveAction)
      }
  }
}
