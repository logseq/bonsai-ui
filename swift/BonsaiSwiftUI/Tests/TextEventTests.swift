import Foundation
import Testing

@testable import BonsaiSwiftUI

struct TextEventTests {
  @Test func unicodeEditMatchesCanonicalCrossLanguageBytes() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let fixture = try String(
      contentsOf: root.appendingPathComponent(
        "protocol/generated/fixtures/swift_text_edit_unicode.hex"), encoding: .utf8)
    let expected = Data(
      try fixture.split(whereSeparator: \.isWhitespace).map { try #require(UInt8($0, radix: 16)) })
    let edit = TextEdit(
      sessionID: 7, localRevision: 3, baseDocumentRevision: 2,
      value: try textValue("拼😀音", marked: NSRange(location: 0, length: 4)))
    let event = NativeEvent(
      sequence: 3, displayedRevision: 2, nodeID: 4, handlerID: 44, payload: .textEdit(edit))
    #expect(try EventBatch.encode(epoch: 22, events: [event]) == expected)
  }

  @Test func heterogeneousEventsKeepOrderAndBoundTheirPayloads() throws {
    let values: [NativeEventPayload] = [
      .press, .textSubmit("😀"), .focusChanged(true), .textLimitReached,
    ]
    let events = values.enumerated().map { index, payload in
      NativeEvent(
        sequence: UInt64(index + 1), displayedRevision: 1, nodeID: 3, handlerID: 9, payload: payload
      )
    }
    var reader = WireReader(try EventBatch.encode(epoch: 1, events: events))
    _ = try reader.data(ProtocolLimits.headerBytes)
    #expect(try reader.integer(UInt32.self) == 4)
    for (index, tag) in [
      EventTagId.press, EventTagId.textSubmit, EventTagId.focusChanged, EventTagId.textLimitReached,
    ].enumerated() {
      let length = Int(try reader.integer(UInt32.self))
      var record = WireReader(try reader.data(length))
      #expect(try record.integer(UInt64.self) == UInt64(index + 1))
      _ = try record.data(24)
      #expect(try record.integer(UInt16.self) == tag)
      if tag == EventTagId.textSubmit { #expect(try record.string() == "😀") }
      if tag == EventTagId.focusChanged { #expect(try record.flag()) }
      #expect(record.remaining == 0)
    }
    #expect(reader.remaining == 0)
    let huge = NativeEvent(
      sequence: 1, displayedRevision: 1, nodeID: 1, handlerID: 1,
      payload: .textSubmit(String(repeating: "a", count: ProtocolLimits.maxStringBytes + 1)))
    #expect(throws: WireError.limitExceeded) { try EventBatch.encode(epoch: 1, events: [huge]) }
    let invalid = NativeEvent(
      sequence: 1, displayedRevision: 1, nodeID: 1, handlerID: 1,
      payload: .textEdit(
        TextEdit(
          sessionID: UInt64.max, localRevision: 1, baseDocumentRevision: 1,
          value: try textValue("Bad"))))
    #expect(throws: TextSessionError.invalidRevision) {
      try EventBatch.encode(epoch: 1, events: [invalid])
    }
  }
}

func readTextExample(_ output: NativeOutput) throws -> (TextSnapshot, UInt64, [Int: UInt64]) {
  for operation in try WireFrame.decode(output.bytes).operations
  where operation.opcode == OperationId.createNode || operation.opcode == OperationId.updateProps {
    var reader = WireReader(operation.body)
    let node = try reader.integer(UInt64.self)
    let kind = Int(try reader.integer(UInt16.self))
    guard kind == NodeKindId.textEditor else { continue }
    let creating = operation.opcode == OperationId.createNode
    if !creating { #expect(try reader.integer(UInt64.self) == 1023) }
    var properties = try RenderTextEditor.decode(&reader)
    properties.autofocus = try reader.flag()
    let bindings = creating ? try reader.bindings() : [:]
    #expect(reader.remaining == 0)
    return (properties.snapshot, node, bindings)
  }
  throw TextSessionError.invalidRevision
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeTextEditsReachTheActualOcamlExampleAndRejectStaleLocalVersions()
    async throws
  {
    let runtime = try await NativeRuntime.open(entrypoint: "text-session")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let (snapshot, node, bindings) = try readTextExample(initial)
      let frame = try WireFrame.decode(initial.bytes)
      var edits: [NativeEventPayload] = []
      let controller = NativeTextController(
        snapshot: snapshot,
        configuration: try TextEditorConfiguration(),
        emit: {
          edits.append($0)
          return true
        },
        failed: { Issue.record("Unexpected native editing failure: \($0)") })
      defer { controller.dispose() }
      let value = try textValue("拼😀音", marked: NSRange(location: 0, length: 4))
      controller.view.setMarkedText(
        "拼😀音", selectedRange: NSRange(location: 4, length: 0),
        replacementRange: NSRange(location: 0, length: snapshot.value.text.utf16.count))
      let edit = try #require(edits.last?.textEdit)
      let handler = try #require(bindings[EventTagId.textEdit])
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      let first = NativeEvent(
        sequence: 1, displayedRevision: frame.revision, nodeID: node,
        handlerID: handler, payload: .textEdit(edit))
      let changed = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: frame.epoch, events: [first]))
      let (ack, _, _) = try readTextExample(changed)
      #expect(
        ack.value == value && ack.acceptedLocalRevision == 1 && ack.documentRevision == 2
          && ack.mode == .ack)
      #expect(try !controller.apply(ack))
      #expect(controller.session.value == value)
      try await runtime.acknowledge(changed, monotonicNanoseconds: 4)
      let stale = NativeEvent(
        sequence: 2, displayedRevision: changed.revision, nodeID: node,
        handlerID: handler, payload: .textEdit(edit))
      let ignored = try await runtime.pump(
        monotonicNanoseconds: 5,
        events: EventBatch.encode(epoch: frame.epoch, events: [stale]))
      #expect(ignored.status == 0 && ignored.bytes.isEmpty && ignored.revision == changed.revision)
      try await runtime.acknowledge(ignored, monotonicNanoseconds: 6)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
