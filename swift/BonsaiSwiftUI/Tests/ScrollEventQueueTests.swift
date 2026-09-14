import Foundation
import Testing

@testable import BonsaiSwiftUI

struct ScrollEventQueueTests {
  private func event(
    _ sequence: UInt64, _ pixels: Double, _ delta: Double,
    node: UInt64 = 1, handler: UInt64 = 2, revision: UInt64 = 1
  ) -> NativeEvent {
    NativeEvent(
      sequence: sequence, displayedRevision: revision, nodeID: node,
      handlerID: handler, payload: .scroll(pixels: pixels, delta: delta))
  }

  @Test func adjacentRunsKeepTravelLatestPositionAndLosslessBoundaries() {
    var queue = NativeEventQueue()
    #expect(true == queue.append(event(1, 23, 23)))
    #expect(true == queue.append(event(2, 24, 1)))
    #expect(queue.events.count == 1)
    #expect(queue.events.last?.payload == .scroll(pixels: 24, delta: 24))
    #expect(true == queue.append(event(3, 24, 0)))
    #expect(true == queue.append(event(4, 20, -4)))
    #expect(
      true == queue.append(NativeEvent(sequence: 5, displayedRevision: 1, nodeID: 1, handlerID: 3)))
    #expect(true == queue.append(event(6, 21, 1)))
    #expect(true == queue.append(event(7, 22, 1, node: 2)))
    #expect(true == queue.append(event(8, 23, 1, node: 2, handler: 4)))
    #expect(true == queue.append(event(9, 24, 1, node: 2, handler: 4, revision: 2)))
    #expect(queue.events.map(\.sequence) == [2, 3, 4, 5, 6, 7, 8, 9])
  }

  @Test func everyFlushBoundaryPreservesThresholdTransitionsAndZeroEvents() {
    for deltas: [Double] in [[23, 1], [24, 0], [20, -4], [20, -4, 20, 4], [100], [-23, -1]] {
      func result(_ events: [NativeEvent]) -> (trace: [Int], carry: Double, pixels: Double) {
        var carry = 0.0
        var trace: [Int] = []
        var pixels = 0.0
        for event in events {
          guard case .scroll(let nextPixels, let delta) = event.payload else { continue }
          pixels = nextPixels
          if delta == 0 { trace.append(0) }
          carry += delta
          while carry >= 24 {
            trace.append(1)
            carry -= 24
          }
          while carry <= -24 {
            trace.append(-1)
            carry += 24
          }
        }
        return (trace, carry, pixels)
      }
      var pixels = 0.0
      let input = deltas.enumerated().map { index, delta in
        pixels += delta
        return event(UInt64(index + 1), pixels, delta)
      }
      for mask in 0..<(1 << max(0, deltas.count - 1)) {
        var queue = NativeEventQueue()
        var delivered: [NativeEvent] = []
        for (index, event) in input.enumerated() {
          #expect(true == queue.append(event))
          if mask & (1 << index) != 0 {
            let prepared = queue.events
            queue.removeAll()
            delivered.append(contentsOf: prepared)
          }
        }
        delivered.append(contentsOf: queue.events)
        let actual = result(delivered)
        let expected = result(input)
        #expect(
          actual.trace == expected.trace && actual.carry == expected.carry
            && actual.pixels == expected.pixels)
      }
    }
  }

  @Test func boundedQueueRejectsWithoutDroppingPreparedOrOverflowingRuns() throws {
    var queue = NativeEventQueue()
    for i in 1...1024 { #expect(true == queue.append(event(UInt64(i), 0, 0))) }
    let prepared = queue.events
    let bytes = try EventBatch.encode(epoch: 1, events: prepared)
    #expect(false == queue.append(event(1025, 0, 0)))
    #expect(queue.events.count == 1024)
    queue.removeAll()
    #expect(true == queue.append(event(1025, 2, 2)))
    #expect(try EventBatch.encode(epoch: 1, events: prepared) == bytes)
    queue.removeAll()
    #expect(true == queue.append(event(1, 0, .greatestFiniteMagnitude)))
    #expect(true == queue.append(event(2, 0, .greatestFiniteMagnitude)))
    #expect(queue.events.count == 2)
    for invalid in [Double.nan, .infinity, -.infinity] {
      #expect(false == queue.append(event(3, invalid, 1)))
      #expect(false == queue.append(event(3, 1, invalid)))
    }
  }
}
