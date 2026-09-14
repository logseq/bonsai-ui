import Observation
import SwiftUI

extension NodeProperties {
  var scrollAxis: Bool? {
    switch self {
    case .scroll(let vertical, _, _, _): vertical
    case .collection(let catalog): catalog.vertical
    case .scrollSections(let sections): sections.vertical
    case .scrollTargets(let targets): targets.vertical
    default: nil
    }
  }
}

@MainActor @Observable final class ScrollObserver {
  private(set) var vertical: Bool
  private(set) var generation: UInt64 = 0
  @ObservationIgnored private var handler: UInt64?
  @ObservationIgnored private var presented = false
  @ObservationIgnored private var mounts = 0
  @ObservationIgnored private var disposed = false
  @ObservationIgnored private var previousPixels: Double?
  @ObservationIgnored private let emit: (NativeEventPayload) -> Bool

  init(vertical: Bool, handler: UInt64?, emit: @escaping (NativeEventPayload) -> Bool) {
    self.vertical = vertical
    self.handler = handler
    self.emit = emit
  }
  var isCollecting: Bool { presented && mounts > 0 && handler != nil && !disposed }
  private func reset() {
    generation += 1
    previousPixels = nil
  }
  func synchronize(vertical: Bool, handler: UInt64?) {
    guard self.vertical != vertical || self.handler != handler else { return }
    self.vertical = vertical
    self.handler = handler
    presented = false
    reset()
  }
  func setPresented(_ value: Bool) {
    guard !disposed, presented != value else { return }
    presented = value
    reset()
  }
  func attach() { mounts += 1 }
  func detach() {
    mounts = max(0, mounts - 1)
    if mounts == 0 { reset() }
  }
  @discardableResult func observe(_ pixels: Double, generation: UInt64) -> Bool {
    guard !disposed, generation == self.generation, pixels.isFinite else { return false }
    let previous = previousPixels
    guard previous.map({ (pixels - $0).isFinite }) ?? true else { return false }
    previousPixels = pixels
    guard isCollecting else { return false }
    guard let previous, pixels != previous else { return true }
    return emit(.scroll(pixels: pixels, delta: pixels - previous))
  }
  @discardableResult func phase(_ pixels: Double, generation: UInt64) -> Bool {
    guard observe(pixels, generation: generation), isCollecting else { return false }
    return emit(.scroll(pixels: pixels, delta: 0))
  }
  func dispose() {
    disposed = true
    presented = false
    reset()
  }
}

private struct ScrollSample: Equatable {
  let generation: UInt64
  let pixels: Double
}

private struct ObservedScroll: ViewModifier {
  let observer: ScrollObserver
  func body(content: Content) -> some View {
    let generation = observer.generation
    let vertical = observer.vertical
    content
      .onAppear { observer.attach() }
      .onDisappear { observer.detach() }
      .onScrollGeometryChange(for: ScrollSample.self) { geometry in
        ScrollSample(
          generation: generation,
          pixels: vertical ? geometry.visibleRect.minY : geometry.visibleRect.minX)
      } action: { _, sample in
        observer.observe(sample.pixels, generation: sample.generation)
      }
      .onScrollPhaseChange { _, _, context in
        let rect = context.geometry.visibleRect
        observer.phase(vertical ? rect.minY : rect.minX, generation: generation)
      }
  }
}

struct ScrollObservationModifier: ViewModifier {
  let observer: ScrollObserver?
  @ViewBuilder func body(content: Content) -> some View {
    if let observer { content.modifier(ObservedScroll(observer: observer)) } else { content }
  }
}
