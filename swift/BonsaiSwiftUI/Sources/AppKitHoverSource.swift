#if os(macOS)
  import AppKit

  @MainActor final class AppKitHoverSource: HoverWindowSource {
    private var monitor: Any?
    private let devices: AppKitPointerDevices.Lease

    init(
      window: NSWindow, devices: AppKitPointerDevices = .shared,
      receive: @escaping @MainActor (HoverInput.Change) -> Void
    ) {
      self.devices = devices.lease()
      monitor = NSEvent.addLocalMonitorForEvents(
        matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
      ) { [weak window, devices = self.devices] event in
        MainActor.assumeIsolated {
          guard let window, event.window === window, window.isVisible,
            let root = window.contentView,
            let buttons = UInt32(exactly: NSEvent.pressedMouseButtons),
            let device = devices.device(for: event)
          else { return }
          let point = root.convert(event.locationInWindow, from: nil)
          receive(
            HoverInput.Change(
              sample: HoverSample(
                id: device.id, kind: device.kind,
                position: CGPoint(
                  x: point.x - root.bounds.minX,
                  y: root.isFlipped ? point.y - root.bounds.minY : root.bounds.maxY - point.y),
                buttons: buttons), present: true))
        }
        return event
      }
    }

    func dispose() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      devices.release()
    }
  }
#endif
