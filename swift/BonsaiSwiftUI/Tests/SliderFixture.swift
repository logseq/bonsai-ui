#if !BONSAI_STANDALONE_TEST
  @testable import BonsaiSwiftUI
#endif

extension TreeFixture {
  static func slider(
    _ id: UInt64 = 1, lower: Double = 20, upper: Double? = nil,
    minimum: Double = 0, maximum: Double = 100, step: Double? = 10,
    enabled: UInt8 = 1, vertical: UInt8 = 0, changes: UInt8 = 1,
    update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(upper == nil ? 45 : 46))
      if update { $0.integer(UInt64(upper == nil ? 255 : 1023)) }
      $0.integer(lower.bitPattern)
      if let upper { $0.integer(upper.bitPattern) }
      $0.integer(minimum.bitPattern)
      $0.integer(maximum.bitPattern)
      $0.integer(UInt8(step == nil ? 0 : 1))
      if let step { $0.integer(step.bitPattern) }
      $0.integer(enabled)
      $0.integer(vertical)
      $0.integer(changes)
      try! $0.string(upper == nil ? "Level" : "Lower")
      if upper != nil { try! $0.string("Upper") }
      if !update {
        $0.integer(UInt16(enabled == 1 ? (changes == 1 ? 2 : 1) : 0))
        if enabled == 1 {
          if changes == 1 {
            $0.integer(
              UInt16(upper == nil ? EventTagId.sliderChanged : EventTagId.rangeSliderChanged))
            $0.integer(UInt64(91))
          }
          $0.integer(
            UInt16(upper == nil ? EventTagId.sliderChangeEnd : EventTagId.rangeSliderChangeEnd))
          $0.integer(UInt64(92))
        }
      }
    }
  }
}
