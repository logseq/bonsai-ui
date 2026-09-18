import Testing

@testable import BonsaiSwiftUI

struct NativeListStyleTests {
  private func frame(_ style: UInt8) -> WireFrame {
    TreeFixture.frame([
      TreeFixture.operation(OperationId.createNode) {
        $0.integer(UInt64(1))
        $0.integer(UInt16(NodeKindId.nativeList))
        $0.integer(style)
        $0.integer(UInt8(0))
        $0.integer(UInt16(0))
      }, TreeFixture.root(1),
    ])
  }

  @Test(arguments: [UInt8(0), UInt8(1)])
  func supportedStylesPublishNativeList(style: UInt8) throws {
    let store = try NodeStore().staging(frame(style)).tree
    #expect(store.root == 1)
  }

  @Test func unavailableStyleFailsBeforePublicationWithCapabilityDiagnostic() throws {
    do {
      _ = try NodeStore().staging(frame(2))
      Issue.record("macOS accepted Inset_grouped")
    } catch {
      #expect(String(describing: error).contains("Inset_grouped"))
      #expect(String(describing: error).contains("macOS"))
    }
  }

  @Test func malformedStyleIsRejected() {
    #expect(throws: (any Error).self) { try NodeStore().staging(frame(3)) }
  }
}
