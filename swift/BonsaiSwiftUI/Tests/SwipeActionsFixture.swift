import Foundation

#if !BONSAI_STANDALONE_TEST
  @testable import BonsaiSwiftUI
#endif

extension TreeFixture {
  static func outlineRow(
    _ id: UInt64, key: String, separator: UInt8 = 0, expanded: Bool? = nil, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(82))
      if update { $0.integer(UInt64(7)) }
      $0.integer(separator)
      try! $0.string(key)
      $0.integer(UInt8(expanded == nil ? 0 : expanded == true ? 2 : 1))
      if !update {
        $0.integer(UInt16(expanded == nil ? 0 : 1))
        if expanded != nil {
          $0.integer(UInt16(EventTagId.valueChanged))
          $0.integer(id + 90)
        }
      }
    }
  }

  static func rowSlots(
    _ row: UInt64, label: UInt64, swipe: UInt64? = nil, context: UInt64? = nil,
    descendants: [UInt64] = []
  ) -> [WireOperation] {
    let labelSlot = row * 10000 + 1
    let swipeSlot = swipe ?? row * 10000 + 2
    let contextSlot = context ?? row * 10000 + 3
    return [create(labelSlot, kind: 145), children(labelSlot, [label])]
      + (swipe == nil ? [self.swipe(swipeSlot, full: 0)] : [])
      + (context == nil
        ? [
          operation(OperationId.createNode) {
            $0.integer(contextSlot)
            $0.integer(UInt16(146))
            $0.integer(UInt8(1))
            $0.integer(UInt16(0))
          }
        ] : [])
      + [children(row, [labelSlot, swipeSlot, contextSlot] + descendants)]
  }

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
      children(1, [3, 5]),
      operation(OperationId.createNode) {
        $0.integer(UInt64(10))
        $0.integer(UInt16(80))
        $0.integer(UInt8(0))
        $0.integer(UInt8(0))
        $0.integer(UInt16(0))
      },
      operation(OperationId.createNode) {
        $0.integer(UInt64(11))
        $0.integer(UInt16(81))
        $0.integer(UInt8(0))
        $0.integer(UInt8(0))
        $0.integer(UInt8(0))
        try! $0.string("section")
        $0.integer(UInt16(0))
      },
      outlineRow(12, key: "row"),
      text(13, ""), text(14, ""), children(11, [13, 14, 12]), children(10, [11]),
      root(10),
    ] + rowSlots(12, label: 2, swipe: 1)
  }
}
