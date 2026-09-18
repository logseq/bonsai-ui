import SwiftUI

// Native menu configuration is the presentation boundary. SwiftUI's contextMenu
// builder is cached between openings and can rebuild handlers while tracking.
// Keep SwiftUI content in the original tree and attach native interaction through
// a noninteractive geometry anchor; every opening receives a fresh immutable menu.
#if os(macOS)
  import AppKit

  struct NativeContextMenuAnchor: NSViewRepresentable {
    let controller: ContextMenuController
    func makeNSView(context: Context) -> ContextMenuAnchorView { ContextMenuAnchorView() }
    func updateNSView(_ view: ContextMenuAnchorView, context: Context) {
      view.configure(controller)
    }
    static func dismantleNSView(_ view: ContextMenuAnchorView, coordinator: ()) { view.detach() }
  }

  final class ContextMenuAnchorView: NSView {
    private(set) var controller: ContextMenuController?
    private var registeredWindowID: ObjectIdentifier?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      register()
    }
    func configure(_ controller: ContextMenuController) {
      if self.controller !== controller {
        detach()
        self.controller = controller
      }
      register()
    }
    private func register() {
      let next = window.map(ObjectIdentifier.init)
      guard next != registeredWindowID else { return }
      if let registeredWindowID {
        ContextMenuWindows.shared.remove(self, from: registeredWindowID)
        controller?.invalidatePresentation()
      }
      registeredWindowID = next
      if let window { ContextMenuWindows.shared.add(self, to: window) }
    }
    func detach() {
      if let registeredWindowID { ContextMenuWindows.shared.remove(self, from: registeredWindowID) }
      registeredWindowID = nil
      controller?.invalidatePresentation()
      controller = nil
    }
    func contains(_ point: CGPoint) -> Bool {
      guard window != nil, !isHiddenOrHasHiddenAncestor, controller?.isAvailable == true else {
        return false
      }
      return visibleRect.contains(convert(point, from: nil))
    }
    func menu() -> NSMenu? {
      guard let controller, controller.isAvailable else { return nil }
      return NSHostingMenu(
        rootView: NativeContextMenuContent(
          controller: controller, presentation: controller.capture()))
    }
  }

  @MainActor private final class ContextMenuWindows {
    static let shared = ContextMenuWindows()
    @MainActor private final class Anchor {
      weak var view: ContextMenuAnchorView?
      init(_ view: ContextMenuAnchorView) { self.view = view }
    }
    @MainActor private final class Source {
      weak var window: NSWindow?
      var anchors: [Anchor] = []
      var monitor: Any?
      init(_ window: NSWindow) {
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) {
          [weak self] event in
          let consumed = MainActor.assumeIsolated {
            guard let self, event.window === self.window,
              event.type == .rightMouseDown || event.modifierFlags.contains(.control),
              let anchor = self.anchors.compactMap(\.view).last(where: {
                $0.contains(event.locationInWindow)
              }),
              let menu = anchor.menu()
            else { return false }
            NSMenu.popUpContextMenu(menu, with: event, for: anchor)
            return true
          }
          return consumed ? nil : event
        }
      }
      func dispose() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        anchors = []
      }
    }
    private var sources: [ObjectIdentifier: Source] = [:]
    func add(_ view: ContextMenuAnchorView, to window: NSWindow) {
      let id = ObjectIdentifier(window)
      let source = sources[id] ?? Source(window)
      sources[id] = source
      source.anchors.removeAll { $0.view == nil || $0.view === view }
      source.anchors.append(Anchor(view))
    }
    func remove(_ view: ContextMenuAnchorView, from id: ObjectIdentifier) {
      guard let source = sources[id] else { return }
      source.anchors.removeAll { $0.view == nil || $0.view === view }
      if source.anchors.isEmpty {
        source.dispose()
        sources.removeValue(forKey: id)
      }
    }
  }
