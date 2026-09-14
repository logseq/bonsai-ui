import Foundation
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func image(
    _ id: UInt64 = 1, source: UInt8 = 0, location: String = "gallery-demo.png",
    sizing: UInt8 = 0, scale: Double = 1, update: Bool = false
  ) -> WireOperation {
    modifier(id, kind: NodeKindId.image, mask: 7, update: update) {
      $0.integer(source)
      $0.integer(UInt32(location.utf8.count))
      $0.bytes.append(contentsOf: location.utf8)
      $0.integer(sizing)
      $0.integer(scale.bitPattern)
    }
  }
}

struct ImageWireTests {
  @Test func imageSourcesAndNativeSizingStageAndUpdate() throws {
    for source: UInt8 in [0, 1] {
      for sizing: UInt8 in [0, 1, 2, 3] {
        let operation = TreeFixture.image(
          source: source,
          location: source == 0 ? "gallery-demo.png" : "https://example.invalid/image.png",
          sizing: sizing)
        let before = try NodeStore().staging(TreeFixture.frame([operation, TreeFixture.root(1)]))
          .tree
        #expect(before.nodes[1]?.kind == NodeKindId.image)
        let after = try before.staging(
          TreeFixture.frame([TreeFixture.image(scale: 2, update: true)], base: 1, revision: 2)
        ).tree
        #expect(after.nodes[1]?.properties != before.nodes[1]?.properties)
      }
    }
  }

  @Test func malformedImagesCannotPublishPartialUpdates() throws {
    let before = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.create(1), TreeFixture.text(2, "Original"), TreeFixture.image(3),
        TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
      ])
    ).tree
    var invalid = [
      TreeFixture.image(3, source: 2, update: true), TreeFixture.image(3, sizing: 4, update: true),
    ]
    for path in [
      "", "/tmp/private.png", "../escape.png", "a/../b.png", "a//b.png", "a\\b.png", "a\0b.png",
    ] {
      invalid.append(TreeFixture.image(3, location: path, update: true))
    }
    for url in [
      "", "relative.png", "file:///tmp/image.png", "https://", "ftp://host/image.png",
      "https://host/a\0b",
    ] {
      invalid.append(TreeFixture.image(3, source: 1, location: url, update: true))
    }
    for scale in [0, -1, Double.nan, .infinity, -.infinity] {
      invalid.append(TreeFixture.image(3, scale: scale, update: true))
    }
    let valid = TreeFixture.image(3, update: true)
    for count in 0..<valid.body.count {
      invalid.append(WireOperation(opcode: valid.opcode, body: valid.body.prefix(count)))
    }
    let snapshot = before
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try before.staging(
          TreeFixture.frame(
            [TreeFixture.text(2, "Must not leak", update: true), operation], base: 1, revision: 2))
      }
      #expect(before == snapshot)
    }
    #expect(throws: (any Error).self) {
      try before.staging(
        TreeFixture.frame(
          [TreeFixture.text(4, "Unexpected child"), TreeFixture.children(3, [4])], base: 1,
          revision: 2))
    }
  }
}
