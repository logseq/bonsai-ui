import QuartzCore
import SwiftUI

@MainActor
private final class PresentationMonitor {
  var ticket: PresentationTicket?
  var completed: PresentationTicket?
  var inFlight: PresentationTicket?
  var onVisibility: @MainActor (Bool) -> Void = { _ in }
  var onPresented: @MainActor (PresentationTicket) async -> Bool = { _ in false }
  private var lastVisibility: Bool?

  func invalidateVisibility() { lastVisibility = nil }

  func visibility(_ visible: Bool) {
    if lastVisibility != visible {
      lastVisibility = visible
      onVisibility(visible)
    }
  }

  func begin(visible: Bool) -> PresentationTicket? {
    guard visible, let ticket, completed != ticket, inFlight != ticket else { return nil }
    inFlight = ticket
    return ticket
  }

  func finish(_ observed: PresentationTicket, visible: Bool) async {
    defer { if inFlight == observed { inFlight = nil } }
    guard visible, ticket == observed, completed != observed else { return }
    if await onPresented(observed), ticket == observed { completed = observed }
  }
}

#if os(macOS)
  final class NativePresentationView: NSView {
    private let monitor = PresentationMonitor()
    private var observing = false
    private weak var observedWindow: NSWindow?
    private var visibilityObservation: NSKeyValueObservation?

    private func observeWindowVisibility() {
      guard observedWindow !== window else { return }
      visibilityObservation = nil
      observedWindow = window
      visibilityObservation = window?.observe(\.isVisible, options: [.initial]) {
        [weak self] _, _ in
        MainActor.assumeIsolated { self?.schedule() }
      }
    }
    private var title: String?
    private var windowHost = NativeWindowHost()
    private var visibleNow: Bool {
      window?.isVisible == true && !isHiddenOrHasHiddenAncestor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(
      ticket: PresentationTicket?, title: String? = nil,
      windowHost: NativeWindowHost? = nil,
      onVisibility: @escaping @MainActor (Bool) -> Void,
      onPresented: @escaping @MainActor (PresentationTicket) async -> Bool
    ) {
      self.title = title
      if let windowHost, self.windowHost !== windowHost {
        if self.windowHost.owns(self) { monitor.visibility(false) }
        self.windowHost.detach(owner: self)
        self.windowHost = windowHost
        monitor.invalidateVisibility()
      }
      self.windowHost.attach(window: window, title: title, owner: self)
      wantsLayer = true
      monitor.ticket = ticket
      monitor.onVisibility = onVisibility
      monitor.onPresented = onPresented
      observeWindowVisibility()
      if !observing {
        observing = true
        for name in [
          NSWindow.didExposeNotification, NSWindow.didChangeOcclusionStateNotification,
          NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
        ] {
          NotificationCenter.default.addObserver(
            self, selector: #selector(windowChanged(_:)),
            name: name, object: nil)
        }
      }
      schedule()
    }

    @objc private func windowChanged(_ notification: Notification) {
      if let changed = notification.object as? NSWindow, changed === window { schedule() }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil, windowHost.owns(self) { monitor.visibility(false) }
      windowHost.attach(window: window, title: title, owner: self)
      observeWindowVisibility()
      schedule()
    }
    func dismantle() {
      visibilityObservation = nil
      observedWindow = nil
      if windowHost.owns(self) { monitor.visibility(false) }
      windowHost.detach(owner: self)
      monitor.ticket = nil
    }
    override func viewDidHide() {
      super.viewDidHide()
      schedule()
    }
    override func viewDidUnhide() {
      super.viewDidUnhide()
      schedule()
    }

    private func schedule() {
      needsLayout = true
      Task { @MainActor [weak self] in
        guard let self, windowHost.owns(self) else { return }
        monitor.visibility(visibleNow)
        if visibleNow { needsLayout = true }
      }
    }

    override func layout() {
      super.layout()
      guard windowHost.owns(self), let observed = monitor.begin(visible: visibleNow) else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      CATransaction.setCompletionBlock { [weak self] in
        Task { @MainActor [weak self] in
          guard let self, windowHost.owns(self) else { return }
          await monitor.finish(observed, visible: visibleNow)
        }
      }
      layer?.setNeedsDisplay()
      CATransaction.commit()
    }
  }

  struct PresentationProbe: NSViewRepresentable {
    let ticket: PresentationTicket?
    let title: String?
    var windowHost: NativeWindowHost? = nil
    let onVisibility: @MainActor (Bool) -> Void
    let onPresented: @MainActor (PresentationTicket) async -> Bool
    func makeNSView(context: Context) -> NativePresentationView { NativePresentationView() }
    func updateNSView(_ view: NativePresentationView, context: Context) {
      view.configure(
        ticket: ticket, title: title, windowHost: windowHost,
        onVisibility: onVisibility, onPresented: onPresented)
    }
    static func dismantleNSView(_ view: NativePresentationView, coordinator: ()) {
      view.dismantle()
    }
  }
#else
  final class NativePresentationView: UIView {
    private let monitor = PresentationMonitor()
    private var title: String?
    private var windowHost = NativeWindowHost()
    private var visibleNow: Bool {
      guard let window, !window.isHidden, window.alpha > 0 else { return false }
      var ancestor: UIView? = self
      while let view = ancestor {
        if view.isHidden || view.alpha == 0 { return false }
        ancestor = view.superview
      }
      return true
    }

    func configure(
      ticket: PresentationTicket?, title: String? = nil,
      windowHost: NativeWindowHost? = nil,
      onVisibility: @escaping @MainActor (Bool) -> Void,
      onPresented: @escaping @MainActor (PresentationTicket) async -> Bool
    ) {
      self.title = title
      if let windowHost, self.windowHost !== windowHost {
        if self.windowHost.owns(self) { monitor.visibility(false) }
        self.windowHost.detach(owner: self)
        self.windowHost = windowHost
        monitor.invalidateVisibility()
      }
      self.windowHost.attach(window: window, title: title, owner: self)
      isUserInteractionEnabled = false
      monitor.ticket = ticket
      monitor.onVisibility = onVisibility
      monitor.onPresented = onPresented
      schedule()
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      if window == nil, windowHost.owns(self) { monitor.visibility(false) }
      windowHost.attach(window: window, title: title, owner: self)
      schedule()
    }
    func dismantle() {
      if windowHost.owns(self) { monitor.visibility(false) }
      windowHost.detach(owner: self)
      monitor.ticket = nil
    }
    private func schedule() {
      setNeedsLayout()
      Task { @MainActor [weak self] in
        guard let self, windowHost.owns(self) else { return }
        monitor.visibility(visibleNow)
        if visibleNow { setNeedsLayout() }
      }
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      guard windowHost.owns(self), let observed = monitor.begin(visible: visibleNow) else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      CATransaction.setCompletionBlock { [weak self] in
        Task { @MainActor [weak self] in
          guard let self, windowHost.owns(self) else { return }
          await monitor.finish(observed, visible: visibleNow)
        }
      }
      layer.setNeedsDisplay()
      CATransaction.commit()
    }
  }

  struct PresentationProbe: UIViewRepresentable {
    let ticket: PresentationTicket?
    let title: String?
    var windowHost: NativeWindowHost? = nil
    let onVisibility: @MainActor (Bool) -> Void
    let onPresented: @MainActor (PresentationTicket) async -> Bool
    func makeUIView(context: Context) -> NativePresentationView { NativePresentationView() }
    func updateUIView(_ view: NativePresentationView, context: Context) {
      view.configure(
        ticket: ticket, title: title, windowHost: windowHost,
        onVisibility: onVisibility, onPresented: onPresented)
    }
    static func dismantleUIView(_ view: NativePresentationView, coordinator: ()) {
      view.dismantle()
    }
  }
#endif
