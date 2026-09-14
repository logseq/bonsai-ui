import CryptoKit
import Foundation
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test func fileSelectionPreservesAllResultsAndRejectsMalformedListsInActualOcaml() async throws {
    func record(_ writer: inout WireWriter, path: String?, data: Data?) throws {
      writer.integer(UInt8(path == nil ? 0 : 1))
      if let path { try writer.string(path) }
      writer.integer(UInt8(data == nil ? 0 : 1))
      if let data {
        writer.integer(UInt32(data.count))
        writer.bytes.append(data)
      }
    }
    let opaque = Data([0, 255, 128])
    let digest = Insecure.MD5.hash(data: opaque).map { String(format: "%02x", $0) }.joined()
    var multiple = WireWriter()
    multiple.integer(UInt32(3))
    try record(&multiple, path: "/first/同名.txt", data: nil)
    try record(&multiple, path: "/second/同名.txt", data: opaque)
    try record(&multiple, path: nil, data: Data())
    var empty = WireWriter()
    empty.integer(UInt32(0))
    var oldSingle = WireWriter()
    oldSingle.integer(UInt8(1))
    try record(&oldSingle, path: "/old.txt", data: nil)
    var noFile = WireWriter()
    noFile.integer(UInt32(1))
    try record(&noFile, path: nil, data: nil)
    var invalid: [Data] = (0..<multiple.bytes.count).map { Data(multiple.bytes.prefix($0)) }
    invalid += [
      multiple.bytes + Data([0]), oldSingle.bytes, Data([0]), noFile.bytes,
      Data([255, 255, 255, 255]), Data([1, 0, 0, 0, 2, 0]),
    ]
    let cases =
      [
        (
          multiple.bytes,
          "Files: /first/同名.txt:none|/second/同名.txt:3:\(digest)|none:0:d41d8cd98f00b204e9800998ecf8427e"
        ),
        (empty.bytes, "Files: "),
      ]
      + invalid.map { ($0, "Files: invalid response") }
    let runtime = try await NativeRuntime.open(entrypoint: "native-file-results")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(initial.bytes)
      var tree = try NodeStore().staging(frame).tree
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      var clock: Int64 = 2
      var sequence: UInt64 = 0
      var revision = frame.revision
      for (bytes, expected) in cases {
        let button = try #require(tree.nodes.values.first { $0.bindings[EventTagId.press] != nil })
        sequence += 1
        clock += 1
        let request = try await runtime.pump(
          monotonicNanoseconds: clock,
          events: EventBatch.encode(
            epoch: frame.epoch,
            events: [
              NativeEvent(
                sequence: sequence, displayedRevision: revision, nodeID: button.id,
                handlerID: try #require(button.bindings[EventTagId.press]))
            ]))
        let requestFrame = try WireFrame.decode(request.bytes)
        tree = try tree.staging(requestFrame).tree
        revision = requestFrame.revision
        let operation = try #require(
          requestFrame.operations.first { $0.opcode == OperationId.hostRequest })
        var reader = WireReader(operation.body)
        let id = try reader.integer(UInt64.self)
        let kind = try reader.integer(UInt16.self)
        let count = try reader.integer(UInt16.self)
        let first = try reader.string()
        let second = try reader.string()
        let multiple = try reader.flag()
        #expect(kind == 4 && count == 2)
        #expect(first == "txt" && second == "bin" && multiple)
        #expect(reader.remaining == 0)
        clock += 1
        try await runtime.acknowledge(request, monotonicNanoseconds: clock)
        sequence += 1
        clock += 1
        let response = try await runtime.pump(
          monotonicNanoseconds: clock,
          events: EventBatch.encode(
            epoch: frame.epoch,
            events: [
              NativeEvent(
                sequence: sequence, displayedRevision: revision, nodeID: 0, handlerID: 0,
                payload: .hostResponse(HostResponse(requestID: id, status: .ok, value: bytes)))
            ]))
        #expect(response.status == 0)
        if !response.bytes.isEmpty {
          let update = try WireFrame.decode(response.bytes)
          tree = try tree.staging(update).tree
          revision = update.revision
        }
        #expect(
          tree.nodes.values.contains {
            if case .text(let text) = $0.properties { return text.value == expected }
            return false
          })
        clock += 1
        try await runtime.acknowledge(response, monotonicNanoseconds: clock)
      }
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
