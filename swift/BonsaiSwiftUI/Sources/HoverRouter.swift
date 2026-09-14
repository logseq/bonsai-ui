import Foundation

@MainActor final class HoverRouter {
  struct Sample: Equatable {
    let pointer: HoverSample
    let window: ObjectIdentifier
    let present: Bool
  }
  struct Hit {
    let pointer: NativePointer
    let inside: Bool
  }
  struct Region {
    let id: RenderIdentity
    let subtree: Range<Int>
    let order: Int
    let blocksBehind: Bool
    let bindings: [Int: UInt64]
    let locate: (Sample) -> Hit?
    let emit: (NativeEventPayload) -> Bool
  }
  private struct Entry {
    let region: Region
    var transitions: HoverTransitions
  }
  private var entries: [RenderIdentity: Entry] = [:]
  private var samples: [UInt64: Sample] = [:]
  private var presented = false
  private var refreshing = false
  private var revision: UInt64 = 0
  private var needsRetry = false

  func replace(_ regions: [Region]) {
    entries = Dictionary(
      uniqueKeysWithValues: regions.map { region in
        let previous = entries[region.id]
        return (
          region.id,
          Entry(
            region: region,
            transitions: previous?.region.bindings == region.bindings
              ? previous!.transitions : HoverTransitions())
        )
      })
    revision += 1
    needsRetry = true
  }

  func setPresented(_ presented: Bool) {
    self.presented = presented
    if presented { refresh() }
  }

  func receive(_ sample: Sample) {
    guard sample.pointer.isValid else { return }
    guard samples[sample.pointer.id] != sample || needsRetry else { return }
    samples[sample.pointer.id] = sample
    refresh()
  }

  func refresh() {
    guard presented, !refreshing else { return }
    refreshing = true
    needsRetry = true
    defer { refreshing = false }
    let version = revision
    let regions = entries.values.map(\.region).sorted { $0.order > $1.order }
    for sample in samples.values.sorted(by: { $0.pointer.id < $1.pointer.id }) {
      var hits: [RenderIdentity: Hit] = [:]
      for region in regions {
        if let hit = region.locate(sample), hit.pointer.isValid,
          hit.pointer.id == sample.pointer.id
        {
          hits[region.id] = hit
        } else {
          entries[region.id]?.transitions.remove(sample.pointer.id)
        }
      }
      var allowed: Set<RenderIdentity> = []
      var blockers: [Region] = []
      if sample.present {
        for region in regions where hits[region.id]?.inside == true {
          guard blockers.allSatisfy({ region.subtree.contains($0.order) }) else { continue }
          allowed.insert(region.id)
          if region.blocksBehind { blockers.append(region) }
        }
      }
      // Depart front-to-back; enter ancestors before their descendants.
      for inside in [false, true] {
        let ordered = inside ? Array(regions.reversed()) : regions
        for region in ordered where allowed.contains(region.id) == inside {
          guard presented, revision == version else { return }
          guard let hit = hits[region.id], var next = entries[region.id]?.transitions else {
            continue
          }
          guard let event = next.update(hit.pointer, inside: inside) else { continue }
          guard region.emit(event) else { return }
          guard entries[region.id]?.region.bindings == region.bindings else { return }
          entries[region.id]?.transitions = next
        }
      }
      if !sample.present || hits.isEmpty { samples.removeValue(forKey: sample.pointer.id) }
    }
    needsRetry = false
  }

  func reset() {
    presented = false
    entries.removeAll()
    samples.removeAll()
    revision += 1
  }
  func discardSamples() {
    presented = false
    samples.removeAll()
    for id in entries.keys { entries[id]?.transitions.reset() }
    revision += 1
  }
}
