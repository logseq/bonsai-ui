import Foundation
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test func decodeRealOcamlFrameAndRejectCorruptTransport() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "counter")
    let output = try await runtime.pump(monotonicNanoseconds: 1)
    let frame = try WireFrame.decode(output.bytes)
    #expect(frame.kind == FrameKindId.fullSnapshot)
    #expect(frame.epoch > 0)
    #expect(frame.baseRevision == 0)
    #expect(frame.revision == output.revision)
    #expect(frame.operations.contains { $0.opcode == OperationId.createNode })
    #expect(frame.operations.contains { $0.opcode == OperationId.setRoot })

    // Every truncation must fail without reading outside the supplied data.
    for length in 0..<output.bytes.count {
      #expect(throws: (any Error).self) {
        try WireFrame.decode(output.bytes.prefix(length))
      }
    }
    let mutations: [(Int, UInt8, WireError)] = [
      (0, 0, .invalidMagic), (4, 255, .incompatibleVersion),
      (6, 255, .incompatibleVersion), (8, 47, .invalidHeader),
      (10, 4, .invalidFrameKind), (11, 1, .invalidHeader),
      (19, 255, .invalidHeader), (40, 1, .invalidHeader),
      (44, 1, .invalidHeader), (48, 99, .invalidOrder),
    ]
    for (offset, value, expected) in mutations {
      var corrupt = output.bytes
      corrupt[offset] = value
      #expect(throws: expected) { try WireFrame.decode(corrupt) }
    }
    var trailing = output.bytes
    trailing.append(0)
    #expect(throws: WireError.invalidLength) { try WireFrame.decode(trailing) }
    var unknownOperation = output.bytes
    unknownOperation[53] = 255
    #expect(throws: WireError.invalidOperation) { try WireFrame.decode(unknownOperation) }
    var oversizedOperation = output.bytes
    oversizedOperation.replaceSubrange(54..<58, with: [255, 255, 255, 255])
    #expect(throws: WireError.truncated) { try WireFrame.decode(oversizedOperation) }
    var missingEnd = output.bytes
    missingEnd[missingEnd.count - 5] = UInt8(OperationId.beginFrame)
    #expect(throws: WireError.invalidOrder) { try WireFrame.decode(missingEnd) }
    #expect(throws: WireError.limitExceeded) {
      try WireFrame.decode(Data(count: ProtocolLimits.maxFrameBytes + 1))
    }
    // Data slices can have a nonzero startIndex and need not be aligned.
    var padded = Data([0])
    padded.append(output.bytes)
    #expect(try WireFrame.decode(padded.dropFirst()) == frame)
    await runtime.close()
  }
}
