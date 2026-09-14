struct NativeKeyboardPresses {
  enum Phase { case began, ended, cancelled }
  private struct Sample {
    let sequence: AnyObject
    let timestamp: Double
    let phase: Phase
    var handled: Bool
  }
  private var samples: [UInt64: Sample] = [:]
  mutating func receive(
    source: UInt64, sequence: AnyObject, timestamp: Double, phase: Phase,
    dispatch: (NativeKey.Action?) -> Bool
  ) -> Bool {
    let existing = samples[source]
    if let existing, existing.sequence !== sequence, phase != .began { return false }
    let previous = existing?.sequence === sequence ? existing : nil
    if previous?.timestamp == timestamp, previous?.phase == phase {
      return previous?.handled == true
    }
    let action: NativeKey.Action?
    switch phase {
    case .began: action = previous?.phase == .began ? .repeat : .down
    case .ended: action = .up
    case .cancelled: action = nil
    }
    let handled = dispatch(action)
    samples[source] = Sample(
      sequence: sequence, timestamp: timestamp, phase: phase, handled: handled)
    return handled
  }
  mutating func retire() {
    for source in samples.keys { samples[source]?.handled = false }
  }
  mutating func finish(source: UInt64, timestamp: Double) {
    guard let sample = samples[source], sample.phase != .began,
      sample.timestamp == timestamp
    else { return }
    samples.removeValue(forKey: source)
  }
}
