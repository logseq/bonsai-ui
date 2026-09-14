import Testing

@testable import BonsaiSwiftUI

struct KeyboardPressesTests {
  private final class Press {}
  @Test func twoObserversDispatchEachNativeSampleOnceIncludingRepeatsAndRelease() {
    var presses = NativeKeyboardPresses()
    let sequence = Press()
    var actions: [NativeKey.Action?] = []
    let dispatch: (NativeKey.Action?) -> Bool = {
      actions.append($0)
      return true
    }
    for (timestamp, phase) in [(1.0, NativeKeyboardPresses.Phase.began), (2, .began), (3, .ended)] {
      for _ in 0..<2 {
        let handled = presses.receive(
          source: 4, sequence: sequence, timestamp: timestamp, phase: phase, dispatch: dispatch)
        #expect(handled)
      }
    }
    #expect(actions == [.down, .repeat, .up])
    presses.finish(source: 4, timestamp: 3)
    _ = presses.receive(
      source: 4, sequence: sequence, timestamp: 4, phase: .began, dispatch: dispatch)
    #expect(actions == [.down, .repeat, .up, .down])
  }

  @Test func ignoredPressStillReleasesAndCancellationDoesNotInventARelease() {
    var presses = NativeKeyboardPresses()
    let sequence = Press()
    var actions: [NativeKey.Action?] = []
    let dispatch: (NativeKey.Action?) -> Bool = {
      actions.append($0)
      return false
    }
    _ = presses.receive(
      source: 4, sequence: sequence, timestamp: 1, phase: .began, dispatch: dispatch)
    _ = presses.receive(
      source: 5, sequence: sequence, timestamp: 1, phase: .began, dispatch: dispatch)
    _ = presses.receive(
      source: 4, sequence: sequence, timestamp: 2, phase: .cancelled, dispatch: dispatch)
    _ = presses.receive(
      source: 4, sequence: sequence, timestamp: 2, phase: .cancelled, dispatch: dispatch)
    _ = presses.receive(
      source: 5, sequence: sequence, timestamp: 3, phase: .ended, dispatch: dispatch)
    #expect(actions == [.down, .down, nil, .up])
  }

  @Test func retirementDropsCachedHandlingWithoutTurningHeldKeysIntoNewDowns() {
    var presses = NativeKeyboardPresses()
    let sequence = Press()
    var actions: [NativeKey.Action?] = []
    let dispatch: (NativeKey.Action?) -> Bool = {
      actions.append($0)
      return true
    }
    _ = presses.receive(
      source: 4, sequence: sequence, timestamp: 1, phase: .began, dispatch: dispatch)
    presses.retire()
    let stale = presses.receive(
      source: 4, sequence: sequence, timestamp: 1, phase: .began, dispatch: dispatch)
    #expect(!stale)
    presses.finish(source: 4, timestamp: 1)
    _ = presses.receive(
      source: 4, sequence: sequence, timestamp: 2, phase: .began, dispatch: dispatch)
    _ = presses.receive(
      source: 4, sequence: sequence, timestamp: 3, phase: .ended, dispatch: dispatch)
    _ = presses.receive(
      source: 4, sequence: sequence, timestamp: 4, phase: .began, dispatch: dispatch)
    presses.finish(source: 4, timestamp: 3)
    _ = presses.receive(
      source: 4, sequence: sequence, timestamp: 5, phase: .began, dispatch: dispatch)
    #expect(actions == [.down, .repeat, .up, .down, .repeat])
  }
  @Test func newNativePressAfterFocusLossStartsAgainAndOldReleaseCannotFinishIt() {
    var presses = NativeKeyboardPresses()
    let old = Press()
    let current = Press()
    var actions: [NativeKey.Action?] = []
    let dispatch: (NativeKey.Action?) -> Bool = {
      actions.append($0)
      return true
    }
    _ = presses.receive(source: 4, sequence: old, timestamp: 1, phase: .began, dispatch: dispatch)
    presses.retire()
    _ = presses.receive(
      source: 4, sequence: current, timestamp: 2, phase: .began, dispatch: dispatch)
    let stale = presses.receive(
      source: 4, sequence: old, timestamp: 3, phase: .ended, dispatch: dispatch)
    #expect(!stale)
    _ = presses.receive(
      source: 4, sequence: current, timestamp: 4, phase: .began, dispatch: dispatch)
    _ = presses.receive(
      source: 4, sequence: current, timestamp: 5, phase: .ended, dispatch: dispatch)
    #expect(actions == [.down, .down, .repeat, .up])
  }

}
