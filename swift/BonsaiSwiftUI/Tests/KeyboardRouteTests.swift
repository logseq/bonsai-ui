import Testing

@testable import BonsaiSwiftUI

struct KeyboardRouteTests {
  private func target(
    _ node: UInt64, handled: Bool = false, generation: UInt64 = 0,
    focus: UInt64 = 0
  ) -> NativeKeyboardRoute.Target {
    .init(
      id: RenderIdentity(epoch: 1, node: node), generation: generation,
      focusGeneration: focus, handled: handled)
  }
  private func key(_ action: NativeKey.Action) -> NativeKey {
    NativeKey(logical: 97, physical: 0x70004, action: action, modifiers: 0)
  }

  @Test func handledStopsBubblingAndRetainsOnlyAdmittedOwners() {
    var route = NativeKeyboardRoute()
    let changed = route.prepare([target(1), target(2, handled: true), target(3)], responder: nil)
    #expect(changed)
    var events: [UInt64] = []
    for action in [NativeKey.Action.down, .repeat, .up] {
      #expect(
        route.dispatch(key(action), source: 4) { id, _ in
          events.append(id.node)
          return true
        })
    }
    #expect(events == [1, 2, 1, 2, 1, 2])
    #expect(
      !route.dispatch(key(.up), source: 4) { _, _ in
        Issue.record("An orphan release reached a listener")
        return true
      })
  }

  @Test func rejectedDownAndRepeatCannotRejoinTheHeldSequence() {
    var route = NativeKeyboardRoute()
    _ = route.prepare([target(1), target(2)], responder: nil)
    var admitted: Set<UInt64> = [2]
    var events: [String] = []
    let receive: (RenderIdentity, NativeKey) -> Bool = { id, key in
      guard admitted.contains(id.node) else { return false }
      events.append("\(id.node):\(key.action)")
      return true
    }
    let handled = route.dispatch(key(.down), source: 4, receive: receive)
    #expect(!handled)
    admitted = [1, 2]
    _ = route.dispatch(key(.repeat), source: 4, receive: receive)
    admitted = []
    _ = route.dispatch(key(.repeat), source: 4, receive: receive)
    admitted = [1, 2]
    _ = route.dispatch(key(.up), source: 4, receive: receive)
    #expect(events == ["2:down", "2:repeat"])
    admitted = []
    _ = route.dispatch(key(.down), source: 4, receive: receive)
    admitted = [1, 2]
    _ = route.dispatch(key(.repeat), source: 4, receive: receive)
    _ = route.dispatch(key(.up), source: 4, receive: receive)
    #expect(events == ["2:down", "2:repeat"])
  }

  @Test func focusBindingPolicyAndResponderChangesRetireHeldKeys() {
    final class Owner {}
    let first = Owner()
    let second = Owner()
    var route = NativeKeyboardRoute()
    let changes: [([NativeKeyboardRoute.Target], ObjectIdentifier?)] = [
      ([target(1)], ObjectIdentifier(first)),
      ([target(1, generation: 1)], ObjectIdentifier(first)),
      ([target(1, generation: 1, focus: 1)], ObjectIdentifier(first)),
      ([target(1, handled: true, generation: 1, focus: 1)], ObjectIdentifier(first)),
      ([target(1, handled: true, generation: 1, focus: 1)], ObjectIdentifier(second)),
      ([], nil),
    ]
    for (targets, responder) in changes {
      let changed = route.prepare(targets, responder: responder)
      #expect(changed)
      let unchanged = route.prepare(targets, responder: responder)
      #expect(!unchanged)
      #expect(
        !route.dispatch(key(.up), source: 4) { _, _ in
          Issue.record("An old key survived a route change")
          return true
        })
      _ = route.dispatch(key(.down), source: 4) { _, _ in true }
    }
  }

  @Test func cancellationRetiresOnlyItsKeyAndResetRetiresEveryKey() {
    var route = NativeKeyboardRoute()
    _ = route.prepare([target(1, handled: true)], responder: nil)
    for source: UInt64 in [4, 5] {
      #expect(route.dispatch(key(.down), source: source) { _, _ in true })
    }
    route.cancel(4)
    #expect(!route.dispatch(key(.up), source: 4) { _, _ in true })
    #expect(route.dispatch(key(.up), source: 5) { _, _ in true })
    _ = route.dispatch(key(.down), source: 5) { _, _ in true }
    route.reset()
    #expect(!route.dispatch(key(.repeat), source: 5) { _, _ in true })
    #expect(!route.dispatch(key(.up), source: 5) { _, _ in true })
  }
}
