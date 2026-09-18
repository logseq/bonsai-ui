import Foundation

#if !BONSAI_STANDALONE_TEST
  @testable import BonsaiSwiftUI
#endif

extension TreeFixture {
  static func swipe(_ id: UInt64 = 1, enabled: UInt8 = 1, full: UInt8 = 1, update: Bool = false)
    -> WireOperation
  {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(42))
      if update { $0.integer(UInt64(3)) }
      $0.integer(enabled)
      $0.integer(full)
      if !update { $0.integer(UInt16(0)) }
    }
  }
  static func swipeAction(
    _ id: UInt64 = 3, title: String = "Archive", side: UInt8 = 0,
    enabled: UInt8 = 1, role: UInt8 = 0, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(43))
      if update { $0.integer(UInt64(63)) }
      try! $0.string(title)
      $0.integer(side)
      $0.integer(enabled)
      $0.integer(role)
      $0.integer(UInt32(0xff26_783c))
      $0.integer(UInt8(1))
      try! $0.string("archivebox")
      if !update {
        $0.integer(UInt16(enabled == 1 ? 1 : 0))
        if enabled == 1 {
          $0.integer(UInt16(1))
          $0.integer(id + 90)
        }
      }
    }
  }
  static func swipeTree() -> [WireOperation] {
    [
      swipe(), text(2, "Message preview"), swipeAction(),
      swipeAction(5, title: "Mark read", side: 1),
      children(1, [2, 3, 5]),
      operation(OperationId.createNode) {
        $0.integer(UInt64(10))
        $0.integer(UInt16(80))
        $0.integer(UInt16(0))
      },
      operation(OperationId.createNode) {
        $0.integer(UInt64(11))
        $0.integer(UInt16(81))
        $0.integer(UInt8(0))
        $0.integer(UInt8(0))
        $0.integer(UInt8(0))
        $0.integer(UInt16(0))
      },
      operation(OperationId.createNode) {
        $0.integer(UInt64(12))
        $0.integer(UInt16(82))
        $0.integer(UInt8(0))
        $0.integer(UInt16(0))
      },
      text(13, ""), text(14, ""), children(12, [1]), children(11, [13, 14, 12]), children(10, [11]),
      root(10),
    ]
  }
}
