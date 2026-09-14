import Observation
import SwiftUI

enum RenderPresentation: Equatable, Sendable {
  case popover(RenderPopover)
  case sheet(RenderSheet)
  var presented: Bool {
    switch self {
    case .popover(let value): value.presented
    case .sheet(let value): value.presented
    }
  }
  var isModal: Bool { if case .sheet = self { true } else { false } }
  var allowsDismissal: Bool {
    switch self {
    case .popover: true
    case .sheet(let value): value.configuration.interactive
    }
  }
  func sameConfiguration(as other: Self) -> Bool {
    switch (self, other) {
    case (.popover(let left), .popover(let right)): left.edge == right.edge
    case (.sheet(let left), .sheet(let right)): left.configuration == right.configuration
    default: false
    }
  }
}

@MainActor @Observable final class PresentationController {
  struct Request: Equatable { let serial: UInt64 }
  private var properties: RenderPresentation
  private(set) var presented: Bool
  private(set) var active = false
  private(set) var nativeVisible = false
  private(set) var generation: UInt64 = 0
  private(set) var pending: Request?
  private var serial: UInt64 = 0
  private var disposed = false
  init(_ properties: RenderPresentation) {
    self.properties = properties
    presented = properties.presented
  }
  func invalidateBinding() {
    generation += 1
    pending = nil
    nativeVisible = false
    presented = properties.presented
  }
  func synchronize(_ next: RenderPresentation) {
    if !next.sameConfiguration(as: properties) { invalidateBinding() }
    properties = next
    let visible = pending == nil && next.presented
    if presented != visible {
      generation += 1
      nativeVisible = false
    }
    presented = visible
  }
  func setPresentationActive(_ value: Bool) {
    guard active != value else { return }
    active = value
    invalidateBinding()
  }
  func appeared(_ value: Bool, token: UInt64) {
    guard token == generation, !disposed else { return }
    nativeVisible = value && active && presented
  }
  @discardableResult func requestDismissal(emit: (NativeEventPayload) -> Bool) -> Bool {
    guard !disposed, active, presented, properties.allowsDismissal else { return false }
    guard emit(.valueChanged(false)) else {
      generation += 1
      return false
    }
    serial += 1
    pending = Request(serial: serial)
    presented = false
    nativeVisible = false
    return true
  }
  func resolve(_ request: Request) {
    guard pending == request else { return }
    pending = nil
    if presented != properties.presented { generation += 1 }
    presented = properties.presented
  }
  func binding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<Bool> {
    // A dismissed native surface may read again before its delayed callback.
    // Reading must not renew ownership after a replacement or restoration.
    let token = generation
    return Binding(
      get: { self.active && self.presented },
      set: { value in
        guard !value, token == self.generation else { return }
        self.requestDismissal(emit: emit)
      })
  }
  func dispose() {
    disposed = true
    active = false
    invalidateBinding()
  }
}
