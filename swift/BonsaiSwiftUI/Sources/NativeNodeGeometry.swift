import SwiftUI

enum NodeLayoutAnchors: PreferenceKey {
  static let defaultValue: [RenderIdentity: Anchor<CGRect>] = [:]
  static func reduce(
    value: inout [RenderIdentity: Anchor<CGRect>],
    nextValue: () -> [RenderIdentity: Anchor<CGRect>]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

/// Resolve layout at the application root, preserving native child layout traits.
struct NativeLayoutObserver: ViewModifier {
  let tree: RenderTree
  @MainActor private final class Attachment {
    let owner = UUID()
    var nodes: [RenderIdentity: RenderNodeState] = [:]

    func record(_ frames: [RenderIdentity: CGRect], tree: RenderTree) {
      var next: [RenderIdentity: RenderNodeState] = [:]
      for (id, frame) in frames {
        guard let node = tree.nodes[id.node], node.id == id else { continue }
        next[id] = node
        node.layoutOwner = owner
        node.layoutFrame = frame
      }
      for (id, node) in nodes where next[id] !== node && node.layoutOwner == owner {
        node.layoutOwner = nil
        node.layoutFrame = nil
      }
      nodes = next
    }
    func clear() {
      for node in nodes.values where node.layoutOwner == owner {
        node.layoutOwner = nil
        node.layoutFrame = nil
      }
      nodes.removeAll()
    }
  }
  @State private var attachment = Attachment()

  func body(content: Content) -> some View {
    content
      .overlayPreferenceValue(NodeLayoutAnchors.self) { anchors in
        GeometryReader { geometry in
          let frames = anchors.mapValues { geometry[$0] }
          Color.clear
            .onChange(of: frames, initial: true) { _, frames in
              attachment.record(frames, tree: tree)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      .onDisappear { attachment.clear() }
  }
}