#else
  import UIKit

  struct NativeContextMenuAnchor: UIViewRepresentable {
    let controller: ContextMenuController
    func makeUIView(context: Context) -> ContextMenuAnchorView { ContextMenuAnchorView() }
    func updateUIView(_ view: ContextMenuAnchorView, context: Context) {
      view.configure(controller)
    }
    static func dismantleUIView(_ view: ContextMenuAnchorView, coordinator: ()) { view.detach() }
  }

  final class ContextMenuAnchorView: UIView {
    private(set) var controller: ContextMenuController?
    private var registeredSurfaceID: ObjectIdentifier?
    private var registeredWindowID: ObjectIdentifier?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func didMoveToSuperview() {
      super.didMoveToSuperview()
      register()
    }
    override func didMoveToWindow() {
      super.didMoveToWindow()
      register()
    }
    func configure(_ controller: ContextMenuController) {
      isAccessibilityElement = false
      if self.controller !== controller {
        detach()
        self.controller = controller
      }
      register()
    }
    private var interactionSurface: UIView? {
      guard window != nil else { return nil }
      var responder: UIResponder? = self
      while let current = responder {
        if let controller = current as? UIViewController,
          let view = controller.viewIfLoaded, view.window === window
        {
          return view
        }
        responder = current.next
      }
      return nil
    }
    private func register() {
      let surface = interactionSurface
      let next = surface.map(ObjectIdentifier.init)
      let nextWindow = window.map(ObjectIdentifier.init)
      guard next != registeredSurfaceID || nextWindow != registeredWindowID else { return }
      if let registeredSurfaceID {
        ContextMenuSurfaces.shared.remove(self, from: registeredSurfaceID)
        controller?.invalidatePresentation()
      }
      registeredSurfaceID = next
      registeredWindowID = nextWindow
      if let surface { ContextMenuSurfaces.shared.add(self, to: surface) }
    }
    func detach() {
      if let registeredSurfaceID {
        ContextMenuSurfaces.shared.remove(self, from: registeredSurfaceID)
      }
      registeredSurfaceID = nil
      registeredWindowID = nil
      controller?.invalidatePresentation()
      controller = nil
    }
    func contains(_ point: CGPoint) -> Bool {
      guard let window, controller?.isAvailable == true,
        bounds.contains(convert(point, from: window))
      else { return false }
      var ancestor: UIView? = self
      while let view = ancestor {
        if view.isHidden || view.alpha == 0
          || (view.clipsToBounds && !view.bounds.contains(view.convert(point, from: window)))
        {
          return false
        }
        ancestor = view.superview
      }
      return true
    }
  }

  @MainActor private final class ContextMenuSurfaces {
    static let shared = ContextMenuSurfaces()
    @MainActor private final class Anchor {
      weak var view: ContextMenuAnchorView?
      init(_ view: ContextMenuAnchorView) { self.view = view }
    }
    @MainActor private final class Source: NSObject, UIContextMenuInteractionDelegate {
      private weak var surface: UIView?
      private var window: UIWindow? { surface?.window }
      var anchors: [Anchor] = []
      private var interaction: UIContextMenuInteraction!
      private var presentedPreview: UITargetedPreview?
      private var presentedIdentifier: String?
      init(_ surface: UIView) {
        self.surface = surface
        super.init()
        interaction = UIContextMenuInteraction(delegate: self)
        surface.addInteraction(interaction)
      }
      func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
      ) -> UIContextMenuConfiguration? {
        let location = interaction.view?.convert(location, to: window) ?? location
        guard let anchor = anchors.compactMap(\.view).last(where: { $0.contains(location) }),
          let controller = anchor.controller, controller.isAvailable, let window
        else { return nil }
        let rect = anchor.convert(anchor.bounds, to: window).intersection(window.bounds)
        guard !rect.isEmpty,
          let snapshot = window.resizableSnapshotView(
            from: rect, afterScreenUpdates: false, withCapInsets: .zero)
        else { return nil }
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(rect: CGRect(origin: .zero, size: rect.size))
        // UIKit animates the preview view. Never give it the live application window.
        presentedPreview = UITargetedPreview(
          view: snapshot, parameters: parameters,
          target: UIPreviewTarget(container: window, center: CGPoint(x: rect.midX, y: rect.midY)))
        let presentation = controller.capture()
        let identifier =
          "\(presentation.owner.epoch):\(presentation.owner.node):\(presentation.serial)"
        presentedIdentifier = identifier
        return UIContextMenuConfiguration(identifier: identifier as NSString, previewProvider: nil)
        { _ in
          return UIMenu(
            children: presentation.items.map { item in
              var attributes: UIMenuElement.Attributes = []
              if !item.properties.enabled { attributes.insert(.disabled) }
              if item.properties.role == 1 { attributes.insert(.destructive) }
              return UIAction(
                title: item.properties.title,
                image: item.properties.symbol.flatMap { UIImage(systemName: $0) },
                attributes: attributes
              ) { _ in controller.perform(item, from: presentation) }
            })
        }
      }
      func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
        highlightPreviewForItemWithIdentifier identifier: NSCopying
      ) -> UITargetedPreview? { preview(configuration) }
      func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
        dismissalPreviewForItemWithIdentifier identifier: NSCopying
      ) -> UITargetedPreview? { preview(configuration) }
      private func preview(_ configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard configuration.identifier as? String == presentedIdentifier else { return nil }
        return presentedPreview
      }
      func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
      ) {
        let clear = { [weak self] in
          guard let self, configuration.identifier as? String == self.presentedIdentifier else {
            return
          }
          self.presentedPreview = nil
          self.presentedIdentifier = nil
        }
        if let animator { animator.addCompletion(clear) } else { clear() }
      }
      func dispose() {
        interaction.dismissMenu()
        interaction.view?.removeInteraction(interaction)
        anchors = []
        presentedPreview = nil
        presentedIdentifier = nil
      }
    }
    private var sources: [ObjectIdentifier: Source] = [:]
    func add(_ view: ContextMenuAnchorView, to surface: UIView) {
      let id = ObjectIdentifier(surface)
      let source = sources[id] ?? Source(surface)
      sources[id] = source
      source.anchors.removeAll { $0.view == nil || $0.view === view }
      source.anchors.append(Anchor(view))
    }
    func remove(_ view: ContextMenuAnchorView, from id: ObjectIdentifier) {
      guard let source = sources[id] else { return }
      source.anchors.removeAll { $0.view == nil || $0.view === view }
      if source.anchors.isEmpty {
        source.dispose()
        sources.removeValue(forKey: id)
      }
    }
  }
#endif
