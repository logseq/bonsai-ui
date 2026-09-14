import Foundation

struct NativeEventQueue {
  private(set) var events: [NativeEvent] = []
  private var byteCount = ProtocolLimits.headerBytes + 4
  private var recordByteCounts: [Int] = []
  let maximumCount: Int
  let maximumBytes: Int
  init(
    maximumCount: Int = 1024,
    maximumBytes: Int = ProtocolLimits.maxFrameBytes
  ) {
    self.maximumCount = min(maximumCount, 1024)
    self.maximumBytes = min(maximumBytes, ProtocolLimits.maxFrameBytes)
  }
  mutating func append(_ event: NativeEvent) -> Bool {
    guard event.sequence > (events.last?.sequence ?? 0),
      let encoded = try? EventBatch.encode(epoch: 1, events: [event])
    else { return false }
    let recordBytes = encoded.count - ProtocolLimits.headerBytes - 4
    var candidate = event
    let replacing: Bool
    if let last = events.last, last.nodeID == event.nodeID,
      last.handlerID == event.handlerID, last.displayedRevision == event.displayedRevision
    {
      switch (last.payload, event.payload) {
      case (.scroll(_, let previous), .scroll(let pixels, let delta)):
        let sum = previous + delta
        replacing = previous != 0 && delta != 0 && (previous > 0) == (delta > 0) && sum.isFinite
        if replacing { candidate.payload = .scroll(pixels: pixels, delta: sum) }
      case (.visibleRange, .visibleRange), (.navigationSplit, .navigationSplit),
        (.tabSelection, .tabSelection), (.valueChanged, .valueChanged),
        (.pickerSelection, .pickerSelection),
        (.scrollPosition, .scrollPosition),
        (.civilDate, .civilDate), (.civilTime, .civilTime),
        (.sliderChanged, .sliderChanged), (.rangeSliderChanged, .rangeSliderChanged):
        replacing = true
      case (.textEdit(let previous), .textEdit(let next)):
        replacing =
          previous.sessionID == next.sessionID && next.localRevision > previous.localRevision
      default: replacing = false
      }
    } else {
      replacing = false
    }
    let nextBytes = byteCount - (replacing ? (recordByteCounts.last ?? 0) : 0) + recordBytes
    guard nextBytes <= maximumBytes, events.count + (replacing ? 0 : 1) <= maximumCount
    else { return false }
    candidate.payload = candidate.payload.owningApplicationBytes
    if replacing {
      events[events.count - 1] = candidate
      recordByteCounts[recordByteCounts.count - 1] = recordBytes
    } else {
      events.append(candidate)
      recordByteCounts.append(recordBytes)
    }
    byteCount = nextBytes
    return true
  }
  // OCaml rejects an entire batch containing a cancelled or duplicate reply.
  // Keep each application reply separate from other replies and UI input.
  var pumpEvents: [NativeEvent] {
    if events.first?.payload.isApplicationReply == true { return Array(events.prefix(1)) }
    return Array(events.prefix { !$0.payload.isApplicationReply })
  }
  mutating func removePrefix(_ count: Int) {
    precondition(count >= 0 && count <= events.count)
    byteCount -= recordByteCounts.prefix(count).reduce(0, +)
    events.removeFirst(count)
    recordByteCounts.removeFirst(count)
  }
  mutating func removeAll() {
    events.removeAll(keepingCapacity: true)
    byteCount = ProtocolLimits.headerBytes + 4
    recordByteCounts.removeAll(keepingCapacity: true)
  }
}
