struct HoverTransitions {
  private var entered: Set<UInt64> = []

  mutating func update(_ pointer: NativePointer, inside: Bool) -> NativeEventPayload? {
    guard pointer.isValid, entered.contains(pointer.id) != inside else { return nil }
    if inside {
      entered.insert(pointer.id)
      return .pointerEnter(pointer)
    }
    entered.remove(pointer.id)
    return .pointerLeave(pointer)
  }

  mutating func reset() { entered.removeAll(keepingCapacity: true) }
  mutating func remove(_ id: UInt64) { entered.remove(id) }
}
