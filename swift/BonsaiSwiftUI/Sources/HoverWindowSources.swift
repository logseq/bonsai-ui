import Foundation

@MainActor protocol HoverWindowSource: AnyObject, Sendable {
  func dispose()
}

@MainActor final class HoverWindowSources<Window: AnyObject> {
  typealias Factory = (Window, @escaping @MainActor (HoverInput.Change) -> Void) ->
    any HoverWindowSource
  private struct Entry: Sendable {
    let generation: UUID
    let source: any HoverWindowSource
    let window: WeakWindow
  }
  @MainActor private final class WeakWindow {
    weak var value: Window?
    init(_ value: Window) { self.value = value }
  }
  private let create: Factory
  private let receive: (HoverRouter.Sample) -> Void
  private var entries: [ObjectIdentifier: Entry] = [:]

  init(create: @escaping Factory, receive: @escaping (HoverRouter.Sample) -> Void) {
    self.create = create
    self.receive = receive
  }
  var count: Int { entries.count }

  func replace(_ windows: [ObjectIdentifier: Window]) {
    for id in Array(entries.keys)
    where windows[id] == nil || entries[id]?.window.value !== windows[id] {
      entries.removeValue(forKey: id)?.source.dispose()
    }
    for (id, window) in windows where entries[id] == nil {
      let generation = UUID()
      let source = create(window) { [weak self, weak window] change in
        guard let self, window != nil, self.entries[id]?.generation == generation,
          change.sample.isValid
        else { return }
        self.receive(
          HoverRouter.Sample(pointer: change.sample, window: id, present: change.present))
      }
      entries[id] = Entry(generation: generation, source: source, window: WeakWindow(window))
    }
  }

  deinit {
    let sources = entries.values.map(\.source)
    Task { @MainActor in
      for source in sources { source.dispose() }
    }
  }
}
