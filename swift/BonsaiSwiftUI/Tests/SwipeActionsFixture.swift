import Foundation

#if !BONSAI_STANDALONE_TEST
  @testable import BonsaiSwiftUI
#endif

extension TreeFixture {
  static func swipe(
    _ id: UInt64 = 1, enabled: UInt8 = 1, vertical: UInt8 = 0,
    group: String? = "mail", update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(42))
      if update { $0.integer(UInt64(63)) }
      $0.integer(enabled)
      $0.integer(vertical)
      $0.integer(UInt8(1))
      $0.integer(UInt8(group == nil ? 0 : 1))
      if let group { try! $0.string(group) }
      $0.integer(UInt8(1))
      $0.integer(UInt8(1))
      if !update { $0.integer(UInt16(0)) }
    }
  }
  static func swipeAction(
    _ id: UInt64 = 3, title: String = "Archive", side: UInt8 = 0,
    enabled: UInt8 = 1, extent: Double = 80, full: UInt8 = 1,
    update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(43))
      if update { $0.integer(UInt64(255)) }
      try! $0.string(title)
      $0.integer(side)
      $0.integer(enabled)
      $0.integer(UInt8(0))
      $0.integer(extent.bitPattern)
      $0.integer(UInt32(0xff26_783c))
      $0.integer(UInt8(1))
      $0.integer(full)
      if !update {
        $0.integer(UInt16(enabled == 1 ? 1 : 0))
        if enabled == 1 {
          $0.integer(UInt16(1))
          $0.integer(id + 90)
        }
      }
    }
  }
  static func swipeTree(vertical: UInt8 = 0) -> [WireOperation] {
    [
      swipe(vertical: vertical), text(2, "Message preview"),
      swipeAction(), text(4, "Archive label"), children(3, [4]),
      swipeAction(5, title: "Mark read", side: 1, full: 0), text(6, "Read label"),
      children(5, [6]), children(1, [2, 3, 5]), root(1),
    ]
  }
}
