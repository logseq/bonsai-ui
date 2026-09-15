import Foundation
import Testing

@testable import BonsaiSwiftUI

@MainActor struct PointerContactInputTests {
  @Test func concurrentContactsKeepEveryEdgeAndTheirOwnCoordinatesAndGeneration() throws {
    let input = PointerContactInput(identities: PointerContactIdentities())
    let first = NSObject()
    let second = NSObject()
    input.begin(first, kind: .touch, position: CGPoint(x: 10, y: 20), buttons: 1, generation: 7)
    input.begin(second, kind: .stylus, position: CGPoint(x: 30, y: 40), buttons: 1, generation: 8)
    input.begin(first, kind: .mouse, position: .zero, buttons: 8, generation: 99)
    input.end(second, position: CGPoint(x: 31, y: 41), buttons: 0)
    #expect(input.hasActiveContacts)
    input.end(first, position: CGPoint(x: 11, y: 21), buttons: 0)
    #expect(!input.hasActiveContacts)
    let samples = input.drain()
    #expect(samples.count == 4)
    guard samples.count == 4 else { return }
    #expect(samples.map(\.isDown) == [true, true, false, false])
    #expect(samples.map(\.kind) == [.touch, .stylus, .stylus, .touch])
    #expect(samples.map(\.generation) == [7, 8, 8, 7])
    #expect(
      samples.map(\.position) == [
        CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40),
        CGPoint(x: 31, y: 41), CGPoint(x: 11, y: 21),
      ])
    #expect(samples[0].id == samples[3].id)
    #expect(samples[1].id == samples[2].id)
    #expect(samples[0].id != samples[1].id)
    #expect(input.drain().isEmpty)
  }

  @Test func nestedObserversShareIdentityWithoutSharingContactOwnership() throws {
    let identities = PointerContactIdentities()
    let outer = PointerContactInput(identities: identities)
    let inner = PointerContactInput(identities: identities)
    let first = NSMutableString(string: "same")
    let second = NSMutableString(string: "same")
    outer.begin(first, kind: .touch, position: .zero, buttons: 1, generation: 1)
    outer.begin(second, kind: .touch, position: .zero, buttons: 1, generation: 1)
    inner.begin(second, kind: .touch, position: .zero, buttons: 1, generation: 2)
    inner.begin(first, kind: .touch, position: .zero, buttons: 1, generation: 2)
    let a = outer.drain()
    let b = inner.drain()
    #expect(a.count == 2 && b.count == 2)
    guard a.count == 2 && b.count == 2 else { return }
    #expect(a[0].id == b[1].id && a[1].id == b[0].id)
    #expect(a[0].id != a[1].id)
    outer.reset()
    #expect(inner.hasActiveContacts)
    inner.end(first, position: .zero, buttons: 0)
    #expect(try #require(inner.drain().first).id == a[0].id)
    #expect(inner.hasActiveContacts)
  }

  @Test func mouseAndPencilUseHoverIdentityWhileFingersHaveDistinctContactIDs() throws {
    let input = PointerContactInput(identities: PointerContactIdentities())
    let contacts = (0..<5).map { _ in NSObject() }
    for (contact, kind) in zip(
      contacts, [NativePointer.Kind.mouse, .stylus, .touch, .touch, .unknown])
    {
      input.begin(contact, kind: kind, position: .zero, buttons: 1, generation: 1)
    }
    let samples = input.drain()
    #expect(samples.count == 5)
    guard samples.count == 5 else { return }
    #expect(samples[0].id == 0)
    #expect(samples[1].id == 1)
    #expect(Set(samples.map(\.id)).count == 5)
    #expect(samples.dropFirst(2).allSatisfy { $0.id >= 2 && $0.id <= UInt64(Int64.max) })
  }

  @Test func cancelAndResetDiscardPendingEdgesWithoutInventingReleasesOrKeepingTouchesAlive() {
    let identities = PointerContactIdentities()
    let input = PointerContactInput(identities: identities)
    weak var released: NSObject?
    let second = NSObject()
    let unknown = NSObject()
    // Drain temporary Foundation references before checking retained ownership.
    autoreleasepool {
      let first = NSObject()
      released = first
      input.begin(first, kind: .touch, position: .zero, buttons: 1, generation: 1)
      input.begin(second, kind: .touch, position: .zero, buttons: 1, generation: 1)
      input.cancel(first)
      input.end(first, position: .zero, buttons: 0)
      input.end(unknown, position: .zero, buttons: 0)
      input.cancel(unknown)
    }
    #expect(released == nil)
    #expect(input.hasActiveContacts)
    let remaining = input.drain()
    #expect(remaining.count == 1 && remaining.first?.isDown == true)
    input.end(second, position: .zero, buttons: 0)
    input.reset()
    #expect(!input.hasActiveContacts && input.drain().isEmpty)
    input.end(second, position: .zero, buttons: 0)
    #expect(input.drain().isEmpty)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func batchedConcurrentPointerEdgesReachActualOcamlWithoutLosingContacts()
    async throws
  {
    let runtime = try await NativeRuntime.open(entrypoint: "native-pointer-events")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(initial.bytes)
      let tree = try NodeStore().staging(frame).tree
      let node = try #require(tree.nodes.values.first { $0.kind == NodeKindId.gesture })
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      let input = PointerContactInput(identities: PointerContactIdentities())
      let first = NSObject()
      let second = NSObject()
      input.begin(first, kind: .touch, position: CGPoint(x: 10, y: 20), buttons: 1, generation: 1)
      input.begin(second, kind: .touch, position: CGPoint(x: 30, y: 40), buttons: 1, generation: 1)
      input.end(second, position: CGPoint(x: 31, y: 41), buttons: 0)
      input.end(first, position: CGPoint(x: 11, y: 21), buttons: 0)
      let samples = input.drain()
      #expect(samples.count == 4)
      let events = try samples.enumerated().map { index, sample in
        let payload = sample.payload(local: sample.position, global: sample.position)
        return NativeEvent(
          sequence: UInt64(index + 1), displayedRevision: frame.revision, nodeID: node.id,
          handlerID: try #require(node.bindings[payload.tag]), payload: payload)
      }
      let updated = try await runtime.pump(
        monotonicNanoseconds: 3, events: EventBatch.encode(epoch: frame.epoch, events: events))
      let expected =
        "down:2:10.000:20.000:10.000:20.000:touch:1;"
        + "down:3:30.000:40.000:30.000:40.000:touch:1;"
        + "up:3:31.000:41.000:31.000:41.000:touch:0;"
        + "up:2:11.000:21.000:11.000:21.000:touch:0;"
      #expect(updated.bytes.range(of: Data(expected.utf8)) != nil)
      try await runtime.acknowledge(updated, monotonicNanoseconds: 4)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
