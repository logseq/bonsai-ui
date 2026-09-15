import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor
struct RenderTreeTests {
  @Test(arguments: [100, 1000])
  func controllerIndexesExcludeDecorationsAndClearOnTeardown(decorations: Int) throws {
    let tree = RenderTree()
    var operations = [
      TreeFixture.create(1), TreeFixture.editor(3, kind: 47), TreeFixture.editor(2, kind: 47),
    ]
    let ids = (0..<decorations).map { UInt64($0 + 10) }
    operations += ids.map { TreeFixture.text($0, "Decorative text") }
    operations += [TreeFixture.children(1, [3, 2] + ids), TreeFixture.root(1)]
    tree.commit(try NodeStore().staging(TreeFixture.frame(operations)).tree)
    #expect(tree.nodes.count == decorations + 3)
    #expect(tree.fieldNodes.map(\.id.node) == [2, 3])
    #expect(tree.collectionNodes.isEmpty)
    #expect(tree.focusAndGestureNodes.isEmpty)
    #expect(tree.animationNodes.isEmpty)
    tree.commit(NodeStore())
    #expect(tree.fieldNodes.isEmpty)
    #expect(tree.nodes.isEmpty)
  }

  @Test func nativeEnvironmentReachesDescendantViews() throws {
    let content = EnvironmentProbe().modifier(
      SwiftUIEnvironmentModifier(
        values: ViewEnvironment(mode: 2, tint: 0xff67_50a4, fontFamily: "Inter", controlSize: 3)))
    let renderer = ImageRenderer(content: content)
    let cgImage = try #require(renderer.cgImage)
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    let color = try #require(bitmap.colorAt(x: 4, y: 4)?.usingColorSpace(.sRGB))
    #expect(color.greenComponent > color.redComponent)
  }

  @Test func committedUpdatesReuseUnchangedNodesAndKeyedChildren() throws {
    let store = try NodeStore().staging(TreeFixture.initial).tree
    let model = RenderTree()
    model.commit(store)
    let originalRoot = try #require(model.root)
    let originalButton = try #require(model.nodes[3])
    let originalText = try #require(model.nodes[2])
    let next = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.text(2, "Count: 1", update: true), TreeFixture.children(1, [3, 2]),
        ], base: 1, revision: 2)
    ).tree
    model.commit(next)
    #expect(model.root === originalRoot)
    #expect(model.nodes[3] === originalButton)
    #expect(model.nodes[2] === originalText)
    #expect(originalText.properties == .text("Count: 1"))
    #expect(originalRoot.children.map(\.id.node) == [3, 2])
    let restart = TreeFixture.frame(TreeFixture.initial.operations, epoch: 8)
    model.commit(try NodeStore().staging(restart).tree)
    #expect(model.root !== originalRoot)
    #expect(model.nodes[3] !== originalButton)
    #expect(model.nodes[3]?.id.epoch == 8)
  }

  @Test func swiftUIProducesNonemptyNativeContent() throws {
    let model = RenderTree()
    model.commit(try NodeStore().staging(TreeFixture.initial).tree)
    let root = try #require(model.root)
    let renderer = ImageRenderer(content: NativeNodeView(node: root, activate: { _ in }))
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    #expect(image.width > 30)
    #expect(image.height > 30)
    let bytes = try #require(image.dataProvider?.data)
    #expect(CFDataGetLength(bytes) > 0)
  }
}

private struct EnvironmentProbe: View {
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.controlSize) var controlSize
  @Environment(\.bonsaiFontFamily) var fontFamily

  var body: some View {
    let valid = colorScheme == .dark && controlSize == .large && fontFamily == "Inter"
    (valid ? Color.green : Color.red).frame(width: 8, height: 8)
  }
}
