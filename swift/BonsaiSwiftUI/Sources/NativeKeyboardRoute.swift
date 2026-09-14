struct NativeKeyboardRoute {
  struct Target: Equatable {
    let id: RenderIdentity
    let generation: UInt64
    let focusGeneration: UInt64
    let handled: Bool
  }

  private var targets: [Target] = []
  private var responder: ObjectIdentifier?
  private var held: [UInt64: Set<RenderIdentity>] = [:]

  mutating func prepare(_ targets: [Target], responder: ObjectIdentifier?) -> Bool {
    guard self.targets != targets || self.responder != responder else { return false }
    self.targets = targets
    self.responder = responder
    reset()
    return true
  }
  mutating func reset() { held.removeAll() }
  mutating func cancel(_ source: UInt64) { held.removeValue(forKey: source) }
  mutating func dispatch(
    _ key: NativeKey, source: UInt64,
    receive: (RenderIdentity, NativeKey) -> Bool
  ) -> Bool {
    let previous = held[source]
    guard key.action == .down || previous != nil else { return false }
    var admitted = Set<RenderIdentity>()
    var handled = false
    for target in targets where key.action == .down || previous?.contains(target.id) == true {
      guard receive(target.id, key) else { continue }
      admitted.insert(target.id)
      if target.handled {
        handled = true
        break
      }
    }
    if key.action == .up || admitted.isEmpty {
      held.removeValue(forKey: source)
    } else {
      held[source] = admitted
    }
    return handled
  }
}
