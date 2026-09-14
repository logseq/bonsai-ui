import QuartzCore
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func projection(_ id: UInt64, _ values: [Double], update: Bool = false) -> WireOperation {
    modifier(id, kind: 29, mask: 1, update: update) { writer in
      for value in values { writer.integer(value.bitPattern) }
    }
  }
}

@MainActor struct ProjectionTests {
  private let identity: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]

  @Test func affineAndPerspectiveEffectsMatchNativeProjectionInBothDirections() throws {
    let cases: [[Double]] = [
      identity, [0.8, 0, 0, 0, 1.2, 0, 0, 0, 1],
      [1, 0, 0, 0, 1, 0, 16, -8, 1],
      [1, 0.2, 0.002, 0.3, 1, 0.001, 0, 0, 1],
      [-1, 0, 0, 0, 1, 0, 30, 0, 1],
      [0, 1, 0, -1, 0, 0, 30, 0, 1],
    ]
    for values in cases {
      let model = try tree(values)
      for direction in [LayoutDirection.leftToRight, .rightToLeft] {
        let actual = NativeNodeView(node: try #require(model.root), activate: { _ in })
          .frame(width: 180, height: 120)
        let expected = label.projectionEffect(reference(values)).frame(width: 180, height: 120)
        let image = try raster(actual, direction)
        #expect(try image.matches(raster(expected, direction)))
        #expect(
          stride(from: 0, to: image.pixels.count, by: 4).contains {
            image.pixels[$0] > 200 && image.pixels[$0 + 1] < 100 && image.pixels[$0 + 2] < 100
          })
      }
    }
  }

  @Test func modifierOrderAndNativeLayoutExtentRemainIndependent() throws {
    let scale: [Double] = [2, 0, 0, 0, 1, 0, 0, 0, 1]
    let translation: [Double] = [1, 0, 0, 0, 1, 0, 16, 0, 1]
    var images: [ViewRaster] = []
    for (inner, outer) in [(scale, translation), (translation, scale)] {
      let model = try tree(inner, outer: outer)
      let actual = NativeNodeView(node: try #require(model.root), activate: { _ in })
        .frame(width: 200, height: 100)
      let expected = label.projectionEffect(reference(inner)).projectionEffect(reference(outer))
        .frame(width: 200, height: 100)
      let image = try raster(actual)
      #expect(try image.matches(raster(expected)))
      images.append(image)
    }
    #expect(images[0].pixels != images[1].pixels)
    #expect(
      try raster(NativeNodeView(node: #require(tree(scale).root), activate: { _ in })).width
        == raster(label).width)
  }

  @Test func malformedMatricesCannotPublishPartialUpdates() throws {
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.projection(1, identity), TreeFixture.text(2, "Original"),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    var invalid = [
      TreeFixture.children(1, []), TreeFixture.children(1, [2, 2]),
      TreeFixture.projection(1, identity + [0, 0, 0, 0, 0, 0, 0], update: true),
    ]
    for value in [Double.nan, .infinity, -.infinity] {
      for index in identity.indices {
        var matrix = identity
        matrix[index] = value
        invalid.append(TreeFixture.projection(1, matrix, update: true))
      }
    }
    let update = TreeFixture.projection(1, identity, update: true)
    for count in 0..<update.body.count {
      invalid.append(WireOperation(opcode: update.opcode, body: update.body.prefix(count)))
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try initial.staging(
          TreeFixture.frame(
            [
              TreeFixture.text(2, "Must not leak", update: true), operation,
            ], base: 1, revision: 2))
      }
      #expect(initial.revision == 1)
    }
  }

  private var label: some View {
    Image(systemName: "star.fill").font(.system(size: 30)).symbolRenderingMode(.monochrome)
      .foregroundStyle(Color(.sRGB, red: 1, green: 0, blue: 0))
  }
  private func tree(_ values: [Double], outer: [Double]? = nil) throws -> RenderTree {
    var operations = [
      TreeFixture.projection(1, values), TreeFixture.symbol(2, name: "star.fill", size: 30),
      TreeFixture.children(1, [2]),
    ]
    if let outer {
      operations += [
        TreeFixture.projection(3, outer), TreeFixture.children(3, [1]), TreeFixture.root(3),
      ]
    } else {
      operations.append(TreeFixture.root(1))
    }
    let model = RenderTree()
    model.commit(try NodeStore().staging(TreeFixture.frame(operations)).tree)
    return model
  }
  private func reference(_ values: [Double]) -> ProjectionTransform {
    var transform = CATransform3DIdentity
    transform.m11 = values[0]
    transform.m12 = values[1]
    transform.m14 = values[2]
    transform.m21 = values[3]
    transform.m22 = values[4]
    transform.m24 = values[5]
    transform.m41 = values[6]
    transform.m42 = values[7]
    transform.m44 = values[8]
    return ProjectionTransform(transform)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryProjectionUpdatesPreserveControlsAndActivation() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func named(_ title: String, _ node: RenderNodeState) -> Bool {
      if case .text(let text) = node.properties, text.value == title { return true }
      return node.children.contains { named(title, $0) }
    }
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first {
          if case .button = $0.properties { return named(title, $0) }
          return false
        })
    }
    func press(_ title: String) async throws {
      #expect(session.activate(try button(title)))
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    do {
      try await session.start(entrypoint: "native-projection")
      #expect(try await session.presented(#require(session.ticket)))
      let projected = try button("Projected action")
      let modifier = try #require(session.tree.nodes.values.first { $0.kind == 29 })
      let first = modifier.properties
      for index in 1...4 {
        try await press("Next projection")
        #expect(named("Projection mode: \(index % 4)", try #require(session.tree.root)))
        #expect(try button("Projected action") === projected)
        #expect(session.tree.nodes[modifier.id.node] === modifier)
        if index < 4 { #expect(modifier.properties != first) }
        try await press("Projected action")
        #expect(named("Projected actions: \(index)", try #require(session.tree.root)))
      }
      #expect(modifier.properties == first)
      await session.close()
      #expect(!session.activate(projected))
    } catch {
      await session.close()
      throw error
    }
  }
}
