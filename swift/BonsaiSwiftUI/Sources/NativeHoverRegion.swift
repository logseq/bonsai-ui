import SwiftUI

#if os(macOS)
  import AppKit
  typealias HoverCaptureView = AppKitHoverCapture
  typealias HoverWindow = NSWindow
  typealias PlatformHoverSource = AppKitHoverSource
#else
  import UIKit
  typealias HoverCaptureView = UIKitHoverCapture
  typealias HoverWindow = UIWindow
  typealias PlatformHoverSource = UIKitHoverSource
#endif

@MainActor final class NativeHoverHost {
  let router: HoverRouter
  private struct WeakController { weak var value: HoverRegionController? }
  private var controllers: [RenderIdentity: WeakController] = [:]
  private var scheduled = false
  private let sources: HoverWindowSources<HoverWindow>
  var activeWindowCount: Int { sources.count }

  init(router: HoverRouter) {
    self.router = router
    sources = HoverWindowSources(
      create: { window, receive in
        PlatformHoverSource(window: window, receive: receive)
      }, receive: { [weak router] sample in router?.receive(sample) })
  }

  func register(_ controller: HoverRegionController) {
    controllers[controller.id] = WeakController(value: controller)
    changed()
  }
  func unregister(_ controller: HoverRegionController) {
    if controllers[controller.id]?.value === controller {
      controllers.removeValue(forKey: controller.id)
    }
    changed()
  }
  func discardInput() { sources.replace([:]) }
  func changed() {
    guard !scheduled else { return }
    scheduled = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.scheduled = false
      var windows: [ObjectIdentifier: HoverWindow] = [:]
      for weak in self.controllers.values {
        if let controller = weak.value, controller.collecting, let window = controller.view.window {
          windows[ObjectIdentifier(window)] = window
        }
      }
      self.sources.replace(windows)
      self.router.refresh()
    }
  }
}

@MainActor final class HoverRegionController {
  let id: RenderIdentity
  let view = HoverCaptureView(frame: .zero)
  private let host: NativeHoverHost
  private let emit: (NativeEventPayload) -> Bool
  private var bindings: [Int: UInt64] = [:]
  private var requested = false
  private var mounted = false
  private var disposed = false
  #if os(macOS)
    private var generation: UInt64 = 0
  #endif
  var collecting: Bool { requested && mounted && !disposed }

  init(id: RenderIdentity, host: NativeHoverHost, emit: @escaping (NativeEventPayload) -> Bool) {
    self.id = id
    self.host = host
    self.emit = emit
    view.onGeometry = { [weak self] in self?.host.changed() }
    host.register(self)
  }
  func synchronize(_ bindings: [Int: UInt64]) {
    guard !disposed, self.bindings != bindings else { return }
    self.bindings = bindings
    #if os(macOS)
      generation += 1
      let version = generation
    #endif
    view.setCaptureEnabled(false)
    #if os(macOS)
      view.onSample = { [weak self] pointer, present in
        guard let self, self.collecting, self.generation == version,
          let window = self.view.window
        else { return }
        self.host.router.receive(
          HoverRouter.Sample(
            pointer: HoverSample(
              id: pointer.id, kind: pointer.kind,
              position: CGPoint(x: pointer.globalX, y: pointer.globalY), buttons: pointer.buttons),
            window: ObjectIdentifier(window), present: present))
      }
    #endif
    view.setCaptureEnabled(collecting)
    host.changed()
  }
  func setCollecting(_ enabled: Bool) {
    guard !disposed, requested != enabled else { return }
    requested = enabled
    view.setCaptureEnabled(collecting)
    host.changed()
  }
  func setMounted(_ mounted: Bool) {
    guard !disposed, self.mounted != mounted else { return }
    self.mounted = mounted
    view.setCaptureEnabled(collecting)
    host.changed()
  }
  func region(subtree: Range<Int>, order: Int, blocksBehind: Bool) -> HoverRouter.Region {
    HoverRouter.Region(
      id: id, subtree: subtree, order: order, blocksBehind: blocksBehind,
      bindings: bindings,
      locate: { [weak self] sample in
        guard let self, self.collecting else { return nil }
        return self.view.locate(sample)
      },
      emit: { [weak self] payload in
        guard let self, !self.disposed else { return false }
        return self.emit(payload)
      })
  }
  func dispose() {
    guard !disposed else { return }
    disposed = true
    #if os(macOS)
      generation += 1
      view.onSample = nil
    #endif
    view.onGeometry = nil
    view.dispose()
    host.unregister(self)
  }
}

#if os(macOS)
  struct NativeHoverRegion: NSViewRepresentable {
    let controller: HoverRegionController
    func makeCoordinator() -> HoverRegionController { controller }
    func makeNSView(context: Context) -> HoverCaptureView {
      controller.setMounted(true)
      return controller.view
    }
    func updateNSView(_ view: HoverCaptureView, context: Context) { controller.setMounted(true) }
    static func dismantleNSView(_ view: HoverCaptureView, coordinator: HoverRegionController) {
      coordinator.setMounted(false)
    }
  }
#else
  struct NativeHoverRegion: UIViewRepresentable {
    let controller: HoverRegionController
    func makeCoordinator() -> HoverRegionController { controller }
    func makeUIView(context: Context) -> HoverCaptureView {
      controller.setMounted(true)
      return controller.view
    }
    func updateUIView(_ view: HoverCaptureView, context: Context) { controller.setMounted(true) }
    static func dismantleUIView(_ view: HoverCaptureView, coordinator: HoverRegionController) {
      coordinator.setMounted(false)
    }
  }
#endif
