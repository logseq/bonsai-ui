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
  @ObservationIgnored var onPresentationChange: (() -> Void)?
  private(set) var presented: Bool {
    didSet { if oldValue != presented { onPresentationChange?() } }
  }
  private(set) var active = false {
    didSet { if oldValue != active { onPresentationChange?() } }
  }
  private(set) var nativeVisible = false {
    didSet { if oldValue != nativeVisible { onPresentationChange?() } }
  }
  private(set) var generation: UInt64 = 0
  private(set) var presentationIdentity: UInt64 = 0
  private(set) var pending: Request?
  private var serial: UInt64 = 0
  private var disposed = false
  private var retainingPresentation = false
  private var contentIdentity: RenderIdentity?
  private var contentMounts: [RenderIdentity: Int] = [:]
  init(_ properties: RenderPresentation) {
    self.properties = properties
    presented = properties.presented
  }
  func setContentIdentity(_ identity: RenderIdentity?) {
    guard contentIdentity != identity else { return }
    contentIdentity = identity
    nativeVisible = false
  }
  func isContentMounted(_ identity: RenderIdentity) -> Bool {
    !disposed && contentIdentity == identity && (contentMounts[identity] ?? 0) > 0
  }
  func mountContent(_ identity: RenderIdentity) {
    guard !disposed else { return }
    contentMounts[identity, default: 0] += 1
    renewContent(identity, token: generation)
  }
  func unmountContent(_ identity: RenderIdentity) {
    guard let count = contentMounts[identity] else { return }
    if count == 1 { contentMounts.removeValue(forKey: identity) }
    else { contentMounts[identity] = count - 1 }
    if contentIdentity == identity && contentMounts[identity] == nil { nativeVisible = false }
  }
  func renewContent(_ identity: RenderIdentity, token: UInt64) {
    guard isContentMounted(identity) else { return }
    appeared(true, token: token)
  }
  func invalidateBinding() {
    generation += 1
    pending = nil
    nativeVisible = false
    if !presented && properties.presented { presentationIdentity += 1 }
    presented = properties.presented
  }
  func synchronize(_ next: RenderPresentation) {
    if !next.sameConfiguration(as: properties) { invalidateBinding() }
    properties = next
    let visible = pending == nil && next.presented
    if presented != visible {
      generation += 1
      if visible { presentationIdentity += 1 }
      nativeVisible = false
    }
    presented = visible
  }
  func setPresentationActive(_ value: Bool, retainingPresentation: Bool = false) {
    self.retainingPresentation = retainingPresentation
    guard active != value else { return }
    if !value && !retainingPresentation { presentationIdentity += 1 }
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
    if presented != properties.presented {
      generation += 1
      if properties.presented { presentationIdentity += 1 }
    }
    presented = properties.presented
  }
  func binding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<Bool> {
    // A dismissed native surface may read again before its delayed callback.
    // Reading must not renew ownership after a replacement or restoration.
    let token = generation
    return Binding(
      get: {
        self.presented && (self.active || (self.retainingPresentation && !self.contentMounts.isEmpty))
      },
      set: { value in
        guard !value, token == self.generation else { return }
        self.requestDismissal(emit: emit)
      })
  }
  func nativeBinding(emit: @escaping (NativeEventPayload) -> Bool) -> Binding<Bool> {
    // SwiftUI retains this binding for the lifetime of its native presentation.
    // A gesture on that still-visible surface uses the current admitted action.
    let identity = presentationIdentity
    return Binding(
      get: { self.binding(emit: emit).wrappedValue },
      set: { value in
        guard identity == self.presentationIdentity, !self.disposed else { return }
        let action = self.binding(emit: emit)
        // Releasing the editor synchronously here reenters UIKit keyboard layout
        // while SwiftUI is mutating its interactive SheetBridge state.
        Task { @MainActor in
          guard identity == self.presentationIdentity, !self.disposed else { return }
          action.wrappedValue = value
        }
      })
  }
  func dispose() {
    disposed = true
    contentMounts.removeAll()
    active = false
    invalidateBinding()
  }
}

struct NativePresentationContent: View {
  let node: RenderNodeState
  let controller: PresentationController
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some View {
    NativeNodeView(node: node, activate: activate)
      .onAppear { controller.mountContent(node.id) }
      .onDisappear { controller.unmountContent(node.id) }
      .onChange(of: controller.generation) { _, token in
        controller.renewContent(node.id, token: token)
      }
      .id(node.id)
      .id(controller.presentationIdentity)
  }
}
