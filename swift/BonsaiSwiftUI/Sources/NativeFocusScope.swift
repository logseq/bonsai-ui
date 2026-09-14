import Observation
import SwiftUI

@MainActor @Observable final class FocusScopeController {
  private(set) var autofocusRequest: UInt64 = 0
  @ObservationIgnored private let emit: (NativeEventPayload) -> Bool
  @ObservationIgnored private var handler: UInt64?
  @ObservationIgnored private var autofocus: Bool
  @ObservationIgnored private var autofocusPending: Bool
  private var presented = false
  private var mounted = false
  private var enabled = true
  @ObservationIgnored private var observedFocus = false
  @ObservationIgnored private var deliveredFocus = false
  private var disposed = false
  @ObservationIgnored private(set) var inputGeneration: UInt64 = 0
  var isCollecting: Bool { presented && mounted && !disposed }
  var canRetainFocus: Bool { mounted && enabled && !disposed }
  var hasFocus: Bool { isCollecting && enabled && observedFocus }
  var wantsAutofocus: Bool { isCollecting && enabled && autofocusPending }

  init(autofocus: Bool, handler: UInt64?, emit: @escaping (NativeEventPayload) -> Bool) {
    self.autofocus = autofocus
    autofocusPending = autofocus
    self.handler = handler
    self.emit = emit
  }

  func synchronize(autofocus: Bool, handler: UInt64?) {
    guard !disposed else { return }
    if self.handler != handler {
      inputGeneration += 1
      self.handler = handler
      deliveredFocus = false
      presented = false
    }
    if self.autofocus != autofocus {
      inputGeneration += 1
      self.autofocus = autofocus
      autofocusPending = autofocus
      presented = false
    }
  }

  func setPresented(_ value: Bool) {
    guard !disposed, presented != value else { return }
    inputGeneration += 1
    presented = value
    reconcile()
    requestAutofocus()
  }

  func setMounted(_ value: Bool) {
    guard !disposed, mounted != value else { return }
    inputGeneration += 1
    mounted = value
    if !value { observedFocus = false }
    reconcile()
    requestAutofocus()
  }

  func setEnabled(_ value: Bool) {
    guard !disposed, enabled != value else { return }
    inputGeneration += 1
    enabled = value
    reconcile()
    requestAutofocus()
  }

  func observeFocus(_ focused: Bool) {
    guard !disposed else { return }
    if observedFocus != focused { inputGeneration += 1 }
    observedFocus = focused
    if focused && wantsAutofocus { autofocusPending = false }
    reconcile()
  }

  private func reconcile() {
    let focused = observedFocus && enabled
    guard isCollecting, handler != nil, focused != deliveredFocus else { return }
    if emit(.focusChanged(focused)) { deliveredFocus = focused }
  }

  private func requestAutofocus() {
    guard wantsAutofocus else { return }
    if observedFocus {
      autofocusPending = false
    } else {
      autofocusRequest += 1
    }
  }

  func dispose() {
    inputGeneration += 1
    disposed = true
    presented = false
    mounted = false
    autofocusPending = false
  }
}

struct NativeFocusScope<Content: View>: View {
  let controller: FocusScopeController
  let content: Content
  @FocusState private var focused: Bool
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    content
      .focusable(enabled, interactions: .edit)
      .focused($focused)
      .onChange(of: focused, initial: true) { _, value in controller.observeFocus(value) }
      .onChange(of: enabled, initial: true) { _, value in controller.setEnabled(value) }
      .onChange(of: controller.autofocusRequest, initial: true) { _, _ in
        if controller.wantsAutofocus { focused = true }
      }
      .onAppear { controller.setMounted(true) }
      .onDisappear { controller.setMounted(false) }
  }
}
