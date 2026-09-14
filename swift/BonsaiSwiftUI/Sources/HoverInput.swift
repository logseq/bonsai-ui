import Foundation

struct HoverSample: Equatable {
  let id: UInt64
  let kind: NativePointer.Kind
  let position: CGPoint
  let buttons: UInt32

  var isValid: Bool {
    id <= UInt64(Int64.max) && position.x.isFinite && position.y.isFinite
  }
}

struct HoverInput {
  enum ContactPhase { case active, ended, cancelled }
  struct Change: Equatable {
    let sample: HoverSample
    let present: Bool
  }
  private var mouseContactActive = false

  mutating func hover(_ sample: HoverSample, present: Bool) -> Change? {
    guard sample.isValid else { return nil }
    if sample.id == 0 && (mouseContactActive || (!present && sample.buttons != 0)) { return nil }
    return Change(sample: sample, present: present)
  }

  mutating func mouseContact(_ sample: HoverSample, phase: ContactPhase) -> Change? {
    guard sample.isValid, sample.id == 0, sample.kind == .mouse else { return nil }
    mouseContactActive = phase == .active || (phase == .ended && sample.buttons != 0)
    return Change(sample: sample, present: phase != .cancelled)
  }

  mutating func reset() {
    mouseContactActive = false
  }
}
