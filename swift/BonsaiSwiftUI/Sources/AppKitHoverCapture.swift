#if os(macOS)
  import AppKit

  final class AppKitHoverCapture: NSView {
    var onSample: ((NativePointer, Bool) -> Void)?
    var onGeometry: (() -> Void)?
    private let devices = AppKitPointerDevices.acquire()
    private var captureEnabled = false
    private var disposed = false
    private var area: NSTrackingArea?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setCaptureEnabled(_ enabled: Bool) {
      guard !disposed, captureEnabled != enabled else { return }
      captureEnabled = enabled
      updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      updateTrackingAreas()
    }

    override func viewDidHide() {
      super.viewDidHide()
      updateTrackingAreas()
    }

    override func viewDidUnhide() {
      super.viewDidUnhide()
      updateTrackingAreas()
    }

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      defer { onGeometry?() }
      guard captureEnabled, !disposed, window != nil, !isHiddenOrHasHiddenAncestor else {
        if let area { removeTrackingArea(area) }
        area = nil
        return
      }
      guard area == nil else { return }
      let next = NSTrackingArea(
        rect: .zero,
        options: [
          .mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect,
          .enabledDuringMouseDrag,
        ],
        owner: self)
      area = next
      addTrackingArea(next)
    }

    override func mouseEntered(with event: NSEvent) { capture(event, entering: true) }
    override func mouseExited(with event: NSEvent) { capture(event, entering: false) }
    override func mouseMoved(with event: NSEvent) {
      guard event.type == .mouseMoved, let pointer = pointer(event) else { return }
      onSample?(pointer, true)
    }

    private func capture(_ event: NSEvent, entering: Bool) {
      guard event.type == (entering ? .mouseEntered : .mouseExited), let pointer = pointer(event)
      else { return }
      onSample?(pointer, true)
    }

    private func pointer(_ event: NSEvent) -> NativePointer? {
      guard captureEnabled, !disposed, !isHiddenOrHasHiddenAncestor,
        let window, window.isVisible, let root = window.contentView
      else {
        onGeometry?()
        return nil
      }
      guard event.windowNumber == window.windowNumber,
        let buttons = UInt32(exactly: NSEvent.pressedMouseButtons),
        let device = devices.device(for: event)
      else { return nil }
      if event.type == .mouseEntered || event.type == .mouseExited,
        let eventArea = event.trackingArea, eventArea !== area
      {
        return nil
      }
      let local = convert(event.locationInWindow, from: nil)
      let global = root.convert(event.locationInWindow, from: nil)
      let pointer = NativePointer(
        id: device.id,
        localX: local.x - bounds.minX,
        localY: local.y - bounds.minY,
        globalX: global.x - root.bounds.minX,
        globalY: root.isFlipped ? global.y - root.bounds.minY : root.bounds.maxY - global.y,
        kind: device.kind, buttons: buttons)
      return pointer.isValid ? pointer : nil
    }

    func locate(_ sample: HoverRouter.Sample) -> HoverRouter.Hit? {
      guard captureEnabled, !disposed, let window, ObjectIdentifier(window) == sample.window,
        window.isVisible, !isHiddenOrHasHiddenAncestor, let root = window.contentView
      else { return nil }
      let position = CGPoint(
        x: sample.pointer.position.x + root.bounds.minX,
        y: root.isFlipped
          ? sample.pointer.position.y + root.bounds.minY
          : root.bounds.maxY - sample.pointer.position.y)
      let local = convert(position, from: root)
      let pointer = NativePointer(
        id: sample.pointer.id, localX: local.x - bounds.minX, localY: local.y - bounds.minY,
        globalX: sample.pointer.position.x, globalY: sample.pointer.position.y,
        kind: sample.pointer.kind, buttons: sample.pointer.buttons)
      return HoverRouter.Hit(
        pointer: pointer,
        inside: !isHiddenOrHasHiddenAncestor && bounds.contains(local)
          && visibleRect.contains(local))
    }

    func dispose() {
      guard !disposed else { return }
      disposed = true
      devices.release()
      captureEnabled = false
      onSample = nil
      updateTrackingAreas()
      onGeometry = nil
    }
  }
#endif
