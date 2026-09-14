import Foundation

#if !BONSAI_STANDALONE_TEST
  @testable import BonsaiSwiftUI
#endif

struct TreeFixture {
  static func operation(_ opcode: Int, _ write: (inout WireWriter) -> Void) -> WireOperation {
    var body = WireWriter()
    write(&body)
    return WireOperation(opcode: opcode, body: body.bytes)
  }

  static func create(_ id: UInt64, kind: Int = NodeKindId.column) -> WireOperation {
    operation(OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(kind))
      if kind == NodeKindId.row || kind == NodeKindId.column {
        $0.integer(UInt8(0))
        $0.integer(UInt8(1))
      } else if kind == NodeKindId.stack {
        $0.integer(UInt8(4))
      }
      $0.integer(UInt16(0))
    }
  }

  static func textProperties(_ writer: inout WireWriter, _ value: String) {
    writer.integer(UInt32(value.utf8.count))
    writer.bytes.append(contentsOf: value.utf8)
    writer.bytes.append(contentsOf: [0, 0, 0, 0])
  }

  static func text(_ id: UInt64, _ value: String, update: Bool = false) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(NodeKindId.text))
      if update { $0.integer(UInt64(31)) }
      textProperties(&$0, value)
      if !update {
        $0.integer(UInt16(0))
      }
    }
  }

  static func button(
    _ id: UInt64, enabled: Bool = true, role: UInt8 = 2,
    style: UInt8 = 3, autofocus: Bool = false, handler: UInt64? = 9
  ) -> WireOperation {
    operation(OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(NodeKindId.button))
      $0.bytes.append(contentsOf: [enabled ? 1 : 0, role, style, autofocus ? 1 : 0])
      $0.integer(UInt16(handler == nil ? 0 : 1))
      if let handler {
        $0.integer(UInt16(EventTagId.press))
        $0.integer(handler)
      }
    }
  }

  static func children(_ id: UInt64, _ children: [UInt64]) -> WireOperation {
    operation(OperationId.setChildren) {
      $0.integer(id)
      $0.integer(UInt32(children.count))
      for child in children { $0.integer(child) }
    }
  }

  static func root(_ id: UInt64) -> WireOperation {
    operation(OperationId.setRoot) { $0.integer(id) }
  }

  static func frame(
    _ operations: [WireOperation], base: UInt64 = 0,
    revision: UInt64 = 1, epoch: UInt64 = 7
  ) -> WireFrame {
    WireFrame(
      kind: base == 0 ? FrameKindId.fullSnapshot : FrameKindId.incrementalFrame,
      epoch: epoch, baseRevision: base, revision: revision, operations: operations)
  }

  static var initial: WireFrame {
    frame([
      create(1), text(2, "Count: 0"), button(3), text(4, "Increment"),
      children(1, [2, 3]), children(3, [4]), root(1),
    ])
  }
}
