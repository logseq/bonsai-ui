import Testing

@testable import BonsaiSwiftUI

struct HoverTransitionTests {
  private func pointer(_ id: UInt64 = 0, buttons: UInt32 = 0) -> NativePointer {
    NativePointer(
      id: id, localX: 12.5, localY: -8, globalX: 40, globalY: 100,
      kind: id == 0 ? .mouse : .stylus, buttons: buttons)
  }

  @Test func hoverAndButtonHeldSamplesShareOneTransitionHistory() {
    var state = HoverTransitions()
    let hover = pointer()
    let held = pointer(buttons: 3)
    let entered = state.update(hover, inside: true)
    #expect(entered == .pointerEnter(hover))
    let pressedInside = state.update(held, inside: true)
    #expect(pressedInside == nil)
    let draggedOutside = state.update(held, inside: false)
    #expect(draggedOutside == .pointerLeave(held))
    let draggedInside = state.update(held, inside: true)
    #expect(draggedInside == .pointerEnter(held))
    let releasedInside = state.update(hover, inside: true)
    #expect(releasedInside == nil)
    let resumedHover = state.update(hover, inside: true)
    #expect(resumedHover == nil)
    let left = state.update(hover, inside: false)
    #expect(left == .pointerLeave(hover))
    let duplicateLeave = state.update(hover, inside: false)
    #expect(duplicateLeave == nil)
  }

  @Test func independentPointersAndResetDoNotInventExitEvents() {
    var state = HoverTransitions()
    let mouse = pointer()
    let pencil = pointer(1)
    let initialOutside = state.update(pencil, inside: false)
    #expect(initialOutside == nil)
    let mouseEnter = state.update(mouse, inside: true)
    let pencilEnter = state.update(pencil, inside: true)
    #expect(mouseEnter == .pointerEnter(mouse))
    #expect(pencilEnter == .pointerEnter(pencil))
    let mouseLeave = state.update(mouse, inside: false)
    #expect(mouseLeave == .pointerLeave(mouse))
    let retainedPencil = state.update(pencil, inside: true)
    #expect(retainedPencil == nil)
    state.reset()
    let staleExit = state.update(pencil, inside: false)
    #expect(staleExit == nil)
    let freshEnter = state.update(pencil, inside: true)
    #expect(freshEnter == .pointerEnter(pencil))
  }

  @Test func malformedSamplesCannotPoisonOrClearAnActivePointer() {
    var state = HoverTransitions()
    let valid = pointer(UInt64(Int64.max), buttons: UInt32.max)
    let entered = state.update(valid, inside: true)
    #expect(entered == .pointerEnter(valid))
    for coordinate in [\NativePointer.localX, \.localY, \.globalX, \.globalY] {
      for bad in [Double.nan, .infinity, -.infinity] {
        var invalid = valid
        invalid[keyPath: coordinate] = bad
        let rejected = state.update(invalid, inside: false)
        #expect(rejected == nil)
      }
    }
    var invalid = valid
    invalid.id = UInt64.max
    let rejectedEnter = state.update(invalid, inside: true)
    #expect(rejectedEnter == nil)
    let left = state.update(valid, inside: false)
    #expect(left == .pointerLeave(valid))
  }
}
