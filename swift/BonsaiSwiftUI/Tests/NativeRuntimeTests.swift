import Foundation
import Testing

@testable import BonsaiSwiftUI

@Suite(.serialized)
struct NativeRuntimeTests {
  @Test func counterFrameAndNoDiffToken() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "counter")
    let frame = try await runtime.pump(monotonicNanoseconds: 1)
    #expect(frame.status == 0)
    #expect(frame.presentationID > 0)
    #expect(frame.bytes.range(of: Data("Count: 0".utf8)) != nil)
    try await runtime.acknowledge(frame, monotonicNanoseconds: 2)
    let unchanged = try await runtime.pump(monotonicNanoseconds: 3)
    #expect(unchanged.bytes.isEmpty)
    #expect(unchanged.presentationID > frame.presentationID)
    #expect(unchanged.revision == frame.revision)
    try await runtime.acknowledge(unchanged, monotonicNanoseconds: 4)
    await runtime.close()
    // The copied frame must remain valid after its native owner is destroyed.
    #expect(frame.bytes.range(of: Data("Increment".utf8)) != nil)
  }

  @Test func pendingTokenAndStaleAcknowledgmentCannotAdvanceRuntime() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "counter")
    let first = try await runtime.pump(monotonicNanoseconds: 10)
    await #expect(throws: NativeRuntimeError.presentationPending) {
      try await runtime.pump(monotonicNanoseconds: 11)
    }
    try await runtime.acknowledge(first, monotonicNanoseconds: 12)
    let second = try await runtime.pump(monotonicNanoseconds: 13)
    await #expect(throws: NativeRuntimeError.invalidPresentation) {
      try await runtime.acknowledge(first, monotonicNanoseconds: 14)
    }
    try await runtime.acknowledge(second, monotonicNanoseconds: 15)
    await runtime.close()
  }

  @Test func rejectionRecoversWithFreshSnapshot() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "counter")
    let frame = try await runtime.pump(monotonicNanoseconds: 1)
    try await runtime.reject(frame)
    let recovered = try await runtime.pump(monotonicNanoseconds: 2)
    #expect(recovered.revision > frame.revision)
    #expect(recovered.bytes.range(of: Data("Count: 0".utf8)) != nil)
    try await runtime.acknowledge(recovered, monotonicNanoseconds: 3)
    await runtime.close()
  }

  @Test func invalidClockDoesNotConsumePendingToken() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "counter")
    await #expect(throws: NativeRuntimeError.invalidClock) {
      try await runtime.pump(monotonicNanoseconds: -1)
    }
    let frame = try await runtime.pump(monotonicNanoseconds: 10)
    await #expect(throws: NativeRuntimeError.invalidClock) {
      try await runtime.acknowledge(frame, monotonicNanoseconds: 9)
    }
    try await runtime.acknowledge(frame, monotonicNanoseconds: 11)
    await #expect(throws: NativeRuntimeError.invalidClock) {
      try await runtime.pump(monotonicNanoseconds: 10)
    }
    await runtime.close()
  }

  @Test func closeIsIdempotentAndRuntimeCanRestart() async throws {
    for _ in 0..<3 {
      let runtime = try await NativeRuntime.open(entrypoint: "counter")
      let frame = try await runtime.pump(monotonicNanoseconds: 1)
      #expect(frame.bytes.range(of: Data("Count: 0".utf8)) != nil)
      await runtime.close()
      await runtime.close()
      await #expect(throws: NativeRuntimeError.disposed) {
        try await runtime.pump(monotonicNanoseconds: 2)
      }
    }
  }

  @Test func invalidEntrypointsAndSecondOwnerFailWithoutDisplacingFirst() async throws {
    for entrypoint in ["", "missing", "counter\0", String(repeating: "x", count: 256)] {
      await #expect(throws: NativeRuntimeError.startupFailed) {
        try await NativeRuntime.open(entrypoint: entrypoint)
      }
    }
    let runtime = try await NativeRuntime.open(entrypoint: "counter")
    await #expect(throws: NativeRuntimeError.startupFailed) {
      try await NativeRuntime.open(entrypoint: "counter")
    }
    let frame = try await runtime.pump(monotonicNanoseconds: 1)
    #expect(frame.bytes.range(of: Data("Count: 0".utf8)) != nil)
    await runtime.close()
  }

  @Test func concurrentPumpsAreSerializedBehindOneToken() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "counter")
    let results = await withTaskGroup(of: Bool.self) { group in
      for _ in 0..<16 {
        group.addTask {
          do {
            _ = try await runtime.pump(monotonicNanoseconds: 1)
            return true
          } catch {
            #expect(error as? NativeRuntimeError == .presentationPending)
            return false
          }
        }
      }
      var values: [Bool] = []
      for await value in group { values.append(value) }
      return values
    }
    #expect(results.filter { $0 }.count == 1)
    await runtime.close()
  }
}
