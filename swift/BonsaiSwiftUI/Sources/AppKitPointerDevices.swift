#if os(macOS)
  import AppKit

  struct AppKitPointerDevice {
    let id: UInt64
    let kind: NativePointer.Kind
  }

  /// Share native device identity across the application's windows and observers.
  @MainActor final class AppKitPointerDevices {
    static let shared = AppKitPointerDevices()
    private var owners: Set<UUID> = []
    private var types: [UInt32: NativePointer.Kind] = [:]
    private var monitor: Any?
    private var inactivity: NSObjectProtocol?

    @MainActor final class Lease {
      private let owner = UUID()
      private let devices: AppKitPointerDevices
      private var released = false

      fileprivate init(_ devices: AppKitPointerDevices) {
        self.devices = devices
        devices.retain(owner)
      }
      func device(for event: NSEvent) -> AppKitPointerDevice? {
        released ? nil : devices.device(for: event)
      }
      func release() {
        guard !released else { return }
        released = true
        devices.release(owner)
      }
      deinit {
        let owner = owner
        let devices = devices
        Task { @MainActor in devices.release(owner) }
      }
    }

    static func acquire() -> Lease { shared.lease() }
    func lease() -> Lease { Lease(self) }

    private func retain(_ owner: UUID) {
      owners.insert(owner)
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: [
        .tabletProximity, .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
      ]) { [weak self] event in
        MainActor.assumeIsolated { self?.observe(event) }
        return event
      }

      inactivity = NotificationCenter.default.addObserver(
        forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.types.removeAll() }
      }
    }

    private func release(_ owner: UUID) {
      owners.remove(owner)
      guard owners.isEmpty else { return }
      if let monitor { NSEvent.removeMonitor(monitor) }
      if let inactivity { NotificationCenter.default.removeObserver(inactivity) }
      monitor = nil
      inactivity = nil
      types.removeAll()
    }

    private func isMouse(_ event: NSEvent) -> Bool {
      switch event.type {
      case .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged:
        true
      default: false
      }
    }

    private func isProximity(_ event: NSEvent) -> Bool {
      event.type == .tabletProximity || (isMouse(event) && event.subtype == .tabletProximity)
    }

    private func observe(_ event: NSEvent) {
      guard isProximity(event), let device = UInt32(exactly: event.deviceID) else { return }
      guard event.isEnteringProximity else {
        types.removeValue(forKey: device)
        return
      }
      switch event.pointingDeviceType {
      case .pen: types[device] = .stylus
      case .eraser: types[device] = .invertedStylus
      case .cursor: types[device] = .mouse
      case .unknown: types[device] = .unknown
      @unknown default: types[device] = .unknown
      }
    }

    private func device(for event: NSEvent) -> AppKitPointerDevice? {
      let proximity = isProximity(event)
      let point = event.type == .tabletPoint || (isMouse(event) && event.subtype == .tabletPoint)
      guard proximity || point else { return AppKitPointerDevice(id: 0, kind: .mouse) }
      // Proximity can also be carried by a mouse packet; monitor order is immaterial.
      if proximity { observe(event) }
      guard let device = UInt32(exactly: event.deviceID) else { return nil }
      return AppKitPointerDevice(id: UInt64(device) + 1, kind: types[device] ?? .unknown)
    }
  }
#endif
